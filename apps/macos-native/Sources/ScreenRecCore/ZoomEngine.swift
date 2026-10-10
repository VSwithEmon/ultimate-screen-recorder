import CoreGraphics
import Foundation

public struct ZoomState: Equatable {
    public var scale: Double
    /// Centre of the visible window, normalised, top-left origin, cropped-source space.
    public var focus: CGPoint
    public static let identity = ZoomState(scale: 1, focus: CGPoint(x: 0.5, y: 0.5))
}

/// One evaluation engine shared by preview and export.
public enum ZoomEngine {
    public static let easeSeconds = 0.55

    public static func easeInOut(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
    }

    /// Amount 0...1 that the event is "applied" at `t` (eased in at the start, out at the end).
    public static func amount(of e: ZoomEvent, at t: Double) -> Double {
        guard e.end > e.start, t >= e.start, t <= e.end else { return 0 }
        if e.instant { return 1 }
        let d = min(easeSeconds, (e.end - e.start) / 2.2)
        guard d > 0 else { return 1 }
        return easeInOut((t - e.start) / d) * easeInOut((e.end - t) / d)
    }

    /// `autoFocus` returns the smoothed cursor position (cropped-source space) at a time.
    public static func state(at t: Double, events: [ZoomEvent], autoFocus: (Double) -> CGPoint?) -> ZoomState {
        var best: (ZoomEvent, Double)?
        for e in events {
            let a = amount(of: e, at: t)
            if a > 0, a > (best?.1 ?? 0) { best = (e, a) }
        }
        guard let (e, a) = best else { return .identity }
        let scale = 1 + (e.scale - 1) * a
        var focus = e.focus
        if e.mode == .auto {
            // Hold the focus inside the event so the easing in/out phases do not drift.
            focus = autoFocus(min(max(t, e.start), e.end)) ?? e.focus
        }
        // Blend toward the centre while easing so entering/leaving does not jump.
        focus = CGPoint(x: 0.5 + (focus.x - 0.5) * a, y: 0.5 + (focus.y - 0.5) * a)
        return ZoomState(scale: scale, focus: clampFocus(focus, scale: scale))
    }

    /// Keep the visible window inside the content.
    public static func clampFocus(_ f: CGPoint, scale: Double) -> CGPoint {
        let half = 0.5 / max(scale, 1)
        return CGPoint(x: min(max(f.x, half), 1 - half), y: min(max(f.y, half), 1 - half))
    }

    /// Builds zoom events from click activity: clicks closer than `gap` share one event.
    public static func autoEvents(from clicks: [CursorEvent], duration: Double, scale: Double = 1.8,
                                  lead: Double = 0.6, tail: Double = 1.4, gap: Double = 2.5) -> [ZoomEvent] {
        guard duration > 0 else { return [] }
        var spans: [(Double, Double)] = []
        for c in clicks.sorted(by: { $0.t < $1.t }) {
            let s = max(0, c.t - lead), e = min(duration, c.t + tail)
            if e - s < 0.3 { continue }
            if let last = spans.last, c.t - lead <= last.1 + (gap - lead - tail > 0 ? gap - lead - tail : 0) {
                spans[spans.count - 1].1 = max(last.1, e)
            } else {
                spans.append((s, e))
            }
        }
        return spans.map { ZoomEvent(start: $0.0, end: $0.1, scale: scale, mode: .auto) }
    }
}
