import SwiftUI
import PhotosUI

struct TrackCover: View {
    @EnvironmentObject var player: Player
    var track: Track?
    var body: some View {
        Group {
            if let track, let url = player.artworkURL(track), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { TrackArtwork(title: track?.title ?? "START", active: player.current?.id == track?.id && player.playing) }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MusicItem: View {
    @EnvironmentObject var player: Player
    let track: Track
    var grid = false
    @State private var edit = false
    @State private var addToPlaylist = false
    private var active: Bool { player.current?.id == track.id }
    var body: some View {
        Button { player.play(track) } label: {
            if grid {
                VStack(alignment: .leading, spacing: 8) {
                    TrackCover(track: track).aspectRatio(1, contentMode: .fit)
                    Text(track.title).font(.subheadline.bold()).lineLimit(2)
                    Text(track.artist ?? "Arquivo local").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                HStack(spacing: 13) {
                    TrackCover(track: track).frame(width: player.state.settings.artworkSize, height: player.state.settings.artworkSize)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text([track.artist ?? "Arquivo local", track.album].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if track.favorite == true { Image(systemName: "heart.fill").font(.caption).foregroundStyle(player.state.settings.color) }
                    Image(systemName: active && player.playing ? "waveform" : "play.fill").font(.caption).foregroundStyle(player.state.settings.color)
                }.padding(.vertical, 5)
            }
        }.foregroundStyle(active ? player.state.settings.color : .white).buttonStyle(.plain)
            .listRowBackground(StartStyle.surface).listRowSeparatorTint(.white.opacity(0.07))
            .contextMenu {
                Button("Tocar a seguir", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(track, next: true) }
                Button("Adicionar à fila", systemImage: "text.badge.plus") { player.enqueue(track, next: false) }
                Button(track.favorite == true ? "Remover favorito" : "Favoritar", systemImage: "heart") { player.toggleFavorite(track) }
                Button("Adicionar à playlist", systemImage: "rectangle.stack.badge.plus") { addToPlaylist = true }
                Button("Editar informações", systemImage: "pencil") { edit = true }
                if let source = track.artworkSource, let url = URL(string: source) { Link("Ver música no iTunes · Fonte da capa", destination: url) }
                ShareLink(item: player.fileURL(track)) { Label("Compartilhar áudio", systemImage: "square.and.arrow.up") }
            }
            .sheet(isPresented: $edit) { TrackEditor(track: track) }
            .sheet(isPresented: $addToPlaylist) { AddToPlaylistView(track: track) }
    }
}

struct TrackEditor: View {
    @EnvironmentObject var player: Player
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var photo: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var removeCover = false
    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title); _artist = State(initialValue: track.artist ?? ""); _album = State(initialValue: track.album ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Informações") {
                    TextField("Nome", text: $title)
                    TextField("Artista", text: $artist)
                    TextField("Álbum", text: $album)
                }
                Section("Capa") {
                    if let data = coverData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 180) }
                    else if !removeCover { TrackCover(track: track).frame(width: 180, height: 180) }
                    PhotosPicker("Escolher imagem", selection: $photo, matching: .images)
                    Button("Usar capa ilustrativa") { coverData = nil; removeCover = true; photo = nil }
                }
                Text("As alterações são guardadas na biblioteca do START. O arquivo original não é reescrito.").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Editar música").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salvar") {
                            var updated = track; updated.title = title; updated.artist = artist.isEmpty ? nil : artist; updated.album = album.isEmpty ? nil : album
                            player.updateTrack(updated, artworkData: coverData, removeArtwork: removeCover)
                            dismiss()
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .task(id: photo) {
                    if let photo, let data = try? await photo.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        coverData = image.jpegData(compressionQuality: 0.85); removeCover = false
                    }
                }
        }.tint(player.state.settings.color)
    }
}
