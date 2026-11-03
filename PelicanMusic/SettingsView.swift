import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var player: Player
    @Environment(\.dismiss) var dismiss
    var openCar: () -> Void
    @State private var export = false
    @State private var restore = false
    @State private var document: BackupDocument?
    @State private var restoreMessage: String?
    var body: some View {
        Form {
            Section("Aparência") {
                Picker("Cor de destaque", selection: $player.state.settings.accent) { ForEach(["Lima", "Azul", "Roxo", "Coral"], id: \.self) { Text($0).tag($0) } }
                Toggle("Biblioteca em grade", isOn: $player.state.settings.grid)
                VStack(alignment: .leading) { Text("Tamanho das capas"); Slider(value: $player.state.settings.artworkSize, in: 44...88, step: 2) }
            }
            Section("Reprodução") {
                Toggle("Retomar a posição das músicas", isOn: $player.state.settings.resumePositions)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Crossfade: \(Int(player.state.settings.crossfade)) segundos")
                    Slider(value: $player.state.settings.crossfade, in: 0...12, step: 1)
                    Text("A próxima faixa entra enquanto a anterior diminui. Zero desativa. O temporizador de fim de faixa e a repetição de uma música têm prioridade.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Abrir modo carro", systemImage: "car.fill", action: openCar)
            }
            Section("Biblioteca") {
                NavigationLink { StorageView() } label: { Label("Armazenamento", systemImage: "internaldrive") }
                NavigationLink { TrackCollectionView(title: "Histórico", kind: .history) } label: { Label("Histórico", systemImage: "clock.arrow.circlepath") }
                Button("Ler metadados ausentes", systemImage: "arrow.triangle.2.circlepath") { player.refreshMissingMetadata() }.disabled(player.importing)
                Text("Use esta opção para completar informações de arquivos importados em versões anteriores.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Backup e restauração") {
                Button("Exportar playlists e preferências", systemImage: "square.and.arrow.up") {
                    do { document = BackupDocument(data: try player.backupData()); export = true } catch { player.error = error.localizedDescription }
                }
                Button("Restaurar backup JSON", systemImage: "square.and.arrow.down") { restore = true }
                if FileManager.default.fileExists(atPath: player.root.appendingPathComponent("before-restore.json").path) {
                    Button("Desfazer última restauração") {
                        do { let data = try Data(contentsOf: player.root.appendingPathComponent("before-restore.json")); let missing = try player.restoreBackup(data); restoreMessage = "Restauração anterior recuperada. \(missing) arquivo(s) sem correspondência." } catch { player.error = error.localizedDescription }
                    }
                }
                Text("O backup inclui playlists, favoritos, histórico, posições e preferências. Áudios e imagens de capa ficam separados. Para outro iPhone, importe primeiro os mesmos áudios; a identificação usa o conteúdo dos arquivos.").font(.caption).foregroundStyle(.secondary)
                if let restoreMessage { Text(restoreMessage).font(.footnote) }
            }
            Section("Receber arquivos") {
                Text("No app Arquivos, compartilhe um áudio e escolha START ou Abrir no START nas opções disponíveis. Você também pode copiar arquivos para a pasta START e importá-los pelo seletor.").font(.footnote)
            }
            Section("Widgets e Atalhos") {
                Text("Adicione o widget START pela edição da Tela de Início. Ele abre a biblioteca, retoma a reprodução ou inicia favoritos. No app Atalhos, procure START para usar Reproduzir, Próxima música e Tocar playlist. Os atalhos abrem o app para executar o comando.").font(.footnote)
                Text("Seu instalador precisa preservar e assinar a extensão de widget incluída no IPA para que ela fique disponível.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Text("START 0.4.0 · Sua música, no seu ritmo.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Ajustes")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Concluir") { dismiss() } } }
            .fileExporter(isPresented: $export, document: document, contentType: .json, defaultFilename: "START-backup-\(Date().formatted(.iso8601.year().month().day()))") { result in
                if case .failure(let error) = result { player.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $restore, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let missing = try player.restoreBackup(Data(contentsOf: url))
                    restoreMessage = "Backup restaurado. \(missing) música(s) precisam ser importadas novamente para recuperar as referências."
                } catch { player.error = error.localizedDescription }
            }
            .tint(player.state.settings.color)
    }
}

struct StorageView: View {
    @EnvironmentObject var player: Player
    @State private var removeAll = false
    private var sorted: [Track] { player.tracks.sorted { ($0.byteCount ?? player.fileSize($0)) > ($1.byteCount ?? player.fileSize($1)) } }
    var body: some View {
        List {
            Section {
                LabeledContent("Áudios", value: ByteCountFormatter.string(fromByteCount: player.totalBytes, countStyle: .file))
                Text("\(player.tracks.count) arquivo(s). Deslize uma faixa para apagá-la do START. O arquivo de origem fora do app permanece intacto.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Maiores arquivos primeiro") {
                ForEach(sorted) { track in
                    HStack { Text(track.title).lineLimit(2); Spacer(); Text(ByteCountFormatter.string(fromByteCount: track.byteCount ?? player.fileSize(track), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                }.onDelete { offsets in player.deleteTracks(Set(offsets.map { sorted[$0].id })) }
            }
            Button("Apagar todos os áudios do START", role: .destructive) { removeAll = true }
        }.navigationTitle("Armazenamento")
            .confirmationDialog("Apagar os áudios importados e suas referências nas playlists?", isPresented: $removeAll, titleVisibility: .visible) {
                Button("Apagar do START", role: .destructive) { player.deleteTracks(Set(player.tracks.map(\.id))) }
            }
    }
}
