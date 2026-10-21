import SwiftUI
import UniformTypeIdentifiers
import ZemuCore

struct AddonItem: Identifiable, Hashable {
    let transportUrl: String
    let manifest: AddonManifest
    /** URL of the installed copy (may differ from the catalog's, e.g. a configured install). */
    let installedUrl: String?

    var id: String { manifest.id + transportUrl }
    var installed: Bool { installedUrl != nil }
    var baseUrl: String { Addon.base(of: installedUrl ?? transportUrl) }
    var configureUrl: String { "\(baseUrl)/configure" }
    var canConfigure: Bool { manifest.configurable || manifest.configurationRequired }
    var isCatalogProvider: Bool { manifest.catalogs.contains { ["movie", "series"].contains($0.type) } }
}

enum AddonTypeFilter: String, CaseIterable {
    case ALL, MOVIE, SERIES, CHANNEL, TV, OTHER
    var label: String {
        switch self { case .ALL: "All"; case .MOVIE: "Movies"; case .SERIES: "Series"; case .CHANNEL: "Channels"; case .TV: "TV"; case .OTHER: "Other" }
    }
}

let installedTab = "installed"

@MainActor @Observable
final class AddonsModel {
    @ObservationIgnored private unowned let s: Session
    var tab = installedTab
    var type = AddonTypeFilter.ALL
    var query = ""
    private var catalogs: [String: [Addon]] = [:]
    private(set) var sources: [AddonCatalogSource] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var busy: Set<String> = []
    var message: String?

    init(_ s: Session) {
        self.s = s
        Task {
            await s.addons.waitReady()
            sources = s.addons.addonCatalogSources()
        }
    }

    var tabs: [(String, String)] { [(installedTab, "Installed (\(s.addons.addons.count))")] + sources.map { ($0.key, $0.name) } }

    var items: [AddonItem] {
        let byId = Dictionary(s.addons.addons.map { ($0.manifest.id, $0) }, uniquingKeysWith: { a, _ in a })
        let raw: [AddonItem] = tab == installedTab
            ? s.addons.addons.map { AddonItem(transportUrl: $0.transportUrl, manifest: $0.manifest, installedUrl: $0.transportUrl) }
            : (catalogs[tab] ?? []).map { AddonItem(transportUrl: $0.transportUrl, manifest: $0.manifest, installedUrl: byId[$0.manifest.id]?.transportUrl) }
        let q = query.trimmed
        return raw.filter { item in
            let types = item.manifest.types.map { $0.lowercased() }
            let typeOk: Bool
            switch type {
            case .ALL: typeOk = true
            case .MOVIE: typeOk = types.contains("movie")
            case .SERIES: typeOk = types.contains("series") || types.contains("anime")
            case .CHANNEL: typeOk = types.contains("channel")
            case .TV: typeOk = types.contains("tv")
            case .OTHER: typeOk = !types.contains { ["movie", "series", "channel", "tv"].contains($0) }
            }
            let qOk = q.isEmpty || item.manifest.name.localizedCaseInsensitiveContains(q) || (item.manifest.description ?? "").localizedCaseInsensitiveContains(q)
            return typeOk && qOk
        }
    }

    func selectTab(_ key: String) {
        tab = key
        error = nil
        if key != installedTab && catalogs[key] == nil { loadCatalog(key) }
    }

    private func loadCatalog(_ key: String) {
        guard let source = sources.first(where: { $0.key == key }) else { return }
        loading = true
        Task {
            do { catalogs[key] = try await s.addons.browse(source) }
            catch { self.error = "Couldn't load \(source.name): \(error.localizedDescription)" }
            loading = false
        }
    }

    func retry() { if tab != installedTab { loadCatalog(tab) } }

    func install(_ item: AddonItem) {
        busy.insert(item.manifest.id)
        Task {
            await installNow(item.transportUrl)
            busy.remove(item.manifest.id)
        }
    }

    func installUrl(_ url: String) { Task { await installNow(url) } }

    private func installNow(_ url: String) async {
        do {
            let a = try await s.addons.install(url)
            s.streams.invalidate()
            message = "Installed \(a.manifest.name) \(a.manifest.version)"
        } catch {
            message = "Couldn't install: \(error.localizedDescription)"
        }
    }

    /** Warning to show before uninstalling, or nil if it's safe. */
    func uninstallWarning(_ item: AddonItem) -> String? {
        item.isCatalogProvider && !s.addons.hasOtherCatalogProvider(excluding: item.manifest.id)
            ? "\(item.manifest.name) is your only catalog/metadata provider. Without it, Home, Movies and Series will be empty until you install another one (for example a TMDB or Cinemeta-compatible addon)."
            : nil
    }

    func uninstall(_ item: AddonItem) {
        guard let url = item.installedUrl else { return }
        s.addons.remove(url)
        s.streams.invalidate()
        message = "Uninstalled \(item.manifest.name)"
    }

    func move(_ from: IndexSet, _ to: Int) { s.addons.move(from: from, to: to) }
}

struct AddonsView: View {
    var app = AppModel.shared
    @State private var url = ""
    @FocusState private var field: Int?
    @State private var confirm: (AddonItem, String)?

    var body: some View {
        @Bindable var vm = app.session.addonsBrowser
        let items = vm.items
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Addons").font(.z(size: 30, weight: .black))
                    Text("Install, remove and configure Stremio addons. Configure opens the addon's own setup page; its Install button installs here. Install links (stremio://) on any website open in Zemu too, and you can drop or paste a manifest URL anywhere in this window.")
                        .font(.z(size: 13)).foregroundStyle(Palette.textSecondary).frame(maxWidth: 820, alignment: .leading)
                }
                DebridQuickLink()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(vm.tabs, id: \.0) { k, label in Chip(title: label, selected: vm.tab == k) { vm.selectTab(k) } } }
                }
                HStack(spacing: 8) {
                    ForEach(AddonTypeFilter.allCases, id: \.self) { t in Chip(title: t.label, selected: vm.type == t) { vm.type = t } }
                    TextField("Search addons", text: $vm.query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                        .focused($field, equals: 1)
                        .zFocusText($vm.query, title: "Search addons", focus: { field = 1 })
                }
                HStack(spacing: 10) {
                    TextField("Install from URL (https://…/manifest.json or stremio://…)", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .focused($field, equals: 2)
                        .onSubmit { if !url.trimmed.isEmpty { vm.installUrl(url); url = "" } }
                        .zFocusText($url, title: "Addon manifest URL", focus: { field = 2 }, onSubmit: { if !url.trimmed.isEmpty { vm.installUrl(url); url = "" } })
                    ZButton(title: "Install", primary: true) { if !url.trimmed.isEmpty { vm.installUrl(url); url = "" } }
                    ZButton(title: "Paste", icon: "doc.on.clipboard") {
                        if let s = NSPasteboard.general.string(forType: .string) { vm.installUrl(s) }
                    }
                }
                .frame(maxWidth: 900)
                if let m = vm.message { Text(m).font(.z(size: 13)).foregroundStyle(Palette.cached) }

                if vm.loading {
                    Text("Loading addons…").foregroundStyle(Palette.textSecondary)
                } else if let e = vm.error {
                    CenteredMessage(title: "Couldn't load this catalog", message: e) { ZButton(title: "Retry") { vm.retry() } }
                } else if items.isEmpty {
                    Text("No addons match.").foregroundStyle(Palette.textSecondary)
                } else {
                    if vm.tab == installedTab && vm.type == .ALL && vm.query.isEmpty {
                        Text("Addons higher in the list are asked first. Drag the handle to reorder.").font(.z(size: 12)).foregroundStyle(Palette.textMuted)
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            AddonCard(item: item, busy: vm.busy.contains(item.manifest.id),
                                      reorderable: vm.tab == installedTab && vm.type == .ALL && vm.query.isEmpty,
                                      onInstall: { vm.install(item) },
                                      onUninstall: {
                                          if let w = vm.uninstallWarning(item) { confirm = (item, w) } else { vm.uninstall(item) }
                                      },
                                      onConfigure: { app.openConfigure(item.configureUrl, name: item.manifest.name) },
                                      onMove: { d in
                                          let to = d < 0 ? max(0, i - 1) : min(items.count, i + 2)
                                          vm.move(IndexSet(integer: i), to)
                                      })
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
        }
        .background(P.background)
        .alert("Remove \(confirm?.0.manifest.name ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Remove Anyway", role: .destructive) { if let c = confirm { vm.uninstall(c.0) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(confirm?.1 ?? "") }
    }
}

/** Shortcut to linking a debrid account, the quickest way to get cached streams. */
private struct DebridQuickLink: View {
    var app = AppModel.shared
    var body: some View {
        let account = app.session.store.debrid
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill").foregroundStyle(Palette.cached)
            if let a = account {
                Text("Linked to \(a.service.label). Torrentio is set up with this account.").font(.z(size: 13))
            } else {
                Text("Quickest setup: link your debrid account and Zemu installs Torrentio configured for it.").font(.z(size: 13))
            }
            ZButton(title: account == nil ? "Link Debrid Account" : "Manage", small: true) { app.go(.settings) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(P.surface))
    }
}

private struct AddonCard: View {
    let item: AddonItem
    let busy: Bool
    let reorderable: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onConfigure: () -> Void
    let onMove: (Int) -> Void

    var body: some View {
        let m = item.manifest
        HStack(spacing: 16) {
            if reorderable {
                VStack(spacing: 2) {
                    Button { onMove(-1) } label: { Image(systemName: "chevron.up").frame(width: 22, height: 18) }.buttonStyle(.plain).help("Move up")
                        .zFocus(activate: { onMove(-1) }, cornerRadius: 4)
                    Button { onMove(1) } label: { Image(systemName: "chevron.down").frame(width: 22, height: 18) }.buttonStyle(.plain).help("Move down")
                        .zFocus(activate: { onMove(1) }, cornerRadius: 4)
                }
                .foregroundStyle(Palette.textMuted)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(P.surfaceHigh)
                Text(String(m.name.prefix(1)).uppercased()).font(.z(size: 24, weight: .black)).foregroundStyle(Palette.textMuted)
                RemoteImage(url: m.logo, maxPixel: 160, contentMode: .fit)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(m.name).font(.z(size: 15.5, weight: .bold)).lineLimit(1)
                    Text("v\(m.version)").font(.z(size: 12)).foregroundStyle(Palette.textMuted)
                }
                if let d = m.description?.nilIfBlank { Text(d).font(.z(size: 12.5)).foregroundStyle(Palette.textSecondary).lineLimit(2) }
                HStack(spacing: 6) {
                    if item.installed { Tag(text: "INSTALLED", color: Palette.match, filled: true) }
                    ForEach(m.types.prefix(4), id: \.self) { Tag(text: $0.uppercased()) }
                    ForEach(m.resources.map(\.name).distinct().filter { ["stream", "subtitles"].contains($0) }, id: \.self) { Tag(text: $0.uppercased(), color: Palette.info) }
                    if m.configurationRequired { Tag(text: "SETUP REQUIRED", color: Palette.cached) } else if m.configurable { Tag(text: "CONFIGURABLE", color: Palette.cached) }
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if item.installed || !m.configurationRequired {
                    ZButton(title: busy ? "Working…" : item.installed ? "Uninstall" : "Install", primary: !item.installed) {
                        if !busy { item.installed ? onUninstall() : onInstall() }
                    }
                }
                if item.canConfigure {
                    ZButton(title: m.configurationRequired && !item.installed ? "Configure & Install" : "Configure", icon: "slider.horizontal.3", action: onConfigure)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(P.surface))
        .contextMenu {
            Button("Copy Manifest URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.installedUrl ?? item.transportUrl, forType: .string)
            }
            if item.canConfigure { Button("Configure in Browser") { NSWorkspace.shared.open(URL(string: item.configureUrl)!) } }
        }
    }
}
