import AVFoundation
import CoreMedia
import ScreenCaptureKit
import ScreenRecCore

struct CaptureOptions {
    var fps = 30
    var systemAudio = true
    var microphone = true
    var camera = false
    /// Phase 0 fallback: the cursor engine (Phase 3) does not exist yet, so bake the OS cursor into the video.
    var cursorInVideo = true
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
        if firstPTS == nil {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: pts)
            firstPTS = pts
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { droppedSamples += 1; return }
        if !input.append(sample) { droppedSamples += 1 }
    }

    /// Returns false if no sample ever arrived (file is removed).
    func finish() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            queue.async { [self] in
                guard firstPTS != nil else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    c.resume(returning: false); return
                }
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
        case .noDisplay: return "No capturable display was found."
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
    var onError: (@Sendable (String) -> Void)?

    init(projectURL: URL, options: CaptureOptions) {
        self.projectURL = projectURL
        self.options = options
        self.t0 = CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }

    func start() async throws -> CaptureInfo {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let filterInfo = SCShareableContent.info(for: filter)
        let scale = CGFloat(filterInfo.pointPixelScale)
        let width = Geometry.evenPixels(filterInfo.contentRect.width * scale)
        let height = Geometry.evenPixels(filterInfo.contentRect.height * scale)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = options.cursorInVideo
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
                                      scale: Double(scale), cursorBakedIntoVideo: options.cursorInVideo)
        info = captureInfo
        return captureInfo
    }

    private func startDevices() throws {
        let session = AVCaptureSession()
        if let micWriter {
            guard let device = AVCaptureDevice.default(for: .audio) else { throw CaptureError.writerSetup("no microphone available") }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CaptureError.writerSetup("cannot use microphone input") }
            session.addInput(input)
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: micWriter.queue)
            guard session.canAddOutput(output) else { throw CaptureError.writerSetup("cannot read microphone samples") }
            session.addOutput(output)
        }
        if options.camera {
            guard let device = AVCaptureDevice.default(for: .video) else { throw CaptureError.writerSetup("no camera available") }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CaptureError.writerSetup("cannot use camera input") }
            session.addInput(input)
            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let w = Geometry.evenPixels(CGFloat(dims.width)), h = Geometry.evenPixels(CGFloat(dims.height))
            let writer = try StreamFileWriter(
                url: projectURL.appendingPathComponent("Media/camera.mov"), fileType: .mov, mediaType: .video,
                settings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
                           AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h * 4]], label: "camera")
            cameraWriter = writer
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: writer.queue)
            guard session.canAddOutput(output) else { throw CaptureError.writerSetup("cannot read camera frames") }
            session.addOutput(output)
            cameraOutput = output
        }
        session.startRunning()
        micSession = session
    }

    func stop() async throws -> CaptureResult {
        micSession?.stopRunning()
        try? await stream?.stopCapture()
        stream = nil

        var sources: [Source] = []
        func offset(_ w: StreamFileWriter) -> Double { (w.firstPTS?.seconds ?? t0) - t0 }

        if let w = videoWriter, await w.finish() {
            sources.append(Source(id: "screen1", type: .screen, path: "Media/screen.mov", startOffset: offset(w)))
        }
        if let w = systemWriter, await w.finish() {
            sources.append(Source(id: "system1", type: .systemAudio, path: "Media/system.m4a", startOffset: offset(w)))
        }
        if let w = cameraWriter, await w.finish() {
            sources.append(Source(id: "camera1", type: .camera, path: "Media/camera.mov", startOffset: offset(w)))
        }
        if let w = micWriter, await w.finish() {
            sources.append(Source(id: "mic1", type: .microphone, path: "Media/mic.m4a", startOffset: offset(w)))
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
