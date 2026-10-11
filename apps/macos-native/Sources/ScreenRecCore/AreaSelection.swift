import CoreGraphics
import Foundation

/// A capture rectangle in display-local points (origin top-left), as used by `SCStreamConfiguration.sourceRect`.
public struct AreaSelection: Equatable {
    public enum Handle: CaseIterable { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }

    public var rect: CGRect
    public init(rect: CGRect) { self.rect = rect }

    /// Whole-pixel size at a backing scale.
    public func pixelSize(scale: CGFloat) -> (w: Int, h: Int) { (Int((rect.width * scale).rounded()), Int((rect.height * scale).rounded())) }
    public func pixelOrigin(scale: CGFloat) -> (x: Int, y: Int) { (Int((rect.minX * scale).rounded()), Int((rect.minY * scale).rounded())) }

    /// Encoder-safe capture size (even pixels).
    public func captureSize(scale: CGFloat) -> CGSize {
        CGSize(width: Geometry.evenPixels(rect.width * scale), height: Geometry.evenPixels(rect.height * scale))
    }

    /// Region of the display this selection covers, 0...1.
    public func normalized(in bounds: CGRect) -> NormRect {
        NormRect(x: Double(rect.minX / bounds.width), y: Double(rect.minY / bounds.height),
                 w: Double(rect.width / bounds.width), h: Double(rect.height / bounds.height))
    }

    public static func fromDrag(from a: CGPoint, to b: CGPoint, bounds: CGRect) -> AreaSelection {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        return AreaSelection(rect: r.intersection(bounds))
    }

    public mutating func move(by d: CGSize, bounds: CGRect) {
        rect = Geometry.clamp(rect.offsetBy(dx: d.width, dy: d.height), to: bounds)
    }

    public mutating func setPixelOrigin(x: Int?, y: Int?, scale: CGFloat, bounds: CGRect) {
        var r = rect
        if let x { r.origin.x = CGFloat(x) / scale }
        if let y { r.origin.y = CGFloat(y) / scale }
        rect = Geometry.clamp(r, to: bounds)
    }

    /// Sets size from pixel values. With `ratio` (width/height) the other side follows.
    public mutating func setPixelSize(w: Int?, h: Int?, scale: CGFloat, bounds: CGRect, ratio: Double?, minSize: CGFloat = 40) {
        var r = rect
        if let w { r.size.width = max(minSize, CGFloat(w) / scale); if let ratio { r.size.height = r.width / CGFloat(ratio) } }
        if let h { r.size.height = max(minSize, CGFloat(h) / scale); if let ratio { r.size.width = r.height * CGFloat(ratio) } }
        rect = AreaSelection.fit(r, in: bounds, ratio: ratio, minSize: minSize)
    }

    /// Re-shapes to an aspect ratio, keeping the centre.
    public mutating func applyRatio(_ ratio: Double, bounds: CGRect, minSize: CGFloat = 40) {
        var r = rect
        let centre = CGPoint(x: r.midX, y: r.midY)
        r.size.height = r.width / CGFloat(ratio)
        r.origin = CGPoint(x: centre.x - r.width / 2, y: centre.y - r.height / 2)
        rect = AreaSelection.fit(r, in: bounds, ratio: ratio, minSize: minSize)
    }

    /// Drags a handle by `delta` (points), optionally locking the aspect ratio. Always stays inside `bounds`.
    public mutating func drag(_ handle: Handle, by delta: CGSize, bounds: CGRect, ratio: Double?, minSize: CGFloat = 40) {
        var x0 = rect.minX, y0 = rect.minY, x1 = rect.maxX, y1 = rect.maxY
        switch handle {
        case .topLeft: x0 += delta.width; y0 += delta.height
        case .top: y0 += delta.height
        case .topRight: x1 += delta.width; y0 += delta.height
        case .right: x1 += delta.width
        case .bottomRight: x1 += delta.width; y1 += delta.height
        case .bottom: y1 += delta.height
        case .bottomLeft: x0 += delta.width; y1 += delta.height
        case .left: x0 += delta.width
        }
        x0 = min(max(x0, bounds.minX), x1 - minSize); x1 = max(min(x1, bounds.maxX), x0 + minSize)
        y0 = min(max(y0, bounds.minY), y1 - minSize); y1 = max(min(y1, bounds.maxY), y0 + minSize)
        var r = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        if let ratio {
            let k = CGFloat(ratio)
            switch handle {
            case .left, .right:
                let h = r.width / k; r.origin.y = rect.midY - h / 2; r.size.height = h
            case .top, .bottom:
                let w = r.height * k; r.origin.x = rect.midX - w / 2; r.size.width = w
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                let h = r.width / k
                if handle == .topLeft || handle == .topRight { r.origin.y = rect.maxY - h }
                r.size.height = h
            }
        }
        rect = AreaSelection.fit(r, in: bounds, ratio: ratio, minSize: minSize)
    }

    /// Shrinks (keeping the aspect ratio when given) and shifts a rect so it lies within bounds.
    static func fit(_ r: CGRect, in bounds: CGRect, ratio: Double?, minSize: CGFloat) -> CGRect {
        var w = max(r.width, minSize), h = max(r.height, minSize)
        let s = min(1, bounds.width / w, bounds.height / h)
        if s < 1 { w *= s; h *= s }
        if ratio != nil { /* ratio already satisfied by construction; scaling preserves it */ }
        return Geometry.clamp(CGRect(x: r.minX, y: r.minY, width: w, height: h), to: bounds)
    }
}

/// A named area saved by the user, stored in pixels so it survives display changes.
public struct SavedArea: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var width: Int
    public var height: Int
    public var x: Int
    public var y: Int
    public init(name: String, width: Int, height: Int, x: Int, y: Int) { self.name = name; self.width = width; self.height = height; self.x = x; self.y = y }

    public func selection(scale: CGFloat, bounds: CGRect) -> AreaSelection {
        var a = AreaSelection(rect: CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale, width: CGFloat(width) / scale, height: CGFloat(height) / scale))
        a.rect = AreaSelection.fit(a.rect, in: bounds, ratio: nil, minSize: 40)
        return a
    }
}
