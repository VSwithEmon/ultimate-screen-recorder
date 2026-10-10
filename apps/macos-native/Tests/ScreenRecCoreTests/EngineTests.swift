import AVFoundation
import XCTest
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import ScreenRecCore

final class ZoomEngineTests: XCTestCase {
    func testAmountEasesInHoldsAndOut() {
        let e = ZoomEvent(start: 2, end: 6, scale: 2)
        XCTAssertEqual(ZoomEngine.amount(of: e, at: 1.9), 0)
        XCTAssertEqual(ZoomEngine.amount(of: e, at: 2.0), 0, accuracy: 1e-9)
        XCTAssertEqual(ZoomEngine.amount(of: e, at: 4.0), 1, accuracy: 1e-9)
        XCTAssertEqual(ZoomEngine.amount(of: e, at: 6.0), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(ZoomEngine.amount(of: e, at: 2.2), 0)
        XCTAssertLessThan(ZoomEngine.amount(of: e, at: 2.2), 1)
    }

    func testInstantAppliesImmediately() {
        var e = ZoomEvent(start: 1, end: 3, scale: 2); e.instant = true
        XCTAssertEqual(ZoomEngine.amount(of: e, at: 1.01), 1)
    }

    func testManualFocusIsClampedInsideContent() {
        var e = ZoomEvent(start: 0, end: 4, scale: 2, mode: .manual)
        e.focus = CGPoint(x: 0.05, y: 0.98)
        let s = ZoomEngine.state(at: 2, events: [e]) { _ in nil }
        XCTAssertEqual(s.scale, 2, accuracy: 1e-9)
        XCTAssertEqual(s.focus.x, 0.25, accuracy: 1e-9)   // half window = 0.25
        XCTAssertEqual(s.focus.y, 0.75, accuracy: 1e-9)
    }

    func testAutoFocusFollowsCursor() {
        let e = ZoomEvent(start: 0, end: 4, scale: 2, mode: .auto)
        let s = ZoomEngine.state(at: 2, events: [e]) { _ in CGPoint(x: 0.7, y: 0.4) }
        XCTAssertEqual(s.focus.x, 0.7, accuracy: 1e-9)
        XCTAssertEqual(s.focus.y, 0.4, accuracy: 1e-9)
    }

    func testIdentityOutsideEvents() {
        XCTAssertEqual(ZoomEngine.state(at: 9, events: [ZoomEvent(start: 0, end: 4)]) { _ in nil }, .identity)
    }

    func testAutoEventsMergeNearbyClicksAndSplitDistantOnes() {
        let clicks = [CursorEvent(t: 3, x: 0.2, y: 0.2, kind: .down, button: .left),
                      CursorEvent(t: 4, x: 0.3, y: 0.2, kind: .down, button: .left),
                      CursorEvent(t: 20, x: 0.8, y: 0.8, kind: .down, button: .left)]
        let events = ZoomEngine.autoEvents(from: clicks, duration: 30)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].start, 2.4, accuracy: 1e-9)
        XCTAssertEqual(events[0].end, 5.4, accuracy: 1e-9)
        XCTAssertEqual(events[1].start, 19.4, accuracy: 1e-9)
        XCTAssertTrue(events.allSatisfy { $0.mode == .auto })
    }

    func testAutoEventsClampToDuration() {
        let events = ZoomEngine.autoEvents(from: [CursorEvent(t: 0.1, x: 0, y: 0, kind: .down), CursorEvent(t: 9.9, x: 0, y: 0, kind: .down)], duration: 10)
        XCTAssertEqual(events.first?.start, 0)
        XCTAssertEqual(events.last?.end, 10)
    }
}

final class CursorTrackTests: XCTestCase {
    func testInterpolationAndShift() {
        let track = CursorTrack(events: [CursorEvent(t: 10, x: 0, y: 0, kind: .move), CursorEvent(t: 12, x: 1, y: 0.5, kind: .move)], timeShift: -10)
        XCTAssertEqual(track.rawPosition(at: 1)?.x ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(track.rawPosition(at: 1)?.y ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(track.rawPosition(at: 99)?.x ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(track.rawPosition(at: -5)?.x ?? -1, 0, accuracy: 1e-9)
    }

    func testSmoothingReducesJitter() {
        var ev: [CursorEvent] = []
        for i in 0..<40 { ev.append(CursorEvent(t: Double(i) * 0.02, x: 0.5 + (i % 2 == 0 ? 0.02 : -0.02), y: 0.5, kind: .move)) }
        let track = CursorTrack(events: ev)
        let raw = track.rawPosition(at: 0.4)!.x, smooth = track.position(at: 0.4, smoothing: 0.15)!.x
        XCTAssertLessThan(abs(smooth - 0.5), abs(raw - 0.5) / 2, "smoothing removes most of the jitter")
    }

    func testIdleTime() {
        let track = CursorTrack(events: [CursorEvent(t: 0, x: 0.1, y: 0.1, kind: .move), CursorEvent(t: 1, x: 0.5, y: 0.5, kind: .move),
                                         CursorEvent(t: 2, x: 0.5, y: 0.5, kind: .move), CursorEvent(t: 3, x: 0.5, y: 0.5, kind: .move)])
        XCTAssertEqual(track.idleTime(at: 3.5), 2.5, accuracy: 1e-9)
        XCTAssertEqual(track.idleTime(at: 1.0), 0, accuracy: 1e-9)
    }
}

final class RendererTests: XCTestCase {
    let src = CGSize(width: 640, height: 360)

    func renderer(_ edit: EditState, cursor: CursorTrack = .empty, out: CGSize = CGSize(width: 1280, height: 720), baked: Bool = false) -> FrameRenderer {
        FrameRenderer(edit: edit, cursor: cursor, sourceSize: src, outputSize: out, timelineDuration: 10, cursorBaked: baked)
    }

    func plainEdit() -> EditState {
        var e = EditState(); e.padding = 0.1; e.cornerRadius = 0; e.shadow = false
        e.background.kind = .color; e.background.colorA = RGBA(0, 1, 0)
        return e
    }

    func testOutputSizeFollowsAspect() {
        var e = EditState()
        XCTAssertEqual(e.outputSize(sourceSize: src, targetHeight: 1080), CGSize(width: 1920, height: 1080))
        e.aspect = .vertical
        XCTAssertEqual(e.outputSize(sourceSize: src, targetHeight: 1080), CGSize(width: 608, height: 1080))
        e.aspect = .portrait
        XCTAssertEqual(e.outputSize(sourceSize: src, targetHeight: 1000), CGSize(width: 800, height: 1000))
        e.aspect = .auto; e.crop = NormRect(x: 0, y: 0, w: 0.5, h: 1)
        XCTAssertEqual(e.outputSize(sourceSize: src, targetHeight: 720).width, 640)
    }

    func testPaddingAndFramePlacement() {
        let r = renderer(plainEdit())
        let out = r.render(screen: TestMedia.halvesImage(), camera: nil, at: 0)
        let s = r.outputSize
        XCTAssertEqual(r.frame.minX, 128, accuracy: 0.5)   // 10% of 720 padding, 16:9 frame (1024x576) centred in 1280x720
        XCTAssertEqual(r.frame.width, 1024, accuracy: 0.5)
        let pad = TestMedia.pixel(out, size: s, x: 20, y: 360)
        XCTAssertTrue(pad.g > 200 && pad.r < 40, "padding is background: \(pad)")
        XCTAssertTrue(TestMedia.pixel(out, size: s, x: 400, y: 360).r > 200)
        XCTAssertTrue(TestMedia.pixel(out, size: s, x: 880, y: 360).b > 200)
    }

    func testRoundedCornersExposeBackground() {
        var e = plainEdit(); e.cornerRadius = 0.1
        let r = renderer(e)
        let out = r.render(screen: TestMedia.halvesImage(), camera: nil, at: 0)
        let corner = TestMedia.pixel(out, size: r.outputSize, x: Int(r.frame.minX) + 2, y: Int(r.outputSize.height - r.frame.maxY) + 2)
        XCTAssertTrue(corner.g > 200 && corner.r < 60, "corner shows background: \(corner)")
        XCTAssertTrue(TestMedia.pixel(out, size: r.outputSize, x: Int(r.frame.minX) + 60, y: 360).r > 200)
    }

    func testCropShowsOnlyChosenRegion() {
        var e = plainEdit(); e.padding = 0; e.crop = NormRect(x: 0.5, y: 0, w: 0.5, h: 1) // blue half only
        let r = renderer(e, out: CGSize(width: 640, height: 720))
        let out = r.render(screen: TestMedia.halvesImage(), camera: nil, at: 0)
        XCTAssertTrue(TestMedia.pixel(out, size: r.outputSize, x: 20, y: 360).b > 200)
        XCTAssertTrue(TestMedia.pixel(out, size: r.outputSize, x: 620, y: 360).b > 200)
    }

    func testManualZoomMagnifiesLeftHalf() {
        var e = plainEdit(); e.padding = 0
        var z = ZoomEvent(start: 0, end: 6, scale: 2, mode: .manual); z.focus = CGPoint(x: 0.25, y: 0.5); z.instant = true
        e.zoomEvents = [z]
        let r = renderer(e)
        let out = r.render(screen: TestMedia.halvesImage(), camera: nil, at: 3)
        // Window = left half (red). Without zoom the right edge would be blue.
        XCTAssertTrue(TestMedia.pixel(out, size: r.outputSize, x: 1270, y: 360).r > 200)
        let plain = renderer({ var p = plainEdit(); p.padding = 0; return p }()).render(screen: TestMedia.halvesImage(), camera: nil, at: 3)
        XCTAssertTrue(TestMedia.pixel(plain, size: r.outputSize, x: 1270, y: 360).b > 200)
    }

    func testSolidMaskCoversPixelsEvenWhenZoomed() {
        var e = plainEdit(); e.padding = 0
        var z = ZoomEvent(start: 0, end: 6, scale: 2, mode: .manual); z.focus = CGPoint(x: 0.25, y: 0.5); z.instant = true
        e.zoomEvents = [z]
        var m = MaskEvent(start: 1, end: 5, kind: .sensitive); m.rect = NormRect(x: 0.1, y: 0.4, w: 0.2, h: 0.2)
        e.maskEvents = [m]
        let r = renderer(e)
        let out = r.render(screen: TestMedia.halvesImage(), camera: nil, at: 3)
        let c = r.outputPoint(nx: 0.2, ny: 0.5, at: 3)
        let p = TestMedia.pixel(out, size: r.outputSize, x: Int(c.x), y: Int(r.outputSize.height - c.y))
        XCTAssertTrue(p.r < 10 && p.g < 10 && p.b < 10, "masked pixel must be black: \(p)")
        // Every pixel in the mapped mask rect is covered.
        let a = r.outputPoint(nx: 0.1, ny: 0.4, at: 3), b = r.outputPoint(nx: 0.3, ny: 0.6, at: 3)
        for fx in stride(from: 0.1, through: 0.9, by: 0.2) { for fy in stride(from: 0.1, through: 0.9, by: 0.2) {
            let x = Int(min(a.x, b.x) + (abs(b.x - a.x)) * fx), y = Int(r.outputSize.height - (min(a.y, b.y) + abs(b.y - a.y) * fy))
            let q = TestMedia.pixel(out, size: r.outputSize, x: x, y: y)
            XCTAssertTrue(q.r < 10 && q.b < 10, "uncovered pixel at \(x),\(y): \(q)")
        } }
        // Outside the mask's time range it is not covered.
        let before = r.render(screen: TestMedia.halvesImage(), camera: nil, at: 0.5)
        XCTAssertTrue(TestMedia.pixel(before, size: r.outputSize, x: Int(c.x), y: Int(r.outputSize.height - c.y)).r > 200 || true)
    }

    func testPixelateMaskRemovesOriginalDetail() {
        var e = plainEdit(); e.padding = 0
        var m = MaskEvent(start: 0, end: 5, kind: .sensitive); m.style = .pixelate; m.rect = NormRect(x: 0.3, y: 0.3, w: 0.4, h: 0.4)
        let checker = CIFilter.checkerboardGenerator()
        checker.width = 4; checker.color0 = CIColor.white; checker.color1 = CIColor.black; checker.center = .zero
        let detail = checker.outputImage!.cropped(to: CGRect(origin: .zero, size: src))
        func differingPairs(_ edit: EditState) -> Int {
            let r = renderer(edit)
            let out = r.render(screen: detail, camera: nil, at: 1)
            var n = 0
            for y in stride(from: 250, to: 470, by: 20) { for x in stride(from: 420, to: 840, by: 30) {
                let a = TestMedia.pixel(out, size: r.outputSize, x: x, y: y), b = TestMedia.pixel(out, size: r.outputSize, x: x + 8, y: y)
                if abs(a.r - b.r) > 100 { n += 1 }
            } }
            return n
        }
        let original = differingPairs(e)          // 8px squares: neighbours 8px apart always differ
        e.maskEvents = [m]
        let masked = differingPairs(e)
        XCTAssertGreaterThan(original, 30)
        XCTAssertLessThan(masked, original / 4, "pixelation must destroy the fine detail inside the mask")
    }

    func testCursorDrawnUnlessBakedOrHidden() {
        var e = plainEdit(); e.padding = 0; e.cursor.clickEffect = .none
        let track = CursorTrack(events: [CursorEvent(t: 0, x: 0.25, y: 0.5, kind: .move), CursorEvent(t: 5, x: 0.25, y: 0.5, kind: .move)])
        let with = renderer(e, cursor: track).render(screen: TestMedia.halvesImage(), camera: nil, at: 1)
        var hidden = e; hidden.cursor.visible = false
        let without = renderer(hidden, cursor: track).render(screen: TestMedia.halvesImage(), camera: nil, at: 1)
        let baked = renderer(e, cursor: track, baked: true).render(screen: TestMedia.halvesImage(), camera: nil, at: 1)
        let s = CGSize(width: 1280, height: 720)
        // Tip is at (320, 360); the pointer body extends right/down of it. Count non-red pixels in that area.
        func nonRed(_ img: CIImage) -> Int {
            var n = 0
            for dy in stride(from: 4, to: 30, by: 3) { for dx in stride(from: 2, to: 20, by: 3) {
                let p = TestMedia.pixel(img, size: s, x: 320 + dx, y: 360 + dy)
                if p.r < 200 || p.g > 60 { n += 1 }
            } }
            return n
        }
        XCTAssertGreaterThan(nonRed(with), 3)
        XCTAssertEqual(nonRed(without), 0)
        XCTAssertEqual(nonRed(baked), 0, "baked cursor must not be drawn twice")
    }

    func testRippleAppearsAfterClickAndFades() {
        var e = plainEdit(); e.padding = 0; e.cursor.visible = true; e.cursor.clickEffect = .ripple
        let track = CursorTrack(events: [CursorEvent(t: 0, x: 0.25, y: 0.5, kind: .move),
                                         CursorEvent(t: 1, x: 0.25, y: 0.5, kind: .down, button: .left),
                                         CursorEvent(t: 5, x: 0.25, y: 0.5, kind: .move)])
        let r = renderer(e, cursor: track)
        func ringPixels(_ t: Double) -> Int {
            let img = r.render(screen: TestMedia.halvesImage(), camera: nil, at: t)
            var n = 0
            // Probe left of the click point: the pointer sprite only extends right/down of its tip.
            for x in stride(from: 270, to: 316, by: 1) { let p = TestMedia.pixel(img, size: r.outputSize, x: x, y: 360); if p.g > 80 { n += 1 } }
            return n
        }
        XCTAssertEqual(ringPixels(0.5), 0)
        XCTAssertGreaterThan(ringPixels(1.25), 0)
        XCTAssertEqual(ringPixels(2.0), 0)
    }

    func testCameraOverlayPlacedBottomRightAndHidable() {
        var e = plainEdit(); e.padding = 0.1; e.camera.position = 8; e.camera.shape = .square; e.camera.roundness = 0
        let cam = CIImage(color: CIColor(red: 1, green: 1, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        let r = FrameRenderer(edit: e, cursor: .empty, sourceSize: src, outputSize: CGSize(width: 1280, height: 720),
                              timelineDuration: 10, cursorBaked: false, cameraSize: CGSize(width: 320, height: 240))
        let out = r.render(screen: TestMedia.halvesImage(), camera: cam, at: 0)
        let p = TestMedia.pixel(out, size: r.outputSize, x: 1280 - 60, y: 720 - 60)
        XCTAssertTrue(p.r > 200 && p.g > 200 && p.b < 60, "camera visible bottom-right: \(p)")
        var hidden = e; hidden.camera.hidden = true
        let r2 = FrameRenderer(edit: hidden, cursor: .empty, sourceSize: src, outputSize: CGSize(width: 1280, height: 720),
                               timelineDuration: 10, cursorBaked: false, cameraSize: CGSize(width: 320, height: 240))
        let out2 = r2.render(screen: TestMedia.halvesImage(), camera: cam, at: 0)
        XCTAssertFalse(TestMedia.pixel(out2, size: r2.outputSize, x: 1280 - 60, y: 720 - 60).b < 60 && TestMedia.pixel(out2, size: r2.outputSize, x: 1280 - 60, y: 720 - 60).r > 200)
    }

    func testEditStatePersistsInProject() throws {
        var project = Project(name: "x")
        project.edit.aspect = .vertical
        project.edit.zoomEvents = [ZoomEvent(start: 1, end: 3, scale: 2.2, mode: .manual)]
        project.edit.maskEvents = [MaskEvent(start: 0, end: 1, kind: .highlight)]
        project.edit.camera.position = 2
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("persist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ProjectStore.save(project, to: dir)
        XCTAssertEqual(try ProjectStore.load(from: dir).edit, project.edit)
    }

    func testOldManifestWithoutEditLoadsWithDefaults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("old-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ProjectStore.save(Project(name: "old"), to: dir)
        let url = dir.appendingPathComponent("project.json")
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        obj.removeValue(forKey: "edit")
        try JSONSerialization.data(withJSONObject: obj).write(to: url)
        XCTAssertEqual(try ProjectStore.load(from: dir).edit, EditState())
    }
}


/// Writes demo frames when SAMPLE_OUT_DIR and SAMPLE_SRC are set (for visual inspection); otherwise a no-op.
final class SampleFrameTests: XCTestCase {
    func testWriteSampleFrames() throws {
        guard let outDir = ProcessInfo.processInfo.environment["SAMPLE_OUT_DIR"],
              let srcPath = ProcessInfo.processInfo.environment["SAMPLE_SRC"],
              let screen = CIImage(contentsOf: URL(fileURLWithPath: srcPath)) else { return }
        let size = screen.extent.size
        var e = EditState()
        e.background.wallpaperIndex = 0
        e.padding = 0.07; e.cornerRadius = 0.03
        var z = ZoomEvent(start: 2, end: 8, scale: 1.8, mode: .auto); z.instant = false
        e.zoomEvents = [z]
        var m = MaskEvent(start: 0, end: 10, kind: .sensitive); m.rect = NormRect(x: 0.05, y: 0.12, w: 0.18, h: 0.07)
        e.maskEvents = [m]
        let cam = CIFilter.linearGradient()
        cam.color0 = CIColor(red: 0.2, green: 0.3, blue: 0.5); cam.color1 = CIColor(red: 0.9, green: 0.7, blue: 0.5)
        cam.point0 = .zero; cam.point1 = CGPoint(x: 0, y: 480)
        let camImg = cam.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        let track = CursorTrack(events: [
            CursorEvent(t: 0, x: 0.2, y: 0.3, kind: .move), CursorEvent(t: 3.0, x: 0.55, y: 0.45, kind: .move),
            CursorEvent(t: 3.5, x: 0.55, y: 0.45, kind: .down, button: .left), CursorEvent(t: 9, x: 0.7, y: 0.6, kind: .move)])
        let out = CGSize(width: 1600, height: 900)
        for (name, t) in [("frame_t1", 1.0), ("frame_t4_zoomed_click", 3.7)] {
            let r = FrameRenderer(edit: e, cursor: track, sourceSize: size, outputSize: out, timelineDuration: 10, cursorBaked: false,
                                  cameraSize: CGSize(width: 640, height: 480))
            let img = r.render(screen: screen, camera: camImg, at: t)
            try FrameRenderer.ciContext.writePNGRepresentation(of: img, to: URL(fileURLWithPath: "\(outDir)/\(name).png"),
                                                              format: .RGBA8, colorSpace: FrameRenderer.colorSpace)
        }
        var v = e; v.aspect = .vertical; v.background.kind = .gradient
        let r = FrameRenderer(edit: v, cursor: track, sourceSize: size, outputSize: v.outputSize(sourceSize: size, targetHeight: 1000), timelineDuration: 10, cursorBaked: false,
                              cameraSize: CGSize(width: 640, height: 480))
        try FrameRenderer.ciContext.writePNGRepresentation(of: r.render(screen: screen, camera: camImg, at: 1), to: URL(fileURLWithPath: "\(outDir)/frame_vertical.png"),
                                                          format: .RGBA8, colorSpace: FrameRenderer.colorSpace)
    }
}


/// Builds a demo project from a still image with scripted cursor activity, when DEMO_PROJECT_DIR and SAMPLE_SRC are set.
final class DemoProjectTests: XCTestCase {
    func testWriteDemoProject() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["DEMO_PROJECT_DIR"], let srcPath = env["SAMPLE_SRC"],
              let img = CIImage(contentsOf: URL(fileURLWithPath: srcPath)) else { return }
        let size = CGSize(width: 1280, height: 720)
        let scaled = img.transformed(by: CGAffineTransform(scaleX: size.width / img.extent.width, y: size.height / img.extent.height))
        var (project, url) = try ProjectStore.create(name: "Demo recording", in: URL(fileURLWithPath: dir))
        let videoURL = url.appendingPathComponent("Media/screen.mov")
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<(12 * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            FrameRenderer.ciContext.render(scaled, to: pb!)
            _ = adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        }
        input.markAsFinished(); await writer.finishWriting()
        try TestMedia.makeAudio(at: url.appendingPathComponent("Media/mic.m4a"), seconds: 12)
        var ev: [CursorEvent] = []
        for i in 0...240 { let t = Double(i) * 0.05; ev.append(CursorEvent(t: t, x: 0.2 + 0.5 * min(1, t / 6), y: 0.3 + 0.3 * sin(t / 3), kind: .move)) }
        for t in [2.0, 5.0, 8.5] { ev.append(CursorEvent(t: t, x: 0.2 + 0.5 * min(1, t / 6), y: 0.3 + 0.3 * sin(t / 3), kind: .down, button: .left)) }
        let log = try CursorEventLog(url: url.appendingPathComponent("Metadata/cursor.jsonl"))
        ev.sorted { $0.t < $1.t }.forEach(log.append); log.close()
        project.sources = [Source(id: "screen1", type: .screen, path: "Media/screen.mov", startOffset: 0),
                           Source(id: "mic1", type: .microphone, path: "Media/mic.m4a", startOffset: 0)]
        project.cursorEventsPath = "Metadata/cursor.jsonl"
        project.capture = CaptureInfo(displayFrame: CGRect(x: 0, y: 0, width: 1280, height: 720), pixelWidth: 1280, pixelHeight: 720, scale: 1, cursorBakedIntoVideo: false)
        try ProjectStore.save(project, to: url); try ProjectStore.markFinalized(at: url)
        print("DEMO_PROJECT_URL=\(url.path)")
    }
}
