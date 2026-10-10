import Foundation

public struct Canvas: Codable, Equatable {
    public var width: Int
    public var height: Int
    public var fps: Int
    public init(width: Int, height: Int, fps: Int) { self.width = width; self.height = height; self.fps = fps }
}

public enum SourceType: String, Codable {
    case screen, camera, microphone, systemAudio
}

public struct Source: Codable, Equatable, Identifiable {
    public var id: String
    public var type: SourceType
    /// Path relative to the project package.
    public var path: String
    /// Seconds between the shared recording clock origin (t0) and this stream's first sample.
    public var startOffset: Double
    public init(id: String, type: SourceType, path: String, startOffset: Double) {
        self.id = id; self.type = type; self.path = path; self.startOffset = startOffset
    }
}

/// Describes how the screen source maps to display space, so cursor metadata can be re-projected.
public struct CaptureInfo: Codable, Equatable {
    /// Display frame in global top-left points.
    public var displayFrame: CGRect
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scale: Double
    /// True when the OS cursor is baked into the screen video (no separate cursor rendering possible).
    public var cursorBakedIntoVideo: Bool
    public init(displayFrame: CGRect, pixelWidth: Int, pixelHeight: Int, scale: Double, cursorBakedIntoVideo: Bool) {
        self.displayFrame = displayFrame; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.scale = scale; self.cursorBakedIntoVideo = cursorBakedIntoVideo
    }
}

public struct ExportSettings: Codable, Equatable {
    public var format: String
    public var codec: String
    public var width: Int
    public var height: Int
    public var fps: Int
    public init(format: String = "mp4", codec: String = "h264", width: Int = 1920, height: Int = 1080, fps: Int = 30) {
        self.format = format; self.codec = codec; self.width = width; self.height = height; self.fps = fps
    }
}

public struct Project: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var projectId: UUID
    public var name: String
    public var createdAt: Date
    public var canvas: Canvas
    public var sources: [Source]
    public var capture: CaptureInfo?
    public var cursorEventsPath: String?
    public var exportSettings: ExportSettings
    public var edit = EditState()

    public init(name: String, canvas: Canvas = Canvas(width: 1920, height: 1080, fps: 30), createdAt: Date = Date()) {
        self.schemaVersion = Project.currentSchemaVersion
        self.projectId = UUID()
        self.name = name
        // ISO-8601 persistence is whole-second; truncate up front so save/load round-trips exactly.
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
        self.canvas = canvas
        self.sources = []
        self.capture = nil
        self.cursorEventsPath = nil
        self.exportSettings = ExportSettings(fps: canvas.fps)
    }
}

extension Project {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, projectId, name, createdAt, canvas, sources, capture, cursorEventsPath, exportSettings, edit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        canvas = try c.decode(Canvas.self, forKey: .canvas)
        sources = try c.decode([Source].self, forKey: .sources)
        capture = try c.decodeIfPresent(CaptureInfo.self, forKey: .capture)
        cursorEventsPath = try c.decodeIfPresent(String.self, forKey: .cursorEventsPath)
        exportSettings = try c.decode(ExportSettings.self, forKey: .exportSettings)
        // Additive field: v1 manifests written before the editor existed load with defaults.
        edit = try c.decodeIfPresent(EditState.self, forKey: .edit) ?? EditState()
    }
}
