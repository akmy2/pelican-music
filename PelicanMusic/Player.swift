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

final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var tracks: [Track] = []
    @Published var current: Track?
    @Published var playing = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    private var audio: AVAudioPlayer?
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
            self.elapsed = self.audio?.currentTime ?? 0
        }
    }

    func importFiles(_ urls: [URL]) {
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let id = UUID()
            let filename = id.uuidString + "." + url.pathExtension
            let destination = root.appendingPathComponent(filename)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                do { _ = try AVAudioPlayer(contentsOf: destination) }
                catch { try? FileManager.default.removeItem(at: destination); throw error }
                tracks.append(Track(id: id, title: url.deletingPathExtension().lastPathComponent, file: filename))
                save()
            } catch { self.error = "Não foi possível importar \(url.lastPathComponent): \(error.localizedDescription)" }
        }
    }

    func remove(_ offsets: IndexSet) {
        for index in offsets {
            let track = tracks[index]
            if current?.id == track.id { pause(); audio = nil; current = nil; duration = 0; elapsed = 0; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
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
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: root.appendingPathComponent(track.file))
            next.delegate = self
            guard next.prepareToPlay(), next.play() else { throw NSError(domain: "Player", code: 1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível reproduzir o arquivo."]) }
            audio?.stop()
            audio = next; current = track; duration = next.duration; elapsed = 0; playing = true
            nowPlaying()
        } catch { self.error = error.localizedDescription }
    }

    func resume() {
        guard let audio else { if let first = tracks.first { play(first) }; return }
        do { try AVAudioSession.sharedInstance().setActive(true); playing = audio.play(); nowPlaying() }
        catch { self.error = error.localizedDescription }
    }
    func pause() { audio?.pause(); playing = false; nowPlaying() }
    func releaseAudio() {
        pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func toggle() { playing ? pause() : resume() }
    func seek(_ value: Double) { audio?.currentTime = min(max(value, 0), duration); elapsed = audio?.currentTime ?? 0; nowPlaying() }
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
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag { next() } else { pause(); error = "A reprodução foi interrompida por um erro." }
    }
    private func nowPlaying() {
        guard let current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: "Biblioteca pessoal",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audio?.currentTime ?? 0,
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
