import AppKit
import ScreenRecCore

/// Menu actions for testers: check for a newer build, report a problem, copy diagnostic details.
@MainActor
enum HelpActions {
    static let issuesURL = URL(string: "https://github.com/VSwithEmon/ultimate-screen-recorder/issues/new?template=bug_report.md")!

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    static func checkForUpdates() {
        Task { @MainActor in
            let alert = NSAlert()
            alert.window.appearance = NSAppearance(named: .darkAqua)
            do {
                switch try await UpdateChecker.check(current: appVersion) {
                case .upToDate(let v):
                    alert.messageText = "You're up to date"
                    alert.informativeText = "Ultimate Screen Recording \(v) is the newest version."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                case .available(let r):
                    alert.messageText = "Version \(r.version) is available"
                    alert.informativeText = "You have \(appVersion). \(r.notes)\n\nDownload the new version, replace the app in Applications, then reopen it."
                    alert.addButton(withTitle: "Open download page")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(UpdateChecker.downloadPage) }
                }
            } catch {
                alert.alertStyle = .warning
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "Check your internet connection and try again. (\(error.localizedDescription))"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    static func diagnosticText(recorder: RecorderModel) -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var chip = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &chip, &size, nil, 0)
        let displays = NSScreen.screens.map { "\(Int($0.frame.width))×\(Int($0.frame.height)) @\(Int($0.backingScaleFactor))x" }
        return DiagnosticInfo.text(
            appVersion: appVersion, macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            chip: String(cString: chip),
            permissions: ["Screen Recording": recorder.screenPermission.label, "Microphone": recorder.micPermission.label, "Camera": recorder.cameraPermission.label],
            displays: displays)
    }

    static func copyDiagnostics(recorder: RecorderModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticText(recorder: recorder), forType: .string)
    }

    static func reportProblem(recorder: RecorderModel) {
        copyDiagnostics(recorder: recorder)    // paste into the report; contains no recordings or personal data
        NSWorkspace.shared.open(issuesURL)
    }
}
