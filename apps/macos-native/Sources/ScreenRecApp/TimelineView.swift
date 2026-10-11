import ScreenRecCore
import SwiftUI

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    private let rulerH: CGFloat = 24, clipH: CGFloat = 40, rowH: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let labelW: CGFloat = 0
            let width = max(geo.size.width - 24, 100) * model.timelineScale
            let pps = width / max(model.duration, 0.1)
            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: model.timelineScale > 1) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            ruler(pps: pps, width: width)
                            clip(pps: pps, width: width)
                            eventRow(pps: pps, width: width, zooms: true)
                            eventRow(pps: pps, width: width, zooms: false)
                        }
                        Playhead(model: model, clock: model.clock, pps: pps)
                    }
                    .frame(width: width, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 4)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        guard v.startLocation.y < rulerH + clipH + 12 else { return }
                        model.seek(to: (v.location.x - 12) / pps)
                    })
                }
                insertButton.offset(x: 12 + labelW, y: geo.size.height - 44)
            }
        }
        .background(Theme.base)
    }

    // MARK: Rows

    private func ruler(pps: CGFloat, width: CGFloat) -> some View {
        // Pick the smallest "nice" step that keeps labels >= 56 pt apart and the tick count bounded.
        let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]
        let step = steps.first { CGFloat($0) * pps >= 56 && model.duration / $0 <= 120 } ?? steps.last!
        return ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: 0.0, through: model.duration, by: step)), id: \.self) { t in
                VStack(spacing: 2) {
                    Text(String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
                    Rectangle().fill(Theme.line).frame(width: 1, height: 5)
                }.position(x: CGFloat(t) * pps + 12, y: rulerH / 2)
            }
        }.frame(width: width, height: rulerH)
    }

    private func clip(pps: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Theme.clip, Color(hex: 0xD97706)], startPoint: .top, endPoint: .bottom))
            WaveShape(peaks: model.waveform).fill(Color(hex: 0x78350F, opacity: 0.55)).padding(.vertical, 5)
            HStack(spacing: 6) {
                Text("Clip").fontWeight(.semibold)
                Text("\(Int(max(0, model.trimEnd - model.trimStart).rounded()))s")
                Label("1×", systemImage: "gauge").labelStyle(.titleAndIcon)
            }.font(.system(size: 12)).foregroundStyle(Color(hex: Palette.clipText)).frame(maxWidth: .infinity)
            // Trimmed-away regions.
            Rectangle().fill(Color.black.opacity(0.62)).frame(width: CGFloat(model.trimStart) * pps)
            Rectangle().fill(Color.black.opacity(0.62)).frame(width: max(0, CGFloat(model.duration - model.trimEnd) * pps))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: width, height: clipH)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Recording clip")
    }

    private func eventRow(pps: CGFloat, width: CGFloat, zooms: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6).fill(Theme.panel.opacity(0.4))
            if zooms {
                ForEach(model.edit.zoomEvents) { z in
                    EventBlock(model: model, start: z.start, end: z.end, pps: pps, color: Theme.blue,
                               label: String(format: "%.1f× · %@", z.scale, z.mode == .auto ? "Auto" : "Manual"), icon: "magnifyingglass",
                               selected: model.selection == .zoom(z.id), snapPoints: snapPoints(excluding: z.id),
                               select: { model.selection = .zoom(z.id) },
                               change: { s, e in model.updateZoom(z.id, key: "zoom-time-\(z.id)") { $0.start = s; $0.end = e } })
                }
            } else {
                ForEach(model.edit.maskEvents) { m in
                    EventBlock(model: model, start: m.start, end: m.end, pps: pps,
                               color: m.kind == .sensitive ? Theme.maskTint : Theme.highlightTint,
                               label: m.kind == .sensitive ? "Sensitive mask" : "Highlight", icon: "rectangle.fill",
                               selected: model.selection == .mask(m.id), snapPoints: snapPoints(excluding: m.id),
                               select: { model.selection = .mask(m.id); model.seek(to: max(m.start, min(model.time, m.end))) },
                               change: { s, e in model.updateMask(m.id, key: "mask-time-\(m.id)") { $0.start = s; $0.end = e } })
                }
            }
        }
        .frame(width: width, height: rowH)
        .accessibilityLabel(zooms ? "Zoom events" : "Mask events")
    }

    private func snapPoints(excluding id: UUID) -> [Double] {
        [model.time, model.trimStart, model.trimEnd, 0, model.duration]
            + model.edit.zoomEvents.filter { $0.id != id }.flatMap { [$0.start, $0.end] }
            + model.edit.maskEvents.filter { $0.id != id }.flatMap { [$0.start, $0.end] }
    }

    private var insertButton: some View {
        Menu {
            Section("Zoom") {
                Button("Automatic zoom") { model.generateAutomaticZoom() }
                Button("Manual zoom") { model.addManualZoom() }
            }
            Section("Camera") {
                Button(model.edit.camera.hidden ? "Show webcam" : "Hide webcam") { model.mutate { $0.camera.hidden.toggle() } }.disabled(!model.hasCamera)
                Button("Fullscreen camera layout (not available yet)") {}.disabled(true)
            }
            Section("Mask") {
                Button("Sensitive data mask") { model.addMask(.sensitive) }
                Button("Highlight mask") { model.addMask(.highlight) }
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Theme.blue, in: Circle()).shadow(color: Theme.blue.opacity(0.5), radius: 8, y: 3)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Insert event")
        .accessibilityLabel("Insert event")
    }
}

struct EventBlock: View {
    @ObservedObject var model: EditorModel
    let start: Double, end: Double, pps: CGFloat
    let color: Color
    let label: String, icon: String
    let selected: Bool
    let snapPoints: [Double]
    let select: () -> Void
    let change: (Double, Double) -> Void
    @State private var base: (Double, Double)?

    var body: some View {
        let w = max(CGFloat(end - start) * pps, 14)
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(color)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.white : Color.white.opacity(0.14), lineWidth: selected ? 2 : 1))
            HStack(spacing: 4) { Image(systemName: icon).font(.system(size: 9)); Text(label).lineLimit(1) }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 8)
            if selected {
                HStack { grip(.leading); Spacer(); grip(.trailing) }
            }
        }
        .frame(width: w, height: 28)
        .offset(x: CGFloat(start) * pps + 12 - 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: -12 + 12)
        .gesture(DragGesture(minimumDistance: 2).onChanged { v in
            select()
            let b = base ?? (start, end); base = b
            let len = b.1 - b.0
            var s = b.0 + Double(v.translation.width / pps)
            s = snap(s, edgeAlso: s + len) ?? s
            s = min(max(s, 0), max(0, model.duration - len))
            change(s, s + len)
        }.onEnded { _ in base = nil })
        .onTapGesture { select() }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func grip(_ side: HorizontalAlignment) -> some View {
        Capsule().fill(.white).frame(width: 3, height: 14).padding(.horizontal, 3)
            .frame(width: 14, height: 28).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let b = base ?? (start, end); base = b
                let d = Double(v.translation.width / pps)
                if side == .leading {
                    var s = b.0 + d; s = snap(s, edgeAlso: nil) ?? s
                    change(min(max(s, 0), b.1 - 0.3), b.1)
                } else {
                    var e = b.1 + d; e = snap(e, edgeAlso: nil) ?? e
                    change(b.0, max(min(e, model.duration), b.0 + 0.3))
                }
            }.onEnded { _ in base = nil })
    }

    private func snap(_ value: Double, edgeAlso other: Double?) -> Double? {
        let tol = Double(6 / pps)
        if let p = snapPoints.first(where: { abs($0 - value) < tol }) { return p }
        if let o = other, let p = snapPoints.first(where: { abs($0 - o) < tol }) { return value + (p - o) }
        return nil
    }
}

struct WaveShape: Shape {
    let peaks: [Float]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard !peaks.isEmpty else { return p }
        let step = rect.width / CGFloat(peaks.count)
        let mid = rect.midY
        for (i, v) in peaks.enumerated() {
            let h = max(1.5, CGFloat(v) * rect.height)
            p.addRoundedRect(in: CGRect(x: CGFloat(i) * step, y: mid - h / 2, width: max(step * 0.7, 0.8), height: h), cornerSize: CGSize(width: 0.5, height: 0.5))
        }
        return p
    }
}


/// The only timeline element that redraws every frame during playback.
struct Playhead: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var clock: PlaybackClock
    let pps: CGFloat
    private let rulerH: CGFloat = 24, clipH: CGFloat = 40, rowH: CGFloat = 32

    var body: some View {
        let x = CGFloat(clock.time) * pps + 12
        let h = rulerH + clipH + rowH * 2 + 18
        ZStack(alignment: .top) {
            Rectangle().fill(Theme.blueFocus).frame(width: 2)
            Circle().fill(Theme.blueFocus).frame(width: 11, height: 11).offset(y: -3)
        }
        .frame(width: 14, height: h)
        .position(x: x, y: h / 2 + 2)
        .gesture(DragGesture().onChanged { v in model.seek(to: Double((v.location.x + x - 7 - 12) / pps)) })
        .accessibilityLabel("Playhead")
    }
}
