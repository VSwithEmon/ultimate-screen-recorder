import AppKit
import SwiftUI
import XCTest
import ScreenRecCore
@testable import ScreenRecApp

/// Renders recorder overlays to PNG for visual review when SAMPLE_OUT_DIR is set; otherwise only checks they build.
@MainActor
final class OverlayRenderTests: XCTestCase {
    func render<V: View>(_ view: V, size: CGSize, name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["SAMPLE_OUT_DIR"] else { return }
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color(hex: 0x6B8CAE)))
        r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return XCTFail("render failed") }
        try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testRenderPickers() throws {
        guard let screen = NSScreen.main else { return }
        let settings = RecordingSettings()
        let size = CGSize(width: 1200, height: 700)
        try render(AreaPickerView(screen: screen, settings: settings, owner: AreaOwner(),
                                  initial: AreaSelection(rect: CGRect(x: 260, y: 180, width: 640, height: 360)),
                                  onChange: { _ in }, onStart: { _ in }), size: size, name: "area_picker")
        try render(AreaPickerView(screen: screen, settings: settings, owner: AreaOwner(), initial: nil, onChange: { _ in }, onStart: { _ in }), size: size, name: "area_empty")
        try render(DisplayPickerView(screen: screen, onStart: {}), size: size, name: "display_picker")
        try render(WindowPickerView(screen: screen, windows: [], onStart: { _ in }), size: size, name: "window_picker")
        try render(RecordingHUDView(recorder: RecorderModel(), onRestart: {}, onStop: {}), size: CGSize(width: 380, height: 70), name: "hud")
    }
}
