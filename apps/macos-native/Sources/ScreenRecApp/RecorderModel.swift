import AppKit
import AVFoundation
import CoreGraphics
import ScreenRecCore
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

    @Published var recordSystemAudio = true
    @Published var recordMicrophone = true
    @Published var cursorInVideo = true

    @Published var exportProgress: Double?
    @Published var exportMessage: String?

    private var session: CaptureSession?
    private var cursorLog: CursorEventLog?
    private var cursorMonitor: Any?
    private var timer: Timer?
    private var projectURL: URL?
    private var project: Project?
    private var startedAt = Date()
    private var exporter: Exporter?

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

    func start() async {
        refreshPermissions()
        guard screenPermission == .granted else {
            state = .failed("Screen Recording permission is not granted. Grant it, then quit and reopen the app.")
            return
        }
        if recordMicrophone && micPermission != .granted {
            state = .failed("Microphone permission is not granted. Grant it or turn the microphone off.")
            return
        }
        state = .starting
        exportMessage = nil
        do {
            let name = "Recording \(Self.nameFormatter.string(from: Date()))"
            let (project, url) = try ProjectStore.create(name: name, in: projectsDirectory)
            self.project = project
            self.projectURL = url

            let session = CaptureSession(projectURL: url, options: CaptureOptions(
                fps: 30, systemAudio: recordSystemAudio, microphone: recordMicrophone, cursorInVideo: cursorInVideo))
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
        } catch {
            // Media written so far stays on disk; the project keeps its in-progress marker so it is recoverable.
            self.session = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func captureFailed(_ message: String) async {
        guard state == .recording else { return }
        await stop()
        if case .finished = state { exportMessage = message } else { state = .failed(message) }
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
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                           .rightMouseDown, .rightMouseUp, .rightMouseDragged]
        cursorMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            let global = Geometry.appKitToGlobalTopLeft(NSEvent.mouseLocation, primaryHeight: primaryHeight)
            let n = Geometry.normalized(global, displayFrame: info.displayFrame)
            let kind: CursorEvent.Kind
            let button: CursorEvent.Button
            switch event.type {
            case .leftMouseDown: (kind, button) = (.down, .left)
            case .rightMouseDown: (kind, button) = (.down, .right)
            case .leftMouseUp: (kind, button) = (.up, .left)
            case .rightMouseUp: (kind, button) = (.up, .right)
            case .leftMouseDragged: (kind, button) = (.drag, .left)
            case .rightMouseDragged: (kind, button) = (.drag, .right)
            default: (kind, button) = (.move, .none)
            }
            // NSEvent.timestamp is seconds since boot on the same mach clock as CMClockGetHostTimeClock().
            log.append(CursorEvent(t: event.timestamp - t0, x: n.x, y: n.y, kind: kind, button: button))
        }
    }

    private func stopCursorCapture() {
        if let m = cursorMonitor { NSEvent.removeMonitor(m) }
        cursorMonitor = nil
        cursorLog?.close()
        cursorLog = nil
    }

    // MARK: Export

    func export(projectURL url: URL) async {
        guard exportProgress == nil else { return }
        do {
            let project = try ProjectStore.load(from: url)
            guard let screen = project.sources.first(where: { $0.type == .screen }) else {
                exportMessage = "Project has no screen source."; return
            }
            let missing = ProjectStore.missingSources(of: project, in: url)
            if !missing.isEmpty { exportMessage = "Missing media: \(missing.joined(separator: ", "))"; return }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.mpeg4Movie]
            panel.nameFieldStringValue = project.name + ".mp4"
            panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            guard panel.runModal() == .OK, let out = panel.url else { return }

            let audio = project.sources.filter { $0.type == .microphone || $0.type == .systemAudio }
                .map { ExportJob.Stream(url: ProjectStore.resolve($0, in: url), offset: $0.startOffset) }
            // Output keeps the source aspect ratio inside 1920x1080 only when it is 16:9; otherwise it is letterboxed.
            let job = ExportJob(video: .init(url: ProjectStore.resolve(screen, in: url), offset: screen.startOffset),
                                audio: audio, outputURL: out,
                                width: project.exportSettings.width, height: project.exportSettings.height,
                                fps: project.exportSettings.fps)
            let exporter = Exporter()
            self.exporter = exporter
            exportProgress = 0
            exportMessage = nil
            try await exporter.export(job) { p in Task { @MainActor [weak self] in self?.exportProgress = p } }
            exportProgress = nil
            exportMessage = "Exported to \(out.path)"
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            exportProgress = nil
            exportMessage = error.localizedDescription
        }
        exporter = nil
    }

    func cancelExport() { exporter?.cancel() }

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"; return f
    }()
}
