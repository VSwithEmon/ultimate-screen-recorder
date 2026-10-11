import Foundation

/// A free, account-less file host the user can opt in to. Nothing is uploaded unless the user asks.
public struct ShareProvider: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let host: String
    public let detail: String
    public let endpoint: URL
    public let maxBytes: Int64
    public let fileField: String
    public let fields: [String: String]
    /// How long the host keeps the file. Every offered provider deletes it automatically.
    public let lifetime: TimeInterval

    private static let litterboxEndpoint = URL(string: "https://litterbox.catbox.moe/resources/internals/api.php")!

    /// Only expiring hosting is offered: a link that cannot be deleted would break the "older shares go away" promise.
    public static let litterbox1h = ShareProvider(
        id: "litterbox-1h", title: "Link that expires in 1 hour", host: "Litterbox (litterbox.catbox.moe)",
        detail: "Deleted automatically after 1 hour. Up to 1 GB.", endpoint: litterboxEndpoint, maxBytes: 1_000_000_000,
        fileField: "fileToUpload", fields: ["reqtype": "fileupload", "time": "1h"], lifetime: 3_600)
    public static let litterbox24h = ShareProvider(
        id: "litterbox-24h", title: "Link that expires in 24 hours", host: "Litterbox (litterbox.catbox.moe)",
        detail: "Deleted automatically after 24 hours. Up to 1 GB.", endpoint: litterboxEndpoint, maxBytes: 1_000_000_000,
        fileField: "fileToUpload", fields: ["reqtype": "fileupload", "time": "24h"], lifetime: 86_400)
    public static let litterbox72h = ShareProvider(
        id: "litterbox-72h", title: "Link that expires in 3 days", host: "Litterbox (litterbox.catbox.moe)",
        detail: "Deleted automatically after 72 hours. Up to 1 GB.", endpoint: litterboxEndpoint, maxBytes: 1_000_000_000,
        fileField: "fileToUpload", fields: ["reqtype": "fileupload", "time": "72h"], lifetime: 259_200)

    public static let all: [ShareProvider] = [.litterbox1h, .litterbox24h, .litterbox72h]
}

public enum ShareError: LocalizedError, Equatable {
    case tooLarge(limit: Int64, actual: Int64)
    case rejected(status: Int, message: String)
    case badResponse(String)
    case network(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .tooLarge(let l, let a):
            return "The video is \(ByteCountFormatter.string(fromByteCount: a, countStyle: .file)), more than this host accepts (\(ByteCountFormatter.string(fromByteCount: l, countStyle: .file)))."
        case .rejected(let s, let m): return "The host refused the upload (HTTP \(s)). \(m)"
        case .badResponse(let m): return "The host's reply wasn't a link: \(m)"
        case .network(let m): return "Upload failed: \(m)"
        case .cancelled: return "Upload cancelled."
        }
    }
}

/// Builds a multipart/form-data body on disk (so large videos are streamed, never held in memory).
public enum MultipartBody {
    public static func write(fields: [String: String], fileField: String, fileURL: URL, filename: String, mimeType: String,
                             boundary: String, to out: URL) throws {
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let h = try FileHandle(forWritingTo: out)
        defer { try? h.close() }
        func put(_ s: String) throws { try h.write(contentsOf: Data(s.utf8)) }
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) {
            try put("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        try put("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { try h.write(contentsOf: chunk) }
        try put("\r\n--\(boundary)--\r\n")
    }
}

public enum ShareUploader {
    /// Accepts only a single https link in the host's plain-text reply.
    public static func parseLink(body: Data, status: Int) throws -> URL {
        let text = (String(data: body, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard (200..<300).contains(status) else { throw ShareError.rejected(status: status, message: String(text.prefix(160))) }
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty, !text.contains(" "), !text.contains("\n") else {
            throw ShareError.badResponse(String(text.prefix(160)))
        }
        return url
    }

    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let report: @Sendable (Double) -> Void
        init(_ r: @escaping @Sendable (Double) -> Void) { report = r }
        func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData b: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            if totalBytesExpectedToSend > 0 { report(Double(totalBytesSent) / Double(totalBytesExpectedToSend)) }
        }
    }

    /// Uploads one file and returns the public link. `session` is injectable so tests never touch the network.
    public static func upload(fileURL: URL, provider: ShareProvider, session: URLSession = .shared,
                              progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let size = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        guard size <= provider.maxBytes else { throw ShareError.tooLarge(limit: provider.maxBytes, actual: size) }

        let boundary = "ScreenRec-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).body")
        defer { try? FileManager.default.removeItem(at: body) }
        try MultipartBody.write(fields: provider.fields, fileField: provider.fileField, fileURL: fileURL,
                                filename: "recording.mp4", mimeType: "video/mp4", boundary: boundary, to: body)

        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("UltimateScreenRecording", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.upload(for: request, fromFile: body, delegate: ProgressDelegate(progress))
            progress(1)
            return try parseLink(body: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let e as ShareError { throw e }
        catch is CancellationError { throw ShareError.cancelled }
        catch let e as URLError where e.code == .cancelled { throw ShareError.cancelled }
        catch { throw ShareError.network(error.localizedDescription) }
    }
}
