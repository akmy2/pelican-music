import XCTest
import AVFoundation
@testable import PelicanMusic

final class AudioRegressionTests: XCTestCase {
    func testPlaybackSessionDoesNotUsePlayAndRecordOptions() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        XCTAssertEqual(session.category, .playback)
        XCTAssertFalse(session.categoryOptions.contains(.allowAirPlay))
    }

    @MainActor func testImportPersistsValidAudioAndRejectsInvalidFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = directory.appendingPathComponent("regression.wav")
        let invalid = directory.appendingPathComponent("broken.mp3")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][frame] = 0 }
        do {
            let file = try AVAudioFile(forWriting: valid, settings: format.settings)
            try file.write(from: buffer)
        }
        try Data("<html>not audio</html>".utf8).write(to: invalid)
        let player = Player(directory: directory.appendingPathComponent("Library"))
        let previousIDs = Set(player.tracks.map(\.id))
        player.importFiles([valid, invalid])
        let deadline = Date().addingTimeInterval(15)
        while player.importing && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertFalse(player.importing, "Import must complete instead of remaining busy")
        let added = player.tracks.filter { !previousIDs.contains($0.id) }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.title, "regression")
        XCTAssertNotNil(player.error)
        XCTAssertTrue(player.error?.contains("broken.mp3") == true)
        XCTAssertTrue(player.importStatus?.contains("1 música(s) importada(s)") == true)
        let reloaded = Player(directory: directory.appendingPathComponent("Library"))
        XCTAssertTrue(reloaded.tracks.contains(where: { $0.id == added.first?.id }))
        let indices = IndexSet(player.tracks.indices.filter { !previousIDs.contains(player.tracks[$0].id) })
        player.remove(indices)
    }
}
