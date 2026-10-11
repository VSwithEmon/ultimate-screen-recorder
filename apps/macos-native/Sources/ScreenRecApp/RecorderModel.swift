import AppKit
import AVFoundation
import CoreGraphics
import ScreenRecCore
import ScreenCaptureKit
import SwiftUI

enum PermissionState: Equatable {
    case granted, denied, notDetermined
    var label: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested"
        }
    }
}

@MainActor
final class RecorderModel: ObservableObject {
    enum State: Equatable {
        case idle, starting, recording, finalizing
        case finished(URL)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var screenPermission: PermissionState = .notDetermined
    @Published var micPermission: PermissionState = .notDetermined
    @Published var cameraPermission: PermissionState = .notDetermined

    var onFinished: ((URL) -> Void)?

    @Published var notice: String?

    private var session: CaptureSession?
    private var cursorLog: CursorEventLog?
    private var cursorTimer: DispatchSourceTimer?
    private var timer: Timer?
    private var projectURL: URL?
    private var project: Project?
    private var startedAt = Date()

    var projectsDirectory: URL {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("ScreenRec")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    init() { refreshPermissions() }

    // MARK: Permissions

    func refreshPermissions() {
        screenPermission = CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micPermission = .granted
        case .denied, .restricted: micPermission = .denied
        default: micPermission = .notDetermined
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraPermission = .granted
        case .denied, .restricted: cameraPermission = .denied
        default: cameraPermission = .notDetermined
        }
    }

    /// Relaunches the app (macOS applies a new Screen Recording permission only to a fresh process).
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    func requestScreenAccess() {
        // The prompt appears once; afterwards the user must enable the app in System Settings and relaunch it.
        _ = CGRequestScreenCaptureAccess()
        refreshPermissions()
    }

    func requestMicAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Recording

    var canStart: Bool {
        switch state {
        case .idle, .finished, .failed: return true
        default: return false
        }
    }

    /// Starts recording `target`. `options` already reflect device choices and permissions.
    func start(target: CaptureTarget, options: CaptureOptions) async {
        refreshPermissions()
        if screenPermission != .granted {
            // The pre-flight check can be stale; ask ScreenCaptureKit directly before giving up.
            if (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) == nil {
                state = .failed("Screen Recording is not allowed for this app yet. Open System Settings, switch \"Ultimate Screen Recording\" on, then quit and reopen the app.")
                return
            }
            screenPermission = .granted
        }
        state = .starting
        notice = nil
        do {
            let name = "Recording \(Self.nameFormatter.string(from: Date()))"
            let (project, url) = try ProjectStore.create(name: name, in: projectsDirectory)
            self.project = project
            self.projectURL = url

            let session = CaptureSession(projectURL: url, options: options, target: target)
            session.onError = { [weak self] msg in Task { @MainActor in await self?.captureFailed(msg) } }
            let info = try await session.start()
            self.session = session
            self.project?.capture = info
            self.project?.cursorEventsPath = "Metadata/cursor.jsonl"
            try startCursorCapture(url: url, t0: session.t0, info: info)

            startedAt = Date()
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed = Date().timeIntervalSince(self.startedAt)
                }
            }
            state = .recording
        } catch {
            teardownCapture()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard state == .recording, let session, var project, let url = projectURL else { return }
        state = .finalizing
        timer?.invalidate(); timer = nil
        stopCursorCapture()
        do {
            let result = try await session.stop()
            project.sources = result.sources
            project.capture = result.info
            try ProjectStore.save(project, to: url)
            try ProjectStore.markFinalized(at: url)
            self.session = nil
            self.project = project
            state = .finished(url)
            onFinished?(url)
        } catch {
            // Media written so far stays on disk; the project keeps its in-progress marker so it is recoverable.
            self.session = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func captureFailed(_ message: String) async {
        guard state == .recording else { return }
        await stop()
        if case .finished = state { notice = message } else { state = .failed(message) }
    }

    private func teardownCapture() {
        timer?.invalidate(); timer = nil
        stopCursorCapture()
        session = nil
    }

    // MARK: Cursor metadata (position + buttons only; keystrokes are never observed)

    private func startCursorCapture(url: URL, t0: Double, info: CaptureInfo) throws {
        let log = try CursorEventLog(url: url.appendingPathComponent("Metadata/cursor.jsonl"))
        cursorLog = log
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var lastPoint = CGPoint(x: -1, y: -1)
        var lastButtons = 0
        // Poll at 90 Hz: position and button state need no special permission, unlike global event monitors.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(11))
        timer.setEventHandler {
            let global = Geometry.appKitToGlobalTopLeft(NSEvent.mouseLocation, primaryHeight: primaryHeight)
            let n = Geometry.normalized(global, displayFrame: info.displayFrame)
            let t = ProcessInfo.processInfo.systemUptime - t0
            let buttons = NSEvent.pressedMouseButtons
            let moved = abs(global.x - lastPoint.x) > 0.01 || abs(global.y - lastPoint.y) > 0.01
            if buttons != lastButtons {
                for (bit, button) in [(0, CursorEvent.Button.left), (1, .right)] where (buttons ^ lastButtons) & (1 << bit) != 0 {
                    log.append(CursorEvent(t: t, x: n.x, y: n.y, kind: buttons & (1 << bit) != 0 ? .down : .up, button: button))
                }
                lastButtons = buttons
            } else if moved {
                log.append(CursorEvent(t: t, x: n.x, y: n.y, kind: buttons != 0 ? .drag : .move, button: buttons & 1 != 0 ? .left : (buttons & 2 != 0 ? .right : .none)))
            }
            lastPoint = global
        }
        timer.resume()
        cursorTimer = timer
    }

    private func stopCursorCapture() {
        cursorTimer?.cancel(); cursorTimer = nil
        cursorLog?.close()
        cursorLog = nil
    }

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"; return f
    }()
}
