import CoreGraphics

/// Coordinate-space helpers. Conventions used throughout the app:
///  - "AppKit global": points, origin at bottom-left of the primary display (NSEvent.mouseLocation, NSScreen.frame).
///  - "Global top-left": points, origin at top-left of the primary display (CoreGraphics, SCDisplay.frame).
///    Secondary displays may have negative coordinates; all math below is origin-agnostic.
///  - "Display local": points, origin at top-left of one display (SCStreamConfiguration.sourceRect).
///  - "Pixels": backing pixels = points * display scale factor.
public enum Geometry {
    public static func appKitToGlobalTopLeft(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    public static func appKitToGlobalTopLeft(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    public static func toDisplayLocal(_ globalTopLeft: CGRect, displayFrame: CGRect) -> CGRect {
        globalTopLeft.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    public static func toGlobal(_ local: CGRect, displayFrame: CGRect) -> CGRect {
        local.offsetBy(dx: displayFrame.minX, dy: displayFrame.minY)
    }

    /// Shift `rect` into `bounds`; shrink only if it is larger than `bounds`.
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let w = min(rect.width, bounds.width)
        let h = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - w)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Point rect -> integer pixel rect at `scale`, rounded outward so no selected pixel is lost.
    public static func pixelRect(forPointRect r: CGRect, scale: CGFloat) -> CGRect {
        let minX = (r.minX * scale).rounded(.down)
        let minY = (r.minY * scale).rounded(.down)
        let maxX = (r.maxX * scale).rounded(.up)
        let maxY = (r.maxY * scale).rounded(.up)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// H.264 requires even dimensions.
    public static func evenPixels(_ value: CGFloat) -> Int {
        let v = Int(value.rounded())
        return max(2, v - (v % 2))
    }

    /// Normalise a global top-left point to 0...1 within a display (not clamped; off-display values fall outside 0...1).
    public static func normalized(_ globalTopLeft: CGPoint, displayFrame: CGRect) -> CGPoint {
        CGPoint(x: (globalTopLeft.x - displayFrame.minX) / displayFrame.width,
                y: (globalTopLeft.y - displayFrame.minY) / displayFrame.height)
    }
}
