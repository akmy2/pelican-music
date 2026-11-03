import WidgetKit
import SwiftUI

struct StartEntry: TimelineEntry { let date: Date }
struct StartProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartEntry { StartEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (StartEntry) -> Void) { completion(StartEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StartEntry>) -> Void) { completion(Timeline(entries: [StartEntry(date: Date())], policy: .never)) }
}

struct StartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StartEntry
    private let lime = Color(red: 0.77, green: 1, blue: 0.08)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("START").font(.system(size: 25, weight: .black, design: .rounded)).italic()
                Spacer()
                Image(systemName: "waveform").foregroundStyle(lime)
            }
            Text("Sua música, no seu ritmo.").font(.caption).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 0)
            if family == .systemMedium {
                HStack(spacing: 12) {
                    shortcut("Retomar", symbol: "play.fill", url: "resume")
                    shortcut("Favoritos", symbol: "heart.fill", url: "favorites")
                    shortcut("Biblioteca", symbol: "music.note.list", url: "library")
                }
            } else {
                Label("Retomar", systemImage: "play.fill").font(.headline).foregroundStyle(.black).padding(.horizontal, 12).padding(.vertical, 8).background(lime, in: Capsule())
            }
        }.foregroundStyle(.white).containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.15, green: 0.1, blue: 0.19), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.widgetURL(URL(string: "pelicanmusic://resume"))
    }
    private func shortcut(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: "pelicanmusic://\(url)")!) {
            VStack(spacing: 5) { Image(systemName: symbol).font(.title3); Text(title).font(.caption2.bold()) }.frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(lime).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

@main struct STARTWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "STARTQuickPlay", provider: StartProvider()) { StartWidgetView(entry: $0) }
            .configurationDisplayName("START — Acesso rápido")
            .description("Abra o START para retomar músicas, ouvir favoritos ou acessar a biblioteca.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
