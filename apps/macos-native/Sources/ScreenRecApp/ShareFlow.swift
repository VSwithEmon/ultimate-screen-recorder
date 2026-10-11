import AppKit
import ScreenRecCore
import SwiftUI

/// Exports a project to a temporary MP4 and, only when the user asks, uploads it to a free file host and returns a link.
@MainActor
final class ShareFlow: ObservableObject {
    enum State: Equatable {
        case idle
        case exporting(Double)
        case uploading(Double)
        case done(URL)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var provider = ShareProvider.litterbox24h
    @Published var consent: Bool { didSet { UserDefaults.standard.set(consent, forKey: Self.consentKey) } }
    private static let consentKey = "shareConsent.v1"
    private var task: Task<Void, Never>?
    private var exporter: Exporter?
    typealias Uploader = @Sendable (URL, ShareProvider, @escaping @Sendable (Double) -> Void) async throws -> URL
    private let uploader: Uploader

    init(uploader: @escaping Uploader = { file, provider, progress in try await ShareUploader.upload(fileURL: file, provider: provider, progress: progress) }) {
        self.uploader = uploader
        consent = UserDefaults.standard.bool(forKey: Self.consentKey)
    }

    var isBusy: Bool { if case .exporting = state { return true }; if case .uploading = state { return true }; return false }

    func start(projectURL: URL, edit override: EditState? = nil) {
        guard consent, !isBusy else { return }
        let provider = provider
        task = Task { @MainActor in
            state = .exporting(0)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: temp) }
            do {
                let project = try ProjectStore.load(from: projectURL)
                let session = try await EditorSession(project: project, packageURL: projectURL)
                let edit = override ?? project.edit
                // Largest size that fits the host's limit: 1080p, then 720p, then 480p.
                for height in [1080, 720, 480] {
                    let ex = Exporter(); exporter = ex
                    try await ex.export(ExportRequest(session: session, edit: edit, outputURL: temp, height: height, fps: 30)) { p in
                        Task { @MainActor [weak self] in if case .exporting = self?.state { self?.state = .exporting(p) } }
                    }
                    let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? 0
                    if size <= provider.maxBytes { break }
                    if height == 480 { throw ShareError.tooLarge(limit: provider.maxBytes, actual: size) }
                }
                try Task.checkCancellation()
                state = .uploading(0)
                let link = try await uploader(temp, provider) { p in
                    Task { @MainActor [weak self] in if case .uploading = self?.state { self?.state = .uploading(p) } }
                }
                copy(link)
                state = .done(link)
            } catch is CancellationError { state = .idle }
            catch ExportError.cancelled { state = .idle }
            catch ShareError.cancelled { state = .idle }
            catch { state = .failed(error.localizedDescription) }
            exporter = nil
        }
    }

    /// Waits for the current run to finish (used by tests).
    func waitUntilFinished() async { await task?.value }

    func cancel() { exporter?.cancel(); task?.cancel() }
    func reset() { if !isBusy { state = .idle } }

    func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

struct ShareLinkView: View {
    @ObservedObject var flow: ShareFlow
    let projectURL: URL
    var edit: EditState?
    var onDone: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch flow.state {
            case .idle: setup
            case .exporting(let p): progress("Preparing your video…", value: p)
            case .uploading(let p): progress("Uploading…", value: p)
            case .done(let url): done(url)
            case .failed(let message): failed(message)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share a link").font(.system(size: 18, weight: .bold))
            Label {
                Text("Your video will be uploaded to a free third-party file host (\(flow.provider.host)). Anyone who has the link can watch it, and we don't control that service. Don't upload anything private.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            } icon: { Image(systemName: "icloud.and.arrow.up").foregroundStyle(Theme.blueFocus) }
            .padding(10).background(Theme.bar, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(ShareProvider.all) { p in
                    Button { flow.provider = p } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: flow.provider == p ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(flow.provider == p ? Theme.blueFocus : Theme.text2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.title).font(.system(size: 13, weight: .semibold))
                                Text(p.detail).font(.system(size: 12)).foregroundStyle(Theme.text2)
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityElement(children: .combine).accessibilityAddTraits(flow.provider == p ? .isSelected : [])
                }
            }
            Toggle(isOn: $flow.consent) {
                Text("I understand my video is sent to this service and the link is public.").font(.system(size: 12))
            }.toggleStyle(.checkbox)
            HStack {
                Button("Cancel", action: onDone).buttonStyle(QuietButtonStyle())
                Spacer()
                Button { flow.start(projectURL: projectURL, edit: edit) } label: { Label("Create link", systemImage: "link") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!flow.consent).opacity(flow.consent ? 1 : 0.55)
            }
        }
    }

    private func progress(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 16, weight: .bold))
            ProgressView(value: value).tint(Theme.blue)
            Text("\(Int(value * 100))%").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text2)
            HStack { Spacer(); Button("Cancel") { flow.cancel() }.buttonStyle(QuietButtonStyle()) }
        }
    }

    private func done(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Link ready and copied", systemImage: "checkmark.circle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ok)
            Text(url.absoluteString).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.bar, in: RoundedRectangle(cornerRadius: 8))
            Text("Anyone with this link can watch the video. \(flow.provider.detail)").font(.system(size: 12)).foregroundStyle(Theme.text2)
            HStack {
                Button { flow.copy(url); copied = true } label: { Label(copied ? "Copied" : "Copy link", systemImage: "doc.on.doc") }.buttonStyle(QuietButtonStyle())
                Button { NSWorkspace.shared.open(url) } label: { Label("Open", systemImage: "safari") }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Done") { flow.reset(); onDone() }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't create a link", systemImage: "exclamationmark.triangle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.bad)
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Text("Nothing was shared. Your recording is unchanged.").font(.system(size: 12)).foregroundStyle(Theme.text3)
            HStack {
                Button("Close") { flow.reset(); onDone() }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Try again") { flow.reset() }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

struct ShareSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ShareLinkView(flow: model.share, projectURL: model.url, edit: model.edit, onDone: { dismiss() })
            .padding(22).frame(width: 440).background(Theme.panel)
            .onDisappear { model.share.reset() }
    }
}
