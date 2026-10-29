import SwiftUI
import ZemuCore

/**
 * "Top 10 Today" rows: Cinemeta's popular movies and series, and Kitsu's trending anime. Home gets
 * movies and series.
 */
enum Top10 {
    static func kinds(_ page: String) -> [(String, String)] {
        switch page {
        case "home": return [("movie", "Movies"), ("series", "Series")]
        case "movie": return [("movie", "Movies")]
        case "series": return [("series", "Series")]
        case "anime": return [("anime", "Anime")]
        default: return []
        }
    }

    static func load(_ kind: String) async -> [Meta] {
        let items = kind == "anime"
            ? try? await AddonClient.catalog("https://anime-kitsu.strem.fun", type: "anime", id: "kitsu-anime-trending")
            : try? await AddonClient.catalog("https://v3-cinemeta.strem.io", type: kind, id: "top")
        return Array((items ?? []).prefix(10))
    }
}

/**
 * A poster with its rank, big, above its top-left corner and just overlapping it; in the accent
 * color while the poster is hovered (iPad pointer).
 */
struct Ranked<Content: View>: View {
    let rank: Int
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            content().padding(.top, 46)
            Text("\(rank)")
                .font(.system(size: 60, weight: .black))
                .foregroundStyle(hover ? P.accent : .white)
                .shadow(color: .black.opacity(0.85), radius: 5, y: 3)
                .offset(x: -8, y: -8)
                .allowsHitTesting(false)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .onHover { hover = $0 }
    }
}
