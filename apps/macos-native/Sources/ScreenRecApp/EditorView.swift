import AVKit
import ScreenRecCore
import SwiftUI

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        v.showsFrameSteppingButtons = false
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { if v.player !== player { v.player = player } }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    var onClose: () -> Void
    @State private var confirmDelete = false
    @State private var presetName = ""
    @State private var askPresetName = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            if let err = model.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.bad)
                    Text("This project could not be opened").font(.headline)
                    Text(err).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                    Button("Back to projects", action: onClose).buttonStyle(PrimaryButtonStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.ready {
                ProgressView("Loading project…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        previewTools
                        PreviewArea(model: model).padding(.horizontal, 12)
                        TransportBar(model: model).padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    InspectorRail(model: model)
                    InspectorHost(model: model).frame(width: 330)
                }
                .frame(maxHeight: .infinity)
                Divider().overlay(Theme.line)
                TimelineView(model: model).frame(height: 188)
            }
        }
        .background(Theme.base)
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $model.showCrop) { CropSheet(model: model) }
        .sheet(isPresented: $model.showExport) { ExportSheet(model: model) }
        .alert("Move this project to the Trash?", isPresented: $confirmDelete) {
            Button("Move to Trash", role: .destructive) { if model.moveProjectToTrash() { onClose() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The recording and its edits will be moved to the Trash. You can restore them from there.") }
        .alert("Save preset", isPresented: $askPresetName) {
            TextField("Name", text: $presetName)
            Button("Save") { if !presetName.trimmingCharacters(in: .whitespaces).isEmpty { model.saveCurrentAsPreset(named: presetName) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saves canvas, cursor, camera and audio settings for reuse.") }
        .overlay(alignment: .top) {
            if let n = model.notice {
                Text(n).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.bar, in: Capsule()).overlay(Capsule().stroke(Theme.control))
                    .padding(.top, 54).transition(.opacity)
                    .task(id: n) { try? await Task.sleep(nanoseconds: 3_500_000_000); if model.notice == n { model.notice = nil } }
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.notice)
        // Keyboard: Space plays, ⌘Z undoes, ⌘E exports, Delete removes the selected event.
        .background {
            Group {
                Button("") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button("") { model.undo() }.keyboardShortcut("z", modifiers: .command)
                Button("") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
                Button("") { model.showExport = true }.keyboardShortcut("e", modifiers: .command)
                Button("") { model.deleteSelection() }.keyboardShortcut(.delete, modifiers: [])
            }.opacity(0).allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            IconButton(system: "folder", help: "Show previous projects") { model.saveNow(); onClose() }
            IconButton(system: "trash", help: "Move project to Trash") { confirmDelete = true }
            Spacer()
            Text(model.project.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(".screenrecproj").font(.system(size: 12)).foregroundStyle(Theme.text3)
            Spacer()
            IconButton(system: "arrow.uturn.backward", help: "Undo (⌘Z)", disabled: !model.canUndo) { model.undo() }
            IconButton(system: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", disabled: !model.canRedo) { model.redo() }
            Menu {
                Button("Save current look as preset…") { presetName = ""; askPresetName = true }
                if !model.presets.isEmpty { Divider(); ForEach(model.presets) { p in Button(p.name) { model.apply(p) } } }
                Divider()
                Button("Reset look to defaults") { model.resetStyle() }
            } label: { Label("Presets", systemImage: "sparkles").font(.system(size: 12, weight: .medium)) }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 8)
            Button { model.showExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut("e", modifiers: .command)
        }
        .padding(.horizontal, 12).frame(height: 46).background(Theme.bar)
    }

    private var previewTools: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(AspectPreset.allCases, id: \.self) { a in
                    Button { model.mutate { $0.aspect = a } } label: {
                        if model.edit.aspect == a { Label(a.title, systemImage: "checkmark") } else { Text(a.title) }
                    }
                }
            } label: { Label(model.edit.aspect == .auto ? "Auto" : model.edit.aspect.title, systemImage: "rectangle") }
                .menuStyle(.borderlessButton).fixedSize()
            Button { model.showCrop = true } label: { Label("Crop", systemImage: "crop") }.buttonStyle(.plain)
            Menu {
                Button("Add sensitive data mask") { model.addMask(.sensitive) }
                Button("Add highlight mask") { model.addMask(.highlight) }
            } label: { Label("Mask", systemImage: "rectangle.fill.badge.plus") }.menuStyle(.borderlessButton).fixedSize()
        }
        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
        .frame(maxWidth: .infinity).frame(height: 36)
    }
}

// MARK: - Preview

struct PreviewArea: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            let canvas = model.edit.outputSize(sourceSize: model.sourceSize, targetHeight: 720)
            let fit = fitRect(canvas, in: geo.size)
            ZStack(alignment: .topLeading) {
                PlayerView(player: model.player)
                    .frame(width: fit.width, height: fit.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if case .mask(let id) = model.selection, let m = model.edit.maskEvents.first(where: { $0.id == id }),
                   model.time >= m.start, model.time <= m.end, let r = model.previewRenderer {
                    MaskOverlay(model: model, mask: m, renderer: r, canvas: canvas, fit: fit.size)
                        .frame(width: fit.width, height: fit.height)
                }
            }
            .frame(width: fit.width, height: fit.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .accessibilityLabel("Video preview")
        }
        .frame(minHeight: 200)
    }

    private func fitRect(_ canvas: CGSize, in size: CGSize) -> CGRect {
        let s = min(size.width / canvas.width, size.height / canvas.height)
        let w = canvas.width * s, h = canvas.height * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

/// Draggable rectangle for the selected mask, mapped through the same zoom transform as the renderer.
struct MaskOverlay: View {
    @ObservedObject var model: EditorModel
    let mask: MaskEvent
    let renderer: FrameRenderer
    let canvas: CGSize
    let fit: CGSize
    @State private var dragStart: NormRect?

    var body: some View {
        let ci = renderer.outputRect(mask.rect, at: model.time)
        let sx = fit.width / canvas.width, sy = fit.height / canvas.height
        let r = CGRect(x: ci.minX * sx, y: (canvas.height - ci.maxY) * sy, width: ci.width * sx, height: ci.height * sy)
        let per = renderer.normalizedPerOutputPixel(at: model.time)
        let color = mask.kind == .sensitive ? Theme.maskTint : Theme.blueFocus
        ZStack(alignment: .topLeading) {
            Rectangle().fill(color.opacity(0.18))
                .overlay(Rectangle().stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .gesture(DragGesture().onChanged { v in
                    let s = dragStart ?? mask.rect; dragStart = s
                    update { $0.rect = NormRect(x: s.x + Double(v.translation.width / sx) * per.x, y: s.y + Double(v.translation.height / sy) * per.y, w: s.w, h: s.h).clamped() }
                }.onEnded { _ in dragStart = nil })
            handle(at: CGPoint(x: r.maxX, y: r.maxY)) { v in
                let s = dragStart ?? mask.rect; dragStart = s
                update { $0.rect = NormRect(x: s.x, y: s.y, w: s.w + Double(v.translation.width / sx) * per.x, h: s.h + Double(v.translation.height / sy) * per.y).clamped() }
            }
            handle(at: CGPoint(x: r.minX, y: r.minY)) { v in
                let s = dragStart ?? mask.rect; dragStart = s
                let dx = Double(v.translation.width / sx) * per.x, dy = Double(v.translation.height / sy) * per.y
                update { $0.rect = NormRect(x: s.x + dx, y: s.y + dy, w: s.w - dx, h: s.h - dy).clamped() }
            }
        }
    }

    private func handle(at p: CGPoint, drag: @escaping (DragGesture.Value) -> Void) -> some View {
        Circle().fill(.white).overlay(Circle().stroke(Theme.blue, lineWidth: 2)).frame(width: 12, height: 12)
            .position(p).gesture(DragGesture().onChanged(drag).onEnded { _ in dragStart = nil })
    }

    private func update(_ f: @escaping (inout MaskEvent) -> Void) {
        model.updateMask(mask.id, key: "mask-geom-\(mask.id)", f)
    }
}

// MARK: - Transport

struct TransportBar: View {
    @ObservedObject var model: EditorModel
    @State private var showTrim = false
    var body: some View {
        HStack {
            Menu {
                Toggle("Zooms", isOn: .constant(true)).disabled(true)
                Toggle("Masks", isOn: .constant(true)).disabled(true)
                Toggle("Camera layouts (not available yet)", isOn: .constant(false)).disabled(true)
                Toggle("Shortcuts (not available yet)", isOn: .constant(false)).disabled(true)
            } label: { Label("2 visible timelines", systemImage: "rectangle.bottomhalf.inset.filled").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).fixedSize().foregroundStyle(Theme.text2)
            Spacer()
            IconButton(system: "backward.end", help: "Previous event or trim point") { model.jump(forward: false) }
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.circle" : "play.circle").font(.system(size: 26, weight: .light))
            }.buttonStyle(.plain).help("Play / pause (Space)").accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            IconButton(system: "forward.end", help: "Next event or trim point") { model.jump(forward: true) }
            Spacer()
            Text(timeString(model.time - model.trimStart) + " / " + timeString(model.trimEnd - model.trimStart))
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
            IconButton(system: "scissors", help: "Trim start or end", active: model.edit.trimStart > 0 || model.edit.trimEnd != nil) { showTrim = true }
                .popover(isPresented: $showTrim) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trim").font(.headline)
                        Button("Start recording here") { model.setTrimStartHere(); showTrim = false }
                        Button("End recording here") { model.setTrimEndHere(); showTrim = false }
                        Button("Reset trim") { model.resetTrim(); showTrim = false }.disabled(model.edit.trimStart == 0 && model.edit.trimEnd == nil)
                    }.padding(14).buttonStyle(.link)
                }
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.text2)
            Slider(value: $model.timelineScale, in: 1...8).frame(width: 70).controlSize(.mini).tint(Theme.blue).help("Timeline zoom")
            Text("1×").font(.system(size: 12)).foregroundStyle(Theme.text3).help("Playback speed changes are not available yet")
        }
        .frame(height: 34)
    }

    private func timeString(_ t: Double) -> String {
        let s = max(0, t)
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}

// MARK: - Rail and inspector host

struct InspectorRail: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(spacing: 6) {
            ForEach(EditorPanel.allCases, id: \.self) { p in
                IconButton(system: p.icon, help: p.title, active: model.panel == p) { model.panel = p; model.selection = nil }
            }
            Spacer()
        }
        .padding(.top, 40).padding(.horizontal, 8)
        .frame(width: 46).background(Theme.base)
    }
}

struct InspectorHost: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        Group {
            switch model.selection {
            case .zoom(let id): ZoomInspector(model: model, id: id)
            case .mask(let id): MaskInspector(model: model, id: id)
            case nil:
                switch model.panel {
                case .canvas: CanvasInspector(model: model)
                case .cursor: CursorInspector(model: model)
                case .camera: CameraInspector(model: model)
                case .captions: CaptionsInspector()
                case .audio: AudioInspector(model: model)
                case .shortcuts: ShortcutsInspector()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.trailing, 10).padding(.bottom, 8)
    }
}
