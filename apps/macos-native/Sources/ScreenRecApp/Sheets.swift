import AVFoundation
import ScreenRecCore
import SwiftUI

// MARK: - Export

struct ExportSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var options = EditorModel.ExportOptions()

    var body: some View {
        let est = model.estimatedSize(options)
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.system(size: 18, weight: .bold))
            Group {
                row("Resolution") {
                    ChipPicker(options: [(720, "720p"), (1080, "1080p"), (1440, "1440p"), (2160, "4K")], selection: $options.height)
                }
                row("Format") {
                    ChipPicker(options: [(false, "MP4 · H.264"), (true, "MP4 · HEVC")], selection: $options.hevc)
                }
                row("Frame rate") {
                    ChipPicker(options: [(24, "24"), (30, "30"), (60, "60")], selection: $options.fps)
                }
            }
            .disabled(model.exportProgress != nil)
            if options.height == 2160 || options.fps == 60 {
                Label("4K and 60 fps depend on your Mac and the source. The recording is \(Int(model.sourceSize.width))×\(Int(model.sourceSize.height)); upscaling does not add detail.",
                      systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            HStack {
                Text("\(Int(est.dims.width))×\(Int(est.dims.height)) · about \(est.megabytes < 1 ? "<1" : String(Int(est.megabytes))) MB · no watermark")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                Spacer()
            }
            if let p = model.exportProgress {
                ProgressView(value: p) { Text("Rendering… \(Int(p * 100))%").font(.system(size: 12)) }.tint(Theme.blue)
            }
            if let m = model.exportMessage { Text(m).font(.system(size: 12)).foregroundStyle(Theme.text2).textSelection(.enabled) }
            HStack {
                Spacer()
                if model.exportProgress != nil {
                    Button("Cancel export") { model.cancelExport() }.buttonStyle(QuietButtonStyle())
                } else {
                    Button("Close") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("Choose location and export…") { Task { await model.export(options) } }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22).frame(width: 520).background(Theme.panel).foregroundStyle(Theme.text)
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack { Text(title).font(.system(size: 12, weight: .semibold)).frame(width: 90, alignment: .leading); content() }
    }
}

// MARK: - Crop

struct CropSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var rect = NormRect.full
    @State private var image: CGImage?
    @State private var ratio: Double?   // width/height, nil = any
    @State private var dragBase: NormRect?

    private var src: CGSize { model.sourceSize }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("Size").foregroundStyle(Theme.text3)
                numberField(value: Binding(get: { rect.w * src.width }, set: { setSize(w: $0, h: nil) }))
                Text("×").foregroundStyle(Theme.text3)
                numberField(value: Binding(get: { rect.h * src.height }, set: { setSize(w: nil, h: $0) }))
                Menu {
                    Button("Any") { ratio = nil }
                    Button("16:9") { setRatio(16.0 / 9) }
                    Button("4:3") { setRatio(4.0 / 3) }
                    Button("1:1") { setRatio(1) }
                    Button("9:16") { setRatio(9.0 / 16) }
                } label: { Label(ratioTitle, systemImage: "rectangle") }.menuStyle(.borderlessButton).fixedSize()
                Text("Position").foregroundStyle(Theme.text3)
                numberField(value: Binding(get: { rect.x * src.width }, set: { move(x: $0, y: nil) }))
                numberField(value: Binding(get: { rect.y * src.height }, set: { move(x: nil, y: $0) }))
                Spacer()
                Button { rect = .full; ratio = nil } label: { Label("Reset", systemImage: "crop") }.buttonStyle(QuietButtonStyle())
            }
            .font(.system(size: 12))

            GeometryReader { geo in
                let fit = fitSize(geo.size)
                ZStack(alignment: .topLeading) {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().frame(width: fit.width, height: fit.height)
                    } else {
                        Rectangle().fill(Theme.bar).frame(width: fit.width, height: fit.height)
                    }
                    Path { p in p.addRect(CGRect(origin: .zero, size: fit)); p.addRect(viewRect(fit)) }
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    Rectangle().stroke(Color.white, lineWidth: 1.5).frame(width: viewRect(fit).width, height: viewRect(fit).height)
                        .position(x: viewRect(fit).midX, y: viewRect(fit).midY)
                        .overlay {
                            // Rule-of-thirds guides.
                            Path { p in
                                let r = viewRect(fit)
                                for i in 1...2 {
                                    let f = CGFloat(i) / 3
                                    p.move(to: CGPoint(x: r.minX + r.width * f, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + r.width * f, y: r.maxY))
                                    p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * f)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * f))
                                }
                            }.stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                        }
                        .allowsHitTesting(false)
                    // Body drag.
                    Color.clear.contentShape(Rectangle()).frame(width: viewRect(fit).width, height: viewRect(fit).height)
                        .position(x: viewRect(fit).midX, y: viewRect(fit).midY)
                        .gesture(DragGesture().onChanged { v in
                            let b = dragBase ?? rect; dragBase = b
                            rect = NormRect(x: b.x + Double(v.translation.width / fit.width), y: b.y + Double(v.translation.height / fit.height), w: b.w, h: b.h).clamped()
                        }.onEnded { _ in dragBase = nil })
                    ForEach(0..<4, id: \.self) { corner in
                        let r = viewRect(fit)
                        let p = CGPoint(x: corner % 2 == 0 ? r.minX : r.maxX, y: corner < 2 ? r.minY : r.maxY)
                        Circle().fill(.white).overlay(Circle().stroke(Theme.blue, lineWidth: 2)).frame(width: 13, height: 13).position(p)
                            .gesture(DragGesture().onChanged { v in resize(corner: corner, translation: v.translation, fit: fit) }.onEnded { _ in dragBase = nil })
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(width: 780, height: 440)

            HStack {
                Text("Crop is non-destructive: the original recording is untouched.").font(.system(size: 12)).foregroundStyle(Theme.text3)
                Spacer()
                Button("Discard changes") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button { model.mutate { $0.crop = rect.clamped() }; dismiss() } label: { Label("Confirm changes", systemImage: "return") }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).background(Theme.panel).foregroundStyle(Theme.text)
        .task {
            rect = model.edit.crop
            image = await Self.frame(model: model)
        }
    }

    private var ratioTitle: String {
        guard let r = ratio else { return "Any" }
        if abs(r - 16.0 / 9) < 0.01 { return "16:9" }; if abs(r - 4.0 / 3) < 0.01 { return "4:3" }
        if abs(r - 1) < 0.01 { return "1:1" }; return "9:16"
    }

    private func numberField(value: Binding<Double>) -> some View {
        TextField("", value: Binding(get: { value.wrappedValue.rounded() }, set: { value.wrappedValue = $0 }), format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.roundedBorder).frame(width: 64).multilineTextAlignment(.trailing)
    }

    private func fitSize(_ s: CGSize) -> CGSize {
        let k = min(s.width / src.width, s.height / src.height)
        return CGSize(width: src.width * k, height: src.height * k)
    }
    private func viewRect(_ fit: CGSize) -> CGRect {
        CGRect(x: rect.x * fit.width, y: rect.y * fit.height, width: rect.w * fit.width, height: rect.h * fit.height)
    }

    private func setSize(w: Double?, h: Double?) {
        var n = rect
        if let w { n.w = w / src.width; if let r = ratio { n.h = n.w * src.width / r / src.height } }
        if let h { n.h = h / src.height; if let r = ratio { n.w = n.h * src.height * r / src.width } }
        rect = n.clamped()
    }
    private func move(x: Double?, y: Double?) {
        var n = rect
        if let x { n.x = x / src.width }; if let y { n.y = y / src.height }
        rect = n.clamped()
    }
    private func setRatio(_ r: Double) {
        ratio = r
        var n = rect
        n.h = n.w * src.width / r / src.height
        if n.h > 1 { n.h = 1; n.w = n.h * src.height * r / src.width }
        rect = n.clamped()
    }

    private func resize(corner: Int, translation t: CGSize, fit: CGSize) {
        let b = dragBase ?? rect; dragBase = b
        let dx = Double(t.width / fit.width), dy = Double(t.height / fit.height)
        var x0 = b.x, y0 = b.y, x1 = b.x + b.w, y1 = b.y + b.h
        if corner % 2 == 0 { x0 += dx } else { x1 += dx }
        if corner < 2 { y0 += dy } else { y1 += dy }
        x0 = min(max(x0, 0), x1 - 0.05); x1 = max(min(x1, 1), x0 + 0.05)
        y0 = min(max(y0, 0), y1 - 0.05); y1 = max(min(y1, 1), y0 + 0.05)
        var n = NormRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
        if let r = ratio {
            let h = n.w * src.width / r / src.height
            if corner < 2 { n.y = y1 - h } else { n.y = y0 }
            n.h = h
        }
        rect = n.clamped()
    }

    @MainActor static func frame(model: EditorModel) async -> CGImage? {
        guard let s = model.project.sources.first(where: { $0.type == .screen }) else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: ProjectStore.resolve(s, in: model.url)))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1600, height: 1000)
        let t = model.time + (model.session?.origin ?? 0) - s.startOffset
        return try? await gen.image(at: CMTime(seconds: max(0, t), preferredTimescale: 600)).image
    }
}
