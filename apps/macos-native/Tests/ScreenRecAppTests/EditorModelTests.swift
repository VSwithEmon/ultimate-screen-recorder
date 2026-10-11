import XCTest
import ScreenRecCore
@testable import ScreenRecApp

@MainActor
final class EditorModelTests: XCTestCase {
    func testModelInitialisesAndReportsMissingMediaWithoutCrashing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (_, url) = try ProjectStore.create(name: "Empty", in: dir)
        let model = try EditorModel(url: url)
        XCTAssertEqual(model.clock.time, 0)
        XCTAssertFalse(model.isPlaying)
        await model.load()
        XCTAssertNotNil(model.loadError, "a project with no screen media must show an error, not crash or hang")
        XCTAssertFalse(model.ready)
    }

    func testTimeAndPlayStateAreForwardedToTheClock() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("model2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (_, url) = try ProjectStore.create(name: "X", in: dir)
        let model = try EditorModel(url: url)
        model.time = 3.5
        XCTAssertEqual(model.clock.time, 3.5)
        model.mutate { $0.padding = 0.2 }
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.edit.padding, EditState().padding)
    }
}
