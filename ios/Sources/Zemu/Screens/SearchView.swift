import SwiftUI
import ZemuCore

@MainActor @Observable
final class SearchModel {
    @ObservationIgnored private unowned let s: Session
    var query = "" { didSet { if query != oldValue { schedule() } } }
    private(set) var rows: [(title: String, items: [Meta])] = []
    private(set) var loading = false
    @ObservationIgnored private var job: Task<Void, Never>?

    init(_ s: Session) { self.s = s }

    var searched: Bool { query.trimmed.count >= 2 && !loading }
    var history: [SearchHistoryEntry] { s.store.searchHistory }
    var picks: [Meta] { s.store.searchPicks }

    private func schedule() {
        job?.cancel()
        let q = query.trimmed
        job = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            guard q.count >= 2 else { rows = []; return }
            loading = true
            let searchable = s.addons.addons.flatMap { a in a.manifest.catalogs.filter { $0.supportsExtra("search") }.map { (a, $0) } }
            let addons = s.addons
            let results = await concurrentMapUI(searchable) { pair -> (String, [Meta]) in
                let (addon, cat) = pair
                let items = (try? await addons.catalog(addon, type: cat.type, id: cat.id, extra: ["search": q])) ?? []
                let title = cat.type == "movie" ? "Movies" : cat.type == "series" ? "Series" : cat.type.prefix(1).uppercased() + cat.type.dropFirst()
                return (title, items)
            }
            guard !Task.isCancelled else { return }
            var grouped: [(String, [Meta])] = []
            for (title, items) in results {
                if let i = grouped.firstIndex(where: { $0.0 == title }) { grouped[i].1 += items } else { grouped.append((title, items)) }
            }
            rows = grouped.map { ($0.0, $0.1.distinct(by: \.id)) }.filter { !$0.1.isEmpty }.map { (title: $0.0, items: $0.1) }
            loading = false
        }
    }

    /** Return in the field: keep this search in the history. */
    func submit() {
        let all = rows.flatMap(\.items)
        if !all.isEmpty { s.store.recordSearch(query, results: interleaved()) }
    }

    /** A result was opened: remember the search and the pick. */
    func picked(_ m: Meta) {
        s.store.recordSearch(query, results: interleaved())
        s.store.recordSearchPick(m)
    }

    /** Movies and series alternating, so the history row shows a mix. */
    private func interleaved() -> [Meta] {
        var out: [Meta] = []
        let lists = rows.map(\.items)
        for i in 0..<(lists.map(\.count).max() ?? 0) { for l in lists where i < l.count { out.append(l[i]) } }
        return out.distinct(by: \.id)
    }

    /** A poster in a past search was opened: that search moves back to the top. */
    func pickedFromHistory(_ entry: SearchHistoryEntry, _ m: Meta) {
        s.store.recordSearch(entry.query, results: entry.results)
        s.store.recordSearchPick(m)
    }

    func removeHistory(_ q: String) { s.store.removeSearch(q) }
    func clearHistory() { s.store.clearSearchHistory() }
}

struct SearchView: View {
    var app = AppModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var vm = app.session.search
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                TextField("Search movies, series and anime", text: $vm.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium))
                    .focused($focused)
                    .onSubmit { vm.submit() }
                    .zFocusText($vm.query, title: "Search movies, series and anime", focus: { focused = true }, onSubmit: { vm.submit() }, preferred: true)
                if !vm.query.isEmpty {
                    Button { vm.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textMuted) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .zSurface(RoundedRectangle(cornerRadius: 12), fill: P.surface, interactive: false)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? P.accent.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1.5))
            .padding(.horizontal, pagePad).padding(.top, 40).padding(.bottom, 12)

            if vm.loading {
                Text("Searching…").foregroundStyle(Palette.textSecondary).padding(.horizontal, pagePad)
            } else if vm.searched && vm.rows.isEmpty {
                Text("No results.").foregroundStyle(Palette.textSecondary).padding(.horizontal, pagePad)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if vm.query.trimmed.isEmpty {
                        history(vm)
                    } else {
                        ForEach(vm.rows, id: \.title) { row in
                            MediaRow(title: row.title, items: row.items) { m in PosterCard(meta: m, onSelect: vm.picked) }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(PageBackground())
        .onAppear { focused = true }
        .onChange(of: app.focusSearch) { _, _ in focused = true }
    }

    @ViewBuilder
    private func history(_ vm: SearchModel) -> some View {
        if vm.history.isEmpty && vm.picks.isEmpty {
            CenteredMessage("Search your addons", "Titles you open from search, and your recent searches with their posters, show up here.")
                .frame(height: 300)
        } else {
            if !vm.picks.isEmpty {
                MediaRow(title: "Recently Viewed from Search", items: vm.picks) { m in PosterCard(meta: m) }
            }
            if !vm.history.isEmpty {
                HStack {
                    SectionTitle(text: "Recent Searches")
                    Spacer()
                    Chip(title: "Clear History", icon: "trash") { vm.clearHistory() }
                }
                .padding(.horizontal, pagePad)
                .padding(.top, 6)
                ForEach(vm.history, id: \.query) { entry in
                    MediaRow(title: "“\(entry.query)”", items: entry.results, trailing: AnyView(
                        HStack(spacing: 8) {
                            Text(Self.ago(entry.at)).font(.system(size: 12)).foregroundStyle(Palette.textMuted)
                            Chip(title: "Search Again", icon: "magnifyingglass") { vm.query = entry.query }
                            Chip(title: "Remove", icon: "xmark") { vm.removeHistory(entry.query) }
                        }
                        .padding(.leading, 8)
                    )) { m in
                        PosterCard(meta: m, width: 130, onSelect: { vm.pickedFromHistory(entry, $0) })
                    }
                }
            }
        }
    }

    static func ago(_ ms: Int64) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: Date(timeIntervalSince1970: Double(ms) / 1000), relativeTo: Date())
    }
}
