import SwiftUI
import ZemuCore

/** How My List is split into sections. */
enum MyListGroup: String, CaseIterable {
    case NONE, TYPE, GENRE, DECADE, RATING, ADDED, WATCHED, RUNTIME

    var label: String {
        switch self {
        case .NONE: "Nothing (one grid)"; case .TYPE: "Movies & Series"; case .GENRE: "Genre"; case .DECADE: "Decade"
        case .RATING: "IMDb rating"; case .ADDED: "Date added"; case .WATCHED: "Watched status"; case .RUNTIME: "Length"
        }
    }
}

/** Order within each section. */
enum MyListSort: String, CaseIterable {
    case ADDED_NEWEST, ADDED_OLDEST, RELEASE_NEWEST, RELEASE_OLDEST, RATING, TITLE_AZ, TITLE_ZA, MATCH, RUNTIME_SHORT, RUNTIME_LONG

    var label: String {
        switch self {
        case .ADDED_NEWEST: "Recently added"; case .ADDED_OLDEST: "Oldest added"
        case .RELEASE_NEWEST: "Release date (newest)"; case .RELEASE_OLDEST: "Release date (oldest)"
        case .RATING: "IMDb rating"; case .TITLE_AZ: "Title A–Z"; case .TITLE_ZA: "Title Z–A"
        case .MATCH: "Best match for you"; case .RUNTIME_SHORT: "Shortest first"; case .RUNTIME_LONG: "Longest first"
        }
    }
}

private struct ListSection: Identifiable {
    let id: String
    let title: String
    var items: [Meta]
}

extension Meta {
    /** Minutes from "120 min", "2h 10m", "45m"; nil when unknown. */
    var runtimeMinutes: Int? {
        guard let r = runtime?.lowercased() else { return nil }
        var mins = 0
        if let h = r.firstMatch(of: /(\d+)\s*h/) { mins += Int(h.1)! * 60 }
        if let m = r.firstMatch(of: /(\d+)\s*m/) { mins += Int(m.1)! }
        if mins == 0, let n = r.firstMatch(of: /\d+/) { mins = Int(n.output)! }
        return mins > 0 ? mins : nil
    }

    /** Sortable release key: full date when known, else the year. */
    var releaseKey: String { releasedDate ?? year.map { "\($0)-00-00" } ?? "" }
}

struct MyListView: View {
    var app = AppModel.shared
    @State private var filter = ""
    @AppStorage("myListLayout") private var rows = false
    @FocusState private var filterFocused: Bool

    var body: some View {
        let store = app.session.store
        let settings = app.settings
        let group = MyListGroup(rawValue: settings.myListGroup) ?? .TYPE
        let sort = MyListSort(rawValue: settings.myListSort) ?? .ADDED_NEWEST
        let all = store.myList
        let q = filter.trimmed.lowercased()
        let list = q.isEmpty ? all : all.filter { m in
            m.title.lowercased().contains(q) || m.genres.contains { $0.lowercased().contains(q) } || (m.releaseInfo ?? "").contains(q)
        }
        let sections = Self.sections(list, group: group, sort: sort, store: store, session: app.session)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("My List").font(.system(size: 30, weight: .black))
                Text("\(all.count) title\(all.count == 1 ? "" : "s")").font(.system(size: 14)).foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 48).padding(.top, 40)

            if !all.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        MenuChip(title: "Group: \(group.label)", selected: group != .NONE, heading: "Group by") {
                            choiceItems(MyListGroup.allCases.map { ($0, $0.label) }, current: group) { g in app.session.store.updateSettings { $0.myListGroup = g.rawValue } }
                        }
                        MenuChip(title: "Sort: \(sort.label)", heading: "Sort by") {
                            choiceItems(MyListSort.allCases.map { ($0, $0.label) }, current: sort) { o in app.session.store.updateSettings { $0.myListSort = o.rawValue } }
                        }
                        Chip(title: "Grid", selected: !rows, icon: "square.grid.3x3") { rows = false }
                        Chip(title: "Rows", selected: rows, icon: "rectangle.grid.1x2") { rows = true }
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Palette.textMuted)
                            TextField("Filter by title, genre or year", text: $filter)
                                .textFieldStyle(.plain)
                                .frame(width: 220)
                                .focused($filterFocused)
                                .zFocusText($filter, title: "Filter My List", focus: { filterFocused = true })
                            if !filter.isEmpty {
                                Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textMuted) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .padding(.horizontal, 48).padding(.vertical, 14)
                }
            }

            if all.isEmpty {
                CenteredMessage("Your list is empty", "Use “My List” on any title (or right-click a poster) to save it here.")
            } else if sections.isEmpty {
                CenteredMessage("Nothing matches", "No titles in your list match “\(filter)”.")
            } else if rows {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(sections) { sec in
                            MediaRow(title: sec.title, items: sec.items, trailing: AnyView(count(sec.items.count))) { m in PosterCard(meta: m) }
                        }
                    }
                    .padding(.bottom, 40)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { sec in
                            SwiftUI.Section {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18, alignment: .top)], alignment: .leading, spacing: 22) {
                                    ForEach(sec.items) { m in PosterCard(meta: m) }
                                }
                                .padding(.horizontal, 48)
                                .padding(.bottom, 18)
                            } header: {
                                if group != .NONE {
                                    HStack(spacing: 10) {
                                        SectionTitle(text: sec.title)
                                        count(sec.items.count)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 48).padding(.vertical, 10)
                                    .background(P.background.opacity(0.94))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .background(P.background)
    }

    private func count(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    // MARK: Grouping and sorting

    @MainActor
    private static func sections(_ list: [Meta], group: MyListGroup, sort: MyListSort, store: UserStore, session: Session) -> [ListSection] {
        let profile = sort == .MATCH ? session.tasteProfile() : nil
        let added = Dictionary(list.map { ($0.id, store.myListAddedAt($0.id)) }, uniquingKeysWith: { a, _ in a })
        func sorted(_ items: [Meta]) -> [Meta] {
            switch sort {
            case .ADDED_NEWEST: return items.stableSorted { added[$0.id]! > added[$1.id]! }
            case .ADDED_OLDEST: return items.stableSorted { added[$0.id]! < added[$1.id]! }
            case .RELEASE_NEWEST: return items.stableSorted { $0.releaseKey > $1.releaseKey }
            case .RELEASE_OLDEST: return items.stableSorted { ($0.releaseKey.isEmpty ? "9999" : $0.releaseKey) < ($1.releaseKey.isEmpty ? "9999" : $1.releaseKey) }
            case .RATING: return items.stableSorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            case .TITLE_AZ: return items.stableSorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            case .TITLE_ZA: return items.stableSorted { $0.title.localizedStandardCompare($1.title) == .orderedDescending }
            case .MATCH: return items.stableSorted { Recommender.matchPercent($0, profile!) > Recommender.matchPercent($1, profile!) }
            case .RUNTIME_SHORT: return items.stableSorted { ($0.runtimeMinutes ?? .max) < ($1.runtimeMinutes ?? .max) }
            case .RUNTIME_LONG: return items.stableSorted { ($0.runtimeMinutes ?? -1) > ($1.runtimeMinutes ?? -1) }
            }
        }

        // Each title's section(s), and the order sections appear in.
        let keys: (Meta) -> [(order: Double, title: String)]
        switch group {
        case .NONE:
            keys = { _ in [(0, "All")] }
        case .TYPE:
            keys = { m in m.isAnime ? [(2, m.type == "movie" ? "Anime Movies" : "Anime Series")] : m.type == "series" ? [(1, "Series")] : [(0, "Movies")] }
        case .GENRE:
            // A title shows under each of its genres; most-used genres first.
            var counts: [String: Int] = [:]
            list.forEach { m in m.genres.forEach { counts[$0, default: 0] += 1 } }
            keys = { m in m.genres.isEmpty ? [(1e9, "Other")] : m.genres.map { (-Double(counts[$0] ?? 0), $0) } }
        case .DECADE:
            keys = { m in
                guard let y = m.year else { return [(1e9, "Unknown year")] }
                let d = y / 10 * 10
                return [(-Double(d), "\(d)s")]
            }
        case .RATING:
            keys = { m in
                guard let r = m.rating else { return [(9, "Not rated")] }
                if r >= 8 { return [(0, "★ 8+  Excellent")] }
                if r >= 7 { return [(1, "★ 7–8  Great")] }
                if r >= 6 { return [(2, "★ 6–7  Good")] }
                return [(3, "★ Under 6")]
            }
        case .ADDED:
            let cal = Calendar.current
            let now = Date()
            keys = { m in
                let d = Date(timeIntervalSince1970: Double(added[m.id]!) / 1000)
                let days = cal.dateComponents([.day], from: d, to: now).day ?? 0
                if days < 7 { return [(0, "This week")] }
                if days < 31 { return [(1, "This month")] }
                let y = cal.component(.year, from: d)
                if y == cal.component(.year, from: now) { return [(2, "Earlier this year")] }
                return [(Double(3000 - y), "\(y)")]
            }
        case .WATCHED:
            let watched = store.watched
            let history = Dictionary(store.history.map { ($0.meta.id, $0) }, uniquingKeysWith: { a, _ in a })
            keys = { m in
                if watched.contains(m.id) { return [(2, "Watched")] }
                if let e = history[m.id], e.progress > 0.01 || e.durationMs == 0 { return [(0, "In progress")] }
                return [(1, "Not started")]
            }
        case .RUNTIME:
            keys = { m in
                if m.type == "series" { return [(4, "Series")] }
                guard let r = m.runtimeMinutes else { return [(5, "Unknown length")] }
                if r < 90 { return [(0, "Under 1½ hours")] }
                if r <= 120 { return [(1, "1½ – 2 hours")] }
                if r <= 150 { return [(2, "2 – 2½ hours")] }
                return [(3, "Over 2½ hours")]
            }
        }

        var bucket: [String: (order: Double, items: [Meta])] = [:]
        for m in list {
            for k in keys(m) {
                bucket[k.title, default: (k.order, [])].items.append(m)
            }
        }
        return bucket.sorted { ($0.value.order, $0.key) < ($1.value.order, $1.key) }
            .map { ListSection(id: $0.key, title: $0.key, items: sorted($0.value.items)) }
    }
}
