import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Renders one output frame from a screen frame, optional camera frame and the edit state at a timeline time.
/// Used by both the live preview and the exporter, so what you see is what you export.
/// All CoreImage coordinates are bottom-left origin; normalised inputs are top-left origin.
public final class FrameRenderer {
    public static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    public static let ciContext = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])

    public let edit: EditState
    public let cursor: CursorTrack
    public let sourceSize: CGSize
    public let outputSize: CGSize
    public let timelineDuration: Double
    public let cursorBaked: Bool

    /// Crop in source pixels (CI coordinates).
    public let cropPx: CGRect
    /// Screen frame inside the canvas (CI coordinates).
    public let frame: CGRect
    /// Frame pixels per cropped-source pixel at zoom 1.
    public let baseScale: Double

    private let base: CIImage
    private let frameMask: CIImage
    private let sprite: (image: CIImage, hotspot: CGPoint)
    private let ring: CIImage
    private let disc: CIImage
    private var cameraLayout: (rect: CGRect, aspect: CGFloat, mask: CIImage)?

    public init(edit: EditState, cursor: CursorTrack, sourceSize: CGSize, outputSize: CGSize,
                timelineDuration: Double, cursorBaked: Bool, backgroundImage: CIImage? = nil, cameraSize: CGSize? = nil) {
        self.edit = edit
        self.cursor = cursor
        self.sourceSize = sourceSize
        self.outputSize = outputSize
        self.timelineDuration = timelineDuration
        self.cursorBaked = cursorBaked

        let c = edit.crop.clamped()
        cropPx = CGRect(x: c.x * sourceSize.width, y: (1 - c.y - c.h) * sourceSize.height,
                        width: c.w * sourceSize.width, height: c.h * sourceSize.height)

        let canvas = CGRect(origin: .zero, size: outputSize)
        let pad = CGFloat(min(max(edit.padding, 0), 0.4)) * min(outputSize.width, outputSize.height)
        let area = canvas.insetBy(dx: pad, dy: pad)
        let fit = min(area.width / cropPx.width, area.height / cropPx.height)
        baseScale = Double(fit)
        let fs = CGSize(width: cropPx.width * fit, height: cropPx.height * fit)
        frame = CGRect(x: area.midX - fs.width / 2, y: area.midY - fs.height / 2, width: fs.width, height: fs.height)

        let radius = CGFloat(min(max(edit.cornerRadius, 0), 0.1)) * min(frame.width, frame.height)
        frameMask = FrameRenderer.roundedMask(size: outputSize, rect: frame, radius: radius)

        // Background + shadow rasterised once.
        var bg = FrameRenderer.makeBackground(edit.background, size: outputSize, image: backgroundImage)
        if edit.shadow {
            bg = FrameRenderer.shadowImage(size: outputSize, rect: frame, radius: radius).composited(over: bg)
        }
        if let cg = FrameRenderer.ciContext.createCGImage(bg, from: canvas) { base = CIImage(cgImage: cg) } else { base = bg.cropped(to: canvas) }

        sprite = FrameRenderer.makeSprite(edit.cursor.style)
        ring = FrameRenderer.makeShape(ring: true)
        disc = FrameRenderer.makeShape(ring: false)

        if let cs = cameraSize, cs.width > 0 {
            cameraLayout = FrameRenderer.layoutCamera(edit.camera, camera: cs, canvas: outputSize)
        }
    }

    // MARK: Geometry (shared with UI overlays)

    public func zoomState(at tau: Double) -> ZoomState {
        ZoomEngine.state(at: tau, events: edit.zoomEvents) { [self] t in
            guard let p = cursor.position(at: t, smoothing: 0.3) else { return nil }
            let c = edit.crop.clamped()
            return CGPoint(x: (p.x - c.x) / c.w, y: (p.y - c.y) / c.h)
        }
    }

    private func window(_ z: ZoomState) -> (origin: CGPoint, k: Double) {
        let cw = Double(cropPx.width), ch = Double(cropPx.height)
        let ww = cw / z.scale, wh = ch / z.scale
        return (CGPoint(x: z.focus.x * cw - ww / 2, y: (1 - z.focus.y) * ch - wh / 2), baseScale * z.scale)
    }

    /// Cropped-source normalised point (top-left origin) -> canvas point (CI coordinates).
    public func outputPoint(nx: Double, ny: Double, at tau: Double) -> CGPoint {
        let z = zoomState(at: tau), w = window(z)
        return CGPoint(x: Double(frame.minX) + (nx * Double(cropPx.width) - Double(w.origin.x)) * w.k,
                       y: Double(frame.minY) + ((1 - ny) * Double(cropPx.height) - Double(w.origin.y)) * w.k)
    }

    /// Canvas rectangle (CI coordinates) of a cropped-source normalised rect at a timeline time.
    public func outputRect(_ r: NormRect, at tau: Double) -> CGRect {
        let a = outputPoint(nx: r.x, ny: r.y + r.h, at: tau)
        let k = window(zoomState(at: tau)).k
        return CGRect(x: a.x, y: a.y, width: r.w * Double(cropPx.width) * k, height: r.h * Double(cropPx.height) * k)
    }

    /// Cropped-source normalised units per canvas pixel, used to turn UI drags into edit-space deltas.
    public func normalizedPerOutputPixel(at tau: Double) -> (x: Double, y: Double) {
        let k = window(zoomState(at: tau)).k
        return (1 / (k * Double(cropPx.width)), 1 / (k * Double(cropPx.height)))
    }

    // MARK: Render

    public func render(screen: CIImage?, camera: CIImage?, at tau: Double) -> CIImage {
        let z = zoomState(at: tau)
        let w = window(z)
        let k = CGFloat(w.k)
        let t = CGAffineTransform(a: k, b: 0, c: 0, d: k,
                                  tx: frame.minX + k * (-cropPx.minX - w.origin.x),
                                  ty: frame.minY + k * (-cropPx.minY - w.origin.y))
        let src = screen ?? CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: sourceSize))
        var content = src.transformed(by: t).cropped(to: frame)

        // Cursor and click effects are drawn under masks so a mask always covers them.
        if edit.cursor.visible, !cursorBaked, !cursor.isEmpty {
            content = drawCursor(over: content, at: tau, zoom: z)
        }
        content = applyMasks(to: content, at: tau)

        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = content
        blend.backgroundImage = base
        blend.maskImage = frameMask
        var out = blend.outputImage ?? base

        if let cam = camera, !edit.camera.hidden, let layout = cameraLayout {
            out = drawCamera(cam, layout: layout).composited(over: out)
        }
        return out.cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    // MARK: Masks

    private func applyMasks(to image: CIImage, at tau: Double) -> CIImage {
        var content = image
        for m in edit.maskEvents where tau >= m.start && tau <= m.end {
            let r = outputRect(m.rect, at: tau).intersection(frame)
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            switch m.kind {
            case .sensitive:
                switch m.style {
                case .solid:
                    content = CIImage(color: .black).cropped(to: r).composited(over: content)
                case .pixelate:
                    let px = CIFilter.pixellate()
                    px.inputImage = content.clampedToExtent()
                    px.scale = Float(max(r.width, r.height) / 14)
                    px.center = CGPoint(x: r.midX, y: r.midY)
                    if let o = px.outputImage { content = o.cropped(to: r).composited(over: content) }
                }
            case .highlight:
                let dim = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.55)).cropped(to: frame)
                content = content.cropped(to: r).composited(over: dim.composited(over: content))
            }
        }
        return content
    }

    // MARK: Cursor

    private func drawCursor(over content: CIImage, at tau: Double, zoom z: ZoomState) -> CIImage {
        var out = content
        let c = edit.crop.clamped()
        func map(_ p: CGPoint) -> CGPoint { outputPoint(nx: (p.x - c.x) / c.w, ny: (p.y - c.y) / c.h, at: tau) }
        let frameH = Double(frame.height)
        let zoomBoost = z.scale.squareRoot()

        // Click effects.
        if edit.cursor.clickEffect != .none {
            for click in cursor.clicks where tau >= click.t && tau - click.t <= 0.6 {
                let q = (tau - click.t) / 0.6
                let centre = map(CGPoint(x: click.x, y: click.y))
                let img: CIImage, diameter: Double, alpha: Double
                if edit.cursor.clickEffect == .ripple {
                    img = ring; diameter = frameH * (0.03 + 0.09 * q) * zoomBoost; alpha = 0.85 * (1 - q)
                } else {
                    img = disc; diameter = frameH * 0.05 * (1 - 0.3 * q) * zoomBoost; alpha = 0.4 * (1 - q)
                }
                out = place(img, centre: centre, diameter: diameter, alpha: alpha).composited(over: out)
            }
        }

        // Pointer.
        let end = timelineDuration - edit.cursor.stopBeforeEnd
        let t = edit.cursor.stopBeforeEnd > 0 ? min(tau, end) : tau
        let smoothing = edit.cursor.smoothing + (edit.cursor.removeShakes ? 0.05 : 0)
        guard let pos = cursor.position(at: t, smoothing: smoothing) else { return out }
        var alpha = 1.0
        if edit.cursor.hideWhenIdle {
            let idle = cursor.idleTime(at: t)
            alpha = idle <= 1.2 ? 1 : max(0, 1 - (idle - 1.2) / 0.3)
        }
        guard alpha > 0 else { return out }
        let pt = map(pos)
        let targetH = frameH * 0.035 * edit.cursor.size * zoomBoost
        let s = CGFloat(targetH) / sprite.image.extent.height
        var img = sprite.image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        img = img.transformed(by: CGAffineTransform(translationX: pt.x - sprite.hotspot.x * s, y: pt.y - sprite.hotspot.y * s))
        if alpha < 1 { img = FrameRenderer.withAlpha(img, alpha) }
        return img.composited(over: out)
    }

    private func place(_ image: CIImage, centre: CGPoint, diameter: Double, alpha: Double) -> CIImage {
        let s = CGFloat(diameter) / image.extent.width
        let moved = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            .transformed(by: CGAffineTransform(translationX: centre.x - CGFloat(diameter) / 2, y: centre.y - CGFloat(diameter) / 2))
        return FrameRenderer.withAlpha(moved, alpha)
    }

    // MARK: Camera

    private static func layoutCamera(_ cam: CameraSettings, camera: CGSize, canvas: CGSize) -> (rect: CGRect, aspect: CGFloat, mask: CIImage) {
        let aspect: CGFloat
        switch cam.shape {
        case .square: aspect = 1
        case .horizontal: aspect = 4.0 / 3
        case .vertical: aspect = 3.0 / 4
        case .original: aspect = camera.width / camera.height
        }
        let base = CGFloat(min(max(cam.size, 0.08), 0.6)) * canvas.width
        let w = aspect >= 1 ? base : base * aspect
        let h = w / aspect
        let margin = 0.03 * min(canvas.width, canvas.height)
        let col = CGFloat(cam.position % 3), row = CGFloat(cam.position / 3)
        let x = margin + col * (canvas.width - 2 * margin - w) / 2
        let topY = margin + row * (canvas.height - 2 * margin - h) / 2
        let rect = CGRect(x: x, y: canvas.height - topY - h, width: w, height: h)
        let radius = CGFloat(min(max(cam.roundness, 0), 1)) * min(w, h) / 2
        return (rect, aspect, roundedMask(size: rect.size, rect: CGRect(origin: .zero, size: rect.size), radius: radius))
    }

    private func drawCamera(_ cam: CIImage, layout: (rect: CGRect, aspect: CGFloat, mask: CIImage)) -> CIImage {
        let e = cam.extent
        var crop = e
        if e.width / e.height > layout.aspect {
            crop.size.width = e.height * layout.aspect; crop.origin.x = e.midX - crop.width / 2
        } else {
            crop.size.height = e.width / layout.aspect; crop.origin.y = e.midY - crop.height / 2
        }
        let s = layout.rect.width / crop.width
        var img = cam.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
        if edit.camera.mirror {
            img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(translationX: layout.rect.width, y: 0)))
        }
        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = img
        blend.backgroundImage = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: layout.rect.size))
        blend.maskImage = layout.mask
        return (blend.outputImage ?? img).transformed(by: CGAffineTransform(translationX: layout.rect.minX, y: layout.rect.minY))
    }

    // MARK: Image helpers

    static func withAlpha(_ image: CIImage, _ a: Double) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(a))
        return f.outputImage ?? image
    }

    private static func bitmap(_ size: CGSize) -> CGContext {
        CGContext(data: nil, width: Int(size.width.rounded()), height: Int(size.height.rounded()), bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func roundedMask(size: CGSize, rect: CGRect, radius: CGFloat) -> CIImage {
        let ctx = bitmap(size)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        return CIImage(cgImage: ctx.makeImage()!)
    }

    static func shadowImage(size: CGSize, rect: CGRect, radius: CGFloat) -> CIImage {
        let ctx = bitmap(size)
        ctx.setShadow(offset: CGSize(width: 0, height: -0.014 * size.height), blur: 0.045 * size.height,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        return CIImage(cgImage: ctx.makeImage()!)
    }

    static func makeShape(ring: Bool) -> CIImage {
        let ctx = bitmap(CGSize(width: 256, height: 256))
        if ring {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.setLineWidth(14)
            ctx.strokeEllipse(in: CGRect(x: 10, y: 10, width: 236, height: 236))
        } else {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: 248, height: 248))
        }
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Original pointer artwork. Returns the sprite and the tip's position in sprite CI coordinates.
    static func makeSprite(_ style: CursorSettings.Style) -> (CIImage, CGPoint) {
        let size = CGSize(width: 96, height: 96)
        let ctx = bitmap(size)
        if style == .dot {
            ctx.setFillColor(CGColor(red: 0.2, green: 0.22, blue: 0.27, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: 18, y: 18, width: 60, height: 60))
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.setLineWidth(5)
            ctx.strokeEllipse(in: CGRect(x: 18, y: 18, width: 60, height: 60))
            return (CIImage(cgImage: ctx.makeImage()!), CGPoint(x: 48, y: 48))
        }
        // Pointer in a top-left 64x64 grid, flipped into CG coordinates (y up) inside a 96 box with 12px margin.
        let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 46), (11, 36), (19, 54), (28, 50), (20, 33), (34, 33)]
        let path = CGMutablePath()
        for (i, p) in pts.enumerated() {
            let pt = CGPoint(x: 14 + p.0, y: 96 - 12 - p.1)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        let fill: CGColor = style == .arrow ? CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let stroke: CGColor = style == .arrow ? CGColor(red: 1, green: 1, blue: 1, alpha: 1) : CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        ctx.setLineJoin(.round)
        ctx.addPath(path); ctx.setFillColor(fill); ctx.setStrokeColor(stroke); ctx.setLineWidth(5)
        ctx.drawPath(using: .fillStroke)
        return (CIImage(cgImage: ctx.makeImage()!), CGPoint(x: 14, y: 84))
    }

    static func makeBackground(_ style: CanvasBackground, size: CGSize, image: CIImage?) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        func ci(_ c: RGBA) -> CIColor { CIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        func linear(_ a: RGBA, _ b: RGBA, angle: Double) -> CIImage {
            let rad = angle * .pi / 180
            let half = hypot(size.width, size.height) / 2
            let dx = CGFloat(cos(rad)) * half, dy = CGFloat(-sin(rad)) * half
            let f = CIFilter.linearGradient()
            f.point0 = CGPoint(x: rect.midX - dx, y: rect.midY - dy)
            f.point1 = CGPoint(x: rect.midX + dx, y: rect.midY + dy)
            f.color0 = ci(a); f.color1 = ci(b)
            return f.outputImage!.cropped(to: rect)
        }
        var out: CIImage
        switch style.kind {
        case .color:
            out = CIImage(color: ci(style.colorA)).cropped(to: rect)
        case .gradient:
            out = linear(style.colorA, style.colorB, angle: style.angleDegrees)
        case .wallpaper:
            let def = Wallpapers.all[min(max(style.wallpaperIndex, 0), Wallpapers.all.count - 1)]
            out = linear(def.base.0, def.base.1, angle: def.angle)
            for b in def.blobs {
                let g = CIFilter.radialGradient()
                g.center = CGPoint(x: b.x * size.width, y: b.y * size.height)
                g.radius0 = 0; g.radius1 = Float(b.r * Double(max(size.width, size.height)))
                g.color0 = ci(b.c); g.color1 = CIColor(red: b.c.r, green: b.c.g, blue: b.c.b, alpha: 0)
                out = g.outputImage!.cropped(to: rect).composited(over: out)
            }
        case .image:
            if let img = image {
                let s = max(size.width / img.extent.width, size.height / img.extent.height)
                let scaled = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
                out = scaled.transformed(by: CGAffineTransform(translationX: rect.midX - scaled.extent.midX, y: rect.midY - scaled.extent.midY)).cropped(to: rect)
            } else {
                out = linear(style.colorA, style.colorB, angle: style.angleDegrees)
            }
        }
        if style.blur > 0, style.kind == .wallpaper || style.kind == .image {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = out.clampedToExtent()
            blur.radius = Float(style.blur * 0.03 * Double(size.height))
            out = blur.outputImage!.cropped(to: rect)
        }
        return out
    }
}
