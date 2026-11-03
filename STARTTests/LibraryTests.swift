import XCTest
import AVFoundation
@testable import PelicanMusic

final class LibraryTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @MainActor func testLegacyLibraryMigrationSearchSortFavoritesAndPlaylists() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let legacy: [[String: String]] = [["id": id.uuidString, "title": "Música antiga", "file": "old.mp3"]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: directory.appendingPathComponent("library.json"))
        let player = Player(directory: directory)
        XCTAssertEqual(player.tracks.count, 1)
        XCTAssertEqual(player.tracks.first?.id, id)
        var edited = player.tracks[0]; edited.artist = "Artista de teste"; edited.album = "Álbum de teste"
        player.updateTrack(edited)
        XCTAssertEqual(player.displayTracks(search: "artista").count, 1)
        XCTAssertEqual(player.displayTracks(search: "álbum").count, 1)
        player.toggleFavorite(edited)
        XCTAssertEqual(player.favoriteTracks.count, 1)
        player.createPlaylist("Viagem")
        let list = player.state.playlists[0]
        player.add(edited, to: list.id); player.add(edited, to: list.id)
        XCTAssertEqual(player.state.playlists[0].trackIDs, [id], "Playlist must not duplicate the same track")
        player.enqueue(edited, next: true)
        let reloaded = Player(directory: directory)
        XCTAssertEqual(reloaded.favoriteTracks.count, 1)
        XCTAssertEqual(reloaded.state.playlists[0].trackIDs, [id])
        XCTAssertEqual(reloaded.queueTracks.first?.id, id)
        player.deleteTracks([id])
        XCTAssertTrue(player.state.playlists[0].trackIDs.isEmpty)
        XCTAssertTrue(player.state.queueIDs.isEmpty)
    }

    @MainActor func testBackupRemapsTracksByContentWithoutOverwritingAudio() throws {
        let source = try root(), target = try root()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
        let first = Player(directory: source), second = Player(directory: target)
        let original = Track(id: UUID(), title: "Minha música", file: "a.wav", fingerprint: "same-content", favorite: true)
        let local = Track(id: UUID(), title: "Outro nome", file: "local.wav", fingerprint: "same-content")
        first.tracks = [original]; second.tracks = [local]
        first.createPlaylist("Favoritas"); first.add(original, to: first.state.playlists[0].id)
        first.state.positions[original.id.uuidString] = 42
        first.state.settings.crossfade = 5
        let missing = try second.restoreBackup(first.backupData())
        XCTAssertEqual(missing, 0)
        XCTAssertEqual(second.tracks[0].file, "local.wav")
        XCTAssertEqual(second.tracks[0].id, local.id)
        XCTAssertEqual(second.tracks[0].title, "Minha música")
        XCTAssertEqual(second.state.playlists[0].trackIDs, [local.id])
        XCTAssertEqual(second.state.positions[local.id.uuidString], 42)
        XCTAssertEqual(second.state.settings.crossfade, 5)
    }

    @MainActor func testFolderImportSkipsDuplicateBytesAndReportsInvalidAudio() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("Collection")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][frame] = 0 }
        let audio = folder.appendingPathComponent("first.wav")
        do { let output = try AVAudioFile(forWriting: audio, settings: format.settings); try output.write(from: buffer) }
        try FileManager.default.copyItem(at: audio, to: folder.appendingPathComponent("duplicate.wav"))
        try Data("invalid audio".utf8).write(to: folder.appendingPathComponent("broken.mp3"))
        let player = Player(directory: directory.appendingPathComponent("Library"))
        player.importFiles([folder])
        let deadline = Date().addingTimeInterval(20)
        while player.importing && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertFalse(player.importing)
        XCTAssertEqual(player.tracks.count, 1)
        XCTAssertEqual(player.importFailures.count, 1)
        XCTAssertTrue(player.importStatus?.contains("1 duplicada(s)") == true)
        XCTAssertNotNil(player.tracks.first?.fingerprint)
        XCTAssertGreaterThan(player.tracks.first?.length ?? 0, 0)
        XCTAssertGreaterThan(player.totalBytes, 0)
    }

    @MainActor func testSleepConfigurationAndHistoryPersistence() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let player = Player(directory: directory)
        player.setSleep(minutes: 15)
        XCTAssertNotNil(player.sleepDeadline)
        player.sleepAtTrackEnd()
        XCTAssertNil(player.sleepDeadline); XCTAssertTrue(player.stopAfterTrack)
        player.setSleep(minutes: nil)
        XCTAssertFalse(player.stopAfterTrack)
        player.state.history = [ListenEvent(trackID: UUID())]
        player.state.settings.shuffle = true
        player.state.settings.repeatMode = .one
        let reloaded = Player(directory: directory)
        XCTAssertEqual(reloaded.state.history.count, 1)
        XCTAssertTrue(reloaded.state.settings.shuffle)
        XCTAssertEqual(reloaded.state.settings.repeatMode, .one)
    }
}
