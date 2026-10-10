import AVFoundation
import CoreMedia

public struct ExportJob {
    public struct Stream {
        public var url: URL
        /// Seconds from the shared recording clock origin to this stream's first sample.
        public var offset: Double
        public init(url: URL, offset: Double) { self.url = url; self.offset = offset }
    }

    public var video: Stream
    public var audio: [Stream]
    public var outputURL: URL
    public var width: Int
    public var height: Int
    public var fps: Int
    /// nil = derive from pixel count (~0.1 bit per pixel per frame, 4 Mbps floor).
    public var videoBitrate: Int?

    public init(video: Stream, audio: [Stream], outputURL: URL, width: Int = 1920, height: Int = 1080, fps: Int = 30, videoBitrate: Int? = nil) {
        self.video = video; self.audio = audio; self.outputURL = outputURL
        self.width = width; self.height = height; self.fps = fps; self.videoBitrate = videoBitrate
    }
}

public enum ExportError: Error, LocalizedError {
    case noVideoTrack
    case invalidDimensions
    case readerFailed(String)
    case writerFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The screen recording contains no video track."
        case .invalidDimensions: return "Export dimensions must be positive and even."
        case .readerFailed(let m): return "Reading source media failed: \(m)"
        case .writerFailed(let m): return "Writing the export failed: \(m)"
        case .cancelled: return "Export cancelled."
        }
    }
}

/// Phase 0 exporter: AVMutableComposition (aligns streams) -> reader -> H.264/AAC MP4.
/// Writes to a hidden temp file and moves into place on success, so a failed or cancelled export never leaves a corrupt file.
public final class Exporter: @unchecked Sendable {
    public init() {}

    private let stateLock = NSLock()
    private var cancelFlag = false
    private var isCancelled: Bool { stateLock.lock(); defer { stateLock.unlock() }; return cancelFlag }

    public func cancel() { stateLock.lock(); cancelFlag = true; stateLock.unlock() }

    public func export(_ job: ExportJob, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard job.width > 0, job.height > 0, job.width % 2 == 0, job.height % 2 == 0 else { throw ExportError.invalidDimensions }

        // ---- Build composition -------------------------------------------------
        let composition = AVMutableComposition()
        let origin = min(job.video.offset, job.audio.map(\.offset).min() ?? job.video.offset)

        let vAsset = AVURLAsset(url: job.video.url)
        guard let vTrack = try await vAsset.loadTracks(withMediaType: .video).first else { throw ExportError.noVideoTrack }
        let vDuration = try await vAsset.load(.duration)
        let naturalSize = try await vTrack.load(.naturalSize)
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.readerFailed("could not create composition video track")
        }
        let vStart = CMTime(seconds: job.video.offset - origin, preferredTimescale: 60000)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: vDuration), of: vTrack, at: vStart)

        for stream in job.audio {
            let aAsset = AVURLAsset(url: stream.url)
            guard let aTrack = try await aAsset.loadTracks(withMediaType: .audio).first else { continue }
            let aDuration = try await aAsset.load(.duration)
            guard let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let at = CMTime(seconds: stream.offset - origin, preferredTimescale: 60000)
            try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: aDuration), of: aTrack, at: at)
        }

        let totalDuration = composition.duration

        // ---- Video composition: aspect-fit into the output canvas --------------
        let renderSize = CGSize(width: job.width, height: job.height)
        let fit = min(renderSize.width / naturalSize.width, renderSize.height / naturalSize.height)
        let scaled = CGSize(width: naturalSize.width * fit, height: naturalSize.height * fit)
        let transform = CGAffineTransform(scaleX: fit, y: fit)
            .concatenating(CGAffineTransform(translationX: (renderSize.width - scaled.width) / 2,
                                             y: (renderSize.height - scaled.height) / 2))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(job.fps))
        videoComposition.instructions = [instruction]

        // ---- Reader ------------------------------------------------------------
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
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            reader.add(out)
            audioOut = out
        }

        // ---- Writer ------------------------------------------------------------
        let fm = FileManager.default
        let tempURL = job.outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).partial.mp4")
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let bitrate = job.videoBitrate ?? max(4_000_000, Int(Double(job.width * job.height * job.fps) * 0.1))
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: job.width,
            AVVideoHeightKey: job.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: job.fps,
                AVVideoMaxKeyFrameIntervalKey: job.fps * 2,
            ],
        ])
        vInput.expectsMediaDataInRealTime = false
        writer.add(vInput)
        var aInput: AVAssetWriterInput?
        if audioOut != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            aInput = input
        }

        guard reader.startReading() else {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        // ---- Pump --------------------------------------------------------------
        let total = max(totalDuration.seconds, 0.001)
        let group = DispatchGroup()

        func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, label: String, reportsProgress: Bool) {
            group.enter()
            let queue = DispatchQueue(label: "export.\(label)")
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while input.isReadyForMoreMediaData {
                    if isCancelled { input.markAsFinished(); group.leave(); return }
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished(); group.leave(); return
                    }
                    if !input.append(sample) { input.markAsFinished(); group.leave(); return }
                    if reportsProgress {
                        progress(min(1, CMSampleBufferGetPresentationTimeStamp(sample).seconds / total))
                    }
                }
            }
        }

        pump(vInput, videoOut, label: "video", reportsProgress: true)
        if let aInput, let audioOut { pump(aInput, audioOut, label: "audio", reportsProgress: false) }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { c.resume() }
        }

        // ---- Finish ------------------------------------------------------------
        if isCancelled {
            reader.cancelReading(); writer.cancelWriting()
            try? fm.removeItem(at: tempURL)
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
