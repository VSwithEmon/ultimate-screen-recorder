import AppKit
import XCTest
import ScreenRecCore
@testable import ScreenRecApp

@MainActor
final class ShareFlowTests: XCTestCase {
    var dir: URL!
    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shareflow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    func testNothingHappensWithoutConsent() async throws {
        let (_, url) = try await TestMedia.makeProject(in: dir, seconds: 1)
        let called = LockedBox(false)
        let flow = ShareFlow(history: ShareHistoryStore(url: dir.appendingPathComponent("h.json")), uploader: { _, _, _ in called.value = true; return URL(string: "https://x.test/a")! })
        flow.consent = false
        flow.start(projectURL: url)
        await flow.waitUntilFinished()
        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(called.value, "no upload without explicit consent")
    }

    func testHappyPathExportsThenUploadsThenCopiesLink() async throws {
        let (_, url) = try await TestMedia.makeProject(in: dir, seconds: 1, micOffset: 0)
        let seen = LockedBox<(Int64, String)?>(nil)
        let tempPath = LockedBox("")
        let flow = ShareFlow(history: ShareHistoryStore(url: dir.appendingPathComponent("h.json")), uploader: { file, provider, progress in
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            seen.value = (size, provider.id); tempPath.value = file.path
            progress(0.5); progress(1)
            return URL(string: "https://files.test/clip.mp4")!
        })
        flow.consent = true
        flow.provider = .litterbox72h
        flow.start(projectURL: url)
        await flow.waitUntilFinished()
        XCTAssertEqual(flow.state, .done(URL(string: "https://files.test/clip.mp4")!))
        XCTAssertGreaterThan(seen.value?.0 ?? 0, 1000, "a real MP4 was exported before upload")
        XCTAssertEqual(seen.value?.1, "litterbox-72h")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://files.test/clip.mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath.value), "temporary export is deleted afterwards")
        let store = ShareHistoryStore(url: dir.appendingPathComponent("h.json"))
        XCTAssertEqual(store.records.count, 1, "the link is remembered")
        XCTAssertEqual(store.records.first?.providerID, "litterbox-72h")
        XCTAssertEqual(store.records.first?.expiresAt.timeIntervalSince(store.records.first!.createdAt) ?? 0, 259_200, accuracy: 1)
    }

    func testUploadFailureIsReportedAndLeavesRecordingAlone() async throws {
        let (_, url) = try await TestMedia.makeProject(in: dir, seconds: 1)
        let flow = ShareFlow(history: ShareHistoryStore(url: dir.appendingPathComponent("h.json")), uploader: { _, _, _ in throw ShareError.rejected(status: 503, message: "busy") })
        flow.consent = true
        flow.start(projectURL: url)
        await flow.waitUntilFinished()
        guard case .failed(let m) = flow.state else { return XCTFail("expected failure, got \(flow.state)") }
        XCTAssertTrue(m.contains("503"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("Media/screen.mov").path))
    }

    func testMissingProjectFailsCleanly() async throws {
        let flow = ShareFlow(history: ShareHistoryStore(url: dir.appendingPathComponent("h.json")), uploader: { _, _, _ in URL(string: "https://x.test")! })
        flow.consent = true
        flow.start(projectURL: dir.appendingPathComponent("nope.screenrecproj"))
        await flow.waitUntilFinished()
        guard case .failed = flow.state else { return XCTFail("expected failure") }
    }
}

@MainActor
final class RetentionRunnerTests: XCTestCase {
    func testOnlyOlderThanFiveAreTrashedAndProtectedOneSurvives() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ret-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var urls: [URL] = []
        for i in 0..<8 {
            let u = dir.appendingPathComponent("R\(i).screenrecproj"); try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 100)], ofItemAtPath: u.path)
            urls.append(u)
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("notes"), withIntermediateDirectories: true)   // not a project: untouched
        let fakeTrash = dir.appendingPathComponent("_trash"); try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        let moved = RecordingRetentionRunner.apply(in: dir, protecting: [urls[0]]) { u in
            (try? FileManager.default.moveItem(at: u, to: fakeTrash.appendingPathComponent(u.lastPathComponent))) != nil
        }
        XCTAssertEqual(moved, 2, "R1 and R2 are the unprotected excess")
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        XCTAssertEqual(left, ["R0.screenrecproj", "R3.screenrecproj", "R4.screenrecproj", "R5.screenrecproj", "R6.screenrecproj", "R7.screenrecproj", "notes", "_trash"])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: fakeTrash.path)), ["R1.screenrecproj", "R2.screenrecproj"])
    }
}
