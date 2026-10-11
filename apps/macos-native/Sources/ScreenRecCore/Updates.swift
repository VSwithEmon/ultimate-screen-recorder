import Foundation

/// Describes the newest published build (served as `latest.json` next to the download page).
public struct LatestRelease: Codable, Equatable {
    public var version: String
    public var file: String
    public var sha256: String
    public var notes: String
    public var minimumMacOS: String
    public init(version: String, file: String, sha256: String, notes: String, minimumMacOS: String) {
        self.version = version; self.file = file; self.sha256 = sha256; self.notes = notes; self.minimumMacOS = minimumMacOS
    }
}

public enum UpdateCheckResult: Equatable {
    case upToDate(current: String)
    case available(LatestRelease)
}

public enum UpdateChecker {
    public static let latestURL = URL(string: "https://vswithemon.github.io/ultimate-screen-recorder/latest.json")!
    public static let downloadPage = URL(string: "https://vswithemon.github.io/ultimate-screen-recorder/#download")!

    /// Dotted numeric comparison: "0.10.0" is newer than "0.9.3"; missing parts count as 0.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Only contacts the network when the user chooses "Check for Updates…". Sends nothing about the user or the Mac.
    public static func check(current: String, url: URL = latestURL, session: URLSession = .shared) async throws -> UpdateCheckResult {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let latest = try JSONDecoder().decode(LatestRelease.self, from: data)
        return isNewer(latest.version, than: current) ? .available(latest) : .upToDate(current: current)
    }
}

/// Plain-text details a tester can paste into a bug report. Contains no recordings, names or personal data.
public enum DiagnosticInfo {
    public static func text(appVersion: String, macOS: String, chip: String, permissions: [String: String], displays: [String], extra: [String] = []) -> String {
        var lines = ["Ultimate Screen Recording \(appVersion)", "macOS \(macOS) · \(chip)"]
        lines += permissions.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        lines += displays.enumerated().map { "Display \($0.offset + 1): \($0.element)" }
        lines += extra
        return lines.joined(separator: "\n")
    }
}
