import AppKit
import ScreenRecCore
import SwiftUI
import UniformTypeIdentifiers

extension EditorModel {
    func updateZoom(_ id: UUID, key: String? = nil, _ f: @escaping (inout ZoomEvent) -> Void) {
        mutate(key ?? "zoom-\(id)") { e in if let i = e.zoomEvents.firstIndex(where: { $0.id == id }) { f(&e.zoomEvents[i]) } }
    }
    func updateMask(_ id: UUID, key: String? = nil, _ f: @escaping (inout MaskEvent) -> Void) {
        mutate(key ?? "mask-\(id)") { e in if let i = e.maskEvents.firstIndex(where: { $0.id == id }) { f(&e.maskEvents[i]) } }
    }
}

private func rgbaBinding(_ get: @escaping () -> RGBA, _ set: @escaping (RGBA) -> Void) -> Binding<Color> {
    Binding(get: { let c = get(); return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) },
            set: { color in
                let n = NSColor(color).usingColorSpace(.sRGB) ?? .black
                set(RGBA(Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent), Double(n.alphaComponent)))
            })
}

// MARK: Canvas

struct CanvasInspector: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        Panel {
            InspectorSection(title: "Background") {
                ChipPicker(options: [(CanvasBackground.Kind.wallpaper, "Wallpaper"), (.gradient, "Gradient"), (.color, "Color"), (.image, "Image")],
                           selection: Binding(get: { model.edit.background.kind }, set: { k in model.mutate { $0.background.kind = k } }))
            }
            switch model.edit.background.kind {
            case .wallpaper:
                WallpaperPicker(model: model)
                SliderRow(title: "Background blur", value: Binding(get: { model.edit.background.blur }, set: { v in model.mutate("bg-blur") { $0.background.blur = v } }), defaultValue: 0)
            case .gradient:
                InspectorSection(title: "Gradient") {
                    HStack {
                        ColorPicker("From", selection: rgbaBinding({ model.edit.background.colorA }, { c in model.mutate("bgA") { $0.background.colorA = c } }))
                        ColorPicker("To", selection: rgbaBinding({ model.edit.background.colorB }, { c in model.mutate("bgB") { $0.background.colorB = c } }))
                    }.font(.system(size: 12))
                    SliderRow(title: "Angle", value: Binding(get: { model.edit.background.angleDegrees }, set: { v in model.mutate("bg-angle") { $0.background.angleDegrees = v } }),
                              range: 0...360, defaultValue: 135, format: { String(format: "%.0f°", $0) })
                }
            case .color:
                InspectorSection(title: "Color") {
                    ColorPicker("Background color", selection: rgbaBinding({ model.edit.background.colorA }, { c in model.mutate("bgA") { $0.background.colorA = c } })).font(.system(size: 12))
                }
            case .image:
                InspectorSection(title: "Background image", subtitle: "Choose an image from your computer. It is copied into the project.") {
                    Button { chooseImage() } label: {
                        Label(model.edit.background.imagePath == nil ? "Choose image…" : "Replace image…", systemImage: "photo").frame(maxWidth: .infinity)
                    }.buttonStyle(QuietButtonStyle()).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.control))
                    if let p = model.edit.background.imagePath { Text(p).font(.system(size: 12)).foregroundStyle(Theme.text3) }
                }
                SliderRow(title: "Background blur", value: Binding(get: { model.edit.background.blur }, set: { v in model.mutate("bg-blur") { $0.background.blur = v } }), defaultValue: 0)
            }
            Divider().overlay(Theme.line)
            SliderRow(title: "Padding", value: model.binding(\.padding), range: 0...0.3, defaultValue: 0.08)
            SliderRow(title: "Rounded corners", value: model.binding(\.cornerRadius), range: 0...0.1, defaultValue: 0.025, format: { String(format: "%.1f%%", $0 * 100) })
            ToggleRow(title: "Shadow", isOn: model.binding(\.shadow))
        }
    }

    private func rgb(_ c: RGBA) -> Color { Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1) }

    private func chooseImage() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { model.importBackgroundImage(from: u) }
    }
}

// MARK: Zoom

struct ZoomInspector: View {
    @ObservedObject var model: EditorModel
    let id: UUID
    var body: some View {
        if let z = model.edit.zoomEvents.first(where: { $0.id == id }) {
            Panel {
                Button { model.selection = nil } label: { Label("Close zoom editor", systemImage: "arrow.left") }
                    .buttonStyle(QuietButtonStyle()).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.control))
                InspectorSection(title: "Zoom level", subtitle: "How close to zoom during this zoom phase") {
                    SliderRow(title: "", value: Binding(get: { z.scale }, set: { v in model.updateZoom(id) { $0.scale = v } }),
                              range: 1.1...4, defaultValue: 1.8, format: { String(format: "%.1f×", $0) })
                    Button { model.mutate { e in for i in e.zoomEvents.indices { e.zoomEvents[i].scale = z.scale } } } label: {
                        Label("Apply zoom level to all other zooms", systemImage: "plus.square").frame(maxWidth: .infinity)
                    }.buttonStyle(QuietButtonStyle()).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.control))
                }
                InspectorSection(title: "Zoom mode", subtitle: z.mode == .auto
                                 ? (model.hasCursorData ? "The zoomed view follows the mouse cursor." : "No cursor data was recorded, so this will stay centred. Use Manual to choose a point.")
                                 : "The zoomed view stays on the point you choose.") {
                    ChipPicker(options: [(ZoomEvent.Mode.auto, "Auto"), (.manual, "Manual")],
                               selection: Binding(get: { z.mode }, set: { m in model.updateZoom(id) { $0.mode = m } }))
                    if z.mode == .manual {
                        FocusPicker(focus: Binding(get: { z.focus }, set: { p in model.updateZoom(id, key: "zoom-focus-\(id)") { $0.focus = p } }), scale: z.scale)
                    }
                }
                ToggleRow(title: "Instant animation", subtitle: "Apply the zoom immediately instead of easing in and out.",
                          isOn: Binding(get: { z.instant }, set: { v in model.updateZoom(id) { $0.instant = v } }))
                Divider().overlay(Theme.line)
                Button(role: .destructive) { model.deleteSelection() } label: { Label("Delete zoom", systemImage: "trash") }
                    .buttonStyle(QuietButtonStyle()).foregroundStyle(Theme.bad).padding(.top, 8)
            }
        }
    }
}

/// Click or drag to set the manual zoom focus; the outlined window shows what will be visible.
struct FocusPicker: View {
    @Binding var focus: CGPoint
    let scale: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let c = ZoomEngine.clampFocus(focus, scale: scale)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.bar).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.control))
                Rectangle().fill(Theme.blueTint).overlay(Rectangle().stroke(Theme.blueBright, lineWidth: 1.5))
                    .frame(width: w / scale, height: h / scale).position(x: c.x * w, y: c.y * h)
                Circle().fill(.white).frame(width: 8, height: 8).position(x: c.x * w, y: c.y * h)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                focus = CGPoint(x: min(max(v.location.x / w, 0), 1), y: min(max(v.location.y / h, 0), 1))
            })
        }
        .aspectRatio(16.0 / 10, contentMode: .fit)
        .accessibilityLabel("Manual zoom focus point")
        .help("Click or drag to choose the zoom focus")
    }
}

// MARK: Mask

struct MaskInspector: View {
    @ObservedObject var model: EditorModel
    let id: UUID
    var body: some View {
        if let m = model.edit.maskEvents.first(where: { $0.id == id }) {
            Panel {
                Button { model.selection = nil } label: { Label("Close mask editor", systemImage: "arrow.left") }
                    .buttonStyle(QuietButtonStyle()).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.control))
                InspectorSection(title: m.kind == .sensitive ? "Sensitive data mask" : "Highlight mask",
                                 subtitle: m.kind == .sensitive ? "Covers the selected area for the time it spans on the timeline. Drag the box in the preview to move or resize it."
                                                               : "Dims everything outside the selected area while it is active.") {
                    if m.kind == .sensitive {
                        ChipPicker(options: [(MaskEvent.Style.solid, "Solid cover"), (.pixelate, "Pixelate")],
                                   selection: Binding(get: { m.style }, set: { s in model.updateMask(id) { $0.style = s } }))
                        if m.style == .pixelate {
                            Label("Pixelation can leave text partly readable. Use Solid cover for passwords, keys and personal data.", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12)).foregroundStyle(Color(hex: 0xFCD34D))
                        }
                    }
                }
                Button(role: .destructive) { model.deleteSelection() } label: { Label("Delete mask", systemImage: "trash") }
                    .buttonStyle(QuietButtonStyle()).foregroundStyle(Theme.bad)
            }
        }
    }
}

// MARK: Cursor

struct CursorInspector: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        Panel {
            if model.cursorBaked {
                Notice(text: "The cursor was recorded inside the video, so it can't be restyled in this project. New recordings keep it separate.")
            } else if !model.hasCursorData {
                Notice(text: "No cursor data was recorded for this project, so cursor effects, smoothing and automatic zoom are unavailable.")
            }
            let off = model.cursorBaked || !model.hasCursorData
            Group {
                SliderRow(title: "Cursor size", value: Binding(get: { model.edit.cursor.size }, set: { v in model.mutate("cur-size") { $0.cursor.size = v } }),
                          range: 0.5...3, defaultValue: 1, format: { String(format: "%.1f×", $0) })
                InspectorSection(title: "Cursor style") {
                    ChipPicker(options: [(CursorSettings.Style.arrow, "Arrow"), (.outline, "Outline"), (.dot, "Dot")],
                               selection: Binding(get: { model.edit.cursor.style }, set: { s in model.mutate { $0.cursor.style = s } }))
                }
                ToggleRow(title: "Hide cursor if not moving", isOn: Binding(get: { model.edit.cursor.hideWhenIdle }, set: { v in model.mutate { $0.cursor.hideWhenIdle = v } }))
                ToggleRow(title: "Hide cursor", isOn: Binding(get: { !model.edit.cursor.visible }, set: { v in model.mutate { $0.cursor.visible = !v } }))
                Divider().overlay(Theme.line)
                InspectorSection(title: "Click effect") {
                    ChipPicker(options: [(CursorSettings.ClickEffect.none, "None"), (.circle, "Circle"), (.ripple, "Ripple")],
                               selection: Binding(get: { model.edit.cursor.clickEffect }, set: { s in model.mutate { $0.cursor.clickEffect = s } }))
                }
                Divider().overlay(Theme.line)
                SliderRow(title: "Smoothing", value: Binding(get: { model.edit.cursor.smoothing }, set: { v in model.mutate("cur-smooth") { $0.cursor.smoothing = v } }),
                          range: 0...0.5, defaultValue: 0.12, format: { String(format: "%.2fs", $0) })
                ToggleRow(title: "Remove cursor shakes", subtitle: "Smooths sudden, short movements.", isOn: Binding(get: { model.edit.cursor.removeShakes }, set: { v in model.mutate { $0.cursor.removeShakes = v } }))
                SliderRow(title: "Stop cursor before the end", value: Binding(get: { model.edit.cursor.stopBeforeEnd }, set: { v in model.mutate("cur-stop") { $0.cursor.stopBeforeEnd = v } }),
                          range: 0...3, defaultValue: 0, format: { $0 == 0 ? "Off" : String(format: "%.1fs", $0) })
                Text("Click sounds and cursor rotation are not available yet.").font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.top, 6)
            }
            .disabled(off).opacity(off ? 0.45 : 1)
        }
    }
}

struct Notice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Theme.text2)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bar, in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 8)
    }
}

// MARK: Camera

struct CameraInspector: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        Panel {
            if !model.hasCamera {
                Notice(text: "No camera was recorded in this project. Turn on Camera before recording to add a webcam layer.")
            }
            Group {
                InspectorSection(title: "Camera position") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(0..<9, id: \.self) { i in
                            Button { model.mutate { $0.camera.position = i } } label: {
                                Circle().fill(model.edit.camera.position == i ? Theme.blueBright : Theme.hover).frame(width: 14, height: 14)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }.buttonStyle(.plain).accessibilityLabel("Position \(i + 1)")
                        }
                    }
                    .padding(8).background(Theme.bar, in: RoundedRectangle(cornerRadius: 8))
                }
                SliderRow(title: "Camera size", value: Binding(get: { model.edit.camera.size }, set: { v in model.mutate("cam-size") { $0.camera.size = v } }), range: 0.1...0.5, defaultValue: 0.22)
                SliderRow(title: "Roundness", value: Binding(get: { model.edit.camera.roundness }, set: { v in model.mutate("cam-round") { $0.camera.roundness = v } }), defaultValue: 0.5)
                InspectorSection(title: "Shape") {
                    ChipPicker(options: [(CameraSettings.Shape.square, "Square"), (.horizontal, "Horizontal"), (.vertical, "Vertical"), (.original, "Original")],
                               selection: Binding(get: { model.edit.camera.shape }, set: { s in model.mutate { $0.camera.shape = s } }))
                }
                ToggleRow(title: "Mirror horizontally", isOn: Binding(get: { model.edit.camera.mirror }, set: { v in model.mutate { $0.camera.mirror = v } }))
                ToggleRow(title: "Hide camera", isOn: Binding(get: { model.edit.camera.hidden }, set: { v in model.mutate { $0.camera.hidden = v } }))
                Text("Camera layouts over time and size-during-zoom are not available yet.").font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.top, 6)
            }
            .disabled(!model.hasCamera).opacity(model.hasCamera ? 1 : 0.45)
        }
    }
}

// MARK: Audio / Captions / Shortcuts

struct AudioInspector: View {
    @ObservedObject var model: EditorModel
    @StateObject private var previewer = MusicPreviewer()
    private let library = MusicLibrary.shared

    var body: some View {
        let hasMic = model.project.sources.contains { $0.type == .microphone }
        let hasSys = model.project.sources.contains { $0.type == .systemAudio }
        Panel {
            if !hasMic && !hasSys { Notice(text: "This recording has no audio tracks. You can still add background music.") }
            InspectorSection(title: "Microphone") {
                ToggleRow(title: "Mute microphone", isOn: Binding(get: { model.edit.audio.muteMicrophone }, set: { v in model.mutate { $0.audio.muteMicrophone = v } }), disabled: !hasMic)
                SliderRow(title: "Microphone volume", value: Binding(get: { model.edit.audio.micGain }, set: { v in model.mutate("mic-gain") { $0.audio.micGain = v } }),
                          range: 0...2, defaultValue: 1).disabled(!hasMic)
            }
            InspectorSection(title: "System audio") {
                SliderRow(title: "System audio volume", value: Binding(get: { model.edit.audio.systemGain }, set: { v in model.mutate("sys-gain") { $0.audio.systemGain = v } }),
                          range: 0...2, defaultValue: 1).disabled(!hasSys)
            }
            Divider().overlay(Theme.line)
            musicSection
            Text("Noise reduction is planned for a later phase.").font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.top, 8)
        }
        .onDisappear { previewer.stop() }
    }

    @ViewBuilder private var musicSection: some View {
        InspectorSection(title: "Background music", subtitle: "Plays under your recording, loops to fill it, and fades in and out.") {
            if let m = model.edit.audio.music {
                HStack {
                    Image(systemName: "music.note").foregroundStyle(Theme.blueFocus)
                    Text(m.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button("Remove") { model.removeMusic() }.buttonStyle(QuietButtonStyle()).foregroundStyle(Theme.bad)
                }
                .padding(10).background(Theme.bar, in: RoundedRectangle(cornerRadius: 8))
                SliderRow(title: "Music volume", value: Binding(get: { m.gain }, set: { v in model.mutate("music-gain") { $0.audio.music?.gain = v } }), range: 0...1, defaultValue: 0.35)
                SliderRow(title: "Fade in", value: Binding(get: { m.fadeIn }, set: { v in model.mutate("music-fin") { $0.audio.music?.fadeIn = v } }), range: 0...5, defaultValue: 1, format: { String(format: "%.1fs", $0) })
                SliderRow(title: "Fade out", value: Binding(get: { m.fadeOut }, set: { v in model.mutate("music-fout") { $0.audio.music?.fadeOut = v } }), range: 0...8, defaultValue: 2, format: { String(format: "%.1fs", $0) })
                ToggleRow(title: "Loop music", subtitle: "Repeat the track if the recording is longer.", isOn: Binding(get: { m.loop }, set: { v in model.mutate { $0.audio.music?.loop = v } }))
            }
            if library.tracks.isEmpty {
                Notice(text: "Built-in music isn't included in this build. You can still add your own audio file.")
            } else {
                ForEach(library.tracks) { t in
                    HStack(spacing: 8) {
                        Button { previewer.toggle(t, library: library) } label: {
                            Image(systemName: previewer.playingID == t.id ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 20))
                        }.buttonStyle(.plain).foregroundStyle(Theme.blueFocus)
                        .accessibilityLabel(previewer.playingID == t.id ? "Stop preview of \(t.title)" : "Preview \(t.title)")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.system(size: 13, weight: .semibold))
                            Text("\(t.mood) · \(Int(t.seconds))s").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        let using = model.edit.audio.music?.path == "Media/music-\(t.id).m4a"
                        Button(using ? "In use" : "Use") { model.useBuiltInMusic(t) }
                            .buttonStyle(QuietButtonStyle(selected: using)).disabled(using)
                    }
                    .padding(.vertical, 3)
                }
            }
            Button { chooseAudio() } label: { Label("Add your own audio file…", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                .buttonStyle(QuietButtonStyle()).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.control)).padding(.top, 4)
            Text("Built-in music is original and released under CC0 (public domain): free for any use, with no attribution. Only add your own files if you have the rights to use them.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseAudio() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.audio]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { model.importMusic(from: u) }
    }
}

struct WallpaperSwatch: View {
    let def: Wallpapers.Def
    private static func c(_ x: RGBA, _ a: Double? = nil) -> Color { Color(.sRGB, red: x.r, green: x.g, blue: x.b, opacity: a ?? x.a) }
    var body: some View {
        let c: (RGBA, Double?) -> Color = { Self.c($0, $1) }
        let rad = (def.angle - 90) * .pi / 180
        let start = UnitPoint(x: 0.5 - 0.5 * cos(rad), y: 0.5 - 0.5 * sin(rad)), end = UnitPoint(x: 0.5 + 0.5 * cos(rad), y: 0.5 + 0.5 * sin(rad))
        ZStack {
            LinearGradient(colors: [c(def.base.0, 1), c(def.base.1, 1)], startPoint: start, endPoint: end)
            ForEach(Array(def.blobs.enumerated()), id: \.offset) { _, b in
                RadialGradient(colors: [c(b.c, nil), c(b.c, 0)], center: UnitPoint(x: b.x, y: 1 - b.y), startRadius: 0, endRadius: 60 * b.r + 10)
            }
        }
    }
}

struct WallpaperPicker: View {
    @ObservedObject var model: EditorModel
    @State private var category = Wallpapers.Category.all

    var body: some View {
        let indices = Wallpapers.all.indices.filter { category == .all || Wallpapers.all[$0].category == category }
        InspectorSection(title: "Wallpaper") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Wallpapers.Category.allCases, id: \.self) { c in
                        Button(c.rawValue) { category = c }.buttonStyle(QuietButtonStyle(selected: category == c))
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(indices, id: \.self) { i in
                    let w = Wallpapers.all[i], on = model.edit.background.wallpaperIndex == i
                    Button { model.mutate { $0.background.wallpaperIndex = i } } label: {
                        WallpaperSwatch(def: w).frame(height: 42).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.blueFocus : Theme.control, lineWidth: on ? 3 : 1))
                    }.buttonStyle(.plain).help(w.name).accessibilityLabel("\(w.name) wallpaper").accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("\(Wallpapers.all[min(max(model.edit.background.wallpaperIndex, 0), Wallpapers.all.count - 1)].name) · \(indices.count) shown of \(Wallpapers.all.count)")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
            Button { if let i = indices.randomElement() { model.mutate { $0.background.wallpaperIndex = i } } } label: {
                Label("Pick random wallpaper", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }.buttonStyle(QuietButtonStyle()).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.control))
        }
    }
}
struct CaptionsInspector: View {
    var body: some View {
        Panel {
            InspectorSection(title: "Generate transcript", subtitle: "Local transcription with an open Whisper model is planned. Nothing will be sent to a server.") {
                Notice(text: "Not available yet. This panel will let you pick a language and model size, then edit captions and export SRT.")
            }
        }
    }
}

struct ShortcutsInspector: View {
    var body: some View {
        Panel {
            InspectorSection(title: "Keyboard shortcut overlays", subtitle: "Show pressed shortcuts on screen while recording.") {
                Notice(text: "Not available yet. It needs the optional Input Monitoring permission and is planned for a later phase.")
            }
            Text("Editor shortcuts: Space play/pause · ⌘Z undo · ⇧⌘Z redo · ⌘E export · Delete removes the selected event.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
        }
    }
}
