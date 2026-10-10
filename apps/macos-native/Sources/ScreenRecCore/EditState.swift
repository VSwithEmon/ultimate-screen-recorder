import CoreGraphics
import Foundation

public struct RGBA: Codable, Equatable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public static let black = RGBA(0, 0, 0)
    public static let white = RGBA(1, 1, 1)
}

public enum AspectPreset: String, Codable, CaseIterable {
    case auto, wide, square, classic, vertical, tall, portrait
    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .wide: return "Wide 16:9"
        case .square: return "Square 1:1"
        case .classic: return "Classic 4:3"
        case .vertical: return "Vertical 9:16"
        case .tall: return "Tall 3:4"
        case .portrait: return "Portrait 4:5"
        }
    }
    /// width / height; `auto` follows the cropped source.
    public func ratio(auto: Double) -> Double {
        switch self {
        case .auto: return auto
        case .wide: return 16.0 / 9
        case .square: return 1
        case .classic: return 4.0 / 3
        case .vertical: return 9.0 / 16
        case .tall: return 3.0 / 4
        case .portrait: return 4.0 / 5
        }
    }
}

/// Normalised rectangle, origin top-left, 0...1.
public struct NormRect: Codable, Equatable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public static let full = NormRect(x: 0, y: 0, w: 1, h: 1)
    public var isFull: Bool { x == 0 && y == 0 && w == 1 && h == 1 }
    public func clamped() -> NormRect {
        let w = min(max(w, 0.02), 1), h = min(max(h, 0.02), 1)
        return NormRect(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), w: w, h: h)
    }
}

public struct CanvasBackground: Codable, Equatable {
    public enum Kind: String, Codable { case wallpaper, gradient, color, image }
    public var kind: Kind = .wallpaper
    public var wallpaperIndex: Int = 0
    public var colorA = RGBA(0.145, 0.388, 0.922)
    public var colorB = RGBA(0.06, 0.09, 0.16)
    public var angleDegrees: Double = 135
    /// Path relative to the project package (copied in on import).
    public var imagePath: String?
    /// 0...1, blurs wallpaper/image backgrounds.
    public var blur: Double = 0
    public init() {}
}

/// Original procedural wallpapers (no third-party artwork).
public enum Wallpapers {
    public struct Def { public let name: String; public let base: (RGBA, RGBA); public let blobs: [(x: Double, y: Double, r: Double, c: RGBA)] }
    public static let all: [Def] = [
        Def(name: "Ocean", base: (RGBA(0.04, 0.10, 0.30), RGBA(0.15, 0.45, 0.95)), blobs: [(0.2, 0.9, 0.7, RGBA(0.4, 0.8, 1, 0.8)), (0.9, 0.2, 0.6, RGBA(0.1, 0.2, 0.7, 0.9))]),
        Def(name: "Aurora", base: (RGBA(0.02, 0.10, 0.14), RGBA(0.1, 0.55, 0.5)), blobs: [(0.8, 0.8, 0.6, RGBA(0.45, 0.35, 0.95, 0.8)), (0.1, 0.2, 0.5, RGBA(0.2, 0.9, 0.6, 0.7))]),
        Def(name: "Dusk", base: (RGBA(0.16, 0.08, 0.3), RGBA(0.95, 0.45, 0.4)), blobs: [(0.9, 0.9, 0.6, RGBA(1, 0.75, 0.4, 0.8)), (0.1, 0.1, 0.6, RGBA(0.3, 0.2, 0.7, 0.9))]),
        Def(name: "Graphite", base: (RGBA(0.06, 0.07, 0.09), RGBA(0.22, 0.25, 0.3)), blobs: [(0.7, 0.9, 0.5, RGBA(0.4, 0.45, 0.55, 0.6))]),
        Def(name: "Mint", base: (RGBA(0.75, 0.95, 0.9), RGBA(0.35, 0.75, 0.7)), blobs: [(0.1, 0.9, 0.6, RGBA(1, 1, 1, 0.8))]),
        Def(name: "Peach", base: (RGBA(1, 0.85, 0.75), RGBA(0.95, 0.55, 0.55)), blobs: [(0.9, 0.9, 0.6, RGBA(1, 0.95, 0.8, 0.8))]),
    ]
}

public struct ZoomEvent: Codable, Equatable, Identifiable {
    public enum Mode: String, Codable { case auto, manual }
    public var id = UUID()
    /// Timeline seconds (0 = start of the recording before trim).
    public var start: Double
    public var end: Double
    public var scale: Double = 1.8
    public var mode: Mode = .auto
    /// Used in manual mode; normalised, origin top-left, in cropped-source space.
    public var focus = CGPoint(x: 0.5, y: 0.5)
    public var instant = false
    public init(start: Double, end: Double, scale: Double = 1.8, mode: Mode = .auto) {
        self.start = start; self.end = end; self.scale = scale; self.mode = mode
    }
}

public struct MaskEvent: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable { case sensitive, highlight }
    public enum Style: String, Codable { case solid, pixelate }
    public var id = UUID()
    public var start: Double
    public var end: Double
    public var kind: Kind
    public var style: Style = .solid
    /// Normalised to the cropped source, origin top-left.
    public var rect = NormRect(x: 0.3, y: 0.3, w: 0.3, h: 0.15)
    public init(start: Double, end: Double, kind: Kind) { self.start = start; self.end = end; self.kind = kind }
}

public struct CursorSettings: Codable, Equatable {
    public enum Style: String, Codable, CaseIterable { case arrow, outline, dot }
    public enum ClickEffect: String, Codable, CaseIterable { case none, circle, ripple }
    public var visible = true
    public var size = 1.0
    public var style = Style.arrow
    public var hideWhenIdle = false
    public var smoothing = 0.12
    public var removeShakes = true
    public var clickEffect = ClickEffect.ripple
    /// Seconds before the end where the cursor stops following the mouse (0 = off).
    public var stopBeforeEnd = 0.0
    public init() {}
}

public struct CameraSettings: Codable, Equatable {
    public enum Shape: String, Codable, CaseIterable { case square, horizontal, vertical, original }
    public var hidden = false
    /// 0...8, row-major from top-left.
    public var position = 8
    public var size = 0.22
    public var roundness = 0.5
    public var shape = Shape.horizontal
    public var mirror = false
    public init() {}
}

public struct AudioSettings: Codable, Equatable {
    public var muteMicrophone = false
    public var micGain = 1.0
    public var systemGain = 1.0
    public init() {}
}

public struct EditState: Codable, Equatable {
    public var aspect = AspectPreset.auto
    public var crop = NormRect.full
    public var background = CanvasBackground()
    /// Fraction of the canvas' shorter side.
    public var padding = 0.08
    /// Fraction of the frame's shorter side (0...0.1).
    public var cornerRadius = 0.025
    public var shadow = true
    public var zoomEvents: [ZoomEvent] = []
    public var maskEvents: [MaskEvent] = []
    public var cursor = CursorSettings()
    public var camera = CameraSettings()
    public var audio = AudioSettings()
    /// Timeline seconds. `trimEnd == nil` keeps everything to the end.
    public var trimStart = 0.0
    public var trimEnd: Double?
    public init() {}

    /// Output canvas size for a target height; width follows the aspect, both even.
    public func outputSize(sourceSize: CGSize, targetHeight: Int) -> CGSize {
        let cropAspect = (sourceSize.width * crop.w) / (sourceSize.height * crop.h)
        let ratio = aspect.ratio(auto: cropAspect)
        let h = Geometry.evenPixels(CGFloat(targetHeight))
        let w = Geometry.evenPixels(CGFloat(Double(h) * ratio))
        return CGSize(width: w, height: h)
    }
}
