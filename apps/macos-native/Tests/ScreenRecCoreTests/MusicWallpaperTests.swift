import AVFoundation
import CoreImage
import XCTest
@testable import ScreenRecCore

final class MusicTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("music-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// 2 s project plus a 1 s music file inside its package.
    func project(music: Bool = true, loop: Bool = true, gain: Double = 0.4) async throws -> (Project, URL, MusicSettings) {
        var (project, url) = try await TestMedia.makeProject(in: dir, seconds: 2)
        try TestMedia.makeAudio(at: url.appendingPathComponent("Media/music.m4a"), seconds: 1)
        var m = MusicSettings(path: "Media/music.m4a", title: "Test Loop")
        m.loop = loop; m.gain = gain
        project.edit.audio.music = music ? m : nil
        try ProjectStore.save(project, to: url)
        return (project, url, m)
    }

    func testShortMusicLoopsToCoverTheTimeline() async throws {
        let (p, url, m) = try await project()
        let session = try await EditorSession(project: p, packageURL: url)
        try await session.loadMusic(m)
        let tl = try session.makeTimeline(music: m)
        let id = try XCTUnwrap(tl.musicID)
        let track = try XCTUnwrap(tl.composition.track(withTrackID: id))
        XCTAssertEqual(track.timeRange.duration.seconds, 2.0, accuracy: 0.05, "1 s of music loops twice to cover 2 s")
    }

    func testNonLoopingMusicPlaysOnceAndTrimIsRespected() async throws {
        var (p, url, m) = try await project(loop: false)
        let session = try await EditorSession(project: p, packageURL: url)
        try await session.loadMusic(m)
        let once = try session.makeTimeline(music: m)
        XCTAssertEqual(once.composition.track(withTrackID: try XCTUnwrap(once.musicID))?.timeRange.duration.seconds ?? 0, 1.0, accuracy: 0.05)
        m.loop = true
        let trimmed = try session.makeTimeline(trimStart: 0.5, trimEnd: 1.5, music: m)
        XCTAssertEqual(trimmed.duration, 1.0, accuracy: 0.05)
        XCTAssertEqual(trimmed.composition.track(withTrackID: try XCTUnwrap(trimmed.musicID))?.timeRange.duration.seconds ?? 0, 1.0, accuracy: 0.05, "music starts at the trimmed start")
        p.edit.audio.music = nil; _ = url
    }

    func testNoMusicMeansNoMusicTrack() async throws {
        let (p, url, _) = try await project(music: false)
        let session = try await EditorSession(project: p, packageURL: url)
        try await session.loadMusic(nil)
        XCTAssertNil(try session.makeTimeline(music: nil).musicID)
    }

    func testFadesAreInTheAudioMix() async throws {
        var (p, url, m) = try await project(gain: 0.5)
        m.fadeIn = 0.4; m.fadeOut = 0.5
        p.edit.audio.music = m
        let session = try await EditorSession(project: p, packageURL: url)
        try await session.loadMusic(m)
        let tl = try session.makeTimeline(music: m)
        let mix = try XCTUnwrap(session.audioMix(for: tl, edit: p.edit) as? AVMutableAudioMix)
        let musicParams = try XCTUnwrap(mix.inputParameters.first { $0.trackID == tl.musicID })
        var s: Float = -1, e: Float = -1; var r = CMTimeRange.zero
        XCTAssertTrue(musicParams.getVolumeRamp(for: .zero, startVolume: &s, endVolume: &e, timeRange: &r))
        XCTAssertEqual(s, 0, accuracy: 0.001); XCTAssertEqual(e, 0.5, accuracy: 0.001); XCTAssertEqual(r.duration.seconds, 0.4, accuracy: 0.01)
        XCTAssertTrue(musicParams.getVolumeRamp(for: CMTime(seconds: 1.6, preferredTimescale: 600), startVolume: &s, endVolume: &e, timeRange: &r))
        XCTAssertEqual(s, 0.5, accuracy: 0.001); XCTAssertEqual(e, 0, accuracy: 0.001)
    }

    func testExportContainsTheMusicAudio() async throws {
        let (p, url, m) = try await project()
        let session = try await EditorSession(project: p, packageURL: url)
        let out = dir.appendingPathComponent("withmusic.mp4")
        try await Exporter().export(ExportRequest(session: session, edit: p.edit, outputURL: out, height: 360, fps: 30)) { _ in }
        let asset = AVURLAsset(url: out)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "music is the only audio (the project has no mic/system track)")
        let d = try await asset.load(.duration).seconds
        XCTAssertEqual(d, 2.0, accuracy: 0.2)
        XCTAssertEqual(m.title, "Test Loop")
    }

    func testMusicSettingsRoundTripAndOldProjectsStillLoad() throws {
        var e = EditState(); e.audio.music = MusicSettings(path: "Media/m.m4a", title: "T")
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(EditState.self, from: data), e)
        let old = try JSONSerialization.data(withJSONObject: ["muteMicrophone": true, "micGain": 1, "systemGain": 1])
        XCTAssertNil(try JSONDecoder().decode(AudioSettings.self, from: old).music, "projects saved before music existed load fine")
    }
}

final class WallpaperTests: XCTestCase {
    func testLibraryIsLargeCategorisedAndBackwardCompatible() {
        XCTAssertGreaterThanOrEqual(Wallpapers.all.count, 26)
        XCTAssertEqual(Wallpapers.all.prefix(6).map(\.name), ["Ocean", "Aurora", "Dusk", "Graphite", "Mint", "Peach"], "indexes of earlier wallpapers never change")
        XCTAssertEqual(Set(Wallpapers.all.map(\.name)).count, Wallpapers.all.count, "names are unique")
        for c in Wallpapers.Category.allCases where c != .all { XCTAssertTrue(Wallpapers.all.contains { $0.category == c }, "\(c) has wallpapers") }
    }

    func testEveryWallpaperRendersAndTheyLookDifferent() {
        var averages: [[Double]] = []
        for i in Wallpapers.all.indices {
            var bg = CanvasBackground(); bg.kind = .wallpaper; bg.wallpaperIndex = i
            let img = FrameRenderer.makeBackground(bg, size: CGSize(width: 64, height: 64), image: nil)
            let corners = [(2, 2), (61, 2), (2, 61), (61, 61), (32, 32)].map { TestMedia.pixel(img, size: CGSize(width: 64, height: 64), x: $0.0, y: $0.1) }
            XCTAssertTrue(corners.allSatisfy { $0.a == 255 }, "\(Wallpapers.all[i].name) fully covers the canvas")
            averages.append([Double(corners.map(\.r).reduce(0, +)), Double(corners.map(\.g).reduce(0, +)), Double(corners.map(\.b).reduce(0, +))].map { $0 / 5 })
        }
        for i in averages.indices { for j in averages.indices where j > i {
            let d = zip(averages[i], averages[j]).map { abs($0 - $1) }.reduce(0, +)
            XCTAssertGreaterThan(d, 6, "\(Wallpapers.all[i].name) and \(Wallpapers.all[j].name) are too similar")
        } }
    }
}
