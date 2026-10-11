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

/// Original procedural wallpapers (no third-party artwork). Existing indexes never change; new ones are appended.
public enum Wallpapers {
    public enum Category: String, CaseIterable { case all = "All", blue = "Blue", warm = "Warm", cool = "Green & Teal", dark = "Dark", light = "Light", vivid = "Vivid" }
    public struct Blob { public let x, y, r: Double; public let c: RGBA }
    public struct Def {
        public let name: String
        public let category: Category
        public let angle: Double
        public let base: (RGBA, RGBA)
        public let blobs: [Blob]
    }
    private static func b(_ x: Double, _ y: Double, _ r: Double, _ c: RGBA) -> Blob { Blob(x: x, y: y, r: r, c: c) }
    private static func d(_ n: String, _ cat: Category, _ ang: Double = 120, _ a: RGBA, _ z: RGBA, _ blobs: [Blob]) -> Def {
        Def(name: n, category: cat, angle: ang, base: (a, z), blobs: blobs)
    }
    public static let all: [Def] = [
        d("Ocean", .blue, 120, RGBA(0.04, 0.10, 0.30), RGBA(0.15, 0.45, 0.95), [b(0.2, 0.9, 0.7, RGBA(0.4, 0.8, 1, 0.8)), b(0.9, 0.2, 0.6, RGBA(0.1, 0.2, 0.7, 0.9))]),
        d("Aurora", .cool, 120, RGBA(0.02, 0.10, 0.14), RGBA(0.1, 0.55, 0.5), [b(0.8, 0.8, 0.6, RGBA(0.45, 0.35, 0.95, 0.8)), b(0.1, 0.2, 0.5, RGBA(0.2, 0.9, 0.6, 0.7))]),
        d("Dusk", .warm, 120, RGBA(0.16, 0.08, 0.3), RGBA(0.95, 0.45, 0.4), [b(0.9, 0.9, 0.6, RGBA(1, 0.75, 0.4, 0.8)), b(0.1, 0.1, 0.6, RGBA(0.3, 0.2, 0.7, 0.9))]),
        d("Graphite", .dark, 120, RGBA(0.06, 0.07, 0.09), RGBA(0.22, 0.25, 0.3), [b(0.7, 0.9, 0.5, RGBA(0.4, 0.45, 0.55, 0.6))]),
        d("Mint", .light, 120, RGBA(0.75, 0.95, 0.9), RGBA(0.35, 0.75, 0.7), [b(0.1, 0.9, 0.6, RGBA(1, 1, 1, 0.8))]),
        d("Peach", .light, 120, RGBA(1, 0.85, 0.75), RGBA(0.95, 0.55, 0.55), [b(0.9, 0.9, 0.6, RGBA(1, 0.95, 0.8, 0.8))]),
        // --- added in 0.5.0 ---
        d("Deep Sea", .blue, 100, RGBA(0.01, 0.05, 0.16), RGBA(0.05, 0.28, 0.55), [b(0.5, 1.0, 0.8, RGBA(0.1, 0.55, 0.8, 0.7)), b(0.1, 0.3, 0.5, RGBA(0.02, 0.1, 0.35, 0.9))]),
        d("Sky", .blue, 90, RGBA(0.45, 0.72, 0.98), RGBA(0.85, 0.94, 1), [b(0.2, 0.2, 0.6, RGBA(1, 1, 1, 0.8)), b(0.85, 0.7, 0.5, RGBA(0.55, 0.78, 1, 0.8))]),
        d("Indigo Night", .blue, 135, RGBA(0.08, 0.06, 0.25), RGBA(0.32, 0.25, 0.75), [b(0.85, 0.15, 0.6, RGBA(0.55, 0.45, 1, 0.7)), b(0.1, 0.9, 0.5, RGBA(0.1, 0.1, 0.45, 0.9))]),
        d("Glacier", .blue, 110, RGBA(0.8, 0.92, 1), RGBA(0.3, 0.62, 0.9), [b(0.1, 0.1, 0.6, RGBA(1, 1, 1, 0.9)), b(0.9, 0.9, 0.7, RGBA(0.2, 0.5, 0.85, 0.7))]),
        d("Sunset", .warm, 110, RGBA(0.98, 0.45, 0.25), RGBA(0.55, 0.1, 0.45), [b(0.5, 0.05, 0.8, RGBA(1, 0.8, 0.35, 0.85)), b(0.95, 0.95, 0.6, RGBA(0.35, 0.05, 0.4, 0.9))]),
        d("Ember", .warm, 125, RGBA(0.25, 0.04, 0.06), RGBA(0.92, 0.3, 0.12), [b(0.2, 0.95, 0.7, RGBA(1, 0.6, 0.2, 0.8)), b(0.9, 0.1, 0.5, RGBA(0.5, 0.05, 0.1, 0.9))]),
        d("Rose Gold", .warm, 120, RGBA(0.96, 0.78, 0.74), RGBA(0.82, 0.5, 0.55), [b(0.85, 0.15, 0.6, RGBA(1, 0.92, 0.85, 0.85)), b(0.1, 0.9, 0.5, RGBA(0.7, 0.35, 0.45, 0.7))]),
        d("Sand", .warm, 100, RGBA(0.95, 0.88, 0.74), RGBA(0.84, 0.68, 0.5), [b(0.15, 0.2, 0.6, RGBA(1, 0.97, 0.88, 0.9))]),
        d("Forest", .cool, 120, RGBA(0.02, 0.14, 0.09), RGBA(0.16, 0.5, 0.3), [b(0.85, 0.85, 0.6, RGBA(0.45, 0.85, 0.5, 0.6)), b(0.1, 0.2, 0.5, RGBA(0.01, 0.07, 0.05, 0.9))]),
        d("Lagoon", .cool, 110, RGBA(0.02, 0.28, 0.35), RGBA(0.2, 0.78, 0.7), [b(0.2, 0.9, 0.6, RGBA(0.7, 1, 0.9, 0.7)), b(0.9, 0.1, 0.5, RGBA(0.02, 0.15, 0.3, 0.8))]),
        d("Sage", .cool, 115, RGBA(0.76, 0.85, 0.74), RGBA(0.45, 0.62, 0.5), [b(0.15, 0.15, 0.6, RGBA(0.95, 1, 0.92, 0.85))]),
        d("Midnight", .dark, 130, RGBA(0.02, 0.02, 0.06), RGBA(0.12, 0.13, 0.28), [b(0.85, 0.1, 0.5, RGBA(0.25, 0.28, 0.6, 0.6))]),
        d("Charcoal", .dark, 120, RGBA(0.04, 0.04, 0.05), RGBA(0.14, 0.15, 0.17), [b(0.2, 0.9, 0.5, RGBA(0.25, 0.26, 0.3, 0.6))]),
        d("Plum", .dark, 125, RGBA(0.1, 0.03, 0.15), RGBA(0.42, 0.14, 0.45), [b(0.9, 0.9, 0.6, RGBA(0.75, 0.3, 0.7, 0.55)), b(0.1, 0.1, 0.5, RGBA(0.05, 0.02, 0.15, 0.9))]),
        d("Cloud", .light, 100, RGBA(0.93, 0.95, 0.98), RGBA(0.78, 0.84, 0.93), [b(0.2, 0.15, 0.6, RGBA(1, 1, 1, 0.95)), b(0.9, 0.9, 0.5, RGBA(0.7, 0.78, 0.9, 0.7))]),
        d("Lavender", .light, 115, RGBA(0.85, 0.8, 0.98), RGBA(0.62, 0.55, 0.9), [b(0.15, 0.85, 0.6, RGBA(1, 0.9, 1, 0.8))]),
        d("Candy", .vivid, 130, RGBA(1, 0.4, 0.7), RGBA(0.45, 0.35, 1), [b(0.1, 0.1, 0.6, RGBA(1, 0.8, 0.4, 0.8)), b(0.9, 0.9, 0.6, RGBA(0.2, 0.8, 1, 0.8))]),
        d("Neon", .vivid, 135, RGBA(0.08, 0.02, 0.2), RGBA(0.05, 0.85, 0.85), [b(0.1, 0.9, 0.6, RGBA(1, 0.1, 0.7, 0.8)), b(0.9, 0.2, 0.6, RGBA(0.1, 0.9, 0.9, 0.7))]),
        d("Tropical", .vivid, 120, RGBA(0.0, 0.7, 0.65), RGBA(1, 0.6, 0.2), [b(0.9, 0.1, 0.6, RGBA(1, 0.85, 0.3, 0.8)), b(0.1, 0.9, 0.6, RGBA(0.0, 0.45, 0.6, 0.8))]),
        d("Spectrum", .vivid, 125, RGBA(0.2, 0.2, 0.95), RGBA(0.95, 0.25, 0.4), [b(0.1, 0.9, 0.6, RGBA(0.1, 0.9, 0.9, 0.8)), b(0.9, 0.1, 0.6, RGBA(1, 0.85, 0.2, 0.8))]),
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

/// Background music mixed under the recording. The audio file lives inside the project package.
public struct MusicSettings: Codable, Equatable {
    /// Path relative to the project package.
    public var path: String
    public var title: String
    public var gain = 0.35
    public var fadeIn = 1.0
    public var fadeOut = 2.0
    public var loop = true
    public init(path: String, title: String) { self.path = path; self.title = title }
}

public struct AudioSettings: Codable, Equatable {
    public var music: MusicSettings?
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
