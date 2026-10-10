import XCTest
import AVFoundation
@testable import ScreenRecCore

final class ExportSmokeTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("screenrec-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: synthetic media

    func makeVideo(at url: URL, seconds: Int, fps: Int = 30, size: CGSize = CGSize(width: 640, height: 360)) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for i in 0..<(seconds * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            let buf = pb!
            CVPixelBufferLockBaseAddress(buf, [])
            memset(CVPixelBufferGetBaseAddress(buf), Int32(i * 4 % 256), CVPixelBufferGetDataSize(buf))
            CVPixelBufferUnlockBaseAddress(buf, [])
            XCTAssertTrue(adaptor.append(buf, withPresentationTime: CMTime(value: Int64(i), timescale: CMTimeScale(fps))))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    func makeAudio(at url: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2])
        let frames = AVAudioFrameCount(seconds * 48000)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<2 {
            let p = buf.floatChannelData![ch]
            for n in 0..<Int(frames) { p[n] = 0.3 * sinf(2 * .pi * 440 * Float(n) / 48000) }
        }
        try file.write(from: buf)
    }

    // MARK: tests

    func testExport1080p30H264WithAlignedAudio() async throws {
        let v = dir.appendingPathComponent("screen.mov")
        let a = dir.appendingPathComponent("mic.m4a")
        let out = dir.appendingPathComponent("out.mp4")
        try await makeVideo(at: v, seconds: 2)
        try makeAudio(at: a, seconds: 2)

        // Audio starts 0.5 s after the video on the shared clock: output must run 2.5 s.
        let job = ExportJob(video: .init(url: v, offset: 0), audio: [.init(url: a, offset: 0.5)],
                            outputURL: out, width: 1920, height: 1080, fps: 30)
        let lastProgress = LockedBox<Double>(0)
        try await Exporter().export(job) { lastProgress.value = $0 }
        XCTAssertEqual(lastProgress.value, 1, accuracy: 1e-9)

        let asset = AVURLAsset(url: out)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2.5, accuracy: 0.15)

        let vTracks = try await asset.loadTracks(withMediaType: .video); let vTrack = try XCTUnwrap(vTracks.first)
        let size = try await vTrack.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
        let fps = try await vTrack.load(.nominalFrameRate)
        XCTAssertEqual(fps, 30, accuracy: 1)
        let fmt = try await vTrack.load(.formatDescriptions).first
        XCTAssertEqual(fmt.map { CMFormatDescriptionGetMediaSubType($0) }, kCMVideoCodecType_H264)

        let aTracks = try await asset.loadTracks(withMediaType: .audio); let aTrack = try XCTUnwrap(aTracks.first)
        // Audio track must begin ~0.5 s into the output (leading silence/empty edit), proving alignment.
        let aRange = try await aTrack.load(.timeRange)
        XCTAssertEqual(aRange.end.seconds, 2.5, accuracy: 0.15)

        // No partial files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".partial") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testVideoOnlyExport() async throws {
        let v = dir.appendingPathComponent("screen.mov")
        let out = dir.appendingPathComponent("out.mp4")
        try await makeVideo(at: v, seconds: 1)
        try await Exporter().export(ExportJob(video: .init(url: v, offset: 0), audio: [], outputURL: out,
                                              width: 1280, height: 720, fps: 30)) { _ in }
        let asset = AVURLAsset(url: out)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
        let dur = try await asset.load(.duration).seconds; XCTAssertEqual(dur, 1, accuracy: 0.1)
    }

    func testOddDimensionsRejected() async throws {
        let v = dir.appendingPathComponent("screen.mov")
        try await makeVideo(at: v, seconds: 1)
        do {
            try await Exporter().export(ExportJob(video: .init(url: v, offset: 0), audio: [],
                                                  outputURL: dir.appendingPathComponent("o.mp4"), width: 1281, height: 720)) { _ in }
            XCTFail("expected failure")
        } catch { guard case ExportError.invalidDimensions = error else { return XCTFail("wrong error \(error)") } }
    }

    func testCancellationLeavesNoOutput() async throws {
        let v = dir.appendingPathComponent("screen.mov")
        let out = dir.appendingPathComponent("out.mp4")
        try await makeVideo(at: v, seconds: 3)
        let exporter = Exporter()
        exporter.cancel()
        do {
            try await exporter.export(ExportJob(video: .init(url: v, offset: 0), audio: [], outputURL: out)) { _ in }
            XCTFail("expected cancel")
        } catch { guard case ExportError.cancelled = error else { return XCTFail("wrong error \(error)") } }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".partial") }.isEmpty)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}
