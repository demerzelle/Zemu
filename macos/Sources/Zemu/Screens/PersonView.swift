import SwiftUI
import ZemuCore

/** Unified person data for the page, from TMDB or the free sources. */
struct PersonPage {
    var name: String
    var photo: String?
    var facts: [String]
    var bio: String?
    var movies: [Meta]
    var series: [Meta]
    /** TMDB credits need resolving to IMDb ids before opening. */
    var tmdbCredits: [String: TmdbCredit] = [:]
}

@MainActor @Observable
final class PersonModel {
    let key: String
    @ObservationIgnored private unowned let s: Session
    private(set) var page: PersonPage?
    private(set) var error: String?

    init(_ s: Session, key: String) {
        self.s = s
        self.key = key
        // Show the name and photo right away; the full filmography (Wikidata) can take a while.
        if !key.hasPrefix("tmdb:") || !s.tmdb.enabled {
            Task {
                if let h = await s.freeCast.personHeader(key), page == nil {
                    page = PersonPage(name: h.name, photo: h.photo, facts: ["Loading filmography…"], bio: nil, movies: [], series: [])
                }
            }
        }
        Task {
            do {
                if let p = try await load() { page = p }
                else if page == nil { error = "No details found for this person" }
                else { page?.facts = ["No filmography found"] }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func load() async throws -> PersonPage? {
        if key.hasPrefix("tmdb:"), let tmdbId = Int64(key.removingPrefix("tmdb:")), s.tmdb.enabled {
            let p = try await s.tmdb.person(tmdbId)
            let credits = p.credits
            let movies = Array(credits.filter { !$0.isSeries }.prefix(40))
            let series = Array(credits.filter(\.isSeries).prefix(40))
            return PersonPage(
                name: p.name, photo: p.photo,
                facts: [p.department, p.birthday.map { b in "Born \(b)" + (p.placeOfBirth.map { " · \($0)" } ?? "") }, p.deathday.map { "Died \($0)" }].compactMap { $0 },
                bio: p.biography,
                movies: movies.map(Self.asMeta), series: series.map(Self.asMeta),
                tmdbCredits: Dictionary((movies + series).map { (Self.asMeta($0).id, $0) }, uniquingKeysWith: { a, _ in a })
            )
        }
        guard let p = await s.freeCast.person(key) else { return nil }
        return PersonPage(
            name: p.name, photo: p.photo,
            facts: [p.description.map { $0.prefix(1).uppercased() + $0.dropFirst() }, p.born.map { "Born \($0)" }].compactMap { $0 },
            bio: nil,
            movies: Array(p.credits.filter { $0.type == "movie" }.prefix(60)),
            series: Array(p.credits.filter { $0.type == "series" }.prefix(60))
        )
    }

    private static func asMeta(_ c: TmdbCredit) -> Meta {
        Meta(id: "tmdb:\(c.mediaType):\(c.id)", type: c.isSeries ? "series" : "movie", name: c.displayTitle, poster: c.poster,
             releaseInfo: c.year, imdbRating: c.voteCount > 20 ? String(format: "%.1f", c.vote) : nil)
    }

    /** IMDb-based metas open directly; TMDB credits are translated first. */
    func resolve(_ meta: Meta) async -> Meta? {
        if meta.isImdb { return meta }
        guard let credit = page?.tmdbCredits[meta.id], let imdb = try? await s.tmdb.imdbIdFor(credit) else { return nil }
        return Meta(id: imdb, type: meta.type, name: meta.name, poster: meta.poster)
    }
}

struct PersonView: View {
    let key: String
    var app = AppModel.shared
    @State private var vm: PersonModel?

    var body: some View {
        Group {
            if let vm, let p = vm.page { content(vm, p) }
            else if let e = vm?.error { CenteredMessage("Couldn't load this person", e) }
            else { CenteredMessage("Loading…") }
        }
        .background(P.background)
        .onAppear { if vm == nil { vm = PersonModel(app.session, key: key) } }
    }

    private func content(_ vm: PersonModel, _ p: PersonPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(P.surfaceHigh)
                        RemoteImage(url: p.photo, maxPixel: 500, alignment: .top)
                    }
                    .frame(width: 170, height: 255)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(p.name).font(.z(size: 34, weight: .black))
                        Text(p.facts.joined(separator: "   ·   ")).font(.z(size: 13.5)).foregroundStyle(Palette.textSecondary)
                        if let bio = p.bio?.nilIfBlank { ScrollingText(text: bio, maxHeight: 170).frame(maxWidth: 760, alignment: .leading) }
                        Text("\(p.movies.count) movies · \(p.series.count) series").font(.z(size: 12.5)).foregroundStyle(Palette.textMuted)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 56)
                if !p.movies.isEmpty {
                    MediaRow(title: "Movies", items: p.movies) { m in creditCard(vm, m) }
                }
                if !p.series.isEmpty {
                    MediaRow(title: "Series", items: p.series) { m in creditCard(vm, m) }
                }
            }
            .padding(.bottom, 48)
        }
    }

    private func creditCard(_ vm: PersonModel, _ m: Meta) -> some View {
        Button {
            Task {
                if let r = await vm.resolve(m) { app.open(r) } else { app.toast("\"\(m.title)\" isn't in the catalog yet") }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(P.surface)
                    Text(m.title).font(.z(size: 12.5, weight: .semibold)).foregroundStyle(Palette.textMuted).multilineTextAlignment(.center).padding(8)
                    RemoteImage(url: m.posterUrl, maxPixel: 420)
                }
                .frame(width: 140, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(m.title).font(.z(size: 12)).lineLimit(1).frame(width: 140, alignment: .leading)
                if let y = m.releaseInfo { Text(y).font(.z(size: 11)).foregroundStyle(Palette.textMuted) }
            }
        }
        .buttonStyle(.plain)
        .zFocus(activate: {
            Task { if let r = await vm.resolve(m) { app.open(r) } else { app.toast("\"\(m.title)\" isn't in the catalog yet") } }
        }, cornerRadius: 8)
    }
}
