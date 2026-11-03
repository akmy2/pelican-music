import XCTest
import AVFoundation
@testable import PelicanMusic

final class PlaybackTests: XCTestCase {
    private func fixture(_ directory: URL, name: String, frequency: Double) throws -> Track {
        let url = directory.appendingPathComponent(name + ".wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let count: AVAudioFrameCount = 44100 * 12
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        for frame in 0..<Int(count) { buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * frequency * 2 * .pi / 44100) * 0.005) }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        return Track(id: UUID(), title: name, file: url.lastPathComponent, length: 12)
    }
    @MainActor private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
    }
    @MainActor func testPlaybackCrossfadeAdvancesQueueAndResumeRestoresPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try fixture(root, name: "Primeira", frequency: 440)
        let second = try fixture(root, name: "Segunda", frequency: 660)
        let player = Player(directory: root)
        player.tracks = [first, second]; player.save()
        player.state.settings.crossfade = 1
        player.state.settings.repeatMode = .off
        player.playCollection([first, second])
        try await waitUntil { player.playing || player.error != nil }
        XCTAssertNil(player.error)
        XCTAssertTrue(player.playing)
        XCTAssertEqual(player.current?.id, first.id)
        player.seek(11.2)
        try await waitUntil { player.current?.id == second.id && player.playing }
        XCTAssertEqual(player.current?.id, second.id, "Crossfade must advance to the queued track")
        XCTAssertTrue(player.state.queueIDs.isEmpty)
        player.seek(6)
        try await Task.sleep(nanoseconds: 300_000_000)
        player.pause()
        let position = player.state.positions[second.id.uuidString] ?? 0
        XCTAssertGreaterThanOrEqual(position, 5.5)
        let restored = Player(directory: root)
        XCTAssertEqual(restored.current?.id, second.id)
        restored.resume()
        try await waitUntil { restored.playing || restored.error != nil }
        XCTAssertNil(restored.error)
        XCTAssertGreaterThanOrEqual(restored.elapsed, 5.5)
        restored.releaseAudio()
    }
}
