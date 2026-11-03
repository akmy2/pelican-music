import Foundation
import AVFoundation
import CryptoKit
import UIKit

enum AudioImport {
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func inspect(_ url: URL, originalName: String, id: UUID, directory: URL) async throws -> Track {
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard playable, !audioTracks.isEmpty else {
            throw NSError(domain: "START.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Arquivo vazio ou sem áudio reproduzível."])
        }
        let seconds = try await asset.load(.duration).seconds
        var result = Track(id: id, title: originalName, file: url.lastPathComponent)
        result.length = seconds.isFinite ? seconds : 0
        result.addedAt = Date()
        result.byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        for item in (try? await asset.load(.commonMetadata)) ?? [] {
            switch item.commonKey {
            case .commonKeyTitle:
                if let value = try? await item.load(.stringValue), !value.isEmpty { result.title = value }
            case .commonKeyArtist: result.artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName: result.album = try? await item.load(.stringValue)
            case .commonKeyArtwork:
                if let data = try? await item.load(.dataValue), UIImage(data: data) != nil {
                    let name = id.uuidString + ".art"
                    try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                    result.artwork = name
                }
            default: break
            }
        }
        return result
    }
}

extension Player {
    func importFiles(_ urls: [URL]) {
        guard !importing else { error = "Aguarde a importação atual terminar antes de adicionar outros arquivos."; return }
        guard !urls.isEmpty else { importStatus = "Nenhum arquivo selecionado."; return }
        importing = true; importProgress = 0; importFailures = []
        importStatus = "Preparando arquivos…"
        let directory = root
        let existing = tracks
        Task.detached(priority: .userInitiated) { [weak self] in
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            var inputs: [URL] = []
            var problems: [ImportFailure] = []
            for url in urls {
                do {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                    if values.isDirectory == true {
                        let candidates: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4b", "alac"]
                        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
                            throw NSError(domain: "START.Import", code: 2, userInfo: [NSLocalizedDescriptionKey: "Não foi possível ler a pasta."])
                        }
                        for case let file as URL in walker {
                            if candidates.contains(file.pathExtension.lowercased()), (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { inputs.append(file) }
                        }
                    } else { inputs.append(url) }
                } catch { problems.append(ImportFailure(name: url.lastPathComponent, message: error.localizedDescription, retryURL: url)) }
            }
            var hashes = Set(existing.compactMap(\.fingerprint))
            var updatedHashes: [UUID: String] = [:]
            for track in existing where track.fingerprint == nil {
                if let hash = try? AudioImport.hash(directory.appendingPathComponent(track.file)) { hashes.insert(hash); updatedHashes[track.id] = hash }
            }
            var added: [Track] = []
            var duplicates = 0
            for (offset, source) in inputs.enumerated() {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                let id = UUID()
                let name = id.uuidString + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension.lowercased())
                let destination = directory.appendingPathComponent(name)
                do {
                    var coordinationError: NSError?
                    var copyError: Error?
                    NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                        do { try FileManager.default.copyItem(at: readable, to: destination) } catch { copyError = error }
                    }
                    if let coordinationError { throw coordinationError }
                    if let copyError { throw copyError }
                    let hash = try AudioImport.hash(destination)
                    if hashes.contains(hash) { duplicates += 1; try FileManager.default.removeItem(at: destination) }
                    else {
                        var track = try await AudioImport.inspect(destination, originalName: source.deletingPathExtension().lastPathComponent, id: id, directory: directory)
                        track.fingerprint = hash
                        hashes.insert(hash); added.append(track)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".art"))
                    problems.append(ImportFailure(name: source.lastPathComponent, message: Player.describeFileError(error), retryURL: source))
                }
                let progress = Double(offset + 1) / Double(max(inputs.count, 1))
                DispatchQueue.main.async { [weak self] in self?.importProgress = progress; self?.importStatus = "Lendo \(offset + 1) de \(inputs.count)…" }
            }
            let result = added, failed = problems, skipped = duplicates, hashesToSave = updatedHashes
            DispatchQueue.main.async {
                guard let self else { return }
                for index in self.tracks.indices { if let hash = hashesToSave[self.tracks[index].id] { self.tracks[index].fingerprint = hash } }
                self.tracks.append(contentsOf: result); self.save()
                self.importFailures = failed; self.importing = false; self.importProgress = 1
                self.importStatus = "\(result.count) música(s) importada(s) · \(skipped) duplicada(s) · \(failed.count) falha(s)."
                if !failed.isEmpty { self.error = failed.map { "\($0.name): \($0.message)" }.joined(separator: "\n\n") }
                else if inputs.isEmpty { self.importStatus = "Nenhum áudio compatível foi encontrado na seleção." }
            }
        }
    }
}
