import Foundation

public enum ProjectStoreError: Error, Equatable, LocalizedError {
    case notAProject(URL)
    case unsupportedSchema(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case .notAProject(let u): return "\(u.lastPathComponent) is not a valid project package."
        case .unsupportedSchema(let f, let s): return "Project schema v\(f) is newer than this app supports (v\(s))."
        }
    }
}

/// Reads/writes the `.screenrecproj` package: a directory with `project.json`, `Media/` and `Metadata/`.
public enum ProjectStore {
    public static let packageExtension = "screenrecproj"
    public static let manifestName = "project.json"
    public static let inProgressMarker = "Metadata/recording.inprogress"

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Creates an empty package flagged as "recording in progress" so a crash leaves it recoverable.
    public static func create(name: String, in directory: URL) throws -> (project: Project, url: URL) {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let project = Project(name: name)
        let folder = "\(safe)-\(project.projectId.uuidString.prefix(8)).\(packageExtension)"
        let url = directory.appendingPathComponent(folder, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("Metadata"), withIntermediateDirectories: true)
        try Data().write(to: url.appendingPathComponent(inProgressMarker))
        try save(project, to: url)
        return (project, url)
    }

    /// Atomic write: a crash mid-save never leaves a truncated manifest.
    public static func save(_ project: Project, to url: URL) throws {
        let data = try encoder().encode(project)
        try data.write(to: url.appendingPathComponent(manifestName), options: .atomic)
    }

    public static func load(from url: URL) throws -> Project {
        let manifest = url.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifest) else { throw ProjectStoreError.notAProject(url) }
        struct Header: Decodable { var schemaVersion: Int }
        let header = try decoder().decode(Header.self, from: data)
        guard header.schemaVersion <= Project.currentSchemaVersion else {
            throw ProjectStoreError.unsupportedSchema(found: header.schemaVersion, supported: Project.currentSchemaVersion)
        }
        // Migration hook: when schema v2 ships, upgrade older manifests here before decoding.
        return try decoder().decode(Project.self, from: data)
    }

    public static func isIncomplete(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(inProgressMarker).path)
    }

    public static func markFinalized(at url: URL) throws {
        let marker = url.appendingPathComponent(inProgressMarker)
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
    }

    public static func resolve(_ source: Source, in url: URL) -> URL {
        url.appendingPathComponent(source.path)
    }

    /// Returns ids of sources whose media file is missing or empty.
    public static func missingSources(of project: Project, in url: URL) -> [String] {
        project.sources.filter { s in
            let p = resolve(s, in: url).path
            guard let size = (try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? Int else { return true }
            return size == 0
        }.map(\.id)
    }
}
