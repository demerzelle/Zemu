import SwiftUI
import ZemuCore

/** A streaming service or studio logo tile; opens what's on it. */
struct LogoCard: View {
    let meta: Meta
    var selected = false
    var onSecondary: (() -> Void)?
    var app = AppModel.shared
    @State private var hover = false

    private func open() {
        let id = meta.id
        if id.hasPrefix("service:") {
            app.push(.discover(type: meta.type, service: String(id.dropFirst(8)), label: meta.name, studio: nil))
        } else if id.hasPrefix("studio:") {
            app.push(.discover(type: meta.type, service: nil, label: nil, studio: String(id.dropFirst(7))))
        }
    }

    var body: some View {
        Button(action: open) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(meta.id.hasPrefix("studio:") ? Color.white.opacity(0.92) : P.surface)
                Text(meta.title).font(.z(size: 15, weight: .bold)).foregroundStyle(meta.id.hasPrefix("studio:") ? .black : P.text)
                    .multilineTextAlignment(.center).padding(10)
                if let logo = meta.poster {
                    RemoteImage(url: logo, maxPixel: 400, contentMode: meta.id.hasPrefix("studio:") ? .fit : .fill)
                        .padding(meta.id.hasPrefix("studio:") ? 18 : 0)
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.z(size: 20)).foregroundStyle(.white, P.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(8)
                }
            }
            .frame(width: 200 * P.zoom, height: 112 * P.zoom)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.ink.opacity(hover ? 0.9 : 0), lineWidth: 2))
            .scaleEffect(hover ? 1.05 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .zFocus(activate: open, secondary: onSecondary, onFocusChange: { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }, ring: false)
        .help(meta.title)
    }
}

private enum DiscoverSort: String, CaseIterable {
    case popular, newest, rated
    var label: String { switch self { case .popular: "Popular"; case .newest: "Newest"; case .rated: "Top Rated" } }
    func params(_ type: String) -> [String: String] {
        switch self {
        case .popular: DiscoverParams.popular()
        case .newest: DiscoverParams.newest(type)
        case .rated: DiscoverParams.topRated(150)
        }
    }
}

/** Everything on a streaming service, or from a studio or network, as a paged poster grid. */
struct DiscoverGridView: View {
    let type: String
    let service: String?
    let label: String?
    let studio: String?
    var app = AppModel.shared
    @State private var kind = "movie"
    @State private var sort = DiscoverSort.popular
    @State private var items: [Meta] = []
    @State private var page = 0
    @State private var loading = false
    @State private var ended = false

    private var title: String {
        if let st = Studio.of(studio) { return st.label }
        return label ?? "Streaming service"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(.z(size: 26, weight: .black)).padding(.trailing, 10)
                // A studio makes one kind of title; a service has both.
                if studio == nil {
                    Chip(title: "Movies", selected: kind == "movie") { kind = "movie" }
                    Chip(title: "Series", selected: kind == "series") { kind = "series" }
                }
                ForEach(DiscoverSort.allCases, id: \.self) { s in Chip(title: s.label, selected: sort == s) { sort = s } }
            }
            .padding(.horizontal, 48).padding(.top, 84).padding(.bottom, 8)
            if !app.session.tmdb.enabled {
                CenteredMessage("Needs a TMDB key", "Add a free TMDB key in Settings → Addons & Accounts.")
            } else if items.isEmpty {
                CenteredMessage(loading ? "Loading…" : "Nothing found")
            } else {
                PosterGrid(items: items, onNearEnd: { loadMore() })
            }
        }
        .task(id: "\(kind)|\(sort)") {
            items = []; page = 0; ended = false
            loadMore()
        }
        .onAppear { kind = Studio.of(studio)?.type ?? type }
    }

    private func loadMore() {
        guard !loading, !ended, page < 15 else { return }
        loading = true
        let t = Studio.of(studio)?.type ?? kind
        var params = sort.params(t)
        if let st = Studio.of(studio) { params[st.param.0] = st.param.1 }
        if let service { params.merge(DiscoverParams.service(service)) { a, _ in a } }
        let next = page + 1
        Task {
            let found = (try? await app.session.tmdb.discover(type: t, params: params, page: next)) ?? []
            let known = Set(items.map(\.id))
            let fresh = found.filter { !known.contains($0.id) }
            items += fresh
            page = next
            ended = fresh.isEmpty
            loading = false
        }
    }
}

/** Every streaming service in your region. Click opens one; the check marks the ones you subscribe to. */
struct ServicesView: View {
    let type: String
    var app = AppModel.shared
    @State private var all: [Provider]?

    var body: some View {
        let mine = app.settings.myServices
        VStack(alignment: .leading, spacing: 6) {
            Text("All Streaming Services").font(.z(size: 26, weight: .black)).padding(.top, 84)
            Text("Click a service to see what's on it. Right-click (or press O) to mark the ones you subscribe to: they come first and get their own rows.")
                .font(.z(size: 13)).foregroundStyle(Palette.textSecondary)
            if let list = all {
                if list.isEmpty {
                    CenteredMessage("Couldn't load streaming services", "Check the TMDB key in Settings → Addons & Accounts.")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 16)], alignment: .leading, spacing: 16) {
                            ForEach(list.stableSorted { mine[$0.ids] != nil && mine[$1.ids] == nil }, id: \.ids) { p in
                                let toggle = {
                                    app.session.store.updateSettings { s in
                                        if s.myServices[p.ids] != nil { s.myServices[p.ids] = nil } else { s.myServices[p.ids] = p.label }
                                    }
                                }
                                LogoCard(meta: Meta(id: "service:\(p.ids)", type: type, name: p.label, poster: p.logo), selected: mine[p.ids] != nil, onSecondary: toggle)
                                    .contextMenu { Button(mine[p.ids] != nil ? "I don't subscribe to \(p.label)" : "I subscribe to \(p.label)", action: toggle) }
                            }
                        }
                        .padding(.vertical, 12).padding(.bottom, 40)
                    }
                }
            } else {
                CenteredMessage("Loading…")
            }
        }
        .padding(.horizontal, 48)
        .task { all = await app.session.tmdb.allProviders(region: DiscoverParams.region) }
    }
}
