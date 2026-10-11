import XCTest
@testable import ScreenRecCore

final class UpdatesTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("0.5.0", than: "0.4.1"))
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.3"), "numeric, not alphabetical")
        XCTAssertTrue(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.4.1", than: "0.4.1"))
        XCTAssertFalse(UpdateChecker.isNewer("0.4", than: "0.4.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.3.9", than: "0.4.0"))
    }

    func session(status: Int, body: String) -> URLSession {
        MockURLProtocol.handler = { _, _ in (status, Data(body.utf8)) }
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }
    let json = #"{"version":"0.5.0","file":"downloads/x.dmg","sha256":"abc","notes":"New","minimumMacOS":"14.0"}"#

    func testReportsAvailableAndUpToDate() async throws {
        let s1 = session(status: 200, body: json)
        let r1 = try await UpdateChecker.check(current: "0.4.1", session: s1)
        XCTAssertEqual(r1, .available(LatestRelease(version: "0.5.0", file: "downloads/x.dmg", sha256: "abc", notes: "New", minimumMacOS: "14.0")))
        let r2 = try await UpdateChecker.check(current: "0.5.0", session: session(status: 200, body: json))
        XCTAssertEqual(r2, .upToDate(current: "0.5.0"))
    }

    func testServerErrorAndGarbageThrow() async {
        do { _ = try await UpdateChecker.check(current: "0.1", session: session(status: 404, body: "")); XCTFail() } catch {}
        do { _ = try await UpdateChecker.check(current: "0.1", session: session(status: 200, body: "<html>")); XCTFail() } catch {}
    }

    func testDiagnosticTextHasNoPersonalData() {
        let t = DiagnosticInfo.text(appVersion: "0.5.0", macOS: "26.5", chip: "Apple M3 Pro",
                                    permissions: ["Screen Recording": "Granted", "Camera": "Not requested"], displays: ["1470×956 @2x"])
        XCTAssertEqual(t, "Ultimate Screen Recording 0.5.0\nmacOS 26.5 · Apple M3 Pro\nCamera: Not requested\nScreen Recording: Granted\nDisplay 1: 1470×956 @2x")
    }
}
