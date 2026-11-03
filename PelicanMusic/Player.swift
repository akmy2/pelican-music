import Foundation
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI

struct Track: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var file: String
}

final class Player: NSObject, ObservableObject {
    @Published var tracks: [Track] = []
    @Published var current: Track?
    @Published var playing = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    @Published var importing = false
    @Published var importStatus: String?
    private var audio: AVPlayer?
    private var itemStatus: NSKeyValueObservation?
    private var playbackStatus: NSKeyValueObservation?
    private var finishObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var playTask: Task<Void, Never>?
    private var timer: Timer?
    private var resumeAfterInterruption = false
    private let root: URL
    private var indexURL: URL { root.appendingPathComponent("library.json") }

    override init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        super.init()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                tracks = try JSONDecoder().decode([Track].self, from: Data(contentsOf: indexURL))
            }
        } catch { self.error = error.localizedDescription }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        commands.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(event.positionTime); return .success
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let seconds = self.audio?.currentTime().seconds ?? 0
            self.elapsed = seconds.isFinite ? max(0, seconds) : 0
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !importing else { return }
        guard !urls.isEmpty else { importStatus = "Nenhum arquivo selecionado."; return }
        importing = true
        importStatus = "Preparando \(urls.count) arquivo(s)…"
        let directory = root
        Task.detached(priority: .userInitiated) { [weak self] in
            var added: [Track] = []
            var failures: [String] = []
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let id = UUID()
                let ext = url.pathExtension.lowercased()
                let filename = id.uuidString + (ext.isEmpty ? "" : "." + ext)
                let destination = directory.appendingPathComponent(filename)
                do {
                    var coordinationError: NSError?
                    var copyError: Error?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                        do { try FileManager.default.copyItem(at: readable, to: destination) }
                        catch { copyError = error }
                    }
                    if let coordinationError { throw coordinationError }
                    if let copyError { throw copyError }
                    let probe = AVURLAsset(url: destination)
                    let playable = try await probe.load(.isPlayable)
                    let audioTracks = try await probe.loadTracks(withMediaType: .audio)
                    guard playable, !audioTracks.isEmpty else {
                        throw NSError(domain: "START.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Arquivo vazio ou sem áudio reproduzível."])
                    }
                    added.append(Track(id: id, title: url.deletingPathExtension().lastPathComponent, file: filename))
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    failures.append("\(url.lastPathComponent): \(Self.describeFileError(error))")
                }
            }
            let importedTracks = added
            let importFailures = failures
            DispatchQueue.main.async {
                guard let self else { return }
                self.tracks.append(contentsOf: importedTracks)
                self.save()
                self.importing = false
                self.importStatus = "\(importedTracks.count) música(s) importada(s)" + (importFailures.isEmpty ? "." : "; \(importFailures.count) arquivo(s) recusado(s).")
                if !importFailures.isEmpty {
                    self.error = importFailures.joined(separator: "\n\n") + "\n\nOs demais arquivos foram preservados. Confira se o download terminou e se o arquivo abre em outro player. A extensão .mp3, sozinha, não garante o formato do conteúdo."
                }
            }
        }
    }

    func remove(_ offsets: IndexSet) {
        for index in offsets {
            let track = tracks[index]
            if current?.id == track.id { playTask?.cancel(); pause(); clearItem(); audio = nil; current = nil; duration = 0; elapsed = 0; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
            do { try FileManager.default.removeItem(at: root.appendingPathComponent(track.file)) }
            catch { self.error = error.localizedDescription }
        }
        tracks.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        do { try JSONEncoder().encode(tracks).write(to: indexURL, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }

    func play(_ track: Track) {
        playTask?.cancel()
        let url = root.appendingPathComponent(track.file)
        playTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                let length = try await asset.load(.duration).seconds
                guard !Task.isCancelled else { return }
                guard playable else { throw NSError(domain: "START.Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "O iOS não consegue reproduzir este formato."]) }
                // Playback already supports AirPlay. Explicit allowAirPlay is for playAndRecord.
                do { try self.activateSession() }
                catch { self.error = "Não foi possível ativar a saída de áudio. \(error.localizedDescription)"; return }
                self.audio?.pause()
                self.clearItem()
                let item = AVPlayerItem(asset: asset)
                let next = AVPlayer(playerItem: item)
                self.audio = next
                self.current = track
                self.duration = length.isFinite ? max(0, length) : 0
                self.elapsed = 0
                self.playing = false
                self.itemStatus = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
                    DispatchQueue.main.async {
                        guard let self, let item, self.audio?.currentItem === item else { return }
                        if item.status == .failed { self.pause(); self.error = "\(track.title): \(Self.describeFileError(item.error))" }
                    }
                }
                self.playbackStatus = next.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak next] _, _ in
                    DispatchQueue.main.async {
                        guard let self, let next, self.audio === next else { return }
                        self.playing = next.timeControlStatus == .playing
                        self.nowPlaying()
                    }
                }
                self.finishObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in self?.next() }
                self.failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
                    self?.pause()
                    self?.error = "\(track.title): \(Self.describeFileError(notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error))"
                }
                next.play()
                self.nowPlaying()
            } catch {
                if !Task.isCancelled { self.error = "\(track.title): \(Self.describeFileError(error))" }
            }
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }
    private func clearItem() {
        itemStatus = nil; playbackStatus = nil
        if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        finishObserver = nil; failureObserver = nil
    }
    private static func describeFileError(_ error: Error?) -> String {
        guard let error else { return "A leitura do áudio falhou. Tente baixar o arquivo novamente." }
        let issue = error as NSError
        if issue.domain == NSOSStatusErrorDomain {
            return "Não foi possível decodificar o conteúdo de áudio (código \(issue.code)). O formato pode ser incompatível, o arquivo pode estar incompleto ou sua extensão pode não corresponder ao conteúdo."
        }
        if issue.domain == AVFoundationErrorDomain {
            return "O iOS não conseguiu abrir o áudio (código \(issue.code)). Confirme o download e teste o arquivo em outro player."
        }
        return issue.localizedDescription
    }

    func resume() {
        guard let audio else { if let first = tracks.first { play(first) }; return }
        do { try activateSession(); audio.play(); nowPlaying() }
        catch { self.error = error.localizedDescription }
    }
    func pause() { playTask?.cancel(); audio?.pause(); playing = false; nowPlaying() }
    func releaseAudio() {
        pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func toggle() { playing ? pause() : resume() }
    func seek(_ value: Double) {
        elapsed = min(max(value, 0), duration)
        audio?.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        nowPlaying()
    }
    func next() {
        guard !tracks.isEmpty else { return }
        let index = tracks.firstIndex(where: { $0.id == current?.id }) ?? -1
        play(tracks[(index + 1) % tracks.count])
    }
    func previous() {
        if elapsed > 3 { seek(0); return }
        guard !tracks.isEmpty else { return }
        let index = tracks.firstIndex(where: { $0.id == current?.id }) ?? 0
        play(tracks[(index - 1 + tracks.count) % tracks.count])
    }
    private func nowPlaying() {
        guard let current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: "Biblioteca pessoal",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
    }
    @objc private func routeChanged(_ notification: Notification) {
        if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
           AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { pause() }
    }
    @objc private func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { resumeAfterInterruption = playing; pause() }
        else {
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) { resume() }
            resumeAfterInterruption = false
        }
    }
}
