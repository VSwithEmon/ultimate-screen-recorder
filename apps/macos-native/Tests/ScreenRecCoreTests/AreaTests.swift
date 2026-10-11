import AVFoundation
import XCTest
@testable import ScreenRecCore

final class AreaSelectionTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testPixelConversionRetina() {
        let a = AreaSelection(rect: CGRect(x: 100, y: 50, width: 646.5, height: 345.5))
        XCTAssertEqual(a.pixelSize(scale: 2).w, 1293)
        XCTAssertEqual(a.pixelSize(scale: 2).h, 691)
        XCTAssertEqual(a.pixelOrigin(scale: 2).x, 200)
        XCTAssertEqual(a.captureSize(scale: 2), CGSize(width: 1292, height: 690))   // even for H.264
    }

    func testSetPixelSizeAndOriginClampToBounds() {
        var a = AreaSelection(rect: CGRect(x: 1300, y: 800, width: 100, height: 80))
        a.setPixelSize(w: 400, h: nil, scale: 2, bounds: bounds, ratio: nil)
        XCTAssertEqual(a.rect.width, 200)
        XCTAssertTrue(bounds.contains(a.rect), "stays inside the display: \(a.rect)")
        a.setPixelOrigin(x: 99999, y: -50, scale: 2, bounds: bounds)
        XCTAssertEqual(a.rect.maxX, bounds.maxX); XCTAssertEqual(a.rect.minY, 0)
    }

    func testRatioLockOnSizeEntry() {
        var a = AreaSelection(rect: CGRect(x: 100, y: 100, width: 320, height: 240))
        a.setPixelSize(w: 640, h: nil, scale: 1, bounds: bounds, ratio: 16.0 / 9)
        XCTAssertEqual(a.rect.width / a.rect.height, 16.0 / 9, accuracy: 0.001)
    }

    func testApplyRatioKeepsCentreAndFits() {
        var a = AreaSelection(rect: CGRect(x: 400, y: 300, width: 400, height: 400))
        a.applyRatio(16.0 / 9, bounds: bounds)
        XCTAssertEqual(a.rect.width / a.rect.height, 16.0 / 9, accuracy: 0.001)
        XCTAssertEqual(a.rect.midX, 600, accuracy: 0.5)
        var big = AreaSelection(rect: CGRect(x: 0, y: 0, width: 1440, height: 900))
        big.applyRatio(1, bounds: bounds)
        XCTAssertTrue(bounds.contains(big.rect)); XCTAssertEqual(big.rect.width, big.rect.height, accuracy: 0.5)
    }

    func testDragEachHandleMovesOnlyItsEdges() {
        let start = CGRect(x: 400, y: 300, width: 400, height: 300)
        func dragged(_ h: AreaSelection.Handle, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
            var a = AreaSelection(rect: start); a.drag(h, by: CGSize(width: dx, height: dy), bounds: bounds, ratio: nil); return a.rect
        }
        XCTAssertEqual(dragged(.right, 50, 99), CGRect(x: 400, y: 300, width: 450, height: 300))
        XCTAssertEqual(dragged(.left, -50, 99), CGRect(x: 350, y: 300, width: 450, height: 300))
        XCTAssertEqual(dragged(.bottom, 99, 40), CGRect(x: 400, y: 300, width: 400, height: 340))
        XCTAssertEqual(dragged(.top, 99, -40), CGRect(x: 400, y: 260, width: 400, height: 340))
        XCTAssertEqual(dragged(.bottomRight, 10, 20), CGRect(x: 400, y: 300, width: 410, height: 320))
        XCTAssertEqual(dragged(.topLeft, 10, 20), CGRect(x: 410, y: 320, width: 390, height: 280))
    }

    func testDragCannotLeaveDisplayOrInvert() {
        var a = AreaSelection(rect: CGRect(x: 1000, y: 600, width: 300, height: 200))
        a.drag(.bottomRight, by: CGSize(width: 5000, height: 5000), bounds: bounds, ratio: nil)
        XCTAssertEqual(a.rect.maxX, 1440); XCTAssertEqual(a.rect.maxY, 900)
        a.drag(.left, by: CGSize(width: 9999, height: 0), bounds: bounds, ratio: nil)
        XCTAssertGreaterThanOrEqual(a.rect.width, 40)
    }

    func testRatioLockedCornerDrag() {
        var a = AreaSelection(rect: CGRect(x: 200, y: 200, width: 320, height: 180))
        a.drag(.bottomRight, by: CGSize(width: 160, height: 5), bounds: bounds, ratio: 16.0 / 9)
        XCTAssertEqual(a.rect.width / a.rect.height, 16.0 / 9, accuracy: 0.001)
        XCTAssertEqual(a.rect.minX, 200); XCTAssertEqual(a.rect.minY, 200)
    }

    func testNegativeOriginMultiDisplayUsesLocalBounds() {
        // A secondary display whose global origin is negative still has local bounds starting at 0.
        let local = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var a = AreaSelection.fromDrag(from: CGPoint(x: 1800, y: 900), to: CGPoint(x: 2500, y: 1200), bounds: local)
        XCTAssertEqual(a.rect, CGRect(x: 1800, y: 900, width: 120, height: 180))
        a.move(by: CGSize(width: -3000, height: -3000), bounds: local)
        XCTAssertEqual(a.rect.origin, .zero)
        let n = AreaSelection(rect: CGRect(x: 480, y: 270, width: 960, height: 540)).normalized(in: local)
        XCTAssertEqual(n, NormRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5))
    }

    func testSavedAreaSurvivesScaleChange() {
        let saved = SavedArea(name: "Demo", width: 1293, height: 691, x: 0, y: 156)
        let at2x = saved.selection(scale: 2, bounds: bounds)
        XCTAssertEqual(at2x.pixelSize(scale: 2).w, 1293)
        let tooBig = SavedArea(name: "Huge", width: 9000, height: 9000, x: 0, y: 0).selection(scale: 1, bounds: bounds)
        XCTAssertTrue(bounds.contains(tooBig.rect))
        let data = try? JSONEncoder().encode(saved)
        XCTAssertEqual(try? JSONDecoder().decode(SavedArea.self, from: data!), saved)
    }

    func testCursorMappedIntoAreaRegion() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("area-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var (project, url) = try await TestMedia.makeProject(in: dir, seconds: 1, cursor: [
            CursorEvent(t: 0, x: 0.5, y: 0.5, kind: .move), CursorEvent(t: 1, x: 0.5, y: 0.5, kind: .move)])
        // Recorded region = right-bottom quarter; the display-centre cursor sits at the region's top-left corner.
        project.capture?.region = NormRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5)
        try ProjectStore.save(project, to: url)
        let session = try await EditorSession(project: project, packageURL: url)
        let p = try XCTUnwrap(session.cursor.rawPosition(at: 0.5))
        XCTAssertEqual(p.x, 0, accuracy: 1e-9); XCTAssertEqual(p.y, 0, accuracy: 1e-9)
    }
}

final class OffsetSanityTests: XCTestCase {
    /// Regression: an early build stored the camera start on a different clock (-374,332 s), making a 104-hour timeline.
    func testAbsurdCameraOffsetDoesNotWreckTheTimeline() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("offset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var (project, url) = try await TestMedia.makeProject(in: dir, seconds: 2, micOffset: 0.1)
        try FileManager.default.copyItem(at: url.appendingPathComponent("Media/screen.mov"), to: url.appendingPathComponent("Media/camera.mov"))
        project.sources.append(Source(id: "camera1", type: .camera, path: "Media/camera.mov", startOffset: -374332.384))
        try ProjectStore.save(project, to: url)
        let session = try await EditorSession(project: project, packageURL: url)
        XCTAssertLessThan(session.timelineDuration, 5, "timeline must be about 2 s, not \(session.timelineDuration)")
        XCTAssertNotNil(session.cameraSize)
        let tl = try session.makeTimeline()
        XCTAssertEqual(tl.duration, session.timelineDuration, accuracy: 0.01)
    }
}

/// Loads a real project when PROJECT_PATH is set (diagnostics only; prints timing, never pixels).
final class RealProjectDiagnosticTests: XCTestCase {
    func testLoadRealProject() async throws {
        guard let path = ProcessInfo.processInfo.environment["PROJECT_PATH"] else { return }
        let url = URL(fileURLWithPath: path)
        let project = try ProjectStore.load(from: url)
        let t0 = Date()
        for src in project.sources {
            let a = AVURLAsset(url: ProjectStore.resolve(src, in: url))
            let d = try await a.load(.duration).seconds
            let tr = try await a.load(.tracks).first
            let range = try await tr?.load(.timeRange)
            print("DIAG source \(src.type) offset=\(src.startOffset) duration=\(d) trackRange=\(range?.start.seconds ?? -1)..\(range?.end.seconds ?? -1)")
        }
        let session = try await EditorSession(project: project, packageURL: url)
        let loadMs = Int(Date().timeIntervalSince(t0) * 1000)
        let tl = try session.makeTimeline()
        print("DIAG load=\(loadMs)ms timelineDuration=\(session.timelineDuration)s trimmed=\(tl.duration)s cursorEvents=\(session.cursor.events.count) camera=\(session.cameraSize != nil) source=\(session.sourceSize)")
        XCTAssertLessThan(session.timelineDuration, 3600)
    }
}

final class StaleFirstFrameTests: XCTestCase {
    /// A camera file whose first frame is stamped 0 and the rest 4000 s later must be repaired to its real length.
    func testCameraWithStaleFirstSampleIsRepaired() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var (project, url) = try await TestMedia.makeProject(in: dir, seconds: 2)

        let cam = url.appendingPathComponent("Media/camera.mov")
        let writer = try AVAssetWriter(outputURL: cam, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        func frame(at seconds: Double) async throws {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            XCTAssertTrue(adaptor.append(pb!, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 600)))
        }
        try await frame(at: 0)                       // stale frame
        for i in 0..<30 { try await frame(at: 4000 + Double(i) / 30) }   // real frames, ~1 s
        input.markAsFinished(); await writer.finishWriting()
        let brokenDuration = try await AVURLAsset(url: cam).load(.duration).seconds
        XCTAssertGreaterThan(brokenDuration, 3600, "precondition: the broken file is huge")

        project.sources.append(Source(id: "camera1", type: .camera, path: "Media/camera.mov", startOffset: 0))
        try ProjectStore.save(project, to: url)
        let session = try await EditorSession(project: project, packageURL: url)
        XCTAssertLessThan(session.timelineDuration, 5)
        let tl = try session.makeTimeline()
        XCTAssertNotNil(tl.cameraID)
        XCTAssertLessThan(tl.composition.duration.seconds, 5)
    }
}
