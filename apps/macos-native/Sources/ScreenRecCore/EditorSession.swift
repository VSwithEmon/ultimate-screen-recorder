import AVFoundation
import CoreImage
import CoreMedia
import Foundation

// MARK: - Custom compositor (runs the shared FrameRenderer)

final class EditorInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let renderer: FrameRenderer
    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    /// Timeline seconds at composition time 0 (the trim start).
    let tauOffset: Double

    init(timeRange: CMTimeRange, renderer: FrameRenderer, screen: CMPersistentTrackID, camera: CMPersistentTrackID?, tauOffset: Double) {
        self.timeRange = timeRange
        self.renderer = renderer
        self.screenTrackID = screen
        self.cameraTrackID = camera
        self.tauOffset = tauOffset
        var ids = [NSNumber(value: screen)]
        if let camera { ids.append(NSNumber(value: camera)) }
        self.requiredSourceTrackIDs = ids
    }
}

final class EditorCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    private let queue = DispatchQueue(label: "editor.compositor", qos: .userInitiated)

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            guard let inst = request.videoCompositionInstruction as? EditorInstruction,
                  let out = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "ScreenRec", code: 1, userInfo: [NSLocalizedDescriptionKey: "compositor setup failed"]))
                return
            }
            let screen = request.sourceFrame(byTrackID: inst.screenTrackID).map { CIImage(cvPixelBuffer: $0) }
            let camera = inst.cameraTrackID.flatMap { request.sourceFrame(byTrackID: $0) }.map { CIImage(cvPixelBuffer: $0) }
            let tau = inst.tauOffset + request.compositionTime.seconds
            let image = inst.renderer.render(screen: screen, camera: camera, at: tau)
            FrameRenderer.ciContext.render(image, to: out, bounds: CGRect(origin: .zero, size: inst.renderer.outputSize),
                                           colorSpace: FrameRenderer.colorSpace)
            request.finish(withComposedVideoFrame: out)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

// MARK: - Session

public enum EditorSessionError: LocalizedError {
    case noScreen
    public var errorDescription: String? { "The project has no screen recording." }
}

/// Loads a project's media once; builds trimmed compositions and video compositions on demand.
public final class EditorSession {
    public struct Timeline {
        public let composition: AVMutableComposition
        public let screenID: CMPersistentTrackID
        public let cameraID: CMPersistentTrackID?
        public let micID: CMPersistentTrackID?
        public let systemID: CMPersistentTrackID?
        public let musicID: CMPersistentTrackID?
        /// Timeline seconds at composition time 0.
        public let tauOffset: Double
        public let duration: Double
    }

    /// `sourceStart` skips a stale leading sample in files written by early builds.
    private struct Loaded { var source: Source; var asset: AVURLAsset; var track: AVAssetTrack; var duration: Double; var sourceStart = 0.0 }

    public let project: Project
    public let packageURL: URL
    public let sourceSize: CGSize
    public let cameraSize: CGSize?
    public let cursor: CursorTrack
    public let origin: Double
    /// Full length of the recording on the timeline (before trim).
    public let timelineDuration: Double
    public private(set) var backgroundImage: CIImage?
    private let screen: Loaded
    private let camera: Loaded?
    private let mic: Loaded?
    private let system: Loaded?
    private var music: Loaded?
    private var musicPath: String?

    public init(project: Project, packageURL: URL) async throws {
        self.project = project
        self.packageURL = packageURL

        // Projects recorded by early builds can hold a camera offset on the wrong clock (hundreds of thousands of seconds).
        // Anything more than two minutes from the screen's start is treated as "starts with the screen".
        let screenStart = project.sources.first(where: { $0.type == .screen })?.startOffset ?? 0
        func load(_ type: SourceType, _ media: AVMediaType) async throws -> Loaded? {
            guard var s = project.sources.first(where: { $0.type == type }) else { return nil }
            if abs(s.startOffset - screenStart) > 120 { s.startOffset = screenStart }
            let asset = AVURLAsset(url: ProjectStore.resolve(s, in: packageURL))
            guard let track = try await asset.loadTracks(withMediaType: media).first else { return nil }
            var duration = try await asset.load(.duration).seconds
            var start = 0.0
            // Repair: a first sample stamped near 0 followed by real samples days later makes a gigantic, mostly empty file.
            if media == .video, duration > 3600, let real = EditorSession.firstSampleAfterGap(asset: asset, track: track) {
                start = real; duration -= real
            }
            return Loaded(source: s, asset: asset, track: track, duration: duration, sourceStart: start)
        }
        guard let screen = try await load(.screen, .video) else { throw EditorSessionError.noScreen }
        self.screen = screen
        camera = try await load(.camera, .video)
        mic = try await load(.microphone, .audio)
        system = try await load(.systemAudio, .audio)

        sourceSize = try await screen.track.load(.naturalSize)
        if let cam = camera { cameraSize = try await cam.track.load(.naturalSize) } else { cameraSize = nil }

        let all = [screen, camera, mic, system].compactMap { $0 }
        origin = all.map(\.source.startOffset).min() ?? 0
        timelineDuration = all.map { $0.source.startOffset - (all.map(\.source.startOffset).min() ?? 0) + $0.duration }.max() ?? screen.duration

        if let rel = project.cursorEventsPath,
           let events = try? CursorEventLog.read(url: packageURL.appendingPathComponent(rel)) {
            // Area captures cover part of the display; re-express cursor positions relative to the recorded region.
            var mapped = events
            if let r = project.capture?.region, r.w > 0, r.h > 0 {
                mapped = events.map { var e = $0; e.x = (e.x - r.x) / r.w; e.y = (e.y - r.y) / r.h; return e }
            }
            cursor = CursorTrack(events: mapped, timeShift: -origin)
        } else {
            cursor = .empty
        }
        if let path = project.edit.background.imagePath {
            backgroundImage = CIImage(contentsOf: packageURL.appendingPathComponent(path))
        } else {
            backgroundImage = nil
        }
    }

    /// Call after the project's background image file changes.
    public func setBackgroundImage(path: String?) {
        backgroundImage = path.flatMap { CIImage(contentsOf: packageURL.appendingPathComponent($0)) }
    }

    private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 60000) }

    /// Loads the music file named by `settings` (or clears it). Call before `makeTimeline` whenever the music choice changes.
    public func loadMusic(_ settings: MusicSettings?) async throws {
        guard let settings else { music = nil; musicPath = nil; return }
        if musicPath == settings.path, music != nil { return }
        let asset = AVURLAsset(url: packageURL.appendingPathComponent(settings.path))
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { music = nil; musicPath = nil; return }
        let duration = try await asset.load(.duration).seconds
        guard duration > 0.5 else { music = nil; musicPath = nil; return }
        music = Loaded(source: Source(id: "music", type: .systemAudio, path: settings.path, startOffset: 0), asset: asset, track: track, duration: duration)
        musicPath = settings.path
    }

    /// Builds the (trimmed) timeline. Streams are placed by their recorded start offsets.
    public func makeTimeline(trimStart: Double = 0, trimEnd: Double? = nil, music settings: MusicSettings? = nil) throws -> Timeline {
        let ts = min(max(trimStart, 0), timelineDuration)
        let te = min(max(trimEnd ?? timelineDuration, ts + 0.1), timelineDuration)
        let comp = AVMutableComposition()

        func insert(_ l: Loaded?) throws -> CMPersistentTrackID? {
            guard let l, let dst = comp.addMutableTrack(withMediaType: l.track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            let off = l.source.startOffset - origin
            let srcStart = max(0, ts - off), srcEnd = min(l.duration, te - off)
            guard srcEnd > srcStart else { return dst.trackID }
            try dst.insertTimeRange(CMTimeRange(start: t(l.sourceStart + srcStart), end: t(l.sourceStart + srcEnd)), of: l.track, at: t(max(0, off - ts)))
            return dst.trackID
        }
        guard let screenID = try insert(screen) else { throw EditorSessionError.noScreen }
        let cameraID = try insert(camera), micID = try insert(mic), systemID = try insert(system)

        // Background music: starts with the (trimmed) timeline and loops to cover it.
        var musicID: CMPersistentTrackID?
        if let settings, let m = music, musicPath == settings.path,
           let dst = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let length = te - ts
            var placed = 0.0
            while placed < length - 0.01 {
                let piece = min(m.duration, length - placed)
                try dst.insertTimeRange(CMTimeRange(start: .zero, duration: t(piece)), of: m.track, at: t(placed))
                placed += piece
                if !settings.loop { break }
            }
            musicID = dst.trackID
        }
        return Timeline(composition: comp, screenID: screenID, cameraID: cameraID, micID: micID,
                        systemID: systemID, musicID: musicID, tauOffset: ts, duration: te - ts)
    }

    /// Finds the first sample after a gap of more than a minute (compressed samples only, so this is fast).
    static func firstSampleAfterGap(asset: AVURLAsset, track: AVAssetTrack) -> Double? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out)
        guard reader.startReading() else { return nil }
        var previous: Double?
        var count = 0
        while let sb = out.copyNextSampleBuffer(), count < 200 {
            let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            if let prev = previous, pts - prev > 60 { reader.cancelReading(); return pts }
            previous = pts; count += 1
        }
        return nil
    }

    public func renderer(for edit: EditState, outputHeight: Int, timelineBackground: CIImage? = nil) -> FrameRenderer {
        let size = edit.outputSize(sourceSize: sourceSize, targetHeight: outputHeight)
        return FrameRenderer(edit: edit, cursor: cursor, sourceSize: sourceSize, outputSize: size, timelineDuration: timelineDuration,
                             cursorBaked: project.capture?.cursorBakedIntoVideo ?? false,
                             backgroundImage: timelineBackground ?? backgroundImage, cameraSize: cameraSize)
    }

    public func videoComposition(for timeline: Timeline, edit: EditState, outputHeight: Int, fps: Int) -> AVMutableVideoComposition {
        let r = renderer(for: edit, outputHeight: outputHeight)
        let vc = AVMutableVideoComposition()
        vc.renderSize = r.outputSize
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        vc.customVideoCompositorClass = EditorCompositor.self
        let cam = (edit.camera.hidden ? nil : timeline.cameraID)
        vc.instructions = [EditorInstruction(timeRange: CMTimeRange(start: .zero, duration: timeline.composition.duration),
                                             renderer: r, screen: timeline.screenID, camera: cam, tauOffset: timeline.tauOffset)]
        return vc
    }

    public func audioMix(for timeline: Timeline, edit: EditState) -> AVAudioMix? {
        var params: [AVMutableAudioMixInputParameters] = []
        func add(_ id: CMPersistentTrackID?, volume: Float) {
            guard let id, let track = timeline.composition.track(withTrackID: id) else { return }
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(volume, at: .zero)
            params.append(p)
        }
        add(timeline.micID, volume: edit.audio.muteMicrophone ? 0 : Float(edit.audio.micGain))
        add(timeline.systemID, volume: Float(edit.audio.systemGain))
        if let id = timeline.musicID, let track = timeline.composition.track(withTrackID: id), let m = edit.audio.music {
            let p = AVMutableAudioMixInputParameters(track: track)
            let gain = Float(min(max(m.gain, 0), 1.5)), total = timeline.duration
            let fin = min(max(m.fadeIn, 0), total / 2), fout = min(max(m.fadeOut, 0), total / 2)
            if fin > 0 {
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain, timeRange: CMTimeRange(start: .zero, duration: t(fin)))
            } else { p.setVolume(gain, at: .zero) }
            if fout > 0 {
                p.setVolume(gain, at: t(fin))
                p.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0, timeRange: CMTimeRange(start: t(total - fout), duration: t(fout)))
            }
            params.append(p)
        }
        guard !params.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }
}
