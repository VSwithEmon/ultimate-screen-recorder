import AppKit
import SwiftUI
import XCTest
@testable import ScreenRecApp

@MainActor
final class ScreenPlacementTests: XCTestCase {
    func testOverlayPanelsLandOnTheirOwnScreens() {
        let screens = NSScreen.screens
        print("SCREENS:", screens.map { "\($0.localizedName) \($0.frame) id=\($0.displayID)" })
        for s in screens {
            let p = makeOverlayPanel(for: s)
            p.contentView = NSHostingView(rootView: Color.red)
            p.orderFrontRegardless()
            print("PANEL for \(s.localizedName): frame=\(p.frame) screen=\(p.screen?.localizedName ?? "nil") visible=\(p.isVisible)")
            XCTAssertEqual(p.frame, s.frame, "panel frame must equal its screen frame for \(s.localizedName)")
            XCTAssertEqual(p.screen?.displayID, s.displayID, "panel must be on \(s.localizedName)")
            p.close()
        }
    }
}
