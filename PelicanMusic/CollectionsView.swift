import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject var player: Player
    @State private var create = false
    @State private var name = ""
    var body: some View {
        List {
            Section {
                NavigationLink { TrackCollectionView(title: "Favoritos", kind: .favorites) } label: { Label("Favoritos · \(player.favoriteTracks.count)", systemImage: "heart.fill") }
                NavigationLink { TrackCollectionView(title: "Histórico", kind: .history) } label: { Label("Histórico de reprodução", systemImage: "clock.arrow.circlepath") }
                NavigationLink { QueueView() } label: { Label("Fila · \(player.queueTracks.count)", systemImage: "text.line.first.and.arrowtriangle.forward") }
            }
            Section("Suas playlists") {
                if player.state.playlists.isEmpty { Text("Crie uma playlist e adicione músicas pelo menu de cada faixa.").foregroundStyle(.secondary) }
                ForEach(player.state.playlists) { playlist in
                    NavigationLink { PlaylistDetailView(id: playlist.id) } label: {
                        Label { VStack(alignment: .leading) { Text(playlist.name); Text("\(playlist.trackIDs.count) músicas").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "rectangle.stack.fill") }
                    }
                }.onDelete { player.state.playlists.remove(atOffsets: $0) }
            }
        }.scrollContentBackground(.hidden).background(StartStyle.background).navigationTitle("Playlists")
            .toolbar { Button { create = true } label: { Image(systemName: "plus") }.accessibilityLabel("Criar playlist") }
            .alert("Nova playlist", isPresented: $create) {
                TextField("Nome da playlist", text: $name)
                Button("Criar") { player.createPlaylist(name); name = "" }
                Button("Cancelar", role: .cancel) {}
            }
    }
}

enum CollectionKind { case favorites, history }
struct TrackCollectionView: View {
    @EnvironmentObject var player: Player
    var title: String
    var kind: CollectionKind
    private var tracks: [Track] { kind == .favorites ? player.favoriteTracks : player.historyTracks }
    var body: some View {
        List {
            Button("Tocar tudo", systemImage: "play.fill") { player.playCollection(tracks) }.disabled(tracks.isEmpty)
            if tracks.isEmpty { ContentUnavailableView("Ainda não há músicas", systemImage: kind == .favorites ? "heart" : "clock") }
            ForEach(tracks) { MusicItem(track: $0) }
            if kind == .history { Button("Limpar histórico", role: .destructive) { player.clearHistory() } }
        }.navigationTitle(title).scrollContentBackground(.hidden).background(StartStyle.background)
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var player: Player
    let id: UUID
    @State private var add = false
    @State private var rename = false
    @State private var name = ""
    private var index: Int? { player.state.playlists.firstIndex { $0.id == id } }
    private var playlist: MusicPlaylist? { player.state.playlists.first { $0.id == id } }
    private var values: [Track] { playlist?.trackIDs.compactMap { id in player.tracks.first { $0.id == id } } ?? [] }
    var body: some View {
        List {
            Section {
                Button("Tocar playlist", systemImage: "play.fill") { player.playPlaylist(id) }.disabled(values.isEmpty)
                Button("Adicionar músicas", systemImage: "plus") { add = true }
                if let playlist { ShareLink(item: URL(string: "pelicanmusic://playlist/\(playlist.id.uuidString)")!) { Label("Compartilhar atalho desta playlist", systemImage: "square.and.arrow.up") } }
            }
            Section("Arraste para reordenar") {
                ForEach(values) { MusicItem(track: $0) }
                    .onDelete { offsets in
                        guard let index else { return }
                        let ids = Set(offsets.map { values[$0].id })
                        player.state.playlists[index].trackIDs.removeAll { ids.contains($0) }
                    }
                    .onMove { source, destination in guard let index else { return }; player.state.playlists[index].trackIDs.move(fromOffsets: source, toOffset: destination) }
            }
        }.navigationTitle(playlist?.name ?? "Playlist").scrollContentBackground(.hidden).background(StartStyle.background)
            .toolbar { EditButton(); Button("Renomear") { name = playlist?.name ?? ""; rename = true } }
            .alert("Renomear playlist", isPresented: $rename) {
                TextField("Nome", text: $name)
                Button("Salvar") { if let index, !name.trimmingCharacters(in: .whitespaces).isEmpty { player.state.playlists[index].name = name } }
                Button("Cancelar", role: .cancel) {}
            }
            .sheet(isPresented: $add) { PlaylistAddTracksView(id: id) }
    }
}

struct PlaylistAddTracksView: View {
    @EnvironmentObject var player: Player
    @Environment(\.dismiss) var dismiss
    let id: UUID
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List(player.displayTracks(search: search)) { track in
                let selected = player.state.playlists.first(where: { $0.id == id })?.trackIDs.contains(track.id) == true
                Button { player.add(track, to: id) } label: { HStack { Text(track.title).foregroundStyle(.primary); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle") } }.disabled(selected)
            }.navigationTitle("Adicionar músicas").searchable(text: $search, prompt: "Buscar")
                .toolbar { Button("Concluir") { dismiss() } }
        }.tint(player.state.settings.color)
    }
}

struct AddToPlaylistView: View {
    @EnvironmentObject var player: Player
    @Environment(\.dismiss) var dismiss
    let track: Track
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Nova playlist", text: $name)
                    Button("Criar e adicionar") {
                        player.createPlaylist(name)
                        if let playlist = player.state.playlists.last { player.add(track, to: playlist.id) }
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(player.state.playlists) { playlist in
                    Button(playlist.name) { player.add(track, to: playlist.id); dismiss() }
                }
            }.navigationTitle("Adicionar à playlist").toolbar { Button("Fechar") { dismiss() } }
        }.tint(player.state.settings.color)
    }
}

struct QueueView: View {
    @EnvironmentObject var player: Player
    var body: some View {
        List {
            if let current = player.current { Section("Tocando agora") { MusicItem(track: current) } }
            Section("A seguir · Arraste para reordenar") {
                if player.state.queueIDs.isEmpty { Text("A fila está vazia. A sequência da biblioteca ou playlist será usada.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(player.queueTracks.enumerated()), id: \.offset) { pair in MusicItem(track: pair.element) }
                    .onDelete { player.state.queueIDs.remove(atOffsets: $0) }
                    .onMove { player.state.queueIDs.move(fromOffsets: $0, toOffset: $1) }
            }
            Button("Limpar fila", role: .destructive) { player.state.queueIDs = [] }
        }.navigationTitle("Fila de reprodução").toolbar { EditButton() }.scrollContentBackground(.hidden).background(StartStyle.background)
    }
}
