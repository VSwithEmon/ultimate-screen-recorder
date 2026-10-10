import XCTest
@testable import ScreenRecCore

final class ProjectStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("screenrec-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testCreateSaveLoadRoundTrip() throws {
        var (project, url) = try ProjectStore.create(name: "Demo/recording", in: dir)
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".screenrecproj"))
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        project.sources = [Source(id: "screen1", type: .screen, path: "Media/screen.mov", startOffset: 0.012)]
        project.capture = CaptureInfo(displayFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                      pixelWidth: 3840, pixelHeight: 2160, scale: 2, cursorBakedIntoVideo: true)
        try ProjectStore.save(project, to: url)
        let loaded = try ProjectStore.load(from: url)
        XCTAssertEqual(loaded, project)
        XCTAssertEqual(loaded.schemaVersion, Project.currentSchemaVersion)
    }

    func testIncompleteMarkerLifecycle() throws {
        let (_, url) = try ProjectStore.create(name: "x", in: dir)
        XCTAssertTrue(ProjectStore.isIncomplete(at: url))
        try ProjectStore.markFinalized(at: url)
        XCTAssertFalse(ProjectStore.isIncomplete(at: url))
        XCTAssertNoThrow(try ProjectStore.markFinalized(at: url))
    }

    func testNewerSchemaRejected() throws {
        let (_, url) = try ProjectStore.create(name: "x", in: dir)
        let manifest = url.appendingPathComponent(ProjectStore.manifestName)
        var text = try String(contentsOf: manifest, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        try text.write(to: manifest, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ProjectStore.load(from: url)) {
            XCTAssertEqual($0 as? ProjectStoreError, .unsupportedSchema(found: 99, supported: 1))
        }
    }

    func testMissingManifestAndMissingSources() throws {
        XCTAssertThrowsError(try ProjectStore.load(from: dir))
        var (project, url) = try ProjectStore.create(name: "x", in: dir)
        project.sources = [Source(id: "screen1", type: .screen, path: "Media/screen.mov", startOffset: 0)]
        XCTAssertEqual(ProjectStore.missingSources(of: project, in: url), ["screen1"])
        try Data([1, 2, 3]).write(to: url.appendingPathComponent("Media/screen.mov"))
        XCTAssertEqual(ProjectStore.missingSources(of: project, in: url), [])
    }

    func testCursorLogRoundTrip() throws {
        let file = dir.appendingPathComponent("cursor.jsonl")
        let log = try CursorEventLog(url: file)
        let events = [CursorEvent(t: 0.1, x: 0.5, y: 0.25, kind: .move),
                      CursorEvent(t: 0.2, x: 0.5, y: 0.25, kind: .down, button: .left)]
        events.forEach(log.append)
        log.close()
        XCTAssertEqual(try CursorEventLog.read(url: file), events)
    }
}
