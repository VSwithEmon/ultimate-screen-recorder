import XCTest
@testable import ScreenRecCore

/// A URLProtocol that records the request and returns a canned reply. No network is ever used.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        var body = Data()
        if let s = request.httpBodyStream {
            s.open(); var buf = [UInt8](repeating: 0, count: 65536)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; body.append(buf, count: n) }
            s.close()
        } else if let b = request.httpBody { body = b }
        Self.lastRequest = request; Self.lastBody = body
        let (status, data) = Self.handler?(request, body) ?? (500, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ShareTests: XCTestCase {
    var dir: URL!
    var session: URLSession!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: cfg)
        MockURLProtocol.handler = nil
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func file(_ bytes: Int) throws -> URL {
        let u = dir.appendingPathComponent("v.mp4"); try Data(repeating: 0xAB, count: bytes).write(to: u); return u
    }

    func testMultipartBodyContainsFieldsAndExactFileBytes() throws {
        let f = try file(3000)
        let out = dir.appendingPathComponent("b")
        try MultipartBody.write(fields: ["reqtype": "fileupload", "time": "24h"], fileField: "fileToUpload", fileURL: f, filename: "recording.mp4",
                                mimeType: "video/mp4", boundary: "BOUND", to: out)
        let body = try Data(contentsOf: out)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"reqtype\"\r\n\r\nfileupload"))
        XCTAssertTrue(text.contains("name=\"time\"\r\n\r\n24h"))
        XCTAssertTrue(text.contains("name=\"fileToUpload\"; filename=\"recording.mp4\""))
        XCTAssertTrue(text.hasSuffix("\r\n--BOUND--\r\n"))
        XCTAssertNotNil(body.range(of: Data(repeating: 0xAB, count: 3000)), "file bytes are included unchanged")
    }

    func testUploadSendsMultipartToProviderAndReturnsLink() async throws {
        MockURLProtocol.handler = { _, _ in (200, Data("https://litter.catbox.moe/abc123.mp4\n".utf8)) }
        let link = try await ShareUploader.upload(fileURL: try file(5000), provider: .litterbox24h, session: session)
        XCTAssertEqual(link.absoluteString, "https://litter.catbox.moe/abc123.mp4")
        let req = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(req.url, ShareProvider.litterbox24h.endpoint)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        XCTAssertTrue(String(decoding: MockURLProtocol.lastBody, as: UTF8.self).contains("name=\"time\"\r\n\r\n24h"))
    }

    func testTooLargeIsRejectedBeforeAnythingIsSent() async throws {
        MockURLProtocol.lastRequest = nil
        var small = ShareProvider.catbox
        small = ShareProvider(id: "t", title: "t", host: "h", detail: "d", endpoint: small.endpoint, maxBytes: 1000, fileField: "f", fields: [:])
        do { _ = try await ShareUploader.upload(fileURL: try file(5000), provider: small, session: session); XCTFail("expected tooLarge") }
        catch { XCTAssertEqual(error as? ShareError, .tooLarge(limit: 1000, actual: 5000)) }
        XCTAssertNil(MockURLProtocol.lastRequest, "nothing leaves the Mac when the file is too big")
    }

    func testServerErrorAndNonLinkRepliesAreReported() async throws {
        MockURLProtocol.handler = { _, _ in (503, Data("busy".utf8)) }
        do { _ = try await ShareUploader.upload(fileURL: try file(100), provider: .catbox, session: session); XCTFail() }
        catch { XCTAssertEqual(error as? ShareError, .rejected(status: 503, message: "busy")) }
        MockURLProtocol.handler = { _, _ in (200, Data("Error: file type not allowed".utf8)) }
        do { _ = try await ShareUploader.upload(fileURL: try file(100), provider: .catbox, session: session); XCTFail() }
        catch { XCTAssertEqual(error as? ShareError, .badResponse("Error: file type not allowed")) }
    }

    func testOnlyHttpsLinksAreAccepted() {
        XCTAssertThrowsError(try ShareUploader.parseLink(body: Data("http://example.com/a.mp4".utf8), status: 200))
        XCTAssertThrowsError(try ShareUploader.parseLink(body: Data("javascript:alert(1)".utf8), status: 200))
        XCTAssertThrowsError(try ShareUploader.parseLink(body: Data("https://a.com/x\nhttps://b.com/y".utf8), status: 200))
        XCTAssertNoThrow(try ShareUploader.parseLink(body: Data("  https://files.example.com/x.mp4 \n".utf8), status: 200))
    }

    func testProvidersAreHttpsAndAdvertiseLimits() {
        for p in ShareProvider.all { XCTAssertEqual(p.endpoint.scheme, "https"); XCTAssertGreaterThan(p.maxBytes, 0) }
        XCTAssertEqual(ShareProvider.catbox.maxBytes, 200_000_000)
    }
}
