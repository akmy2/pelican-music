import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var spotify: Spotify
    @State private var tab = 0
    @State private var importing = false
    @State private var folder = false
    @State private var expanded = false
    @State private var car = false
    @State private var settings = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView(importAction: { showImport(false) }, folderAction: { showImport(true) })
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Ajustes")
                        }
                    }
            }.tabItem { Label("Início", systemImage: "house.fill") }.tag(0)
            NavigationStack { LibraryView(importAction: { showImport(false) }, folderAction: { showImport(true) }) }
                .tabItem { Label("Biblioteca", systemImage: "music.note.list") }.tag(1)
            NavigationStack { CollectionsView() }.tabItem { Label("Playlists", systemImage: "rectangle.stack") }.tag(2)
            NavigationStack { ConnectionsView() }.tabItem { Label("Conexões", systemImage: "link") }.tag(3)
        }
        .tint(player.state.settings.color)
        .overlay(alignment: .bottom) {
            if player.current != nil { MiniPlayer { expanded = true }.padding(.bottom, 65) }
        }
        .sheet(isPresented: $importing) {
            AudioImporter(folders: folder, onSelection: { urls in importing = false; player.importFiles(urls) }, onCancel: { importing = false })
        }
        .sheet(isPresented: $expanded) { NowPlayingView().presentationDragIndicator(.visible) }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView(openCar: { settings = false; car = true }) } }
        .fullScreenCover(isPresented: $car) { CarModeView() }
        .onOpenURL { url in
            if url.isFileURL { player.importFiles([url]); tab = 1; return }
            switch url.host {
            case "resume": player.resume(); expanded = true
            case "next": player.next(); expanded = true
            case "favorites": player.playCollection(player.favoriteTracks); tab = 1
            case "library": tab = 1
            case "playlist":
                if let id = UUID(uuidString: url.lastPathComponent) { player.playPlaylist(id); expanded = true }
            default: break
            }
        }
        .alert("START", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) {
            Button("OK") { player.error = nil }
        } message: { Text(player.error ?? "") }
    }
    private func showImport(_ isFolder: Bool) { folder = isFolder; importing = true }
}

struct HomeView: View {
    @EnvironmentObject var player: Player
    var importAction: () -> Void
    var folderAction: () -> Void
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("START").font(.system(size: 46, weight: .black, design: .rounded)).italic().tracking(-2)
                        Image(systemName: "play.fill").foregroundStyle(player.state.settings.color)
                    }
                    Text("Sua música, no seu ritmo.").foregroundStyle(.secondary)
                    Button(action: importAction) {
                        Label("Importar músicas", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).foregroundStyle(.black).disabled(player.importing)
                    ImportStatusView()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Button(action: folderAction) { Label("Pastas", systemImage: "folder") }.disabled(player.importing)
                            Link("Spotify", destination: URL(string: "https://open.spotify.com")!).foregroundStyle(.green)
                            Link("SoundCloud", destination: URL(string: "https://soundcloud.com")!).foregroundStyle(.orange)
                            Link("YouTube", destination: URL(string: "https://youtube.com")!).foregroundStyle(.red)
                        }.buttonStyle(.bordered).buttonBorderShape(.capsule).font(.caption)
                    }
                    ZStack(alignment: .bottomLeading) {
                        LandscapeArt()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SEU MOMENTO").font(.caption2.bold()).tracking(2)
                            Text("Seu próximo play").font(.title2.bold())
                            Text("\(player.tracks.count) músicas para levar com você").font(.subheadline)
                            Button { player.resume() } label: {
                                Image(systemName: "play.fill").foregroundStyle(.black).frame(width: 48, height: 48).background(player.state.settings.color, in: Circle())
                            }.buttonStyle(.plain).disabled(player.tracks.isEmpty)
                        }.padding(22)
                    }.frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 24))
                }.padding(.vertical, 4)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            if !player.historyTracks.isEmpty {
                Section("Ouvidas recentemente") { ForEach(player.historyTracks.prefix(5)) { MusicItem(track: $0) } }
            }
            if !player.favoriteTracks.isEmpty {
                Section("Seus favoritos") { ForEach(player.favoriteTracks.prefix(4)) { MusicItem(track: $0) } }
            }
            Section("Adicionadas recentemente") {
                if player.tracks.isEmpty { ContentUnavailableView("Seu primeiro play", systemImage: "music.note", description: Text("Importe um áudio ou uma pasta para começar.")) }
                ForEach(player.displayTracks().prefix(8)) { MusicItem(track: $0) }
            }
        }.scrollContentBackground(.hidden).background(StartStyle.background).navigationBarTitleDisplayMode(.inline)
    }
}

struct LibraryView: View {
    @EnvironmentObject var player: Player
    @State private var search = ""
    @State private var favorites = false
    var importAction: () -> Void
    var folderAction: () -> Void
    private var values: [Track] { player.displayTracks(search: search, favorites: favorites) }
    var body: some View {
        List {
            Section {
                ImportStatusView()
                Toggle("Somente favoritos", isOn: $favorites)
                HStack {
                    Text("\(values.count) músicas").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Ordenar por", selection: $player.state.settings.sort) { ForEach(LibrarySort.allCases) { Text($0.label).tag($0) } }
                        Toggle("Visualizar em grade", isOn: $player.state.settings.grid)
                    } label: { Label("Organizar", systemImage: "arrow.up.arrow.down") }
                }
            }
            Section {
                if values.isEmpty { ContentUnavailableView.search(text: search) }
                if player.state.settings.grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 16)], spacing: 20) {
                        ForEach(values) { MusicItem(track: $0, grid: true) }
                    }.padding(.vertical, 8).listRowBackground(Color.clear)
                } else {
                    ForEach(values) { MusicItem(track: $0) }
                        .onDelete { offsets in player.deleteTracks(Set(offsets.map { values[$0].id })) }
                }
            }
        }.searchable(text: $search, prompt: "Música, artista ou álbum")
            .scrollContentBackground(.hidden).background(StartStyle.background).navigationTitle("Biblioteca")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Importar músicas", systemImage: "plus", action: importAction)
                        Button("Importar pasta", systemImage: "folder.badge.plus", action: folderAction)
                        Button("Tocar resultado", systemImage: "play.fill") { player.playCollection(values) }
                    } label: { Image(systemName: "plus.circle") }.disabled(player.importing)
                }
            }
    }
}

struct ImportStatusView: View {
    @EnvironmentObject var player: Player
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if player.importing { ProgressView(value: player.importProgress).tint(player.state.settings.color) }
            if let status = player.importStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
            if !player.importFailures.isEmpty {
                NavigationLink("Ver \(player.importFailures.count) falha(s) e tentar novamente") { ImportFailuresView() }.font(.caption)
            }
        }
    }
}

struct ImportFailuresView: View {
    @EnvironmentObject var player: Player
    var body: some View {
        List {
            Section {
                Text("Arquivos válidos já foram adicionados. Se a origem temporária não estiver mais disponível, selecione o arquivo novamente no app Arquivos.").font(.footnote)
                Button("Tentar novamente") { player.retryFailedImports() }.disabled(player.importing)
            }
            ForEach(player.importFailures) { item in
                VStack(alignment: .leading, spacing: 8) { Text(item.name).font(.headline); Text(item.message).font(.footnote).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Importações")
    }
}
