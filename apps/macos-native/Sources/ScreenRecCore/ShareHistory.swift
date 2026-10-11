import Foundation

/// One link the user created. Only the most recent `ShareHistory.limit` are kept.
public struct ShareRecord: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var link: URL
    public var providerID: String
    public var createdAt: Date
    public var expiresAt: Date
    public init(name: String, link: URL, providerID: String, createdAt: Date, expiresAt: Date) {
        self.name = name; self.link = link; self.providerID = providerID; self.createdAt = createdAt; self.expiresAt = expiresAt
    }
    public func isExpired(at now: Date = Date()) -> Bool { expiresAt <= now }
    public func remaining(at now: Date = Date()) -> TimeInterval { max(0, expiresAt.timeIntervalSince(now)) }
}

/// The user's most recent shared links, newest first. Older entries drop off and expired ones disappear.
public struct ShareHistory: Codable, Equatable {
    public static let limit = 5
    public private(set) var records: [ShareRecord]

    public init(records: [ShareRecord] = []) { self.records = records }

    public mutating func add(_ record: ShareRecord, now: Date = Date()) {
        records.insert(record, at: 0)
        prune(now: now)
    }

    public mutating func remove(id: UUID) { records.removeAll { $0.id == id } }

    /// Drops expired links, sorts newest first and keeps only the latest five.
    public mutating func prune(now: Date = Date()) {
        records = Array(records.filter { !$0.isExpired(at: now) }.sorted { $0.createdAt > $1.createdAt }.prefix(Self.limit))
    }

    public static func load(from url: URL, now: Date = Date()) -> ShareHistory {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        var h = (try? d.decode(ShareHistory.self, from: Data(contentsOf: url))) ?? ShareHistory()
        h.prune(now: now)
        return h
    }

    public func save(to url: URL) throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(self).write(to: url, options: .atomic)
    }

    public static func describe(remaining: TimeInterval) -> String {
        if remaining <= 0 { return "Expired" }
        if remaining < 3_600 { return "Expires in \(max(1, Int(remaining / 60))) min" }
        if remaining < 86_400 { return "Expires in \(Int((remaining / 3_600).rounded(.down))) h" }
        return "Expires in \(Int((remaining / 86_400).rounded(.down))) d"
    }
}

/// Optional "keep only my last N recordings" rule. It only ever names candidates; the caller moves them to the Trash.
public enum RecordingRetention {
    public static let keep = 5

    /// Recordings beyond the newest `keep`. `protecting` (for example the one just made or one open in the editor) is never returned.
    public static func excess(_ recordings: [(url: URL, date: Date)], keep: Int = RecordingRetention.keep, protecting: Set<URL> = []) -> [URL] {
        let newestFirst = recordings.sorted { $0.date > $1.date }
        return newestFirst.dropFirst(keep).map(\.url).filter { !protecting.contains($0) }
    }
}
