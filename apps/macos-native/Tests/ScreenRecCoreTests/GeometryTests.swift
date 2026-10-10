import XCTest
@testable import ScreenRecCore

final class GeometryTests: XCTestCase {
    func testAppKitFlip() {
        // 1440x900 primary; a 100x50 rect at AppKit (10,20) sits 20 above the bottom edge.
        let r = Geometry.appKitToGlobalTopLeft(CGRect(x: 10, y: 20, width: 100, height: 50), primaryHeight: 900)
        XCTAssertEqual(r, CGRect(x: 10, y: 830, width: 100, height: 50))
    }

    func testNegativeOriginDisplayLocal() {
        // Secondary display left of and above primary.
        let display = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let global = CGRect(x: -1000, y: 100, width: 400, height: 300)
        let local = Geometry.toDisplayLocal(global, displayFrame: display)
        XCTAssertEqual(local, CGRect(x: 920, y: 300, width: 400, height: 300))
        XCTAssertEqual(Geometry.toGlobal(local, displayFrame: display), global)
    }

    func testClampShiftsAndShrinks() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(Geometry.clamp(CGRect(x: 900, y: -50, width: 300, height: 200), to: bounds),
                       CGRect(x: 700, y: 0, width: 300, height: 200))
        XCTAssertEqual(Geometry.clamp(CGRect(x: 0, y: 0, width: 2000, height: 100), to: bounds),
                       CGRect(x: 0, y: 0, width: 1000, height: 100))
    }

    func testPixelRectRoundsOutwardAtRetinaScale() {
        // Fractional point rect at 2x must cover every touched pixel.
        let px = Geometry.pixelRect(forPointRect: CGRect(x: 10.25, y: 5.25, width: 100.5, height: 50.25), scale: 2)
        XCTAssertEqual(px, CGRect(x: 20, y: 10, width: 202, height: 101))
    }

    func testCustomArea1293x691Retina() {
        let px = Geometry.pixelRect(forPointRect: CGRect(x: 0, y: 0, width: 1293, height: 691), scale: 2)
        XCTAssertEqual(px.size, CGSize(width: 2586, height: 1382))
    }

    func testEvenPixels() {
        XCTAssertEqual(Geometry.evenPixels(1293), 1292)
        XCTAssertEqual(Geometry.evenPixels(691), 690)
        XCTAssertEqual(Geometry.evenPixels(0), 2)
    }

    func testNormalizedPointOnNegativeDisplay() {
        let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let n = Geometry.normalized(CGPoint(x: -960, y: 540), displayFrame: display)
        XCTAssertEqual(n.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0.5, accuracy: 1e-9)
    }
}
