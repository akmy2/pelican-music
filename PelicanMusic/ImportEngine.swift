import Foundation
import AVFoundation
import CryptoKit
import UIKit

enum AudioImport {
    static func blocking<Value>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    struct Tags {
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?
        var length: Double?
    }
    static func inspect(_ url: URL, originalName: String, id: UUID, directory: URL) async throws -> Track {
        let asset = AVURLAsset(url: url)
        try await withTaskCancellationHandler {
            let playable = try await asset.load(.isPlayable)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard playable, !audioTracks.isEmpty else {
                throw NSError(domain: "START.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Arquivo vazio ou sem áudio reproduzível."])
            }
        } onCancel: { asset.cancelLoading() }
        try Task.checkCancellation()
        var track = Track(id: id, title: originalName, file: url.lastPathComponent)
        track.addedAt = Date()
        track.byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        // Broken or slow tags must not reject playable audio.
        if let tags = try? await ImportDeadline.run(seconds: 3, stage: "leitura das informações", operation: { try await readTags(url) }) {
            try Task.checkCancellation()
            if let title = tags.title, !title.isEmpty { track.title = title }
            track.artist = tags.artist; track.album = tags.album; track.length = tags.length
            if let data = tags.artwork, data.count <= 12_000_000, UIImage(data: data) != nil {
                let name = id.uuidString + ".art"
                do { try data.write(to: directory.appendingPathComponent(name), options: .atomic); track.artwork = name }
                catch { /* Missing cover must not discard valid music. */ }
            }
        }
        return track
    }
    static func readTags(_ url: URL) async throws -> Tags {
        let asset = AVURLAsset(url: url)
        return try await withTaskCancellationHandler {
            var tags = Tags()
            if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite { tags.length = seconds }
            for item in (try? await asset.load(.commonMetadata)) ?? [] {
                try Task.checkCancellation()
                switch item.commonKey {
                case .commonKeyTitle: tags.title = try? await item.load(.stringValue)
                case .commonKeyArtist: tags.artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName: tags.album = try? await item.load(.stringValue)
                case .commonKeyArtwork: tags.artwork = try? await item.load(.dataValue)
                default: break
                }
            }
            return tags
        } onCancel: { asset.cancelLoading() }
    }
    static func inputs(_ url: URL) throws -> [URL] {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { return [url] }
        let candidates: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4b", "alac"]
        var scanError: Error?
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else {
            throw NSError(domain: "START.Import", code: 2, userInfo: [NSLocalizedDescriptionKey: "Não foi possível ler a pasta."])
        }
        var files: [URL] = []
        for case let file as URL in walker {
            try Task.checkCancellation()
            if candidates.contains(file.pathExtension.lowercased()), (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { files.append(file) }
        }
        if let scanError { throw scanError }
        return files
    }
}

extension Player {
    func cancelImport() {
        importSessionID = nil
        importTask?.cancel(); importTask = nil
        importing = false
        importStatus = "Importação cancelada. As músicas já adicionadas foram mantidas."
    }
    func importFiles(_ urls: [URL]) {
        guard !importing else { error = "Aguarde a importação atual ou toque em Cancelar."; return }
        guard !urls.isEmpty else { importStatus = "Nenhum arquivo selecionado."; return }
        let session = UUID()
        importSessionID = session; importing = true; importProgress = 0; importFailures = []
        importStatus = "Abrindo seleção…"
        let directory = root
        let knownHashes = Set(tracks.compactMap(\.fingerprint))
        importTask = Task.detached(priority: .userInitiated) { [weak self] in
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            @Sendable func report(_ text: String, progress: Double? = nil) async {
                await MainActor.run {
                    guard let self, self.importSessionID == session else { return }
                    self.importStatus = text
                    if let progress { self.importProgress = progress }
                }
            }
            var inputs: [URL] = []
            var failed: [ImportFailure] = []
            for url in urls {
                guard !Task.isCancelled else { return }
                await report("Examinando: \(url.lastPathComponent)")
                do {
                    let found = try await ImportDeadline.run(seconds: 20, stage: "abertura de \(url.lastPathComponent)") { try await AudioImport.blocking { try AudioImport.inputs(url) } }
                    inputs.append(contentsOf: found)
                } catch is CancellationError { return }
                catch { failed.append(ImportFailure(name: url.lastPathComponent, message: error.localizedDescription, retryURL: url)) }
            }
            var hashes = knownHashes
            var added = 0, duplicates = 0
            for (offset, source) in inputs.enumerated() {
                guard !Task.isCancelled else { return }
                let number = "\(offset + 1)/\(inputs.count)"
                let id = UUID()
                let destination = directory.appendingPathComponent(id.uuidString + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension.lowercased()))
                let permissionRoot = urls.first { source.path.hasPrefix($0.path + "/") } ?? source
                let known = hashes
                do {
                    let track: Track? = try await ImportDeadline.run(seconds: 45, stage: "processamento de \(source.lastPathComponent)") {
                        let access = permissionRoot.startAccessingSecurityScopedResource()
                        defer { if access { permissionRoot.stopAccessingSecurityScopedResource() } }
                        var keep = false
                        defer {
                            if !keep {
                                try? FileManager.default.removeItem(at: destination)
                                try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".art"))
                            }
                        }
                        await report("\(number) · Copiando: \(source.lastPathComponent)")
                        try Task.checkCancellation()
                        try await AudioImport.blocking {
                            var coordinationError: NSError?, copyError: Error?
                            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                                do { try FileManager.default.copyItem(at: readable, to: destination) } catch { copyError = error }
                            }
                            if let coordinationError { throw coordinationError }; if let copyError { throw copyError }
                        }
                        try Task.checkCancellation()
                        await report("\(number) · Verificando conteúdo: \(source.lastPathComponent)")
                        let hash = try AudioImport.hash(destination)
                        if known.contains(hash) { return nil }
                        await report("\(number) · Validando áudio: \(source.lastPathComponent)")
                        var track = try await AudioImport.inspect(destination, originalName: source.deletingPathExtension().lastPathComponent, id: id, directory: directory)
                        try Task.checkCancellation()
                        track.fingerprint = hash; keep = true
                        return track
                    }
                    guard !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: destination)
                        return
                    }
                    if let track {
                        if let hash = track.fingerprint { hashes.insert(hash) }
                        let accepted = await MainActor.run { () -> Bool in
                            guard let self, self.importSessionID == session else { return false }
                            self.tracks.append(track); self.save(); self.startAutomaticArtwork()
                            return true
                        }
                        if accepted { added += 1 }
                        else { try? FileManager.default.removeItem(at: destination); return }
                    } else { duplicates += 1 }
                } catch is CancellationError { return }
                catch { failed.append(ImportFailure(name: source.lastPathComponent, message: Player.describeFileError(error), retryURL: permissionRoot)) }
                await report("\(added) adicionada(s) · \(duplicates) duplicada(s) · \(failed.count) falha(s)", progress: Double(offset + 1) / Double(max(inputs.count, 1)))
            }
            let failures = failed, imported = added, skipped = duplicates
            await MainActor.run {
                guard let self, self.importSessionID == session else { return }
                self.importFailures = failures; self.importing = false; self.importProgress = 1
                self.importSessionID = nil; self.importTask = nil
                self.importStatus = "\(imported) música(s) importada(s) · \(skipped) duplicada(s) · \(failures.count) falha(s)."
                if !failures.isEmpty { self.error = failures.map { "\($0.name): \($0.message)" }.joined(separator: "\n\n") }
                else if inputs.isEmpty { self.importStatus = "Nenhum áudio compatível foi encontrado na seleção." }
            }
        }
    }
}
