import AVKit
import ScreenRecCore
import SwiftUI

@main
struct ScreenRecApp: App {
    @StateObject private var model = RecorderModel()

    var body: some Scene {
        WindowGroup("Ultimate Screen Recording") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 560, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissions
            Divider()
            options
            recordControls
            if case .finished(let url) = model.state { result(url) }
            if case .failed(let message) = model.state {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions").font(.headline)
            permissionRow("Screen Recording", model.screenPermission,
                          request: model.requestScreenAccess,
                          settings: { model.openSystemSettings("Privacy_ScreenCapture") })
            permissionRow("Microphone", model.micPermission,
                          request: model.requestMicAccess,
                          settings: { model.openSystemSettings("Privacy_Microphone") })
            if model.screenPermission != .granted {
                Text("After enabling Screen Recording in System Settings, quit and reopen Ultimate Screen Recording — macOS only applies it on next launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(_ title: String, _ state: PermissionState, request: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(state == .granted ? .green : .orange)
            Text(title)
            Text(state.label).foregroundStyle(.secondary)
            Spacer()
            if state != .granted {
                if state == .notDetermined { Button("Request", action: request) }
                Button("Open Settings", action: settings)
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture").font(.headline)
            Text("Main display, 30 fps, H.264. Window and area modes arrive in Phase 1.").font(.caption).foregroundStyle(.secondary)
            Toggle("System audio", isOn: $model.recordSystemAudio)
            Toggle("Microphone", isOn: $model.recordMicrophone)
            Toggle("Include cursor in video (until the Phase 3 cursor engine exists)", isOn: $model.cursorInVideo)
        }
        .disabled(!model.canStart)
    }

    private var recordControls: some View {
        HStack(spacing: 12) {
            switch model.state {
            case .recording:
                Button { Task { await model.stop() } } label: { Label("Stop", systemImage: "stop.circle.fill") }
                    .buttonStyle(.borderedProminent).tint(.red)
                Text(timeString(model.elapsed)).monospacedDigit()
            case .starting, .finalizing:
                ProgressView().controlSize(.small)
                Text(model.state == .starting ? "Starting…" : "Finalizing files…")
            default:
                Button { Task { await model.start() } } label: { Label("Record", systemImage: "record.circle") }
                    .buttonStyle(.borderedProminent).disabled(!model.canStart)
            }
        }
    }

    private func result(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved to \(url.lastPathComponent)").font(.headline)
            if let project = try? ProjectStore.load(from: url),
               let screen = project.sources.first(where: { $0.type == .screen }) {
                PlayerView(url: ProjectStore.resolve(screen, in: url))
                    .frame(minHeight: 220).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button("Export MP4…") { Task { await model.export(projectURL: url) } }
                    .disabled(model.exportProgress != nil)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                if let p = model.exportProgress {
                    ProgressView(value: p).frame(width: 120)
                    Button("Cancel") { model.cancelExport() }
                }
            }
            if let m = model.exportMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

struct PlayerView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = AVPlayer(url: url)
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {}
}
