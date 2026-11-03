import SwiftUI
import UniformTypeIdentifiers
import AVKit

@main struct PelicanMusicApp: App {
    @StateObject private var player = Player()
    @StateObject private var spotify = Spotify()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(player).environmentObject(spotify).preferredColorScheme(.dark) }
    }
}

struct ContentView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var spotify: Spotify
    @State private var importing = false
    @State private var spotifyLink = ""
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SUA MÚSICA. SEU ESPAÇO.").font(.caption).foregroundStyle(.mint)
                            Text("Tudo começa\ncom um play.").font(.largeTitle.bold())
                            Text("Importe suas músicas e ouça mesmo com a tela bloqueada.").foregroundStyle(.secondary)
                            Button("Importar músicas", systemImage: "plus.circle.fill") { importing = true }.buttonStyle(.borderedProminent).tint(.mint)
                        }.padding(.vertical, 12)
                    }
                    Section("Biblioteca · \(player.tracks.count) faixas") {
                        if player.tracks.isEmpty {
                            ContentUnavailableView("Sua biblioteca está pronta", systemImage: "music.note.list", description: Text("Adicione arquivos pelo iCloud Drive ou pelo app Arquivos."))
                        }
                        ForEach(player.tracks) { track in
                            Button { player.play(track) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: player.current?.id == track.id && player.playing ? "waveform" : "music.note")
                                        .foregroundStyle(.mint).frame(width: 38, height: 38).background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading) { Text(track.title).foregroundStyle(.primary); Text("Arquivo local · Offline").font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Image(systemName: "play.fill").foregroundStyle(.mint)
                                }
                            }
                        }.onDelete(perform: player.remove)
                    }
                }.navigationTitle("Pelican Music")
                    .toolbar { EditButton() }
                    .safeAreaInset(edge: .bottom) { if player.current != nil { localControls } }
            }.tabItem { Label("Biblioteca", systemImage: "square.stack.fill") }
            NavigationStack {
                Form {
                    Section("Spotify Premium") {
                        Label(spotify.connected ? "Conta conectada" : "Conecte seu Spotify", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.mint)
                        Text("O Spotify executa o áudio. Abra-o e inicie uma música para ativar o iPhone; depois use os controles aqui.").font(.footnote)
                        TextField("Spotify Client ID", text: $spotify.clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(spotify.connected ? "Conectar novamente" : "Conectar conta") { spotify.connect() }.disabled(spotify.busy)
                        if spotify.connected {
                            TextField("Link de música, álbum ou playlist", text: $spotifyLink).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            Button("Reproduzir link") { send("play", link: spotifyLink) }.disabled(spotify.busy || spotifyLink.isEmpty)
                            HStack {
                                Button { send("previous") } label: { Image(systemName: "backward.end.fill") }
                                Spacer()
                                Button { send("play") } label: { Image(systemName: "play.fill") }
                                Spacer()
                                Button { send("pause") } label: { Image(systemName: "pause.fill") }
                                Spacer()
                                Button { send("next") } label: { Image(systemName: "forward.end.fill") }
                            }.buttonStyle(.borderless).disabled(spotify.busy)
                            Button("Desconectar", role: .destructive) { spotify.disconnect() }
                        }
                        if spotify.busy { ProgressView() }
                        if let message = spotify.message { Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                        Link("Abrir Spotify", destination: URL(string: "https://open.spotify.com")!)
                    }
                    Section("Configuração da conexão") {
                        Text("Cadastre o app no Spotify Developer Dashboard e autorize sua conta como usuário de teste, se necessário. Adicione exatamente este Redirect URI:").font(.footnote)
                        Text("pelicanmusic://spotify-callback").font(.footnote.monospaced()).textSelection(.enabled)
                        Link("Spotify Developer Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                    }
                    Section("SoundCloud") {
                        Text("Integração de conta e streaming ainda não implementada. Depende de credenciais e acesso à API.").font(.footnote).foregroundStyle(.secondary)
                        Link("Abrir SoundCloud", destination: URL(string: "https://soundcloud.com")!)
                    }
                    Section("YouTube") {
                        Text("Nesta versão, os links abrem no YouTube. Player incorporado ainda não implementado. A API oficial não permite áudio com o player oculto.").font(.footnote).foregroundStyle(.secondary)
                        Link("Abrir YouTube", destination: URL(string: "https://www.youtube.com")!)
                    }
                }.navigationTitle("Conexões")
            }.tabItem { Label("Conexões", systemImage: "link") }
        }.tint(.mint)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): player.importFiles(urls)
            case .failure(let error): player.error = error.localizedDescription
            }
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) {
            Button("OK") { player.error = nil }
        } message: { Text(player.error ?? "") }
    }
    private func send(_ action: String, link: String = "") {
        if action == "play" { player.releaseAudio() }
        Task { await spotify.command(action, link: link) }
    }
    private var localControls: some View {
        VStack(spacing: 10) {
            Text(player.current?.title ?? "").font(.headline).lineLimit(1)
            Slider(value: Binding(get: { player.elapsed }, set: { player.seek($0) }), in: 0...max(player.duration, 1))
            HStack {
                Text(clock(player.elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 44)) }.padding(.horizontal, 18)
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                Spacer()
                AirPlayButton().frame(width: 28, height: 28)
                Text(clock(player.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }.padding().background(.ultraThinMaterial)
    }
    private func clock(_ seconds: Double) -> String {
        let seconds = Int(max(0, seconds)); return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
