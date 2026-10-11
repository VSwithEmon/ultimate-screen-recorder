import XCTest
@testable import ScreenRecApp

/// WCAG 2.1 contrast checks on the design tokens, so colour changes can't silently break readability.
final class ContrastTests: XCTestCase {
    static func luminance(_ hex: UInt32) -> Double {
        func f(_ v: UInt32) -> Double { let c = Double(v) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * f((hex >> 16) & 0xFF) + 0.7152 * f((hex >> 8) & 0xFF) + 0.0722 * f(hex & 0xFF)
    }
    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    let surfaces: [(String, UInt32)] = [("base", Palette.base), ("panel", Palette.panel), ("bar", Palette.bar), ("hover", Palette.hover)]

    func testBodyAndSecondaryTextMeetAA() {
        for (sn, s) in surfaces {
            for (tn, t) in [("text", Palette.text), ("text2", Palette.text2), ("text3", Palette.text3), ("blueFocus", Palette.blueFocus), ("bad", Palette.bad), ("ok", Palette.ok)] {
                XCTAssertGreaterThanOrEqual(Self.ratio(t, s), 4.5, "\(tn) on \(sn) = \(Self.ratio(t, s))")
            }
        }
    }

    func testControlBoundariesMeet3to1OnTheirSurfaces() {
        for (sn, s) in surfaces where sn != "hover" {
            XCTAssertGreaterThanOrEqual(Self.ratio(Palette.control, s), 3.0, "control border on \(sn)")
        }
        XCTAssertGreaterThanOrEqual(Self.ratio(Palette.blueFocus, Palette.panel), 3.0, "selected-chip border")
    }

    func testTextOnFilledBackgroundsMeetsAA() {
        XCTAssertGreaterThanOrEqual(Self.ratio(0xFFFFFF, Palette.blue), 4.5, "white on primary button")
        XCTAssertGreaterThanOrEqual(Self.ratio(0xFFFFFF, Palette.bluePressed), 4.5, "white on pressed button")
        XCTAssertGreaterThanOrEqual(Self.ratio(0xFFFFFF, Palette.maskFill), 4.5, "white on mask block")
        XCTAssertGreaterThanOrEqual(Self.ratio(0xFFFFFF, Palette.highlightFill), 4.5, "white on highlight block")
        XCTAssertGreaterThanOrEqual(Self.ratio(Palette.clipText, Palette.clip), 4.5, "label on orange clip")
    }
}
