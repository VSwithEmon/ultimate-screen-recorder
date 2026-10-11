import AppKit
import AVFoundation
import Combine
import ScreenRecCore
import SwiftUI

enum EditorPanel: String, CaseIterable {
    case canvas, cursor, camera, captions, audio, shortcuts
    var icon: String {
        switch self {
        case .canvas: return "rectangle.inset.filled"
        case .cursor: return "cursorarrow"
        case .camera: return "video.fill"
        case .captions: return "captions.bubble"
        case .audio: return "speaker.wave.2.fill"
        case .shortcuts: return "command"
        }
    }
    var title: String { rawValue.capitalized }
}

enum EventSelection: Equatable {
    case zoom(UUID)
    case mask(UUID)
}

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var aspect: AspectPreset
    var background: CanvasBackground
    var padding: Double
    var cornerRadius: Double
    var shadow: Bool
    var cursor: CursorSettings
    var camera: CameraSettings
    var audio: AudioSettings
}

/// Playback position and state live in their own object so only the playhead and time label redraw while playing,
/// not the whole editor.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var time = 0.0
    @Published var isPlaying = false
}

@MainActor
final class EditorModel: ObservableObject {
    let url: URL
    @Published private(set) var project: Project
    @Published private(set) var edit: EditState
    @Published var panel: EditorPanel = .canvas
    @Published var selection: EventSelection?
    let clock = PlaybackClock()
    var time: Double { get { clock.time } set { clock.time = newValue } }
    var isPlaying: Bool { get { clock.isPlaying } set { if clock.isPlaying != newValue { clock.isPlaying = newValue } } }
    @Published private(set) var ready = false
    @Published var loadError: String?
    @Published var waveform: [Float] = []
    @Published var timelineScale = 1.0
    @Published var showCrop = false
    @Published var showExport = false
    @Published var showShare = false
    let share = ShareFlow()
    @Published var exportProgress: Double?
    @Published var exportMessage: String?
    @Published private(set) var presets: [Preset] = []
    @Published var notice: String?

    let player = AVPlayer()
    private(set) var session: EditorSession?
    private var timeline: EditorSession.Timeline?
    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    private var lastCoalesce: (key: String, date: Date)?
    private var saveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var exporter: Exporter?
    private let previewHeight = 720

    init(url: URL) throws {
        self.url = url
        let p = try ProjectStore.load(from: url)
        project = p
        edit = p.edit
        presets = Self.loadPresets()
    }

    var duration: Double { session?.timelineDuration ?? 0 }
    var trimStart: Double { edit.trimStart }
    var trimEnd: Double { min(edit.trimEnd ?? duration, duration) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasCamera: Bool { project.sources.contains { $0.type == .camera } }
    var hasCursorData: Bool { !(session?.cursor.isEmpty ?? true) }
    var cursorBaked: Bool { project.capture?.cursorBakedIntoVideo ?? false }
    var sourceSize: CGSize { session?.sourceSize ?? CGSize(width: 1920, height: 1080) }
    private var cachedRenderer: (EditState, FrameRenderer)?
    /// Renderer used for overlay geometry; rebuilt only when the edit changes.
    var overlayRenderer: FrameRenderer? {
        if let (e, r) = cachedRenderer, e == edit { return r }
        guard let r = session?.renderer(for: edit, outputHeight: previewHeight) else { return nil }
        cachedRenderer = (edit, r)
        return r
    }

    // MARK: Loading

    func load() async {
        do {
            let s = try await EditorSession(project: project, packageURL: url)
            session = s
            try? await s.loadMusic(edit.audio.music)
            try rebuildTimeline()
            installTimeObserver()
            ready = true
            Task { waveform = await WaveformLoader.peaks(project: project, packageURL: url, buckets: 900) }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func shutdown() {
        player.pause()
        if let o = timeObserver { player.removeTimeObserver(o); timeObserver = nil }
        saveNow()
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let tl = self.timeline else { return }
                let new = tl.tauOffset + max(0, t.seconds)
                if abs(new - self.clock.time) > 0.005 { self.clock.time = new }
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    private func rebuildTimeline() throws {
        guard let session else { return }
        let keep = time
        let tl = try session.makeTimeline(trimStart: edit.trimStart, trimEnd: edit.trimEnd, music: edit.audio.music)
        timeline = tl
        let item = AVPlayerItem(asset: tl.composition)
        item.videoComposition = session.videoComposition(for: tl, edit: edit, outputHeight: previewHeight, fps: 30)
        item.audioMix = session.audioMix(for: tl, edit: edit)
        player.replaceCurrentItem(with: item)
        seek(to: min(max(keep, edit.trimStart), trimEnd))
    }

    private func refreshPreview() {
        guard let session, let tl = timeline, let item = player.currentItem else { return }
        item.videoComposition = session.videoComposition(for: tl, edit: edit, outputHeight: previewHeight, fps: 30)
        item.audioMix = session.audioMix(for: tl, edit: edit)
        if player.rate == 0 { seek(to: time) }   // repaint the paused frame
    }

    // MARK: Playback

    func seek(to tau: Double) {
        guard let tl = timeline else { return }
        let clamped = min(max(tau, tl.tauOffset), tl.tauOffset + tl.duration)
        time = clamped
        player.seek(to: CMTime(seconds: clamped - tl.tauOffset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlay() {
        if player.rate != 0 { player.pause(); isPlaying = false; return }
        if time >= trimEnd - 0.05 { seek(to: trimStart) }
        player.play(); isPlaying = true
    }

    func jump(forward: Bool) {
        let marks = ([trimStart, trimEnd] + edit.zoomEvents.flatMap { [$0.start, $0.end] } + edit.maskEvents.flatMap { [$0.start, $0.end] }).sorted()
        if forward { seek(to: marks.first { $0 > time + 0.05 } ?? trimEnd) } else { seek(to: marks.last { $0 < time - 0.05 } ?? trimStart) }
    }

    // MARK: Editing (undo, redo, autosave)

    /// Applies a change. Changes with the same `key` within 0.7 s (slider drags) share one undo step.
    func mutate(_ key: String? = nil, _ change: (inout EditState) -> Void) {
        let before = edit
        var after = edit
        change(&after)
        guard after != before else { return }
        let coalesce = key.map { k in lastCoalesce.map { $0.key == k && Date().timeIntervalSince($0.date) < 0.7 } ?? false } ?? false
        if !coalesce { undoStack.append(before); if undoStack.count > 150 { undoStack.removeFirst() } }
        lastCoalesce = key.map { ($0, Date()) }
        redoStack.removeAll()
        apply(after, before: before)
    }

    private func apply(_ new: EditState, before: EditState) {
        edit = new
        project.edit = new
        if let sel = selection, !selectionExists(sel) { selection = nil }
        let musicChanged = new.audio.music?.path != before.audio.music?.path || new.audio.music?.loop != before.audio.music?.loop
        if musicChanged {
            // A different music file (or looping on/off) changes the timeline itself, not just the mix.
            Task { [weak self] in
                guard let self, let session = self.session else { return }
                try? await session.loadMusic(new.audio.music)
                try? self.rebuildTimeline()
            }
        } else if new.trimStart != before.trimStart || new.trimEnd != before.trimEnd {
            try? rebuildTimeline()
        } else {
            refreshPreview()
        }
        scheduleSave()
    }

    private func selectionExists(_ s: EventSelection) -> Bool {
        switch s {
        case .zoom(let id): return edit.zoomEvents.contains { $0.id == id }
        case .mask(let id): return edit.maskEvents.contains { $0.id == id }
        }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(edit); lastCoalesce = nil
        apply(prev, before: edit)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(edit); lastCoalesce = nil
        apply(next, before: edit)
    }

    func binding<T>(_ kp: WritableKeyPath<EditState, T>) -> Binding<T> {
        let key = String(describing: kp)
        return Binding(get: { self.edit[keyPath: kp] }, set: { v in self.mutate(key) { $0[keyPath: kp] = v } })
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do { try ProjectStore.save(project, to: url) } catch { notice = "Could not save project: \(error.localizedDescription)" }
    }

    // MARK: Events

    func addManualZoom() {
        let start = min(max(time, trimStart), max(trimStart, trimEnd - 1))
        var z = ZoomEvent(start: start, end: min(trimEnd, start + 3), scale: 1.8, mode: .manual)
        z.focus = CGPoint(x: 0.5, y: 0.5)
        mutate { $0.zoomEvents.append(z) }
        selection = .zoom(z.id)
        panel = .canvas
    }

    /// Replaces automatic zoom events with ones derived from clicks; manual zooms are kept.
    func generateAutomaticZoom() {
        guard let session else { return }
        let clicks = session.cursor.clicks
        guard !clicks.isEmpty else { notice = "No clicks were recorded, so automatic zoom has nothing to follow. Add a manual zoom instead."; return }
        let scale = edit.zoomEvents.first?.scale ?? 1.8
        let generated = ZoomEngine.autoEvents(from: clicks, duration: duration, scale: scale)
        mutate { e in e.zoomEvents = e.zoomEvents.filter { $0.mode == .manual } + generated }
        notice = "Added \(generated.count) automatic zoom\(generated.count == 1 ? "" : "s")."
    }

    func addMask(_ kind: MaskEvent.Kind) {
        let start = min(max(time, trimStart), max(trimStart, trimEnd - 1))
        let m = MaskEvent(start: start, end: min(trimEnd, start + 3), kind: kind)
        mutate { $0.maskEvents.append(m) }
        selection = .mask(m.id)
    }

    func deleteSelection() {
        switch selection {
        case .zoom(let id): mutate { $0.zoomEvents.removeAll { $0.id == id } }
        case .mask(let id): mutate { $0.maskEvents.removeAll { $0.id == id } }
        case nil: break
        }
        selection = nil
    }

    func setTrimStartHere() { mutate { $0.trimStart = min(time, (($0.trimEnd ?? duration) - 0.2)) } }
    func setTrimEndHere() { mutate { $0.trimEnd = max(time, $0.trimStart + 0.2) } }
    func resetTrim() { mutate { $0.trimStart = 0; $0.trimEnd = nil } }

    func importBackgroundImage(from source: URL) {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let rel = "Media/background.\(ext)"
        let dest = url.appendingPathComponent(rel)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: source, to: dest)
            session?.setBackgroundImage(path: rel)
            mutate { $0.background.kind = .image; $0.background.imagePath = rel }
            refreshPreview()
        } catch { notice = "Could not import image: \(error.localizedDescription)" }
    }

    // MARK: Music

    /// Copies the track into the project (so the project stays self-contained) and uses it as background music.
    func useBuiltInMusic(_ track: MusicTrack, library: MusicLibrary = .shared) {
        guard let src = library.url(for: track) else { notice = "That track isn't available in this build."; return }
        useMusicFile(src, title: track.title, name: "music-\(track.id).m4a")
    }

    func importMusic(from source: URL) {
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        useMusicFile(source, title: source.deletingPathExtension().lastPathComponent, name: "music-import.\(ext)")
    }

    private func useMusicFile(_ source: URL, title: String, name: String) {
        let rel = "Media/\(name)"
        let dest = url.appendingPathComponent(rel)
        do {
            if source.standardizedFileURL != dest.standardizedFileURL {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: source, to: dest)
            }
            mutate { e in
                var m = e.audio.music ?? MusicSettings(path: rel, title: title)
                m.path = rel; m.title = title
                e.audio.music = m
            }
        } catch { notice = "Could not add the music: \(error.localizedDescription)" }
    }

    func removeMusic() { mutate { $0.audio.music = nil } }

    // MARK: Presets

    private static var presetsURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ultimate Screen Recording")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }

    private static func loadPresets() -> [Preset] {
        (try? JSONDecoder().decode([Preset].self, from: Data(contentsOf: presetsURL))) ?? []
    }

    func saveCurrentAsPreset(named name: String) {
        let e = edit
        presets.append(Preset(name: name, aspect: e.aspect, background: e.background, padding: e.padding, cornerRadius: e.cornerRadius,
                              shadow: e.shadow, cursor: e.cursor, camera: e.camera, audio: e.audio))
        try? JSONEncoder().encode(presets).write(to: Self.presetsURL, options: .atomic)
    }

    func apply(_ p: Preset) {
        mutate { e in
            e.aspect = p.aspect; e.background = p.background; e.padding = p.padding; e.cornerRadius = p.cornerRadius
            e.shadow = p.shadow; e.cursor = p.cursor; e.camera = p.camera; e.audio = p.audio
        }
    }

    func resetStyle() {
        mutate { e in
            let d = EditState()
            e.aspect = d.aspect; e.background = d.background; e.padding = d.padding; e.cornerRadius = d.cornerRadius
            e.shadow = d.shadow; e.cursor = d.cursor; e.camera = d.camera
        }
    }

    // MARK: Project actions

    func moveProjectToTrash() -> Bool {
        shutdown()
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil); return true }
        catch { notice = "Could not move to Trash: \(error.localizedDescription)"; return false }
    }

    // MARK: Export

    struct ExportOptions {
        var height = 1080
        var fps = 30
        var hevc = false
    }

    func estimatedSize(_ o: ExportOptions) -> (dims: CGSize, megabytes: Double) {
        let dims = edit.outputSize(sourceSize: sourceSize, targetHeight: o.height)
        let bitrate = max(4_000_000, Double(dims.width * dims.height) * Double(o.fps) * 0.1) * (o.hevc ? 0.7 : 1) + 192_000
        return (dims, bitrate * max(trimEnd - trimStart, 0) / 8 / 1_000_000)
    }

    func export(_ o: ExportOptions) async {
        guard exportProgress == nil, let session else { return }
        saveNow()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = project.name + ".mp4"
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        panel.title = "Export"
        guard panel.runModal() == .OK, let out = panel.url else { return }
        let exporter = Exporter()
        self.exporter = exporter
        exportProgress = 0; exportMessage = nil
        do {
            try await exporter.export(ExportRequest(session: session, edit: edit, outputURL: out, height: o.height, fps: o.fps,
                                                    codec: o.hevc ? .hevc : .h264)) { p in
                Task { @MainActor [weak self] in self?.exportProgress = p }
            }
            exportMessage = "Exported to \(out.path)"
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            exportMessage = error.localizedDescription
        }
        exportProgress = nil
        self.exporter = nil
    }

    func cancelExport() { exporter?.cancel() }
}

// MARK: - Waveform

enum WaveformLoader {
    /// Peak envelope of the first audio source (microphone preferred), downsampled to `buckets` values 0...1.
    static func peaks(project: Project, packageURL: URL, buckets: Int) async -> [Float] {
        guard let s = project.sources.first(where: { $0.type == .microphone }) ?? project.sources.first(where: { $0.type == .systemAudio }) else { return [] }
        let asset = AVURLAsset(url: ProjectStore.resolve(s, in: packageURL))
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let duration = try? await asset.load(.duration).seconds, duration > 0,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 8000])
        reader.add(out)
        guard reader.startReading() else { return [] }
        let totalSamples = Int(duration * 8000)
        let per = max(1, totalSamples / buckets)
        var result = [Float](repeating: 0, count: buckets)
        var index = 0
        while let sb = out.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sb) {
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / 2)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for v in data {
                let b = min(buckets - 1, index / per)
                result[b] = max(result[b], abs(Float(v)) / 32768)
                index += 1
            }
        }
        let peak = max(result.max() ?? 1, 0.05)
        return result.map { min(1, $0 / peak) }
    }
}
