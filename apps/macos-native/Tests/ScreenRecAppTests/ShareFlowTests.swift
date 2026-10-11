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
        let flow = ShareFlow(uploader: { _, _, _ in called.value = true; return URL(string: "https://x.test/a")! })
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
        let flow = ShareFlow(uploader: { file, provider, progress in
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
    }

    func testUploadFailureIsReportedAndLeavesRecordingAlone() async throws {
        let (_, url) = try await TestMedia.makeProject(in: dir, seconds: 1)
        let flow = ShareFlow(uploader: { _, _, _ in throw ShareError.rejected(status: 503, message: "busy") })
        flow.consent = true
        flow.start(projectURL: url)
        await flow.waitUntilFinished()
        guard case .failed(let m) = flow.state else { return XCTFail("expected failure, got \(flow.state)") }
        XCTAssertTrue(m.contains("503"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("Media/screen.mov").path))
    }

    func testMissingProjectFailsCleanly() async throws {
        let flow = ShareFlow(uploader: { _, _, _ in URL(string: "https://x.test")! })
        flow.consent = true
        flow.start(projectURL: dir.appendingPathComponent("nope.screenrecproj"))
        await flow.waitUntilFinished()
        guard case .failed = flow.state else { return XCTFail("expected failure") }
    }
}
