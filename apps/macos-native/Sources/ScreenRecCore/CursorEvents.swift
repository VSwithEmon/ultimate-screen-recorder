import Foundation

/// One cursor sample. Coordinates are normalised (0...1) to the captured display, origin top-left.
/// Only pointer position and button state are recorded - never key contents.
public struct CursorEvent: Codable, Equatable {
    public enum Kind: String, Codable { case move, down, up, drag }
    public enum Button: String, Codable { case none, left, right, other }
    /// Seconds since the recording clock origin (t0).
    public var t: Double
    public var x: Double
    public var y: Double
    public var kind: Kind
    public var button: Button
    public init(t: Double, x: Double, y: Double, kind: Kind, button: Button = .none) {
        self.t = t; self.x = x; self.y = y; self.kind = kind; self.button = button
    }
}

/// Append-only JSON-lines log; every line is flushed-complete so a crash loses at most the last event.
public final class CursorEventLog {
    private let handle: FileHandle
    private let lock = NSLock()
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()
    private(set) public var count = 0

    public init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    public func append(_ event: CursorEvent) {
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        try? handle.write(contentsOf: line)
        count += 1
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        try? handle.close()
    }

    public static func read(url: URL) throws -> [CursorEvent] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let d = JSONDecoder()
        return try text.split(separator: "\n").map { try d.decode(CursorEvent.self, from: Data($0.utf8)) }
    }
}
