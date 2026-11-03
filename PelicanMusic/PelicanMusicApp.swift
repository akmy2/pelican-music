import SwiftUI
import AVKit

@main struct PelicanMusicApp: App {
    @StateObject private var player = Player.shared
    @StateObject private var spotify = Spotify()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(player).environmentObject(spotify)
                .preferredColorScheme(.dark).environment(\.locale, Locale(identifier: "pt_BR"))
        }
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
