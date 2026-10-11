import AVFoundation
import CoreMedia
import ScreenCaptureKit
import ScreenRecCore

enum CaptureTarget: Equatable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    /// Display plus a rect in display-local points (origin top-left).
    case area(CGDirectDisplayID, CGRect)
}

struct CaptureOptions {
    var fps = 30
    var systemAudio = true
    var microphone = true
    var camera = false
    var cursorInVideo = false
    var hideDesktopIcons = false
    var micDeviceID: String?
    var cameraDeviceID: String?
    /// Chosen camera format size; nil = the device's current format.
    var cameraDimensions: CMVideoDimensions?
}

struct CaptureResult {
    var sources: [Source]
    var info: CaptureInfo
}

/// Writes one sample stream to its own file. Not thread-safe: all calls must come from `queue`.
final class StreamFileWriter: @unchecked Sendable {
    let url: URL
    let queue: DispatchQueue
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private(set) var firstPTS: CMTime?
    private(set) var droppedSamples = 0
    /// Rejects samples with implausible timestamps (some cameras emit a stale first frame stamped near zero).
    var accept: ((CMTime) -> Bool)?

    init(url: URL, fileType: AVFileType, mediaType: AVMediaType, settings: [String: Any], label: String) throws {
        self.url = url
        self.queue = DispatchQueue(label: "capture.\(label)")
        writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        input = AVAssetWriterInput(mediaType: mediaType, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func append(_ sample: CMSampleBuffer) {
        guard sample.isValid, CMSampleBufferGetNumSamples(sample) > 0 else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if let accept, !accept(pts) { droppedSamples += 1; return }
        if firstPTS == nil {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: pts)
            firstPTS = pts
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { droppedSamples += 1; return }
        if !input.append(sample) { droppedSamples += 1 }
    }

    /// Returns false if no sample ever arrived (file is removed).
    /// `endAt` extends the file to the real stop time (a static screen otherwise ends at its last changed frame).
    func finish(endAt: CMTime? = nil) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            queue.async { [self] in
                guard let first = firstPTS else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    c.resume(returning: false); return
                }
                if let endAt, endAt > first, writer.status == .writing { writer.endSession(atSourceTime: endAt) }
                input.markAsFinished()
                writer.finishWriting { c.resume(returning: self.writer.status == .completed) }
            }
        }
    }
}

enum CaptureError: LocalizedError {
    case noDisplay
    case writerSetup(String)
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "The selected screen or window is no longer available."
        case .writerSetup(let m): return "Could not prepare recording files: \(m)"
        }
    }
}

/// Phase 0 capture: one display via ScreenCaptureKit (+ system audio), microphone via AVCaptureSession.
/// All streams carry host-clock timestamps; `t0` is the shared origin and each stream's start offset is saved.
final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let t0: Double
    private let projectURL: URL
    private let options: CaptureOptions
    private var stream: SCStream?
    private var micSession: AVCaptureSession?
    private var videoWriter: StreamFileWriter?
    private var systemWriter: StreamFileWriter?
    private var micWriter: StreamFileWriter?
    private var cameraWriter: StreamFileWriter?
    private var cameraOutput: AVCaptureVideoDataOutput?
    private var info: CaptureInfo?
    /// Seconds to add to camera/microphone timestamps (session clock) to express them on the host clock.
    private var deviceClockDelta = 0.0
    var onError: (@Sendable (String) -> Void)?

    private let target: CaptureTarget

    init(projectURL: URL, options: CaptureOptions, target: CaptureTarget = .display(CGMainDisplayID())) {
        self.projectURL = projectURL
        self.options = options
        self.target = target
        self.t0 = CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }

    func start() async throws -> CaptureInfo {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Never record this app's own windows (toolbar, recording timer, camera preview, notes). Excluding the whole
        // application also covers windows created while recording; the per-window list is only needed to hide desktop icons.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        var excluded = content.windows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
        if options.hideDesktopIcons {
            let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            excluded += content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.apple.finder" && $0.windowLayer == iconLevel }
        }
        var bakeCursor = options.cursorInVideo
        let displayID: CGDirectDisplayID
        var sourceRect: CGRect?
        let filter: SCContentFilter
        switch target {
        case .display(let id), .area(let id, _):
            displayID = id
            guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else { throw CaptureError.noDisplay }
            filter = options.hideDesktopIcons
                ? SCContentFilter(display: display, excludingWindows: excluded)
                : SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            if case .area(_, let r) = target { sourceRect = r }
        case .window(let wid):
            guard let win = content.windows.first(where: { $0.windowID == wid }) else { throw CaptureError.noDisplay }
            // Windows can move while recording, so cursor metadata can't be aligned: bake the cursor in.
            bakeCursor = true
            filter = SCContentFilter(desktopIndependentWindow: win)
            let centre = CGPoint(x: win.frame.midX, y: win.frame.midY)
            displayID = content.displays.first(where: { $0.frame.contains(centre) })?.displayID ?? CGMainDisplayID()
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { throw CaptureError.noDisplay }
        let filterInfo = SCShareableContent.info(for: filter)
        let scale = CGFloat(filterInfo.pointPixelScale)
        let pointSize = sourceRect?.size ?? filterInfo.contentRect.size
        let width = Geometry.evenPixels(pointSize.width * scale)
        let height = Geometry.evenPixels(pointSize.height * scale)
        var region: NormRect?
        if let r = sourceRect { region = AreaSelection(rect: r).normalized(in: CGRect(origin: .zero, size: display.frame.size)) }

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = bakeCursor
        if let r = sourceRect { config.sourceRect = r }
        config.queueDepth = 6
        if options.systemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }

        let media = projectURL.appendingPathComponent("Media")
        do {
            let bitrate = Int(Double(width * height * options.fps) * 0.2)
            videoWriter = try StreamFileWriter(
                url: media.appendingPathComponent("screen.mov"), fileType: .mov, mediaType: .video,
                settings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                           AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,
                                                             AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                                             AVVideoExpectedSourceFrameRateKey: options.fps]],
                label: "screen")
            let aacSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                                              AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
            if options.systemAudio {
                systemWriter = try StreamFileWriter(url: media.appendingPathComponent("system.m4a"), fileType: .m4a,
                                                    mediaType: .audio, settings: aacSettings, label: "system")
            }
            if options.microphone {
                micWriter = try StreamFileWriter(url: media.appendingPathComponent("mic.m4a"), fileType: .m4a,
                                                 mediaType: .audio, settings: aacSettings, label: "mic")
                micWriter?.accept = { [weak self] pts in self?.plausible(pts) ?? true }
            }
        } catch {
            throw CaptureError.writerSetup(error.localizedDescription)
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoWriter!.queue)
        if let systemWriter { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: systemWriter.queue) }
        self.stream = stream

        if micWriter != nil || options.camera { try startDevices() }
        try await stream.startCapture()

        let captureInfo = CaptureInfo(displayFrame: display.frame, pixelWidth: width, pixelHeight: height,
                                      scale: Double(scale), cursorBakedIntoVideo: bakeCursor, region: region)
        info = captureInfo
        return captureInfo
    }

    private func startDevices() throws {
        let session = AVCaptureSession()
        if let micWriter {
            guard let device = options.micDeviceID.flatMap({ AVCaptureDevice(uniqueID: $0) }) ?? AVCaptureDevice.default(for: .audio) else { throw CaptureError.writerSetup("no microphone available") }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CaptureError.writerSetup("cannot use microphone input") }
            session.addInput(input)
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: micWriter.queue)
            guard session.canAddOutput(output) else { throw CaptureError.writerSetup("cannot read microphone samples") }
            session.addOutput(output)
        }
        if options.camera {
            guard let device = options.cameraDeviceID.flatMap({ AVCaptureDevice(uniqueID: $0) }) ?? AVCaptureDevice.default(for: .video) else { throw CaptureError.writerSetup("no camera available") }
            if let want = options.cameraDimensions,
               let format = device.formats.first(where: { let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription); return d.width == want.width && d.height == want.height }) {
                try device.lockForConfiguration(); device.activeFormat = format; device.unlockForConfiguration()
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CaptureError.writerSetup("cannot use camera input") }
            session.addInput(input)
            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let w = Geometry.evenPixels(CGFloat(dims.width)), h = Geometry.evenPixels(CGFloat(dims.height))
            let writer = try StreamFileWriter(
                url: projectURL.appendingPathComponent("Media/camera.mov"), fileType: .mov, mediaType: .video,
                settings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
                           AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h * 4]], label: "camera")
            writer.accept = { [weak self] pts in self?.plausible(pts) ?? true }
            cameraWriter = writer
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: writer.queue)
            guard session.canAddOutput(output) else { throw CaptureError.writerSetup("cannot read camera frames") }
            session.addOutput(output)
            cameraOutput = output
        }
        session.startRunning()
        // Camera frames are stamped on the capture session's clock, which is not the host clock; remember the difference.
        if let clock = session.synchronizationClock {
            deviceClockDelta = CMClockGetTime(CMClockGetHostTimeClock()).seconds - CMClockGetTime(clock).seconds
        }
        micSession = session
    }

    /// A device sample is plausible if, on the host clock, it is within a few seconds of "now".
    private func plausible(_ pts: CMTime) -> Bool {
        abs(pts.seconds + deviceClockDelta - CMClockGetTime(CMClockGetHostTimeClock()).seconds) < 5
    }

    func stop() async throws -> CaptureResult {
        micSession?.stopRunning()
        try? await stream?.stopCapture()
        stream = nil
        let hostNow = CMClockGetTime(CMClockGetHostTimeClock())
        let deviceNow = CMTime(seconds: hostNow.seconds - deviceClockDelta, preferredTimescale: 600)

        var sources: [Source] = []
        let screenOffset = (videoWriter?.firstPTS?.seconds ?? t0) - t0
        func offset(_ w: StreamFileWriter, device: Bool = false) -> Double {
            let v = (w.firstPTS?.seconds ?? t0) + (device ? deviceClockDelta : 0) - t0
            // A stream whose clock could not be reconciled must never wreck the timeline: fall back to the screen's start.
            return abs(v - screenOffset) > 120 ? screenOffset : v
        }

        if let w = videoWriter, await w.finish(endAt: hostNow) {
            sources.append(Source(id: "screen1", type: .screen, path: "Media/screen.mov", startOffset: offset(w)))
        }
        if let w = systemWriter, await w.finish(endAt: hostNow) {
            sources.append(Source(id: "system1", type: .systemAudio, path: "Media/system.m4a", startOffset: offset(w)))
        }
        if let w = cameraWriter, await w.finish(endAt: deviceNow) {
            sources.append(Source(id: "camera1", type: .camera, path: "Media/camera.mov", startOffset: offset(w, device: true)))
        }
        if let w = micWriter, await w.finish(endAt: deviceNow) {
            sources.append(Source(id: "mic1", type: .microphone, path: "Media/mic.m4a", startOffset: offset(w, device: true)))
        }
        guard let info, sources.contains(where: { $0.type == .screen }) else {
            throw CaptureError.writerSetup("no video frames were captured (is Screen Recording permission granted?)")
        }
        return CaptureResult(sources: sources, info: info)
    }

    // MARK: SCStreamOutput / delegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            // Only complete frames carry pixels; idle/blank statuses have no image buffer.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: raw) == .complete else { return }
            videoWriter?.append(sampleBuffer)
        case .audio:
            systemWriter?.append(sampleBuffer)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?("Capture stopped unexpectedly: \(error.localizedDescription)")
    }

    // MARK: Microphone

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === cameraOutput { cameraWriter?.append(sampleBuffer) } else { micWriter?.append(sampleBuffer) }
    }
}
