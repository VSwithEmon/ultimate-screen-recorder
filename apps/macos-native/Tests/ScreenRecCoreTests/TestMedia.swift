import AVFoundation
import CoreImage
import XCTest
@testable import ScreenRecCore

enum TestMedia {
    /// Left half red, right half blue so zoom/crop/mask placement is checkable.
    static func makeVideo(at url: URL, seconds: Int, fps: Int = 30, size: CGSize = CGSize(width: 640, height: 360)) async throws {
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
            let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buf)
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    let p = base + y * stride + x * 4
                    if x < Int(size.width) / 2 { p[0] = 0; p[1] = 0; p[2] = 255 } else { p[0] = 255; p[1] = 0; p[2] = 0 } // BGRA
                    p[3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buf, [])
            XCTAssertTrue(adaptor.append(buf, withPresentationTime: CMTime(value: Int64(i), timescale: CMTimeScale(fps))))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    static func makeAudio(at url: URL, seconds: Double) throws {
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

    /// Creates a real project package on disk from synthetic media.
    static func makeProject(in dir: URL, seconds: Int = 2, micOffset: Double? = nil, edit: EditState = EditState(),
                            cursor: [CursorEvent]? = nil) async throws -> (Project, URL) {
        var (project, url) = try ProjectStore.create(name: "Test", in: dir)
        try await makeVideo(at: url.appendingPathComponent("Media/screen.mov"), seconds: seconds)
        project.sources = [Source(id: "screen1", type: .screen, path: "Media/screen.mov", startOffset: 0)]
        if let off = micOffset {
            try makeAudio(at: url.appendingPathComponent("Media/mic.m4a"), seconds: Double(seconds))
            project.sources.append(Source(id: "mic1", type: .microphone, path: "Media/mic.m4a", startOffset: off))
        }
        if let cursor {
            let log = try CursorEventLog(url: url.appendingPathComponent("Metadata/cursor.jsonl"))
            cursor.forEach(log.append); log.close()
            project.cursorEventsPath = "Metadata/cursor.jsonl"
        }
        project.capture = CaptureInfo(displayFrame: CGRect(x: 0, y: 0, width: 1280, height: 720), pixelWidth: 640, pixelHeight: 360,
                                      scale: 0.5, cursorBakedIntoVideo: false)
        project.edit = edit
        try ProjectStore.save(project, to: url)
        try ProjectStore.markFinalized(at: url)
        return (project, url)
    }

    /// Solid-colour halves image (left red, right blue), CI origin bottom-left.
    static func halvesImage(size: CGSize = CGSize(width: 640, height: 360)) -> CIImage {
        let left = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        let right = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        return right.composited(over: left)
    }

    /// RGBA 0...255 at output pixel (x from left, y from top).
    static func pixel(_ image: CIImage, size: CGSize, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var px = [UInt8](repeating: 0, count: 4)
        let ciY = Int(size.height) - 1 - y
        FrameRenderer.ciContext.render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: x, y: ciY, width: 1, height: 1),
                                       format: .RGBA8, colorSpace: FrameRenderer.colorSpace)
        return (Int(px[0]), Int(px[1]), Int(px[2]), Int(px[3]))
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}
