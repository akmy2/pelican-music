import Foundation
import UIKit

struct ArtworkMatch: Decodable, Identifiable {
    var trackId: Int
    var trackName: String
    var artistName: String
    var collectionName: String?
    var artworkUrl100: URL?
    var trackViewUrl: URL?
    var id: Int { trackId }
}

actor ArtworkCatalog {
    static let shared = ArtworkCatalog()
    private var nextRequest = Date.distantPast
    private struct Response: Decodable { var results: [ArtworkMatch] }
    func search(title: String, artist: String?) async throws -> [ArtworkMatch] {
        let wait = max(0, nextRequest.timeIntervalSinceNow)
        nextRequest = max(Date(), nextRequest).addingTimeInterval(3.2)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        try Task.checkCancellation()
        var url = URLComponents(string: "https://itunes.apple.com/search")!
        url.queryItems = [URLQueryItem(name: "term", value: Self.query(title: title, artist: artist)), URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "media", value: "music"), URLQueryItem(name: "limit", value: "15"), URLQueryItem(name: "country", value: "BR")]
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Response.self, from: data).results
    }
    func image(_ match: ArtworkMatch) async throws -> Data {
        guard let url = match.artworkUrl100, url.scheme == "https", url.host?.hasSuffix("mzstatic.com") == true else { throw URLError(.unsupportedURL) }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 12_000_000, UIImage(data: data) != nil else { throw URLError(.cannotDecodeContentData) }
        return data
    }
    nonisolated static func query(title: String, artist: String?) -> String {
        let clean = title.replacingOccurrences(of: "(?i)\\.(mp3|m4a|wav|aac)$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)[\\[(](youtube|official video|official audio|audio oficial)[\\])]", with: "", options: .regularExpression)
        return [clean, artist ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    nonisolated private static func words(_ text: String) -> Set<String> {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let noise: Set<String> = ["official", "video", "audio", "youtube", "mp3", "oficial", "feat", "ft"]
        return Set(normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !noise.contains($0) })
    }
    nonisolated static func best(_ matches: [ArtworkMatch], title: String, artist: String?) -> ArtworkMatch? {
        let wanted = words(query(title: title, artist: nil))
        guard !wanted.isEmpty else { return nil }
        let artistWords = words(artist ?? "")
        var best: (ArtworkMatch, Double)?
        for match in matches where match.artworkUrl100 != nil {
            let actual = words(match.trackName)
            let overlap = Double(wanted.intersection(actual).count) / Double(max(max(wanted.count, actual.count), 1))
            guard overlap >= 0.75 else { continue }
            if !artistWords.isEmpty {
                let candidateArtist = words(match.artistName)
                guard Double(artistWords.intersection(candidateArtist).count) / Double(max(artistWords.count, 1)) >= 0.5 else { continue }
            } else if overlap < 1 { continue }
            if best == nil || overlap > best!.1 { best = (match, overlap) }
        }
        return best?.0
    }
}

extension Player {
    func startAutomaticArtwork(retry: Bool = false) {
        guard state.settings.automaticArtwork != false else { return }
        if retry {
            for index in tracks.indices where tracks[index].artwork == nil { tracks[index].artworkSearchAttempted = nil }
            save()
        }
        guard artworkTask == nil else { return }
        let session = UUID()
        artworkSessionID = session
        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.artworkSessionID == session { self.artworkTask = nil; self.artworkSessionID = nil } }
            while !Task.isCancelled, self.state.settings.automaticArtwork != false,
                  let track = self.tracks.first(where: { $0.artwork == nil && $0.artworkSearchAttempted != true }) {
                self.artworkStatus = "Buscando capa: \(track.title)"
                do {
                    let matches = try await ArtworkCatalog.shared.search(title: track.title, artist: track.artist)
                    try Task.checkCancellation()
                    let match = ArtworkCatalog.best(matches, title: track.title, artist: track.artist)
                    if let match {
                        let image = try await ArtworkCatalog.shared.image(match)
                        try Task.checkCancellation()
                        if let current = self.tracks.first(where: { $0.id == track.id }), current.artwork == nil {
                            var updated = current; updated.artworkSource = match.trackViewUrl?.absoluteString
                            self.updateTrack(updated, artworkData: image)
                        }
                    }
                    if let index = self.tracks.firstIndex(where: { $0.id == track.id }) { self.tracks[index].artworkSearchAttempted = true; self.save() }
                } catch is CancellationError { return }
                catch {
                    self.artworkStatus = "Busca de capas pausada. Confira a internet; tentaremos novamente ao abrir o app."
                    return
                }
            }
            self.artworkStatus = "Busca automática concluída. Capas incertas foram mantidas como ilustração."
        }
    }
    func stopAutomaticArtwork() { artworkSessionID = nil; artworkTask?.cancel(); artworkTask = nil; artworkStatus = nil }
}
