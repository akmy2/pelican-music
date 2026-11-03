import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension Player {
    func backupData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(MusicBackup(tracks: tracks, state: state))
    }
    @discardableResult func restoreBackup(_ data: Data) throws -> Int {
        let backup = try JSONDecoder().decode(MusicBackup.self, from: data)
        guard backup.version == 1 else { throw NSError(domain: "START.Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Este backup usa uma versão ainda não suportada."]) }
        var mapping: [UUID: UUID] = [:]
        var merged = tracks
        for saved in backup.tracks {
            let matches = tracks.indices.filter { index in
                let local = tracks[index]
                return local.id == saved.id || (saved.fingerprint != nil && saved.fingerprint == local.fingerprint)
            }
            guard matches.count == 1, let index = matches.first else { continue }
            mapping[saved.id] = tracks[index].id
            merged[index].title = saved.title
            merged[index].artist = saved.artist
            merged[index].album = saved.album
            merged[index].favorite = saved.favorite
        }
        var restored = backup.state
        restored.settings.crossfade = min(12, max(0, restored.settings.crossfade.isFinite ? restored.settings.crossfade : 0))
        restored.settings.artworkSize = min(88, max(44, restored.settings.artworkSize.isFinite ? restored.settings.artworkSize : 58))
        restored.queueIDs = restored.queueIDs.compactMap { mapping[$0] }
        restored.lastTrackID = restored.lastTrackID.flatMap { mapping[$0] }
        restored.activeCollection = restored.activeCollection.map { $0.compactMap { mapping[$0] } }
        restored.positions = restored.positions.reduce(into: [:]) { result, pair in
            if let oldID = UUID(uuidString: pair.key), let id = mapping[oldID], pair.value.isFinite { result[id.uuidString] = max(0, pair.value) }
        }
        restored.history = restored.history.compactMap { event in
            guard let id = mapping[event.trackID] else { return nil }
            var event = event; event.trackID = id; return event
        }
        for index in restored.playlists.indices { restored.playlists[index].trackIDs = restored.playlists[index].trackIDs.compactMap { mapping[$0] } }
        let previous = try backupData()
        try previous.write(to: root.appendingPathComponent("before-restore.json"), options: .atomic)
        tracks = merged
        if let id = current?.id { current = tracks.first { $0.id == id } }
        save(); state = restored
        return backup.tracks.count - mapping.count
    }
    func refreshMissingMetadata() {
        guard !importing else { return }
        let originals = tracks.filter { $0.length == nil }
        let session = UUID()
        importSessionID = session; importing = true; importProgress = 0
        importStatus = "Lendo informações dos arquivos…"
        let directory = root
        importTask = Task.detached { [weak self] in
            var count = 0
            for (offset, track) in originals.enumerated() {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.importSessionID == session else { return }
                    self.importStatus = "Informações: \(track.title)"
                    self.importProgress = Double(offset) / Double(max(originals.count, 1))
                }
                let update = try? await ImportDeadline.run(seconds: 15, stage: "informações de \(track.title)") {
                    var updated = try await AudioImport.inspect(directory.appendingPathComponent(track.file), originalName: track.title, id: track.id, directory: directory)
                    updated.favorite = track.favorite
                    updated.fingerprint = track.fingerprint ?? (try? AudioImport.hash(directory.appendingPathComponent(track.file)))
                    return updated
                }
                guard !Task.isCancelled else { return }
                if let update {
                    await MainActor.run {
                        guard let self, self.importSessionID == session, let index = self.tracks.firstIndex(where: { $0.id == track.id }) else { return }
                        self.tracks[index] = update; self.save()
                    }
                    count += 1
                }
            }
            let total = count
            await MainActor.run {
                guard let self, self.importSessionID == session else { return }
                self.importing = false; self.importSessionID = nil; self.importTask = nil
                self.importStatus = "Informações atualizadas em \(total) música(s)."
                self.startAutomaticArtwork()
            }
        }
    }
}
