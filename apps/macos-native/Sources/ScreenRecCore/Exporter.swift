import AVFoundation
import CoreMedia

public struct ExportRequest {
    public var session: EditorSession
    public var edit: EditState
    public var outputURL: URL
    /// Canvas height in pixels (720, 1080, 1440, 2160…); width follows the aspect ratio.
    public var height: Int
    public var fps: Int
    /// nil = derived from pixel count (~0.1 bit/pixel/frame, 4 Mbps floor).
    public var videoBitrate: Int?
    public var codec: AVVideoCodecType

    public init(session: EditorSession, edit: EditState, outputURL: URL, height: Int = 1080, fps: Int = 30,
                videoBitrate: Int? = nil, codec: AVVideoCodecType = .h264) {
        self.session = session; self.edit = edit; self.outputURL = outputURL
        self.height = height; self.fps = fps; self.videoBitrate = videoBitrate; self.codec = codec
    }
}

public enum ExportError: Error, LocalizedError {
    case invalidDimensions
    case readerFailed(String)
    case writerFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: return "Export dimensions must be positive."
        case .readerFailed(let m): return "Reading source media failed: \(m)"
        case .writerFailed(let m): return "Writing the export failed: \(m)"
        case .cancelled: return "Export cancelled."
        }
    }
}

/// Renders the trimmed timeline through the same compositor as the preview, then encodes H.264/HEVC + AAC.
/// Output goes to a hidden temp file and is moved into place on success, so failures never leave a corrupt file.
public final class Exporter: @unchecked Sendable {
    public init() {}

    private let stateLock = NSLock()
    private var cancelFlag = false
    private var isCancelled: Bool { stateLock.lock(); defer { stateLock.unlock() }; return cancelFlag }
    public func cancel() { stateLock.lock(); cancelFlag = true; stateLock.unlock() }

    public func export(_ job: ExportRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard job.height >= 2, job.fps > 0 else { throw ExportError.invalidDimensions }
        let session = job.session
        let timeline = try session.makeTimeline(trimStart: job.edit.trimStart, trimEnd: job.edit.trimEnd)
        let videoComposition = session.videoComposition(for: timeline, edit: job.edit, outputHeight: job.height, fps: job.fps)
        let size = videoComposition.renderSize
        let composition = timeline.composition

        let reader = try AVAssetReader(asset: composition)
        let videoOut = AVAssetReaderVideoCompositionOutput(
            videoTracks: composition.tracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOut.videoComposition = videoComposition
        reader.add(videoOut)

        let audioTracks = composition.tracks(withMediaType: .audio)
        var audioOut: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
            out.audioMix = session.audioMix(for: timeline, edit: job.edit)
            reader.add(out)
            audioOut = out
        }

        let fm = FileManager.default
        let tempURL = job.outputURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial.mp4")
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let bitrate = job.videoBitrate ?? max(4_000_000, Int(Double(Int(size.width) * Int(size.height) * job.fps) * 0.1))
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: job.codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: job.fps,
                AVVideoMaxKeyFrameIntervalKey: job.fps * 2,
            ],
        ])
        vInput.expectsMediaDataInRealTime = false
        writer.add(vInput)
        var aInput: AVAssetWriterInput?
        if audioOut != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            aInput = input
        }

        guard reader.startReading() else { throw ExportError.readerFailed(reader.error?.localizedDescription ?? "unknown") }
        guard writer.startWriting() else { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown") }
        writer.startSession(atSourceTime: .zero)

        let total = max(timeline.duration, 0.001)
        let group = DispatchGroup()
        func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, label: String, reportsProgress: Bool) {
            group.enter()
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "export.\(label)")) { [self] in
                while input.isReadyForMoreMediaData {
                    if isCancelled { input.markAsFinished(); group.leave(); return }
                    guard let sample = output.copyNextSampleBuffer() else { input.markAsFinished(); group.leave(); return }
                    if !input.append(sample) { input.markAsFinished(); group.leave(); return }
                    if reportsProgress { progress(min(1, CMSampleBufferGetPresentationTimeStamp(sample).seconds / total)) }
                }
            }
        }
        pump(vInput, videoOut, label: "video", reportsProgress: true)
        if let aInput, let audioOut { pump(aInput, audioOut, label: "audio", reportsProgress: false) }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in group.notify(queue: .global()) { c.resume() } }

        if isCancelled {
            reader.cancelReading(); writer.cancelWriting(); try? fm.removeItem(at: tempURL)
            throw ExportError.cancelled
        }
        if reader.status == .failed {
            writer.cancelWriting(); try? fm.removeItem(at: tempURL)
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? fm.removeItem(at: tempURL)
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
        if fm.fileExists(atPath: job.outputURL.path) { try fm.removeItem(at: job.outputURL) }
        try fm.moveItem(at: tempURL, to: job.outputURL)
        progress(1)
    }
}
