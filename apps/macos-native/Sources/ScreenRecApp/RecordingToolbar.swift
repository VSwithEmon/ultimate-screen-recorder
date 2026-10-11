import AppKit
import AVFoundation
import ScreenCaptureKit
import ScreenRecCore
import SwiftUI

// MARK: - Toolbar view

struct RecordingToolbarView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var meter: MicMeter
    @ObservedObject var recorder: RecorderModel
    @State private var cameras: [AVCaptureDevice] = []
    @State private var mics: [AVCaptureDevice] = []

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button { coordinator.closeToolbar() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.black.opacity(0.8))
                        .frame(width: 32, height: 32).background(Color.white, in: Circle())
                }.buttonStyle(.plain).help("Close").accessibilityLabel("Close recorder").padding(.trailing, 4)
                divider
                ForEach(CaptureMode.allCases, id: \.self) { m in modeButton(m) }
                divider
                cameraMenu
                micMenu
                systemAudioMenu
                divider
                settingsMenu
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.bar.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.control))
            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)

            if let e = coordinator.errorText {
                HStack(spacing: 10) {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.bad)
                    if recorder.screenPermission != .granted {
                        Button("Open Settings") { recorder.openSystemSettings("Privacy_ScreenCapture") }.buttonStyle(QuietButtonStyle())
                        Button("Quit & reopen") { RecorderModel.relaunch() }.buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8).frame(maxWidth: 760)
                .background(Theme.bar.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .onAppear { cameras = DeviceCatalog.cameras(); mics = DeviceCatalog.microphones() }
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 36).padding(.horizontal, 6) }

    private func modeButton(_ m: CaptureMode) -> some View {
        let enabled = m != .device
        let selected = settings.mode == m
        return Button { coordinator.select(m) } label: {
            VStack(spacing: 3) {
                Image(systemName: m.icon).font(.system(size: 20, weight: .regular)).frame(height: 24)
                Text(m.title).font(.system(size: 12, weight: .medium))
            }
            .frame(width: 62, height: 52)
            .foregroundStyle(enabled ? (selected ? Theme.text : Theme.text2) : Theme.text3.opacity(0.75))
            .background(selected ? Theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .help(enabled ? "Record \(m.title.lowercased())" : "Recording an iPhone or iPad is not available yet")
        .accessibilityLabel(m.title)
    }

    // MARK: Camera

    private var cameraMenu: some View {
        let cam = settings.selectedCamera
        return Menu {
            if cameras.isEmpty { Text("No camera found") }
            ForEach(cameras, id: \.uniqueID) { d in
                Button { settings.cameraID = d.uniqueID; settings.cameraEnabled = true; settings.cameraDimensions = nil; coordinator.refreshDevices() } label: {
                    if settings.cameraEnabled && cam?.uniqueID == d.uniqueID {
                        Label(d.localizedName + (d.uniqueID == AVCaptureDevice.default(for: .video)?.uniqueID ? " (default)" : ""), systemImage: "checkmark")
                    } else { Text(d.localizedName) }
                }
            }
            Divider()
            if let cam {
                Menu("Max camera resolution") {
                    ForEach(DeviceCatalog.resolutions(of: cam), id: \.self) { d in
                        Button { settings.cameraDimensions = d } label: {
                            if let cur = settings.cameraDimensions ?? DeviceCatalog.resolutions(of: cam).first, cur.width == d.width, cur.height == d.height {
                                Label(DeviceCatalog.label(d), systemImage: "checkmark")
                            } else { Text(DeviceCatalog.label(d)) }
                        }
                    }
                }
            }
            Button { settings.hideCameraPreview.toggle(); coordinator.refreshDevices() } label: {
                if settings.hideCameraPreview { Label("Hide camera preview", systemImage: "checkmark") } else { Text("Hide camera preview") }
            }
            Divider()
            Button { settings.cameraEnabled = false; coordinator.refreshDevices() } label: {
                if !settings.cameraEnabled { Label("Don't record camera", systemImage: "checkmark") } else { Text("Don't record camera") }
            }
        } label: {
            barLabel(icon: settings.cameraEnabled ? "video" : "video.slash", text: settings.cameraEnabled ? (cam?.localizedName ?? "Camera") : "No camera")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Camera")
    }

    // MARK: Microphone

    private var micMenu: some View {
        let mic = settings.selectedMic
        return Menu {
            if mics.isEmpty { Text("No microphone found") }
            ForEach(mics, id: \.uniqueID) { d in
                Button { settings.micID = d.uniqueID; settings.micEnabled = true; coordinator.refreshDevices() } label: {
                    if settings.micEnabled && mic?.uniqueID == d.uniqueID {
                        Label(d.localizedName + (d.uniqueID == AVCaptureDevice.default(for: .audio)?.uniqueID ? " (default)" : ""), systemImage: "checkmark")
                    } else { Text(d.localizedName) }
                }
            }
            Divider()
            Button("Reduce noise and normalize volume (not available yet)") {}.disabled(true)
            Divider()
            Button { settings.micEnabled = false; coordinator.refreshDevices() } label: {
                if !settings.micEnabled { Label("Don't record microphone", systemImage: "checkmark") } else { Text("Don't record microphone") }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                barLabel(icon: settings.micEnabled ? "mic" : "mic.slash", text: settings.micEnabled ? (mic?.localizedName ?? "Microphone") : "No microphone")
                // Level meter.
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.control)
                        Capsule().fill(meter.level > 0.9 ? Theme.bad : Theme.ok).frame(width: g.size.width * CGFloat(min(1, settings.micEnabled ? meter.level : 0)))
                    }
                }.frame(height: 3).padding(.horizontal, 6)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Microphone")
    }

    // MARK: System audio

    private var systemAudioMenu: some View {
        Menu {
            Button { settings.systemAudio = .all } label: {
                if settings.systemAudio == .all { Label("Record system audio from all apps", systemImage: "checkmark") } else { Text("Record system audio from all apps") }
            }
            Button("Record system audio from selected apps (not available yet)") {}.disabled(true)
            Divider()
            Button { settings.systemAudio = .none } label: {
                if settings.systemAudio == .none { Label("Don't record system audio", systemImage: "checkmark") } else { Text("Don't record system audio") }
            }
        } label: {
            barLabel(icon: "music.note.tv", text: settings.systemAudio == .all ? "System audio" : "No system audio")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("System audio")
    }

    // MARK: Settings

    private var settingsMenu: some View {
        Menu {
            toggle("Hide desktop icons in recorded video", $settings.hideDesktopIcons)
            toggle("Hide Dock icon while recording", $settings.hideDockIcon)
            toggle("Highlight recorded area during recording", $settings.highlightArea)
            Divider()
            toggle("Open the editor after recording", $settings.openEditorAfter)
            Divider()
            Button(coordinator.notesVisible ? "Hide speaker notes" : "Show speaker notes") { coordinator.toggleNotes() }.keyboardShortcut("/", modifiers: [.command, .option])
            Menu("Recording countdown") {
                ForEach([0, 3, 5, 10], id: \.self) { n in
                    Button { settings.countdown = n } label: {
                        let t = n == 0 ? "Off" : "\(n) seconds"
                        if settings.countdown == n { Label(t, systemImage: "checkmark") } else { Text(t) }
                    }
                }
            }
            Menu("Advanced") {
                Menu("Frame rate") {
                    ForEach([24, 30, 60], id: \.self) { f in
                        Button { settings.fps = f } label: { if settings.fps == f { Label("\(f) fps", systemImage: "checkmark") } else { Text("\(f) fps") } }
                    }
                }
                toggle("Record the cursor into the video (disables cursor editing)", $settings.bakeCursor)
            }
            Divider()
            Button("Reveal recordings folder") { NSWorkspace.shared.open(recorder.projectsDirectory) }
        } label: {
            HStack(spacing: 4) { Image(systemName: "gearshape").font(.system(size: 18)); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
                .foregroundStyle(Theme.text2).frame(width: 52, height: 52)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Recording settings")
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle() } label: { if binding.wrappedValue { Label(title, systemImage: "checkmark") } else { Text(title) } }
    }

    private func barLabel(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 22)
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(maxWidth: 120, alignment: .leading)
        }
        .foregroundStyle(Theme.text).padding(.horizontal, 10).frame(height: 44)
    }
}

// MARK: - Coordinator

@MainActor
final class RecordingCoordinator: ObservableObject {
    let settings = RecordingSettings()
    let recorder: RecorderModel
    let meter = MicMeter()
    @Published var errorText: String?
    @Published var notesVisible = false

    private var toolbar: OverlayPanel?
    private var overlays: [OverlayPanel] = []
    private var camera: NSPanel?
    private let cameraPreview = CameraPreviewController()
    private var hud: NSPanel?
    private var highlight: OverlayPanel?
    private var countdownPanels: [OverlayPanel] = []
    private var notes: NSPanel?
    private var statusItem: NSStatusItem?
    private var hiddenWindows: [NSWindow] = []
    private var area: (displayID: CGDirectDisplayID, selection: AreaSelection)?
    private let areaOwner = AreaOwner()
    private var countdownTask: Task<Void, Never>?

    init(recorder: RecorderModel) { self.recorder = recorder }

    var isActive: Bool { toolbar != nil }

    // MARK: Toolbar lifecycle

    func showToolbar() {
        recorder.refreshPermissions()
        guard toolbar == nil else { toolbar?.makeKeyAndOrderFront(nil); return }
        hiddenWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
        hiddenWindows.forEach { $0.orderOut(nil) }
        errorText = nil
        // As an agent app its panels can appear over other apps' fullscreen spaces on every display.
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let host = FirstMouseHostingView(rootView: RecordingToolbarView(coordinator: self, settings: settings, meter: meter, recorder: recorder))
        host.setFrameSize(host.fittingSize)
        let size = host.fittingSize
        let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 16))
        panel.onEscape = { [weak self] in self?.closeToolbar() }
        panel.orderFrontRegardless()
        toolbar = panel
        refreshDevices()
    }

    func closeToolbar() {
        countdownTask?.cancel()
        clearOverlays()
        toolbar?.close(); toolbar = nil
        stopPreviews()
        settings.mode = nil
        if recorder.state != .recording {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            hiddenWindows.forEach { $0.makeKeyAndOrderFront(nil) }; hiddenWindows = []
        }
    }

    /// Starts/stops camera preview and mic meter to match the current choices.
    func refreshDevices() {
        guard toolbar != nil || recorder.state == .recording else { return }
        if settings.micEnabled, recorder.micPermission == .granted, recorder.state != .recording { meter.start(device: settings.selectedMic) } else { meter.stop() }
        if settings.cameraEnabled, !settings.hideCameraPreview, recorder.cameraPermission == .granted, let cam = settings.selectedCamera {
            cameraPreview.start(device: cam)
            showCameraPanel()
        } else {
            cameraPreview.stop(); camera?.orderOut(nil)
        }
        if settings.micEnabled && recorder.micPermission != .granted { recorder.requestMicAccess() }
        if settings.cameraEnabled && recorder.cameraPermission == .notDetermined { recorder.requestCameraAccess() }
    }

    private func stopPreviews() {
        meter.stop(); cameraPreview.stop(); camera?.close(); camera = nil
    }

    private func showCameraPanel() {
        if let camera { camera.orderFrontRegardless(); return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 260, height: 195)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let view = CameraPreviewView(session: cameraPreview.session).clipShape(RoundedRectangle(cornerRadius: 30)).frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        p.contentView = NSHostingView(rootView: view)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .screenSaver; p.isMovableByWindowBackground = true; p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.setFrameOrigin(NSPoint(x: screen.frame.maxX - size.width - 40, y: screen.frame.maxY - size.height - 70))
        p.orderFrontRegardless()
        camera = p
    }

    // MARK: Mode selection

    func select(_ mode: CaptureMode) {
        errorText = nil
        clearOverlays()
        if settings.mode == mode { settings.mode = nil; return }   // clicking the active mode again clears the selection
        settings.mode = mode
        switch mode {
        case .display: showDisplayPickers()
        case .window: showWindowPickers()
        case .area: showAreaPicker()
        case .device: break
        }
    }

    private func clearOverlays() {
        overlays.forEach { $0.close() }; overlays = []
        highlight?.close(); highlight = nil
    }

    private func addOverlay<V: View>(_ view: V, screen: NSScreen) {
        let p = makeOverlayPanel(for: screen)
        p.contentView = FirstMouseHostingView(rootView: view)
        p.onEscape = { [weak self] in self?.settings.mode = nil; self?.clearOverlays() }
        p.orderFrontRegardless()
        overlays.append(p)
    }

    private func finishOverlays() {
        NSApp.activate(ignoringOtherApps: true)
        // The screen under the mouse takes keyboard focus (Esc, size fields).
        let mouse = NSEvent.mouseLocation
        (overlays.first { $0.frame.contains(mouse) } ?? overlays.first)?.makeKey()
        toolbar?.orderFrontRegardless()
    }

    private func showDisplayPickers() {
        for s in NSScreen.screens {
            addOverlay(DisplayPickerView(screen: s) { [weak self] in self?.begin(target: .display(s.displayID), screen: s) }, screen: s)
        }
        finishOverlays()
    }

    private func showWindowPickers() {
        let windows = WindowCatalog.onScreenWindows()
        for s in NSScreen.screens {
            addOverlay(WindowPickerView(screen: s, windows: windows) { [weak self] id in self?.begin(target: .window(id), screen: s) }, screen: s)
        }
        finishOverlays()
    }

    private func showAreaPicker() {
        areaOwner.displayID = area?.displayID
        for s in NSScreen.screens {
            let initial = area?.displayID == s.displayID ? area?.selection : nil
            addOverlay(AreaPickerView(screen: s, settings: settings, owner: areaOwner, initial: initial,
                                      onChange: { [weak self] sel in if let sel { self?.area = (s.displayID, sel) } },
                                      onStart: { [weak self] sel in self?.begin(target: .area(s.displayID, sel.rect), screen: s) }), screen: s)
        }
        finishOverlays()
    }

    // MARK: Recording

    private func begin(target: CaptureTarget, screen: NSScreen) {
        errorText = nil
        clearOverlays()
        toolbar?.orderOut(nil)
        meter.stop()
        countdownTask?.cancel()
        let seconds = settings.countdown
        countdownTask = Task { @MainActor in
            if seconds > 0 {
                for n in stride(from: seconds, to: 0, by: -1) {
                    showCountdown(n, on: screen)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { hideCountdown(); return }
                }
                hideCountdown()
            }
            await startRecording(target: target, screen: screen)
        }
    }

    private func showCountdown(_ n: Int, on screen: NSScreen) {
        hideCountdown()
        let p = makeOverlayPanel(for: screen, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2), key: false, ignoresMouse: true)
        p.contentView = NSHostingView(rootView: CountdownView(value: n))
        p.orderFrontRegardless()
        countdownPanels = [p]
    }
    private func hideCountdown() { countdownPanels.forEach { $0.close() }; countdownPanels = [] }

    private func startRecording(target: CaptureTarget, screen: NSScreen) async {
        let options = settings.captureOptions(cameraAllowed: recorder.cameraPermission == .granted, micAllowed: recorder.micPermission == .granted)
        if settings.hideDockIcon { NSApp.setActivationPolicy(.accessory) }
        await recorder.start(target: target, options: options)
        if recorder.state == .recording {
            showHUD(on: screen)
            installStatusItem()
            if settings.highlightArea, case .area(_, let r) = target { showHighlight(rect: r, on: screen) }
        } else {
            // Failed to start: restore everything and show the toolbar with the reason.
            NSApp.setActivationPolicy(.regular)
            if case .failed(let m) = recorder.state { errorText = m }
            toolbar?.orderFrontRegardless()
            refreshDevices()
        }
    }

    func stopRecording() {
        Task { await recorder.stop() }
    }

    /// Called by the app once the project has been finalized (or failed).
    func recordingEnded() {
        hud?.close(); hud = nil
        highlight?.close(); highlight = nil
        removeStatusItem()
        stopPreviews()
        toolbar?.close(); toolbar = nil
        settings.mode = nil
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        hiddenWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        hiddenWindows = []
        if hiddenWindows.isEmpty { NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil) }
    }

    private func showHUD(on screen: NSScreen) {
        let host = NSHostingView(rootView: RecordingHUDView(recorder: recorder) { [weak self] in self?.stopRecording() })
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1); p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 40))
        p.orderFrontRegardless()
        hud = p
    }

    private func showHighlight(rect: CGRect, on screen: NSScreen) {
        let p = makeOverlayPanel(for: screen, level: .statusBar, key: false, ignoresMouse: true)
        let r = rect
        p.contentView = NSHostingView(rootView: Rectangle().stroke(Theme.blueBright, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            .frame(width: r.width + 4, height: r.height + 4).position(x: r.midX, y: r.midY).ignoresSafeArea())
        p.orderFrontRegardless()
        highlight = p
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "● Stop recording"
        item.button?.target = self
        item.button?.action = #selector(statusStop)
        statusItem = item
    }
    private func removeStatusItem() { if let s = statusItem { NSStatusBar.system.removeStatusItem(s) }; statusItem = nil }
    @objc private func statusStop() { stopRecording() }

    // MARK: Notes

    func toggleNotes() {
        if let notes { notes.close(); self.notes = nil; notesVisible = false; return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Speaker notes"
        p.contentView = NSHostingView(rootView: SpeakerNotesView(settings: settings))
        p.level = .floating
        p.sharingType = .none     // excluded from screenshots and screen sharing
        p.isReleasedWhenClosed = false
        p.center(); p.orderFrontRegardless()
        notes = p; notesVisible = true
    }
}
