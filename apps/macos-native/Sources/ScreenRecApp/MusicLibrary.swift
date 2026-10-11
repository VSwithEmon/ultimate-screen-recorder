import AVFoundation
import SwiftUI

struct MusicTrack: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let mood: String
    let bpm: Int
    let seconds: Double
    let file: String
    let license: String
}

/// The built-in music: original tracks synthesised by `tools/generate_music.py` and released under CC0 (public domain).
struct MusicLibrary {
    static let shared = MusicLibrary()
    let directory: URL?
    let tracks: [MusicTrack]

    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Music")) {
        self.directory = directory
        if let dir = directory, let data = try? Data(contentsOf: dir.appendingPathComponent("music.json")),
           let t = try? JSONDecoder().decode([MusicTrack].self, from: data) {
            tracks = t.filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.file).path) }
        } else { tracks = [] }
    }

    func url(for track: MusicTrack) -> URL? { directory?.appendingPathComponent(track.file) }
}

/// Plays a short preview of a built-in track.
@MainActor
final class MusicPreviewer: ObservableObject {
    @Published var playingID: String?
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func toggle(_ track: MusicTrack, library: MusicLibrary) {
        if playingID == track.id { stop(); return }
        stop()
        guard let url = library.url(for: track), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = 0.8; p.play()
        player = p; playingID = track.id
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() { stopTask?.cancel(); player?.stop(); player = nil; playingID = nil }
}
