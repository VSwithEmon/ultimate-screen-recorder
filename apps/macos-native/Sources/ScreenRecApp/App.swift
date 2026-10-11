import AVKit
import ScreenRecCore
import SwiftUI

@main
struct UltimateScreenRecordingApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("Ultimate Screen Recording") {
            RootView()
                .environmentObject(app)
                .environmentObject(app.recorder)
                .environmentObject(app.coordinator)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Export…") { app.editor?.showExport = true }.keyboardShortcut("e", modifiers: .command).disabled(app.editor == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { app.editor?.undo() }.keyboardShortcut("z", modifiers: .command).disabled(!(app.editor?.canUndo ?? false))
                Button("Redo") { app.editor?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!(app.editor?.canRedo ?? false))
            }
            CommandMenu("Insert") {
                Button("Automatic Zoom from Clicks") { app.editor?.generateAutomaticZoom() }
                Button("Manual Zoom at Playhead") { app.editor?.addManualZoom() }
                Divider()
                Button("Sensitive Data Mask") { app.editor?.addMask(.sensitive) }
                Button("Highlight Mask") { app.editor?.addMask(.highlight) }
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var editor: EditorModel?
    @Published var openError: String?
    let recorder = RecorderModel()
    let coordinator: RecordingCoordinator

    init() {
        coordinator = RecordingCoordinator(recorder: recorder)
        recorder.onFinished = { [weak self] url in
            guard let self else { return }
            let openEditor = self.coordinator.settings.openEditorAfter
            self.coordinator.recordingEnded()
            if openEditor { self.open(url) }
        }
        // `--open <project>` opens a project directly (used for QA and scripting).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count { open(URL(fileURLWithPath: args[i + 1])) }
    }

    func open(_ url: URL) {
        do {
            let m = try EditorModel(url: url)
            editor = m
            Task { await m.load() }
        } catch {
            openError = error.localizedDescription
        }
    }

    func closeEditor() {
        editor?.shutdown()
        editor = nil
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Group {
            if let editor = app.editor {
                EditorView(model: editor, onClose: { app.closeEditor() })
            } else {
                HomeView()
            }
        }
        .background(Theme.base)
        .alert("Could not open project", isPresented: Binding(get: { app.openError != nil }, set: { if !$0 { app.openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(app.openError ?? "") }
    }
}

struct ProjectItem: Identifiable {
    let id: URL
    let name: String
    let date: Date
    let incomplete: Bool
}

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var model: RecorderModel
    @EnvironmentObject var coordinator: RecordingCoordinator
    @State private var projects: [ProjectItem] = []

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.blueBright)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Ultimate Screen Recording").font(.system(size: 20, weight: .bold))
                            Text("Record beautifully. Edit effortlessly. Share anywhere.").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                    }
                    recordCard
                    permissionsCard
                }
                .padding(28).frame(maxWidth: 520, alignment: .leading)
            }
            .frame(width: 580).background(Theme.panel)
            Divider().overlay(Theme.line)
            projectsList
        }
        .onAppear { reload(); model.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions(); reload() }
    }

    // MARK: Record

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New recording").font(.system(size: 14, weight: .semibold))
            Text("Choose a display, window or area, plus camera, microphone and system audio, in the floating recorder.").font(.system(size: 12)).foregroundStyle(Theme.text3)
            HStack(spacing: 12) {
                if case .finalizing = model.state {
                    ProgressView().controlSize(.small); Text("Saving your recording…").foregroundStyle(Theme.text2)
                } else {
                    Button { coordinator.showToolbar() } label: { Label("Open recorder", systemImage: "record.circle") }
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut("r", modifiers: [.command, .shift])
                }
            }
            if case .failed(let m) = model.state {
                Label(m, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.bad)
            }
            if let n = model.notice { Text(n).font(.system(size: 12)).foregroundStyle(Theme.text2) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bar, in: RoundedRectangle(cornerRadius: 12))
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions").font(.system(size: 14, weight: .semibold))
            permissionRow("Screen Recording", model.screenPermission, request: model.requestScreenAccess, pane: "Privacy_ScreenCapture")
            permissionRow("Microphone", model.micPermission, request: model.requestMicAccess, pane: "Privacy_Microphone")
            permissionRow("Camera", model.cameraPermission, request: model.requestCameraAccess, pane: "Privacy_Camera")
            if model.screenPermission != .granted {
                Text("After enabling Screen Recording in System Settings, quit and reopen the app. macOS applies it on the next launch.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
                Button("Quit and reopen the app") { RecorderModel.relaunch() }.buttonStyle(QuietButtonStyle())
            }
            Text("Cursor tracking records position and clicks only, never what you type.").font(.system(size: 12)).foregroundStyle(Theme.text3)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bar, in: RoundedRectangle(cornerRadius: 12))
    }

    private func permissionRow(_ title: String, _ state: PermissionState, request: @escaping () -> Void, pane: String) -> some View {
        HStack {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(state == .granted ? Theme.ok : Color.orange)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(state.label).font(.system(size: 12)).foregroundStyle(Theme.text3)
            Spacer()
            if state != .granted {
                if state == .notDetermined { Button("Request", action: request).buttonStyle(QuietButtonStyle()) }
                Button("Open Settings") { model.openSystemSettings(pane) }.buttonStyle(QuietButtonStyle())
            }
        }
    }

    // MARK: Projects

    private var projectsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Projects").font(.system(size: 16, weight: .bold))
                Spacer()
                Button { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.directoryURL = model.projectsDirectory
                    if p.runModal() == .OK, let u = p.url { app.open(u) } } label: { Label("Open project…", systemImage: "folder") }.buttonStyle(QuietButtonStyle())
            }.padding(20)
            Divider().overlay(Theme.line)
            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack").font(.system(size: 34)).foregroundStyle(Theme.text3)
                    Text("No projects yet").font(.system(size: 14, weight: .semibold))
                    Text("Record your screen and it will appear here, ready to edit.").font(.system(size: 12)).foregroundStyle(Theme.text3)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(projects) { p in
                    Button { if !p.incomplete { app.open(p.id) } } label: {
                        HStack {
                            Image(systemName: p.incomplete ? "exclamationmark.triangle" : "film").foregroundStyle(p.incomplete ? Color.orange : Theme.blueFocus).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.system(size: 13, weight: .medium))
                                Text(p.incomplete ? "Recording was interrupted and cannot be opened" : p.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
                            }
                            Spacer()
                            if !p.incomplete { Image(systemName: "chevron.right").foregroundStyle(Theme.text3) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(Color.clear)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity).background(Theme.base)
    }

    private func reload() {
        let dir = model.projectsDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        projects = urls.filter { $0.pathExtension == ProjectStore.packageExtension }.compactMap { u in
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let name = (try? ProjectStore.load(from: u).name) ?? u.deletingPathExtension().lastPathComponent
            return ProjectItem(id: u, name: name, date: date, incomplete: ProjectStore.isIncomplete(at: u))
        }.sorted { $0.date > $1.date }
    }

    private func timeString(_ t: TimeInterval) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) }
}
