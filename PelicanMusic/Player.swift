import Foundation
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI
import UIKit

struct Track: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var file: String
    var artist: String?
    var album: String?
    var artwork: String?
    var length: Double?
    var addedAt: Date?
    var fingerprint: String?
    var byteCount: Int64?
    var favorite: Bool?
    var artworkSource: String?
    var artworkSearchAttempted: Bool?
}

final class Player: NSObject, ObservableObject {
    @MainActor static let shared = Player()
    @Published var tracks: [Track] = []
    @Published var current: Track?
    @Published var playing = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    @Published var importing = false
    @Published var importStatus: String?
    @Published var importFailures: [ImportFailure] = []
    @Published var importProgress: Double = 0
    var importSessionID: UUID?
    var importTask: Task<Void, Never>?
    var artworkTask: Task<Void, Never>?
    var artworkSessionID: UUID?
    @Published var artworkStatus: String?
    @Published var state = LibraryState() { didSet { saveState() } }
    @Published var sleepDeadline: Date?
    @Published var stopAfterTrack = false
    @Published var loading = false
    private var audio: AVPlayer?
    private var itemStatus: NSKeyValueObservation?
    private var playbackStatus: NSKeyValueObservation?
    private var finishObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var playTask: Task<Void, Never>?
    private var timer: Timer?
    private var resumeAfterInterruption = false
    let root: URL
    private var indexURL: URL { root.appendingPathComponent("library.json") }
    private var stateURL: URL { root.appendingPathComponent("state.json") }
    private var timeObserver: Any?
    private var fadingOut: AVPlayer?
    private var fadeStarted: Date?
    private var fadeLength: Double = 0
    private var crossfadePending = false
    private var lastPositionSave = Date.distantPast

    override convenience init() {
        self.init(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Music", isDirectory: true))
    }
    init(directory: URL) {
        root = directory
        super.init()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                tracks = try JSONDecoder().decode([Track].self, from: Data(contentsOf: indexURL))
            }
            if FileManager.default.fileExists(atPath: stateURL.path) {
                state = try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: stateURL))
                current = tracks.first { $0.id == state.lastTrackID }
                duration = current?.length ?? 0
                elapsed = current.flatMap { state.positions[$0.id.uuidString] } ?? 0
            }
        } catch { self.error = error.localizedDescription }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.pause() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { self?.seek(event.positionTime) }; return .success
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
    }

    func remove(_ offsets: IndexSet) {
        var removed = Set<UUID>()
        for index in offsets {
            let track = tracks[index]
            if current?.id == track.id { playTask?.cancel(); pause(); clearItem(); audio = nil; current = nil; duration = 0; elapsed = 0; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
            do {
                let url = root.appendingPathComponent(track.file)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                if let artwork = track.artwork { try? FileManager.default.removeItem(at: root.appendingPathComponent(artwork)) }
                removed.insert(track.id)
            }
            catch { self.error = error.localizedDescription }
        }
        tracks.removeAll { removed.contains($0.id) }
        state.queueIDs.removeAll { removed.contains($0) }
        for index in state.playlists.indices { state.playlists[index].trackIDs.removeAll { removed.contains($0) } }
        state.history.removeAll { removed.contains($0.trackID) }
        for id in removed { state.positions[id.uuidString] = nil }
        if let id = state.lastTrackID, removed.contains(id) { state.lastTrackID = nil }
        save()
    }

    func save() {
        do { try JSONEncoder().encode(tracks).write(to: indexURL, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }

    private func saveState() {
        do { try JSONEncoder().encode(state).write(to: stateURL, options: .atomic) }
        catch { self.error = "Não foi possível guardar as preferências: \(error.localizedDescription)" }
    }
    func play(_ track: Track, automatic: Bool = false, fade: Double = 0) {
        storePosition()
        if !automatic { state.activeCollection = nil }
        playTask?.cancel()
        loading = true
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
                catch { self.loading = false; self.crossfadePending = false; self.error = "Não foi possível ativar a saída de áudio. \(error.localizedDescription)"; return }
                self.loading = false
                self.crossfadePending = false
                let previous = self.audio
                if fade <= 0 { previous?.pause(); self.finishFade() }
                self.clearItem()
                let item = AVPlayerItem(asset: asset)
                let next = AVPlayer(playerItem: item)
                self.audio = next
                self.current = track
                self.duration = length.isFinite ? max(0, length) : 0
                self.elapsed = 0
                self.playing = false
                self.state.lastTrackID = track.id
                self.state.history.append(ListenEvent(trackID: track.id))
                if self.state.history.count > 500 { self.state.history.removeFirst(self.state.history.count - 500) }
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
                self.finishObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in self?.advanceAutomatically() }
                self.failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
                    self?.pause()
                    self?.error = "\(track.title): \(Self.describeFileError(notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error))"
                }
                if fade > 0, let previous {
                    self.finishFade()
                    self.fadingOut = previous; self.fadeStarted = Date(); self.fadeLength = fade
                    next.volume = 0
                }
                if self.state.settings.resumePositions, !automatic,
                   let saved = self.state.positions[track.id.uuidString], saved > 3, saved < self.duration - 5 {
                    await next.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
                    guard !Task.isCancelled else { return }
                    self.elapsed = saved
                }
                self.timeObserver = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in self?.tick() }
                next.play()
                self.nowPlaying()
            } catch {
                if !Task.isCancelled { self.loading = false; self.crossfadePending = false; self.error = "\(track.title): \(Self.describeFileError(error))" }
            }
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }
    private func clearItem() {
        if let timeObserver { audio?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        itemStatus = nil; playbackStatus = nil
        if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        finishObserver = nil; failureObserver = nil
    }
    static func describeFileError(_ error: Error?) -> String {
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
        guard let audio else { if let first = current ?? tracks.first { play(first) }; return }
        do { try activateSession(); audio.play(); nowPlaying() }
        catch { self.error = error.localizedDescription }
    }
    func pause() { playTask?.cancel(); loading = false; crossfadePending = false; finishFade(); audio?.pause(); playing = false; storePosition(); nowPlaying() }
    func releaseAudio() {
        pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func toggle() { playing ? pause() : resume() }
    func seek(_ value: Double) {
        finishFade()
        elapsed = min(max(value, 0), duration)
        audio?.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        nowPlaying()
    }
    func next() {
        finishFade()
        if let track = takeNext(automatic: false) { play(track, automatic: true) }
    }
    func previous() {
        if elapsed > 3 { seek(0); return }
        guard !tracks.isEmpty else { return }
        let index = tracks.firstIndex(where: { $0.id == current?.id }) ?? 0
        play(tracks[(index - 1 + tracks.count) % tracks.count], automatic: true)
    }
    func nowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist ?? "Biblioteca pessoal",
            MPMediaItemPropertyAlbumTitle: current.album ?? "START",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        if let url = artworkURL(current), let image = UIImage(contentsOfFile: url.path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func storePosition() {
        guard let current, elapsed.isFinite else { return }
        state.positions[current.id.uuidString] = duration > 0 && elapsed > duration - 3 ? 0 : elapsed
    }
    private func tick() {
        if let audio {
            let seconds = audio.currentTime().seconds
            elapsed = seconds.isFinite ? max(0, seconds) : 0
        }
        if let deadline = sleepDeadline, Date() >= deadline {
            sleepDeadline = nil; pause(); return
        }
        if let started = fadeStarted {
            let progress = min(1, Date().timeIntervalSince(started) / max(fadeLength, 0.1))
            audio?.volume = Float(progress); fadingOut?.volume = Float(1 - progress)
            if progress >= 1 { finishFade() }
        }
        if playing && Date().timeIntervalSince(lastPositionSave) > 5 { storePosition(); lastPositionSave = Date() }
        let fade = state.settings.crossfade
        if playing, fade > 0, duration > fade + 2, duration - elapsed <= fade,
           fadeStarted == nil, !crossfadePending, !stopAfterTrack, state.settings.repeatMode != .one {
            crossfadePending = true
            if let track = takeNext(automatic: true) { play(track, automatic: true, fade: min(fade, duration / 2)) }
        }
    }
    private func finishFade() {
        fadingOut?.pause(); fadingOut = nil; fadeStarted = nil; audio?.volume = 1
    }
    func setSleep(minutes: Int?) {
        stopAfterTrack = false
        sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }
    func sleepAtTrackEnd() { sleepDeadline = nil; stopAfterTrack = true }
    private func advanceAutomatically() {
        guard !crossfadePending else { return }
        state.positions[current?.id.uuidString ?? ""] = 0
        if stopAfterTrack { stopAfterTrack = false; pause(); return }
        if let next = takeNext(automatic: true) { play(next, automatic: true) }
        else { pause(); seek(0) }
    }
    private func takeNext(automatic: Bool) -> Track? {
        if automatic && state.settings.repeatMode == .one { return current }
        while !state.queueIDs.isEmpty {
            let id = state.queueIDs.removeFirst()
            if let track = tracks.first(where: { $0.id == id }) { return track }
        }
        let collection = state.activeCollection.map { ids in ids.compactMap { id in tracks.first { $0.id == id } } } ?? tracks
        if state.settings.shuffle { return collection.filter { $0.id != current?.id }.randomElement() ?? collection.first }
        let index = collection.firstIndex(where: { $0.id == current?.id }) ?? -1
        if index + 1 < collection.count { return collection[index + 1] }
        return !automatic || state.settings.repeatMode == .all ? collection.first : nil
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
