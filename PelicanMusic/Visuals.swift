import SwiftUI

enum StartStyle {
    static let accent = Color(red: 0.77, green: 1, blue: 0.08)
    static let background = Color(red: 0.045, green: 0.045, blue: 0.055)
    static let surface = Color(red: 0.095, green: 0.095, blue: 0.11)
}

struct LandscapeArt: View {
    var seed: Int = 0
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: seed % 2 == 0 ? [Color(red: 0.28, green: 0.1, blue: 0.24), .orange] : [.indigo, .cyan.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(red: 1, green: 0.57, blue: 0.18))
                    .frame(width: size.width * 0.36, height: size.width * 0.36)
                    .position(x: size.width * 0.76, y: size.height * 0.43)
                MountainShape(rise: 0.12).fill(Color(red: 0.43, green: 0.18, blue: 0.26).opacity(0.85))
                MountainShape(rise: 0.34).fill(Color(red: 0.23, green: 0.12, blue: 0.24))
                MountainShape(rise: 0.52).fill(Color(red: 0.12, green: 0.085, blue: 0.17))
                LinearGradient(colors: [.black.opacity(0.06), .black.opacity(0.22)], startPoint: .top, endPoint: .bottom)
            }
        }.clipped().accessibilityHidden(true)
    }
}

private struct MountainShape: Shape {
    let rise: CGFloat
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * (0.48 + rise)))
            path.addLine(to: CGPoint(x: rect.width * 0.25, y: rect.height * (0.63 + rise * 0.3)))
            path.addLine(to: CGPoint(x: rect.width * 0.58, y: rect.height * (0.38 + rise)))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * (0.22 + rise)))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
    }
}

struct TrackArtwork: View {
    @EnvironmentObject var player: Player
    let title: String
    var active = false
    private var seed: Int { title.utf8.reduce(0) { ($0 + Int($1)) % 256 } }
    var body: some View {
        LandscapeArt(seed: seed)
            .overlay {
                Image(systemName: active ? "waveform" : "music.note").font(.title3.weight(.semibold))
                    .foregroundStyle(active ? player.state.settings.color : .white.opacity(0.8))
            }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MusicRow: View {
    let track: Track
    var active = false
    var body: some View {
        HStack(spacing: 14) {
            TrackArtwork(title: track.title, active: active).frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.subheadline.weight(.semibold)).foregroundStyle(active ? StartStyle.accent : .white).lineLimit(2)
                Label("Arquivo local · Offline", systemImage: "folder").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: active ? "waveform" : "play.fill").font(.caption).foregroundStyle(StartStyle.accent)
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
}
