import SwiftUI

func musicTime(_ value: Double) -> String {
    let total = Int(value.isFinite ? max(0, value) : 0)
    return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
}

struct MiniPlayer: View {
    @EnvironmentObject var player: Player
    var expand: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: expand) {
                    HStack {
                        TrackCover(track: player.current).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.current?.title ?? "").font(.subheadline.bold()).lineLimit(1)
                            Text(player.loading ? "Preparando áudio…" : player.current?.artist ?? "Biblioteca pessoal").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain).accessibilityLabel("Abrir player")
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill").foregroundStyle(.black).frame(width: 42, height: 42).background(player.state.settings.color, in: Circle())
                }.disabled(player.loading).accessibilityLabel(player.playing ? "Pausar" : "Reproduzir")
                Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 30, height: 44) }.accessibilityLabel("Próxima música")
            }.padding(12)
            ProgressView(value: min(player.elapsed, max(player.duration, 1)), total: max(player.duration, 1)).padding(.horizontal, 12)
        }.padding(.bottom, 8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
            .padding(.horizontal, 12).tint(player.state.settings.color)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var player: Player
    @Environment(\.dismiss) var dismiss
    @State private var queue = false
    @State private var timer = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    TrackCover(track: player.current).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 28)).shadow(color: player.state.settings.color.opacity(0.12), radius: 24, y: 10)
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(player.current?.title ?? "Escolha uma música").font(.title2.bold()).lineLimit(3)
                            Text(player.current?.artist ?? "Biblioteca pessoal").foregroundStyle(.secondary)
                            if let album = player.current?.album { Text(album).font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if let current = player.current {
                            Button { player.toggleFavorite(current) } label: { Image(systemName: current.favorite == true ? "heart.fill" : "heart").font(.title2) }.accessibilityLabel("Alternar favorito")
                        }
                    }
                    VStack(spacing: 4) {
                        Slider(value: Binding(get: { min(player.elapsed, max(player.duration, 1)) }, set: { player.seek($0) }), in: 0...max(player.duration, 1))
                        HStack { Text(musicTime(player.elapsed)); Spacer(); Text("−" + musicTime(player.duration - player.elapsed)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 24) {
                        Button { player.state.settings.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(player.state.settings.shuffle ? player.state.settings.color : Color.gray) }.accessibilityLabel("Aleatório")
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title) }.accessibilityLabel("Anterior")
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.title).foregroundStyle(.black).frame(width: 74, height: 74).background(player.state.settings.color, in: Circle()) }.disabled(player.loading).accessibilityLabel(player.playing ? "Pausar" : "Reproduzir")
                        Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title) }.accessibilityLabel("Próxima")
                        Button { cycleRepeat() } label: { Image(systemName: player.state.settings.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(player.state.settings.repeatMode == .off ? Color.gray : player.state.settings.color) }.accessibilityLabel("Repetição: \(player.state.settings.repeatMode.rawValue)")
                    }.foregroundStyle(.white).buttonStyle(.plain)
                    HStack {
                        Button { timer = true } label: { Label(player.stopAfterTrack ? "Fim da faixa" : "Dormir", systemImage: "moon.zzz") }
                        Spacer()
                        AirPlayButton().frame(width: 40, height: 40)
                        Spacer()
                        Button { queue = true } label: { Label("Fila", systemImage: "text.line.first.and.arrowtriangle.forward") }
                    }.font(.subheadline)
                    if let deadline = player.sleepDeadline { Text("Parar às \(deadline.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    if player.loading { ProgressView("Preparando áudio…") }
                    Label("Disponível offline", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(player.state.settings.color)
                }.padding(24)
            }.background(LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.18), StartStyle.background], startPoint: .top, endPoint: .bottom))
                .navigationTitle("Tocando no START").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Fechar player") } }
                .sheet(isPresented: $queue) { NavigationStack { QueueView().toolbar { Button("Fechar") { queue = false } } } }
                .confirmationDialog("Temporizador", isPresented: $timer, titleVisibility: .visible) {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { value in Button("\(value) minutos") { player.setSleep(minutes: value) } }
                    Button("Ao terminar esta faixa") { player.sleepAtTrackEnd() }
                    Button("Desativar", role: .destructive) { player.setSleep(minutes: nil) }
                }
        }.tint(player.state.settings.color)
    }
    private func cycleRepeat() {
        switch player.state.settings.repeatMode { case .off: player.state.settings.repeatMode = .all; case .all: player.state.settings.repeatMode = .one; case .one: player.state.settings.repeatMode = .off }
    }
}

struct CarModeView: View {
    @EnvironmentObject var player: Player
    @Environment(\.dismiss) var dismiss
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 30) {
                    HStack { Label("Modo carro", systemImage: "car.fill").font(.headline); Spacer(); Button("Sair") { dismiss() }.frame(minHeight: 50) }
                    Text(player.current?.title ?? "Sua biblioteca está pronta").font(.largeTitle.bold()).multilineTextAlignment(.center).lineLimit(4)
                    Text(player.current?.artist ?? "START").font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 35)).frame(maxWidth: .infinity, minHeight: 96) }.accessibilityLabel("Anterior")
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 44)).foregroundStyle(.black).frame(width: 112, height: 112).background(player.state.settings.color, in: Circle()) }.accessibilityLabel("Reproduzir ou pausar")
                        Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 35)).frame(maxWidth: .infinity, minHeight: 96) }.accessibilityLabel("Próxima")
                    }.buttonStyle(.plain)
                    Text("\(musicTime(player.elapsed)) / \(musicTime(player.duration))").font(.title2.monospacedDigit())
                    AirPlayButton().frame(width: 60, height: 60)
                }.padding(24).frame(minHeight: geometry.size.height)
            }
        }.background(.black).foregroundStyle(.white).tint(player.state.settings.color)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
