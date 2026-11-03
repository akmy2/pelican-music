import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var spotify: Spotify
    @State private var link = ""
    var body: some View {
        Form {
            Section("Aplicativos do telefone") {
                Link("Abrir Spotify", destination: URL(string: "https://open.spotify.com")!)
                Link("Abrir SoundCloud", destination: URL(string: "https://soundcloud.com")!)
                Link("Abrir YouTube", destination: URL(string: "https://youtube.com")!)
                Text("Os links usam o aplicativo ou navegador de origem. O START não consegue ler automaticamente o que outro app está reproduzindo.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Spotify Premium · Integração opcional") {
                Label(spotify.connected ? "Conectado" : "Conectar conta", systemImage: "antenna.radiowaves.left.and.right")
                TextField("Spotify Client ID", text: $spotify.clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(spotify.connected ? "Reconectar" : "Conectar") { spotify.connect() }.disabled(spotify.busy)
                if spotify.connected {
                    TextField("Link de música, álbum ou playlist", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Reproduzir link") { send("play", link: link) }.disabled(link.isEmpty || spotify.busy)
                    HStack {
                        Button { send("previous") } label: { Image(systemName: "backward.end.fill") }
                        Spacer(); Button { send("play") } label: { Image(systemName: "play.fill") }
                        Spacer(); Button { send("pause") } label: { Image(systemName: "pause.fill") }
                        Spacer(); Button { send("next") } label: { Image(systemName: "forward.end.fill") }
                    }.buttonStyle(.borderless).disabled(spotify.busy)
                    Button("Desconectar", role: .destructive) { spotify.disconnect() }
                }
                if spotify.busy { ProgressView() }
                if let message = spotify.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Configurar Spotify") {
                Text("Cadastre um app com Web API e autorize sua conta no Dashboard. Abra o Spotify e inicie uma música para ativar o iPhone antes de enviar comandos.").font(.footnote)
                Text("Redirect URI: pelicanmusic://spotify-callback").font(.caption.monospaced()).textSelection(.enabled)
                Link("Spotify Developer Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
            }
            Section("Áudio fora do START") {
                Text("As músicas locais usam os controles do iOS na tela bloqueada e na Central de Controle. Uma sobreposição global ou uma Dynamic Island em aparelhos sem esse recurso não pode ser criada por um IPA comum.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Conexões").scrollContentBackground(.hidden).background(StartStyle.background)
    }
    private func send(_ action: String, link: String = "") {
        if action == "play" { player.releaseAudio() }
        Task { await spotify.command(action, link: link) }
    }
}
