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

    func testExport1080p30H264WithAlignedAudio() async throws {
        // Audio starts 0.5 s after the video on the shared clock: output must run 2.5 s.
        let (project, url) = try await TestMedia.makeProject(in: dir, micOffset: 0.5)
        let session = try await EditorSession(project: project, packageURL: url)
        let out = dir.appendingPathComponent("out.mp4")
        let last = LockedBox<Double>(0)
        try await Exporter().export(ExportRequest(session: session, edit: project.edit, outputURL: out, height: 1080, fps: 30)) { last.value = $0 }
        XCTAssertEqual(last.value, 1, accuracy: 1e-9)

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
        let aRange = try await aTrack.load(.timeRange)
        XCTAssertEqual(aRange.end.seconds, 2.5, accuracy: 0.15)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".partial") }.isEmpty)
    }

    func testExportedFrameMatchesEditsAndAspect() async throws {
        var edit = EditState()
        edit.aspect = .square
        edit.padding = 0.1
        edit.cornerRadius = 0.1
        edit.shadow = false
        edit.background.kind = .color
        edit.background.colorA = RGBA(0, 1, 0)
        let (project, url) = try await TestMedia.makeProject(in: dir, seconds: 1, edit: edit)
        let session = try await EditorSession(project: project, packageURL: url)
        let out = dir.appendingPathComponent("square.mp4")
        try await Exporter().export(ExportRequest(session: session, edit: edit, outputURL: out, height: 720, fps: 30)) { _ in }

        let asset = AVURLAsset(url: out)
        let vTracks = try await asset.loadTracks(withMediaType: .video)
        let size = try await XCTUnwrap(vTracks.first).load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 720, height: 720), "1:1 canvas")

        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let cg = try gen.copyCGImage(at: CMTime(value: 3, timescale: 30), actualTime: nil)
        let ci = CIImage(cgImage: cg)
        let s = CGSize(width: cg.width, height: cg.height)
        func isGreen(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.g > 200 && p.r < 60 && p.b < 60 }
        // Padding = green; centre-left = red, centre-right = blue (source halves); frame corner rounded = green.
        XCTAssertTrue(isGreen(TestMedia.pixel(ci, size: s, x: 10, y: 360)), "padding")
        let left = TestMedia.pixel(ci, size: s, x: 250, y: 360), right = TestMedia.pixel(ci, size: s, x: 470, y: 360)
        XCTAssertTrue(left.r > 200 && left.b < 60, "left half red: \(left)")
        XCTAssertTrue(right.b > 200 && right.r < 60, "right half blue: \(right)")
        // Frame is 576 wide at x=72..648, 324 tall at y=198..522; its extreme corner must be cut by the radius.
        XCTAssertTrue(isGreen(TestMedia.pixel(ci, size: s, x: 74, y: 200)), "rounded corner")
    }

    func testTrimShortensOutput() async throws {
        var edit = EditState()
        edit.trimStart = 0.5
        edit.trimEnd = 1.5
        let (project, url) = try await TestMedia.makeProject(in: dir, seconds: 2, micOffset: 0, edit: edit)
        let session = try await EditorSession(project: project, packageURL: url)
        let out = dir.appendingPathComponent("trim.mp4")
        try await Exporter().export(ExportRequest(session: session, edit: edit, outputURL: out)) { _ in }
        let d = try await AVURLAsset(url: out).load(.duration).seconds
        XCTAssertEqual(d, 1.0, accuracy: 0.15)
    }

    func testCancellationLeavesNoOutput() async throws {
        let (project, url) = try await TestMedia.makeProject(in: dir, seconds: 2)
        let session = try await EditorSession(project: project, packageURL: url)
        let out = dir.appendingPathComponent("out.mp4")
        let exporter = Exporter()
        exporter.cancel()
        do {
            try await exporter.export(ExportRequest(session: session, edit: project.edit, outputURL: out)) { _ in }
            XCTFail("expected cancel")
        } catch { guard case ExportError.cancelled = error else { return XCTFail("wrong error \(error)") } }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".partial") }.isEmpty)
    }
}
