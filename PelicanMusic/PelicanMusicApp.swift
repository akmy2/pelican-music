import SwiftUI
import UniformTypeIdentifiers
import AVKit

@main struct PelicanMusicApp: App {
    @StateObject private var player = Player()
    @StateObject private var spotify = Spotify()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(player).environmentObject(spotify).preferredColorScheme(.dark).environment(\.locale, Locale(identifier: "pt_BR")) }
    }
}

struct ContentView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var spotify: Spotify
    @State private var importing = false
    @State private var spotifyLink = ""
    @State private var selectedTab = 0
    @State private var expandedPlayer = false
    private let lime = Color(red: 0.77, green: 1, blue: 0.08)
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("START").font(.system(size: 48, weight: .black, design: .rounded)).italic().tracking(-2)
                                Image(systemName: "play.fill").font(.title3).foregroundStyle(lime)
                                Spacer()
                            }
                            Text("Sua música, no seu ritmo.").font(.subheadline).foregroundStyle(.secondary)
                            Button { importing = true } label: {
                                Label("Importar músicas", systemImage: "plus").font(.headline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(lime).foregroundStyle(.black).disabled(player.importing).padding(.top, 12)
                            if player.importing { ProgressView("Importando arquivos…") }
                            if let status = player.importStatus { Label(status, systemImage: "tray.and.arrow.down").font(.caption).foregroundStyle(.secondary).padding(.top, 4) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Button { selectedTab = 1 } label: { Label("Arquivos", systemImage: "folder") }
                                    Link(destination: URL(string: "https://open.spotify.com")!) { Label("Spotify", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green) }
                                    Link(destination: URL(string: "https://soundcloud.com")!) { Label("SoundCloud", systemImage: "cloud.fill").foregroundStyle(.orange) }
                                    Link(destination: URL(string: "https://www.youtube.com")!) { Label("YouTube", systemImage: "play.rectangle.fill").foregroundStyle(.red) }
                                }.font(.caption.weight(.medium)).buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.white)
                            }.padding(.vertical, 12)
                            ZStack(alignment: .bottomLeading) {
                                LandscapeArt()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SEU MOMENTO").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(.white.opacity(0.75))
                                    Text("Seu próximo play").font(.title2.bold())
                                    Text("Explore sua biblioteca").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                                    Button { player.resume() } label: {
                                        Image(systemName: "play.fill").foregroundStyle(.black).padding(16).background(lime, in: Circle())
                                    }.buttonStyle(.plain).disabled(player.tracks.isEmpty).padding(.top, 12)
                                }.padding(24)
                            }.frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.08)))
                        }.padding(.vertical, 8)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    Section("Sua biblioteca · \(player.tracks.count) faixas") {
                        if player.tracks.isEmpty {
                            ContentUnavailableView("Sua biblioteca está pronta", systemImage: "music.note.list", description: Text("Adicione arquivos pelo iCloud Drive ou pelo app Arquivos."))
                        }
                        ForEach(player.tracks) { track in
                            Button { player.play(track) } label: {
                                MusicRow(track: track, active: player.current?.id == track.id && player.playing)
                            }.buttonStyle(.plain).listRowBackground(StartStyle.surface).listRowSeparatorTint(.white.opacity(0.06))
                        }.onDelete(perform: player.remove)
                    }
                }.scrollContentBackground(.hidden).background(Color(red: 0.045, green: 0.045, blue: 0.055))
                    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                    .toolbar { EditButton() }
                    .safeAreaInset(edge: .bottom) { if player.current != nil { localControls } }
            }.tabItem { Label("Início", systemImage: "house.fill") }.tag(0)
            NavigationStack {
                List {
                    Section {
                        Button("Importar músicas", systemImage: "plus.circle.fill") { importing = true }.disabled(player.importing)
                        if player.importing { ProgressView("Importando arquivos…") }
                        if let status = player.importStatus { Text(status).font(.footnote) }
                    }
                    Section("\(player.tracks.count) músicas · Offline") {
                        if player.tracks.isEmpty {
                            ContentUnavailableView("Adicione sua primeira música", systemImage: "music.note", description: Text("Selecione MP3, M4A, WAV ou AAC no app Arquivos."))
                        }
                        ForEach(player.tracks) { track in
                            Button { player.play(track) } label: {
                                MusicRow(track: track, active: player.current?.id == track.id && player.playing)
                            }.buttonStyle(.plain).listRowBackground(StartStyle.surface).listRowSeparatorTint(.white.opacity(0.06))
                        }.onDelete(perform: player.remove)
                    }
                }.scrollContentBackground(.hidden).background(StartStyle.background).navigationTitle("Biblioteca").toolbar { EditButton() }
                    .safeAreaInset(edge: .bottom) { if player.current != nil { localControls } }
            }.tabItem { Label("Biblioteca", systemImage: "music.note.list") }.tag(1)
            NavigationStack {
                Form {
                    Section("Usar as contas do telefone") {
                        Text("Abra o serviço e use a conta que já está conectada no iPhone. Nesse modo, a reprodução e os controles pertencem ao aplicativo de origem; não há conexão da conta ao START.").font(.footnote)
                        Link("Abrir Spotify no telefone", destination: URL(string: "https://open.spotify.com")!)
                        Link("Abrir SoundCloud no telefone", destination: URL(string: "https://soundcloud.com")!)
                    }
                    Section("Controles fora do START") {
                        Text("As músicas locais usam os controles de áudio do iOS na tela bloqueada e na Central de Controle: play, pausa, anterior e próxima. A apresentação na Dynamic Island é gerenciada pelo sistema nos modelos compatíveis.").font(.footnote)
                    }
                    Section("Spotify Premium · Integração opcional por API") {
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
                }.scrollContentBackground(.hidden).background(StartStyle.background).navigationTitle("Conexões")
            }.tabItem { Label("Conexões", systemImage: "link") }.tag(2)
        }.tint(lime)
        .sheet(isPresented: $importing) {
            AudioImporter(onSelection: { urls in
                importing = false
                player.importFiles(urls)
            }, onCancel: { importing = false })
        }
        .sheet(isPresented: $expandedPlayer) { expandedControls.presentationDragIndicator(.visible) }
        .alert("Não foi possível concluir", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) {
            Button("OK") { player.error = nil }
        } message: { Text(player.error ?? "") }
    }
    private func send(_ action: String, link: String = "") {
        if action == "play" { player.releaseAudio() }
        Task { await spotify.command(action, link: link) }
    }
    private var localControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { expandedPlayer = true } label: {
                    HStack(spacing: 12) {
                        TrackArtwork(title: player.current?.title ?? "", active: player.playing).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.current?.title ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            Text("\(player.playing ? "Tocando agora" : "Pausado") · Toque para ampliar").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Abrir player completo")
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.title3)
                        .foregroundStyle(.black).frame(width: 42, height: 42).background(lime, in: Circle())
                }.accessibilityLabel(player.playing ? "Pausar" : "Reproduzir")
                Button { player.next() } label: { Image(systemName: "forward.end.fill").foregroundStyle(.white).frame(width: 32, height: 44) }.accessibilityLabel("Próxima música")
            }.padding(12)
            ProgressView(value: min(max(player.elapsed, 0), max(player.duration, 1)), total: max(player.duration, 1)).tint(lime).padding(.horizontal, 12)
        }.padding(.bottom, 8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
            .padding(.horizontal, 12).padding(.bottom, 8)
    }
    private var expandedControls: some View {
        ScrollView {
        VStack(spacing: 24) {
            HStack {
                Button { expandedPlayer = false } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.accessibilityLabel("Fechar player")
                Spacer()
                Text("TOCANDO NO START").font(.caption.weight(.bold)).tracking(2)
                Spacer()
                AirPlayButton().frame(width: 44, height: 44)
            }.foregroundStyle(.white)
            TrackArtwork(title: player.current?.title ?? "", active: player.playing)
                .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: .orange.opacity(0.15), radius: 30, y: 12)
        VStack(spacing: 10) {
            Text(player.current?.title ?? "").font(.title2.bold()).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            Text("Biblioteca pessoal · Arquivo local").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Slider(value: Binding(get: { player.elapsed }, set: { player.seek($0) }), in: 0...max(player.duration, 1))
            HStack {
                Text(clock(player.elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 44)) }.padding(.horizontal, 18)
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                Spacer()
                Text(clock(player.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
            Label("Disponível offline", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(lime)
        }.padding(24).padding(.top, 10)
        }.background(LinearGradient(colors: [Color(red: 0.16, green: 0.1, blue: 0.18), StartStyle.background], startPoint: .top, endPoint: .bottom)).tint(lime)
    }
    private func clock(_ seconds: Double) -> String {
        let seconds = Int(max(0, seconds)); return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
