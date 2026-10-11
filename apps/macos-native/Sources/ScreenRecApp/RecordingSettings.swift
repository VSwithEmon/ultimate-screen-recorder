import AVFoundation
import CoreMedia
import ScreenRecCore
import SwiftUI

extension CMVideoDimensions: @retroactive Hashable {
    public func hash(into h: inout Hasher) { h.combine(width); h.combine(height) }
    public static func == (a: CMVideoDimensions, b: CMVideoDimensions) -> Bool { a.width == b.width && a.height == b.height }
}

enum DeviceCatalog {
    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }
    static func microphones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }
    /// Distinct format sizes a camera offers, largest first.
    static func resolutions(of device: AVCaptureDevice) -> [CMVideoDimensions] {
        var seen = Set<Int64>(), out: [CMVideoDimensions] = []
        for f in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let key = Int64(d.width) << 32 | Int64(d.height)
            if seen.insert(key).inserted && d.width >= 640 { out.append(d) }
        }
        return out.sorted { Int($0.width) * Int($0.height) > Int($1.width) * Int($1.height) }
    }
    static func label(_ d: CMVideoDimensions) -> String {
        let name = d.height >= 2160 ? " (4K)" : d.height >= 1080 ? " (HD)" : ""
        return "\(d.width)×\(d.height)\(name)"
    }
}

enum CaptureMode: String, CaseIterable {
    case display, window, area, device
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .display: return "display"
        case .window: return "macwindow"
        case .area: return "rectangle.dashed"
        case .device: return "iphone"
        }
    }
}

enum SystemAudioChoice: String, Codable { case all, none }

/// Everything chosen in the toolbar. Persisted so the next recording starts with the same choices.
@MainActor
final class RecordingSettings: ObservableObject {
    private struct Stored: Codable {
        var cameraEnabled = true, cameraID: String?, cameraWidth: Int32?, cameraHeight: Int32?, hideCameraPreview = false
        var micEnabled = true, micID: String?
        var systemAudio = SystemAudioChoice.all
        var hideDesktopIcons = false, hideDockIcon = true, highlightArea = true, openEditorAfter = true
        var countdown = 0, fps = 30, bakeCursor = false
        var savedAreas: [SavedArea] = []
        var keepLastFive = false
    }

    @Published var mode: CaptureMode?
    @Published var cameraEnabled: Bool { didSet { save() } }
    @Published var cameraID: String? { didSet { save() } }
    @Published var cameraDimensions: CMVideoDimensions? { didSet { save() } }
    @Published var hideCameraPreview: Bool { didSet { save() } }
    @Published var micEnabled: Bool { didSet { save() } }
    @Published var micID: String? { didSet { save() } }
    @Published var systemAudio: SystemAudioChoice { didSet { save() } }
    @Published var hideDesktopIcons: Bool { didSet { save() } }
    @Published var hideDockIcon: Bool { didSet { save() } }
    @Published var highlightArea: Bool { didSet { save() } }
    @Published var openEditorAfter: Bool { didSet { save() } }
    @Published var countdown: Int { didSet { save() } }
    @Published var fps: Int { didSet { save() } }
    @Published var bakeCursor: Bool { didSet { save() } }
    @Published var savedAreas: [SavedArea] { didSet { save() } }
    /// Opt-in: move recordings older than the newest five to the Trash after each new recording.
    @Published var keepLastFive: Bool { didSet { save() } }
    @Published var speakerNotes = ""

    private static let key = "recordingSettings.v1"
    private var loading = true

    init() {
        let s = (UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }) ?? Stored()
        cameraEnabled = s.cameraEnabled; cameraID = s.cameraID
        cameraDimensions = (s.cameraWidth != nil && s.cameraHeight != nil) ? CMVideoDimensions(width: s.cameraWidth!, height: s.cameraHeight!) : nil
        hideCameraPreview = s.hideCameraPreview; micEnabled = s.micEnabled; micID = s.micID; systemAudio = s.systemAudio
        hideDesktopIcons = s.hideDesktopIcons; hideDockIcon = s.hideDockIcon; highlightArea = s.highlightArea
        openEditorAfter = s.openEditorAfter; countdown = s.countdown; fps = s.fps; bakeCursor = s.bakeCursor; savedAreas = s.savedAreas; keepLastFive = s.keepLastFive
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let s = Stored(cameraEnabled: cameraEnabled, cameraID: cameraID, cameraWidth: cameraDimensions?.width, cameraHeight: cameraDimensions?.height,
                       hideCameraPreview: hideCameraPreview, micEnabled: micEnabled, micID: micID, systemAudio: systemAudio,
                       hideDesktopIcons: hideDesktopIcons, hideDockIcon: hideDockIcon, highlightArea: highlightArea,
                       openEditorAfter: openEditorAfter, countdown: countdown, fps: fps, bakeCursor: bakeCursor, savedAreas: savedAreas, keepLastFive: keepLastFive)
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func captureOptions(cameraAllowed: Bool, micAllowed: Bool) -> CaptureOptions {
        var o = CaptureOptions()
        o.fps = fps
        o.systemAudio = systemAudio == .all
        o.microphone = micEnabled && micAllowed
        o.camera = cameraEnabled && cameraAllowed
        o.cursorInVideo = bakeCursor
        o.hideDesktopIcons = hideDesktopIcons
        o.micDeviceID = micID
        o.cameraDeviceID = cameraID
        o.cameraDimensions = cameraDimensions
        return o
    }

    var selectedCamera: AVCaptureDevice? {
        cameraID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
    }
    var selectedMic: AVCaptureDevice? {
        micID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .audio)
    }
}

// MARK: - Microphone level meter

final class MicMeterEngine: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "mic.meter")
    var onLevel: (@Sendable (Float) -> Void)?
    private var running = false

    func start(device: AVCaptureDevice) {
        stop()
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        if session.canAddInput(input) { session.addInput(input) }
        let out = AVCaptureAudioDataOutput()
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
        queue.async { [session] in session.startRunning() }
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        queue.async { [session] in session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var size = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &size, bufferListOut: nil, bufferListSize: 0,
                                                                blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard size > 0 else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: size,
                                                                      blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr,
              let asbd = CMSampleBufferGetFormatDescription(sampleBuffer).flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }) else { return }
        var peak: Float = 0
        for buf in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = buf.mData else { continue }
            if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                let p = data.assumingMemoryBound(to: Float.self)
                for i in 0..<Int(buf.mDataByteSize) / 4 { peak = max(peak, abs(p[i])) }
            } else {
                let p = data.assumingMemoryBound(to: Int16.self)
                for i in 0..<Int(buf.mDataByteSize) / 2 { peak = max(peak, abs(Float(p[i])) / 32768) }
            }
        }
        onLevel?(peak)
    }
}

@MainActor
final class MicMeter: ObservableObject {
    @Published var level: Float = 0
    private let engine = MicMeterEngine()
    init() {
        engine.onLevel = { [weak self] v in Task { @MainActor in self?.level = max(v, (self?.level ?? 0) * 0.82) } }
    }
    func start(device: AVCaptureDevice?) { if let device { engine.start(device: device) } }
    func stop() { engine.stop(); level = 0 }
}

// MARK: - Camera preview

final class CameraPreviewController: ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.preview")
    func start(device: AVCaptureDevice) {
        queue.async { [session] in
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
    }
    func stop() { queue.async { [session] in if session.isRunning { session.stopRunning() } } }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        v.layer = layer
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
