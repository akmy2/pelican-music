import Foundation
import SwiftUI

struct MusicPlaylist: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var trackIDs: [UUID] = []
}

struct ListenEvent: Codable, Identifiable {
    var id = UUID()
    var trackID: UUID
    var date = Date()
}

enum RepeatMode: String, Codable, CaseIterable { case off, all, one }
enum LibrarySort: String, Codable, CaseIterable, Identifiable {
    case newest, title, artist, album, duration
    var id: String { rawValue }
    var label: String {
        switch self { case .newest: return "Mais recentes"; case .title: return "Nome"; case .artist: return "Artista"; case .album: return "Álbum"; case .duration: return "Duração" }
    }
}
struct MusicSettings: Codable {
    var accent = "Lima"
    var grid = false
    var artworkSize: Double = 58
    var crossfade: Double = 0
    var resumePositions = true
    var sort = LibrarySort.newest
    var shuffle = false
    var repeatMode = RepeatMode.all
}

struct LibraryState: Codable {
    var playlists: [MusicPlaylist] = []
    var history: [ListenEvent] = []
    var positions: [String: Double] = [:]
    var queueIDs: [UUID] = []
    var lastTrackID: UUID?
    var settings = MusicSettings()
    var activeCollection: [UUID]?
}

struct ImportFailure: Identifiable {
    var id = UUID()
    var name: String
    var message: String
    var retryURL: URL?
}

struct MusicBackup: Codable {
    var version = 1
    var createdAt = Date()
    var tracks: [Track]
    var state: LibraryState
}

extension MusicSettings {
    var color: Color {
        switch accent { case "Azul": return .cyan; case "Roxo": return Color(red: 0.76, green: 0.55, blue: 1); case "Coral": return .orange; default: return StartStyle.accent }
    }
}

extension Player {
    var favoriteTracks: [Track] { tracks.filter { $0.favorite == true } }
    var historyTracks: [Track] {
        var seen = Set<UUID>()
        return state.history.reversed().compactMap { event in
            guard seen.insert(event.trackID).inserted else { return nil }
            return tracks.first { $0.id == event.trackID }
        }
    }
    var queueTracks: [Track] { state.queueIDs.compactMap { id in tracks.first { $0.id == id } } }
    var totalBytes: Int64 { tracks.reduce(0) { $0 + ($1.byteCount ?? fileSize($1)) } }
    func fileURL(_ track: Track) -> URL { root.appendingPathComponent(track.file) }
    func artworkURL(_ track: Track) -> URL? { track.artwork.map { root.appendingPathComponent($0) } }
    func fileSize(_ track: Track) -> Int64 { (try? fileURL(track).resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
    func displayTracks(search: String = "", favorites: Bool = false) -> [Track] {
        let values = (favorites ? favoriteTracks : tracks).filter {
            search.isEmpty || [$0.title, $0.artist ?? "", $0.album ?? ""].joined(separator: " ").localizedStandardContains(search)
        }
        switch state.settings.sort {
        case .newest: return values.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .title: return values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: return values.sorted { ($0.artist ?? "").localizedStandardCompare($1.artist ?? "") == .orderedAscending }
        case .album: return values.sorted { ($0.album ?? "").localizedStandardCompare($1.album ?? "") == .orderedAscending }
        case .duration: return values.sorted { ($0.length ?? 0) > ($1.length ?? 0) }
        }
    }
    func toggleFavorite(_ track: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[index].favorite = !(tracks[index].favorite ?? false)
        if current?.id == track.id { current = tracks[index] }
        save()
    }
    func updateTrack(_ updated: Track, artworkData: Data? = nil, removeArtwork: Bool = false) {
        guard let index = tracks.firstIndex(where: { $0.id == updated.id }) else { return }
        var track = updated
        track.title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !track.title.isEmpty else { error = "Informe um nome para a música."; return }
        do {
            if let data = artworkData {
                let name = track.id.uuidString + ".art"
                try data.write(to: root.appendingPathComponent(name), options: .atomic)
                track.artwork = name
            } else if removeArtwork { track.artwork = nil }
            tracks[index] = track
            if current?.id == track.id { current = track; nowPlaying() }
            save()
        } catch { self.error = error.localizedDescription }
    }
    func createPlaylist(_ name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        state.playlists.append(MusicPlaylist(name: value))
    }
    func add(_ track: Track, to playlistID: UUID) {
        guard let index = state.playlists.firstIndex(where: { $0.id == playlistID }), !state.playlists[index].trackIDs.contains(track.id) else { return }
        state.playlists[index].trackIDs.append(track.id)
    }
    func playPlaylist(_ id: UUID) {
        guard let list = state.playlists.first(where: { $0.id == id }) else { return }
        playCollection(list.trackIDs.compactMap { id in tracks.first { $0.id == id } })
    }
    func playCollection(_ collection: [Track]) {
        guard let first = collection.first else { return }
        state.queueIDs = collection.dropFirst().map(\.id)
        state.activeCollection = collection.map(\.id)
        play(first, automatic: true)
    }
    func enqueue(_ track: Track, next: Bool) {
        if next { state.queueIDs.insert(track.id, at: 0) } else { state.queueIDs.append(track.id) }
    }
    func clearHistory() { state.history = [] }
    func deleteTracks(_ ids: Set<UUID>) {
        remove(IndexSet(tracks.indices.filter { ids.contains(tracks[$0].id) }))
    }
    func retryFailedImports() { importFiles(importFailures.compactMap(\.retryURL)) }
}
