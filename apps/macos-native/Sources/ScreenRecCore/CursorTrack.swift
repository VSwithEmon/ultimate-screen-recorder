import CoreGraphics
import Foundation

/// Cursor metadata queried by time. Times are timeline seconds; positions are normalised to the captured display (top-left origin).
public struct CursorTrack {
    public let events: [CursorEvent]

    public init(events: [CursorEvent], timeShift: Double = 0) {
        self.events = events.map { var e = $0; e.t += timeShift; return e }.sorted { $0.t < $1.t }
    }

    public static let empty = CursorTrack(events: [])
    public var isEmpty: Bool { events.isEmpty }
    public var clicks: [CursorEvent] { events.filter { $0.kind == .down } }

    private func index(atOrBefore t: Double) -> Int? {
        var lo = 0, hi = events.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if events[mid].t <= t { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }

    /// Linear interpolation between neighbouring samples.
    public func rawPosition(at t: Double) -> CGPoint? {
        guard !events.isEmpty else { return nil }
        guard let i = index(atOrBefore: t) else { return CGPoint(x: events[0].x, y: events[0].y) }
        let a = events[i]
        guard i + 1 < events.count else { return CGPoint(x: a.x, y: a.y) }
        let b = events[i + 1]
        let span = b.t - a.t
        let f = span > 0 ? (t - a.t) / span : 0
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// Box-filtered position over [t - window, t + window]; offline so future samples are allowed.
    public func position(at t: Double, smoothing window: Double) -> CGPoint? {
        guard window > 0 else { return rawPosition(at: t) }
        let n = 9
        var sx = 0.0, sy = 0.0, count = 0.0
        for k in 0..<n {
            let tt = t - window + 2 * window * Double(k) / Double(n - 1)
            if let p = rawPosition(at: tt) { sx += p.x; sy += p.y; count += 1 }
        }
        return count > 0 ? CGPoint(x: sx / count, y: sy / count) : nil
    }

    /// Seconds since the pointer last moved (distance above a tiny threshold) as of `t`.
    public func idleTime(at t: Double) -> Double {
        guard var i = index(atOrBefore: t) else { return t }
        let ref = events[i]
        while i > 0 {
            let e = events[i - 1]
            if abs(e.x - ref.x) > 0.001 || abs(e.y - ref.y) > 0.001 { return t - events[i].t }
            i -= 1
        }
        return t - events[0].t
    }
}
