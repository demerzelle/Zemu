import SwiftUI
import UniformTypeIdentifiers
import ZemuCore

/**
 * The category rows of a page. Pinned rows come first and keep their saved titles. The other rows
 * follow the order the user dragged them into. Each row has a pin (keeps it on this page) and,
 * when unpinned, a grip to drag it elsewhere.
 */
struct PageRows: View {
    let rows: [HomeRow]
    let page: String
    let store: UserStore
    let onHover: (Meta) -> Void

    var body: some View {
        let pinned = store.pinnedRows(page: page).map { p in
            HomeRow(key: p.key, title: p.title, items: p.items, priority: 0, style: p.landscape ? .landscape : .poster)
        }
        ForEach(pinned) { row in section(row, pinned: true) }
        ForEach(unpinnedRows()) { row in section(row, pinned: false) }
    }

    private func unpinnedRows() -> [HomeRow] {
        let pinnedKeys = Set(store.pinnedRows(page: page).map(\.key)).union(store.hiddenRows(page: page))
        let order = store.rowOrder(page: page)
        func rank(_ key: String) -> Int { order.firstIndex(of: key) ?? Int.max }
        return rows.filter { !pinnedKeys.contains($0.key) }.stableSorted { rank($0.key) < rank($1.key) }
    }

    private func section(_ row: HomeRow, pinned: Bool) -> some View {
        MediaRow(title: row.title, items: row.items, spacing: row.style == .landscape || row.style == .services || row.style == .studios ? 16 : 14,
                 trailing: AnyView(RowControls(row: row, page: page, pinned: pinned, store: store))) { m in
            card(row, m)
        }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard !pinned, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                guard let key = obj as? NSString else { return }
                Task { @MainActor in move(key as String, before: row.key) }
            }
            return true
        }
    }

    @ViewBuilder
    private func card(_ row: HomeRow, _ m: Meta) -> some View {
        switch row.style {
        case .landscape:
            LandscapeCard(meta: m, subtitle: row.subtitles[m.id], progress: row.progress[m.id], onHover: onHover, resume: row.resume[m.id])
        case .poster:
            if row.key.hasPrefix("top10-"), let i = row.items.firstIndex(where: { $0.id == m.id }) {
                Ranked(rank: i + 1) { PosterCard(meta: m, badge: row.badges[m.id] ?? row.match[m.id].map { "\($0)%" }, onHover: onHover) }
            } else {
                PosterCard(meta: m, badge: row.badges[m.id] ?? row.match[m.id].map { "\($0)%" }, onHover: onHover)
            }
        case .services, .studios:
            LogoCard(meta: m)
        }
    }

    /** Puts [key] just before [target] in the saved order of the unpinned rows. */
    private func move(_ key: String, before target: String) {
        guard key != target else { return }
        var keys = unpinnedRows().map(\.key)
        guard let from = keys.firstIndex(of: key) else { return }
        keys.remove(at: from)
        keys.insert(key, at: keys.firstIndex(of: target) ?? keys.count)
        store.setRowOrder(keys, page: page)
    }
}

/** Pin button and drag grip shown beside a row's title. */
private struct RowControls: View {
    let row: HomeRow
    let page: String
    let pinned: Bool
    let store: UserStore

    var body: some View {
        HStack(spacing: 10) {
            if row.style == .services {
                ZButton(title: "All Services", small: true) { AppModel.shared.push(.services(type: page == "series" ? "series" : "movie")) }
            } else if row.service != nil || row.studio != nil {
                ZButton(title: "See All", small: true) {
                    AppModel.shared.push(.discover(type: row.items.first?.type ?? "movie", service: row.service, label: row.serviceLabel, studio: row.studio))
                }
            }
            Button {
                if pinned {
                    store.unpin(key: row.key, page: page)
                } else {
                    store.pin(PinnedRow(page: page, key: row.key, title: row.title, landscape: row.style == .landscape,
                                        items: Array(row.items.prefix(40))))
                }
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.z(size: 13, weight: .semibold))
                    .foregroundStyle(pinned ? P.accentText : Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help(pinned ? "Unpin this list" : "Pin this list to keep it")
            if !pinned {
                Image(systemName: "line.3.horizontal")
                    .font(.z(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                    .help("Drag to move this list")
                    .onDrag { NSItemProvider(object: row.key as NSString) }
                Button { store.hideRow(row.key, page: page) } label: {
                    Image(systemName: "eye.slash").font(.z(size: 12, weight: .semibold)).foregroundStyle(Palette.textMuted)
                }
                .buttonStyle(.plain)
                .help("Remove this row (Settings → Appearance → Rows brings it back)")
            }
        }
    }
}
