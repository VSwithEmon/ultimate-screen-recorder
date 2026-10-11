import XCTest
@testable import ScreenRecCore

final class ShareHistoryTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func record(_ i: Int, life: TimeInterval = 86_400) -> ShareRecord {
        ShareRecord(name: "R\(i)", link: URL(string: "https://x.test/\(i).mp4")!, providerID: "litterbox-24h",
                    createdAt: t0.addingTimeInterval(Double(i) * 60), expiresAt: t0.addingTimeInterval(Double(i) * 60 + life))
    }

    func testKeepsOnlyTheLastFiveNewestFirst() {
        var h = ShareHistory()
        for i in 0..<8 { h.add(record(i), now: t0.addingTimeInterval(Double(i) * 60)) }
        XCTAssertEqual(h.records.count, 5)
        XCTAssertEqual(h.records.map(\.name), ["R7", "R6", "R5", "R4", "R3"], "R0-R2 dropped off")
    }

    func testExpiredLinksDisappear() {
        var h = ShareHistory()
        h.add(record(0, life: 3_600), now: t0)
        h.add(record(1, life: 86_400), now: t0.addingTimeInterval(60))
        h.prune(now: t0.addingTimeInterval(2 * 3_600))
        XCTAssertEqual(h.records.map(\.name), ["R1"])
    }

    func testRemoveAndPersistence() throws {
        var h = ShareHistory()
        for i in 0..<3 { h.add(record(i), now: t0) }
        h.remove(id: h.records[1].id)
        XCTAssertEqual(h.records.count, 2)
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("h-\(UUID().uuidString)/history.json")
        defer { try? FileManager.default.removeItem(at: f.deletingLastPathComponent()) }
        try h.save(to: f)
        XCTAssertEqual(ShareHistory.load(from: f, now: t0), h)
        XCTAssertEqual(ShareHistory.load(from: f, now: t0.addingTimeInterval(10 * 86_400)).records.count, 0, "everything has expired by then")
        XCTAssertEqual(ShareHistory.load(from: f.deletingLastPathComponent().appendingPathComponent("missing.json")).records.count, 0)
    }

    func testDescribeRemaining() {
        XCTAssertEqual(ShareHistory.describe(remaining: 0), "Expired")
        XCTAssertEqual(ShareHistory.describe(remaining: 30 * 60), "Expires in 30 min")
        XCTAssertEqual(ShareHistory.describe(remaining: 5 * 3_600 + 10), "Expires in 5 h")
        XCTAssertEqual(ShareHistory.describe(remaining: 2 * 86_400 + 5), "Expires in 2 d")
    }

    func testRetentionKeepsNewestFiveAndNeverReturnsProtected() {
        let all = (0..<8).map { (url: URL(fileURLWithPath: "/r/\($0)"), date: t0.addingTimeInterval(Double($0))) }
        XCTAssertEqual(RecordingRetention.excess(all).map(\.path).sorted(), ["/r/0", "/r/1", "/r/2"])
        XCTAssertEqual(RecordingRetention.excess(all, protecting: [URL(fileURLWithPath: "/r/1")]).map(\.path).sorted(), ["/r/0", "/r/2"])
        XCTAssertTrue(RecordingRetention.excess(Array(all.prefix(5))).isEmpty, "five or fewer: nothing to remove")
        XCTAssertTrue(RecordingRetention.excess([]).isEmpty)
    }
}
