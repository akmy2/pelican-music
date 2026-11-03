import AppIntents
import Foundation

struct ResumeMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Reproduzir no START"
    static var description = IntentDescription("Abre o START e retoma a música local ou inicia sua biblioteca.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { Player.shared.resume(); return .result() }
}

struct NextMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Próxima música no START"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { Player.shared.next(); return .result() }
}

struct PlaylistEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    static var defaultQuery = PlaylistQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PlaylistQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PlaylistEntity] {
        await MainActor.run { Player.shared.state.playlists.filter { identifiers.contains($0.id.uuidString) }.map { PlaylistEntity(id: $0.id.uuidString, name: $0.name) } }
    }
    func suggestedEntities() async throws -> [PlaylistEntity] {
        await MainActor.run { Player.shared.state.playlists.map { PlaylistEntity(id: $0.id.uuidString, name: $0.name) } }
    }
}

struct PlayPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Tocar playlist no START"
    static var openAppWhenRun = true
    @Parameter(title: "Playlist") var playlist: PlaylistEntity
    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: playlist.id) { Player.shared.playPlaylist(id) }
        return .result()
    }
}

struct StartShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ResumeMusicIntent(), phrases: ["Reproduzir no \(.applicationName)", "Tocar música no \(.applicationName)"], shortTitle: "Reproduzir", systemImageName: "play.fill")
        AppShortcut(intent: NextMusicIntent(), phrases: ["Próxima música no \(.applicationName)"], shortTitle: "Próxima música", systemImageName: "forward.end.fill")
        AppShortcut(intent: PlayPlaylistIntent(), phrases: ["Tocar playlist no \(.applicationName)"], shortTitle: "Tocar playlist", systemImageName: "rectangle.stack")
    }
}
