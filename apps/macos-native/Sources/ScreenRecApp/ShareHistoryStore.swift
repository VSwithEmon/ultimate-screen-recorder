import AppKit
import ScreenRecCore
import SwiftUI

/// The last five links the user created, kept on this Mac. Expired links disappear on their own.
@MainActor
final class ShareHistoryStore: ObservableObject {
    static let shared = ShareHistoryStore()
    @Published private(set) var records: [ShareRecord] = []
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ultimate Screen Recording/share-history.json")
        refresh()
    }

    func refresh() {
        var h = ShareHistory.load(from: url)
        h.prune()
        records = h.records
        try? h.save(to: url)
    }

    func add(name: String, link: URL, provider: ShareProvider) {
        var h = ShareHistory(records: records)
        let now = Date()
        h.add(ShareRecord(name: name, link: link, providerID: provider.id, createdAt: now, expiresAt: now.addingTimeInterval(provider.lifetime)), now: now)
        records = h.records
        try? h.save(to: url)
    }

    func remove(_ id: UUID) {
        var h = ShareHistory(records: records)
        h.remove(id: id)
        records = h.records
        try? h.save(to: url)
    }
}

struct SharedLinksList: View {
    @ObservedObject var store: ShareHistoryStore
    var body: some View {
        // Re-evaluates every minute so "Expires in" stays current and expired links drop off.
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let live = store.records.filter { !$0.isExpired(at: context.date) }
            if live.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 30)).foregroundStyle(Theme.text3)
                    Text("No shared links").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Your last \(ShareHistory.limit) links appear here. They expire on their own and the host deletes the video.")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).padding(.horizontal, 30)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(live) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer()
                            Text(ShareHistory.describe(remaining: r.remaining(at: context.date))).font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                        Text(r.link.absoluteString).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.blueFocus).textSelection(.enabled).lineLimit(1)
                        HStack(spacing: 8) {
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.link.absoluteString, forType: .string) } label: { Label("Copy link", systemImage: "doc.on.doc") }
                            Button { NSWorkspace.shared.open(r.link) } label: { Label("Open", systemImage: "safari") }
                            Spacer()
                            Button { store.remove(r.id) } label: { Label("Remove from list", systemImage: "xmark.circle") }
                                .help("Forget this link. The video stays online until it expires.")
                        }.buttonStyle(QuietButtonStyle())
                    }
                    .padding(.vertical, 6).listRowBackground(Color.clear)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .onAppear { store.refresh() }
            }
        }
    }
}

/// Applies the opt-in "keep only my last 5 recordings" rule by moving older ones to the Trash.
enum RecordingRetentionRunner {
    @discardableResult
    static func apply(in directory: URL, protecting: Set<URL>,
                      trash: (URL) -> Bool = { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) != nil }) -> Int {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])) ?? []
        let projects: [(url: URL, date: Date)] = items.filter { $0.pathExtension == ProjectStore.packageExtension }.map { u in
            let v = try? u.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            return (u, v?.creationDate ?? v?.contentModificationDate ?? .distantPast)
        }
        let protectedStd = Set(protecting.map { $0.standardizedFileURL })
        var moved = 0
        for u in RecordingRetention.excess(projects.map { ($0.url.standardizedFileURL, $0.date) }, protecting: protectedStd) {
            if trash(u) { moved += 1 }
        }
        return moved
    }
}
