import XCTest
@testable import PelicanMusic

final class ImportDeadlineTests: XCTestCase {
    func testSeveralBlockingProvidersCannotStarveImportDeadlines() async throws {
        let start = Date()
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    do {
                        let _: Int = try await ImportDeadline.run(seconds: 0.05, stage: "provedor bloqueado") {
                            try await AudioImport.blocking { Thread.sleep(forTimeInterval: 1.5); return 1 }
                        }
                        return false
                    } catch { return error is ImportTimeout }
                }
            }
            for await timedOut in group { XCTAssertTrue(timedOut) }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        try await Task.sleep(nanoseconds: 1_600_000_000)
    }
    func testDeadlineReturnsWithoutWaitingForUncooperativeOperation() async throws {
        let start = Date()
        do {
            let _: Int = try await ImportDeadline.run(seconds: 0.05, stage: "provedor lento") {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) { continuation.resume(returning: 7) }
                }
            }
            XCTFail("An unresponsive provider must time out")
        } catch { XCTAssertTrue(error is ImportTimeout) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        try await Task.sleep(nanoseconds: 800_000_000)
    }
    func testCancellationReturnsWithoutWaitingForProvider() async throws {
        let task = Task {
            try await ImportDeadline.run(seconds: 10, stage: "provedor") {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) { continuation.resume(returning: 7) }
                }
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must escape promptly") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        try await Task.sleep(nanoseconds: 800_000_000)
    }
    func testArtworkSelectionRejectsUnrelatedSongsAndWrongArtist() throws {
        let candidates = [
            ArtworkMatch(trackId: 1, trackName: "Horizonte", artistName: "Artista Errado", collectionName: "Outro", artworkUrl100: URL(string: "https://example.com/a.jpg")),
            ArtworkMatch(trackId: 2, trackName: "Outra música", artistName: "Ana", collectionName: "Outro", artworkUrl100: URL(string: "https://example.com/b.jpg")),
            ArtworkMatch(trackId: 3, trackName: "Horizonte", artistName: "Ana", collectionName: "Certo", artworkUrl100: URL(string: "https://example.com/c.jpg"))
        ]
        XCTAssertEqual(ArtworkCatalog.best(candidates, title: "Horizonte (youtube).mp3", artist: "Ana")?.trackId, 3)
        XCTAssertEqual(ArtworkCatalog.best(candidates, title: "Ana - Horizonte", artist: nil)?.trackId, 3)
        XCTAssertNil(ArtworkCatalog.best(candidates, title: "Horizonte", artist: nil), "Different artists with the same title must not be guessed automatically")
        XCTAssertNil(ArtworkCatalog.best(candidates, title: "Set desconhecido de duas horas", artist: nil))
    }
}
