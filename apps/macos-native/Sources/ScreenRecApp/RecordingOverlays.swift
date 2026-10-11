import AppKit
import ScreenRecCore
import SwiftUI

/// Hosting view that handles the very first click, so the first drag on an overlay isn't swallowed by app activation.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless panel that can take keyboard focus (needed for the area size fields).
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Shared by area pickers on every screen: only the screen being drawn on keeps a selection.
@MainActor
final class AreaOwner: ObservableObject {
    @Published var displayID: CGDirectDisplayID?
}

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID() }
    /// Display bounds in global top-left coordinates.
    var cgBounds: CGRect { CGDisplayBounds(displayID) }
}

func makeOverlayPanel(for screen: NSScreen, level: NSWindow.Level = .screenSaver, key: Bool = true, ignoresMouse: Bool = false) -> OverlayPanel {
    let p = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    p.level = level
    p.hidesOnDeactivate = false          // NSPanel hides itself when the app deactivates by default
    p.sharingType = .none                // never part of screenshots or screen sharing
    p.becomesKeyOnlyIfNeeded = false
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false
    p.ignoresMouseEvents = ignoresMouse
    p.isReleasedWhenClosed = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    p.setFrame(screen.frame, display: false)
    return p
}

// MARK: - Display picker

struct DisplayPickerView: View {
    let screen: NSScreen
    let onStart: () -> Void
    var body: some View {
        let mode = CGDisplayCopyDisplayMode(screen.displayID)
        let w = Int(screen.frame.width * screen.backingScaleFactor), h = Int(screen.frame.height * screen.backingScaleFactor)
        let hz = Int(mode?.refreshRate ?? 60)
        ZStack {
            Color.black.opacity(0.55)
            // Text sits on a solid card so contrast never depends on the desktop behind it.
            VStack(spacing: 14) {
                Text(screen.localizedName).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.text)
                Text("\(w)×\(h)\(hz > 0 ? " · \(hz) FPS" : "")").font(.system(size: 15)).foregroundStyle(Theme.text2)
                Button(action: onStart) { Label("Start recording", systemImage: "record.circle") }
                    .buttonStyle(PrimaryButtonStyle()).controlSize(.large).padding(.top, 6)
                Text("Press Esc to cancel").font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            .padding(28)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.control))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Window picker

struct PickWindow: Identifiable, Equatable {
    let id: CGWindowID
    let owner: String
    let title: String
    let frame: CGRect   // global top-left points
}

enum WindowCatalog {
    static func onScreenWindows() -> [PickWindow] {
        let me = ProcessInfo.processInfo.processIdentifier
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"], width > 100, height > 60 else { return nil }
            return PickWindow(id: id, owner: w[kCGWindowOwnerName as String] as? String ?? "App",
                              title: w[kCGWindowName as String] as? String ?? "", frame: CGRect(x: x, y: y, width: width, height: height))
        }
    }
}

struct WindowPickerView: View {
    let screen: NSScreen
    let windows: [PickWindow]
    let onStart: (CGWindowID) -> Void
    @State private var hovered: PickWindow?
    @State private var chosen: PickWindow?

    var body: some View {
        let origin = screen.cgBounds.origin
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.5)
                .onContinuousHover { phase in
                    if chosen != nil { return }
                    if case .active(let p) = phase {
                        let g = CGPoint(x: p.x + origin.x, y: p.y + origin.y)
                        hovered = windows.first { $0.frame.contains(g) }
                    } else { hovered = nil }
                }
                .onTapGesture { location in
                    let g = CGPoint(x: location.x + origin.x, y: location.y + origin.y)
                    chosen = windows.first { $0.frame.contains(g) }
                }
            if let w = chosen ?? hovered {
                let r = w.frame.offsetBy(dx: -origin.x, dy: -origin.y)
                Rectangle().fill(Theme.blue.opacity(0.18)).overlay(Rectangle().stroke(Theme.blueBright, lineWidth: 3))
                    .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY).allowsHitTesting(false)
                VStack(spacing: 10) {
                    Text(w.owner + (w.title.isEmpty ? "" : " — " + w.title)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Theme.panel, in: Capsule()).overlay(Capsule().stroke(Theme.control)).foregroundStyle(Theme.text)
                    if chosen != nil {
                        Button { onStart(w.id) } label: { Label("Start recording", systemImage: "record.circle") }.buttonStyle(PrimaryButtonStyle())
                    }
                }.position(x: r.midX, y: r.midY).allowsHitTesting(chosen != nil)
            } else {
                Text("Click a window to record it").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.panel, in: Capsule()).overlay(Capsule().stroke(Theme.control))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Area picker

struct AreaPickerView: View {
    let screen: NSScreen
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var owner: AreaOwner
    let initial: AreaSelection?
    let onChange: (AreaSelection?) -> Void
    let onStart: (AreaSelection) -> Void

    @State private var area: AreaSelection?
    @State private var ratio: Double?
    @State private var createStart: CGPoint?
    @State private var base: CGRect?
    @State private var savePrompt = false
    @State private var saveName = ""

    private var bounds: CGRect { CGRect(origin: .zero, size: screen.frame.size) }
    private var scale: CGFloat { screen.backingScaleFactor }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dim everything outside the area; empty space is draggable to draw a new area.
            Path { p in p.addRect(bounds); if let r = area?.rect { p.addRect(r) } }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                    let s = createStart ?? v.startLocation; createStart = s
                    area = AreaSelection.fromDrag(from: s, to: v.location, bounds: bounds); claim(); onChange(area)
                }.onEnded { _ in createStart = nil })
            if let a = area {
                let r = a.rect
                Rectangle().stroke(Color.white, lineWidth: 1.5).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY).allowsHitTesting(false)
                Color.clear.contentShape(Rectangle()).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                    .gesture(DragGesture().onChanged { v in
                        let b = base ?? a.rect; base = b
                        var n = AreaSelection(rect: b); n.move(by: v.translation, bounds: bounds); area = n; onChange(n)
                    }.onEnded { _ in base = nil })
                ForEach(AreaSelection.Handle.allCases, id: \.self) { h in handle(h, in: r) }
                controls(for: a)
            } else {
                Text("Drag the area you want to record").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 16).padding(.vertical, 9).background(Theme.panel, in: Capsule()).overlay(Capsule().stroke(Theme.control))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onAppear { area = initial; if initial != nil { owner.displayID = screen.displayID } }
        .onChange(of: owner.displayID) { _, new in if new != screen.displayID { area = nil } }
        .alert("Save this area", isPresented: $savePrompt) {
            TextField("Name", text: $saveName)
            Button("Save") {
                if let a = area, !saveName.trimmingCharacters(in: .whitespaces).isEmpty {
                    let px = a.pixelSize(scale: scale), o = a.pixelOrigin(scale: scale)
                    settings.savedAreas.append(SavedArea(name: saveName, width: px.w, height: px.h, x: o.x, y: o.y))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func position(of h: AreaSelection.Handle, in r: CGRect) -> CGPoint {
        switch h {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .top: return CGPoint(x: r.midX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        }
    }

    private func handle(_ h: AreaSelection.Handle, in r: CGRect) -> some View {
        Circle().fill(.white).overlay(Circle().stroke(Color.black, lineWidth: 1.5)).frame(width: 12, height: 12)
            .padding(8).contentShape(Rectangle())
            .position(position(of: h, in: r))
            .gesture(DragGesture().onChanged { v in
                let b = base ?? r; base = b
                var n = AreaSelection(rect: b); n.drag(h, by: v.translation, bounds: bounds, ratio: ratio); area = n; onChange(n)
            }.onEnded { _ in base = nil })
            .accessibilityLabel("Resize handle")
    }

    private func controls(for a: AreaSelection) -> some View {
        let r = a.rect
        let panelY = r.minY > 150 ? r.minY - 78 : min(r.maxY + 20, bounds.height - 150)
        return ZStack {
            infoPanel(for: a)
                .position(x: min(max(r.midX, 150), bounds.width - 150), y: panelY)
            startButton(for: a)
                .position(x: min(max(r.midX, 90), bounds.width - 90), y: min(r.maxY + 34, bounds.height - 30))
        }
    }

    private func startButton(for a: AreaSelection) -> some View {
        Button { onStart(a) } label: { Label("Start recording", systemImage: "record.circle") }
            .buttonStyle(PrimaryButtonStyle()).controlSize(.large)
    }

    private func infoPanel(for a: AreaSelection) -> some View {
        let px = a.pixelSize(scale: scale)
        let o = a.pixelOrigin(scale: scale)
        return VStack(spacing: 8) {
            sizeRow(px: px)
            positionRow(o: o)
            optionsRow
        }
        .font(.system(size: 12)).foregroundStyle(Theme.text)
        .padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.control))
    }

    private func sizeRow(px: (w: Int, h: Int)) -> some View {
        HStack(spacing: 8) {
            Text("Size").foregroundStyle(Theme.text2)
            numberField(px.w) { v in update { $0.setPixelSize(w: v, h: nil, scale: scale, bounds: bounds, ratio: ratio) } }
            Text("×").foregroundStyle(Theme.text2)
            numberField(px.h) { v in update { $0.setPixelSize(w: nil, h: v, scale: scale, bounds: bounds, ratio: ratio) } }
            Text("px").foregroundStyle(Theme.text2)
        }
    }

    private func positionRow(o: (x: Int, y: Int)) -> some View {
        HStack(spacing: 8) {
            Text("Position").foregroundStyle(Theme.text2)
            numberField(o.x) { v in update { $0.setPixelOrigin(x: v, y: nil, scale: scale, bounds: bounds) } }
            numberField(o.y) { v in update { $0.setPixelOrigin(x: nil, y: v, scale: scale, bounds: bounds) } }
            Text("px").foregroundStyle(Theme.text2)
        }
    }

    private static let ratios: [(String, Double)] = [("16:9", 16.0 / 9), ("4:3", 4.0 / 3), ("1:1", 1.0), ("9:16", 9.0 / 16), ("4:5", 4.0 / 5)]

    private var optionsRow: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Any") { ratio = nil }
                ForEach(Self.ratios, id: \.0) { item in
                    Button(item.0) { ratio = item.1; update { $0.applyRatio(item.1, bounds: bounds) } }
                }
            } label: { Label(ratioTitle, systemImage: "rectangle") }.menuStyle(.borderlessButton).fixedSize()
            savedMenu
        }
    }

    private var savedMenu: some View {
        Menu {
            Button("Save this area…") { saveName = ""; savePrompt = true }
            if !settings.savedAreas.isEmpty {
                Divider()
                ForEach(settings.savedAreas) { s in
                    Button("\(s.name)  \(s.width)×\(s.height)") { area = s.selection(scale: scale, bounds: bounds); onChange(area) }
                }
                Divider()
                Menu("Delete saved area") { ForEach(settings.savedAreas) { s in Button(s.name) { settings.savedAreas.removeAll { $0.id == s.id } } } }
            }
        } label: { Label("Saved", systemImage: "rectangle.dashed") }.menuStyle(.borderlessButton).fixedSize()
    }

    private var ratioTitle: String {
        guard let r = ratio else { return "Any" }
        for (t, v) in Self.ratios where abs(v - r) < 0.01 { return t }
        return "Any"
    }

    private func claim() { if owner.displayID != screen.displayID { owner.displayID = screen.displayID } }

    private func update(_ f: (inout AreaSelection) -> Void) {
        guard var a = area else { return }
        f(&a); area = a; onChange(a)
    }

    private func numberField(_ value: Int, set: @escaping (Int) -> Void) -> some View {
        TextField("", value: Binding(get: { value }, set: { set($0) }), format: .number.grouping(.never))
            .textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 62, height: 24)
            .background(Theme.base, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.control))
    }
}

// MARK: - Countdown, HUD, notes

struct CountdownView: View {
    let value: Int
    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            Text("\(value)").font(.system(size: 130, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                .frame(width: 260, height: 260).background(Theme.panel.opacity(0.94), in: Circle()).overlay(Circle().stroke(Theme.control))
        }.ignoresSafeArea()
    }
}

struct RecordingHUDView: View {
    @ObservedObject var recorder: RecorderModel
    let onStop: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.bad).frame(width: 10, height: 10)
            Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60)).font(.system(size: 15, weight: .semibold).monospacedDigit())
            Button(action: onStop) { Label("Stop", systemImage: "stop.fill") }.buttonStyle(PrimaryButtonStyle()).tint(.red)
        }
        .padding(.horizontal, 16).frame(height: 48).foregroundStyle(Theme.text)
        .background(Theme.bar, in: Capsule()).overlay(Capsule().stroke(Theme.control))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }
}

struct SpeakerNotesView: View {
    @ObservedObject var settings: RecordingSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speaker notes").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
            TextEditor(text: $settings.speakerNotes).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(6).background(Theme.base, in: RoundedRectangle(cornerRadius: 8))
            Text("Private: these notes are never recorded.").font(.system(size: 12)).foregroundStyle(Theme.text3)
        }.padding(12).background(Theme.panel).foregroundStyle(Theme.text)
    }
}


/// Shown after a recording stops (capture is already finished, so this window can never appear in the video).
struct AfterRecordingView: View {
    let name: String
    let details: String
    let onOpen: () -> Void
    let onRestart: () -> Void
    let onDiscard: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Theme.ok)
            Text("Recording saved").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
            VStack(spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(details).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            Button(action: onOpen) { Label("Open in editor", systemImage: "slider.horizontal.below.rectangle").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            Button(action: onRestart) { Label("Restart recording", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                .buttonStyle(QuietButtonStyle()).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.control))
            Text("Restart discards this take (it goes to the Trash) and starts a new one with the same settings.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Button("Discard", action: onDiscard).foregroundStyle(Theme.bad)
                Button("Close", action: onClose).keyboardShortcut(.cancelAction)
            }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
        }
        .padding(24).frame(width: 340)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.control))
        .padding(30)
    }
}
