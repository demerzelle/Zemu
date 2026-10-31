import SwiftUI
import ZemuCore

struct DetailsView: View {
    let type: String
    let id: String
    let section: String
    let play: Bool
    let seed: Meta?
    var app = AppModel.shared

    @State private var vm: DetailsModel?

    var body: some View {
        Group {
            if let vm { DetailsContent(vm: vm, section: section, leaveAfterAutoPlay: play) } else { P.background }
        }
        .onAppear { if vm == nil { vm = DetailsModel(app.session, type: type, id: id, seed: seed, autoPlay: play) } }
        .id("\(type)/\(id)")
    }
}

private struct DetailsContent: View {
    let vm: DetailsModel
    let section: String
    let leaveAfterAutoPlay: Bool
    var app = AppModel.shared
    @State private var showCast = false
    @State private var hoveredEpisode: Video?

    var body: some View {
        if let m = vm.meta {
            content(m)
        } else if vm.metaLoading {
            CenteredMessage("Loading…").background(P.background)
        } else {
            CenteredMessage(title: "Couldn't load this title", message: "The metadata addon didn't respond.") {
                ZButton(title: "Retry", primary: true) { Task { await vm.loadMeta() } }
            }
            .background(PageBackground())
        }
    }

    @ViewBuilder
    private func content(_ m: Meta) -> some View {
        let streams = vm.streams
        let best = vm.preferred(streams)
        let settings = app.settings
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                P.background
                Backdrop(meta: m, trailerAfter: nil)
                    .frame(height: 600)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(m, best: best, proxy: proxy)
                            .id("top")
                        if showCast {
                            CastRow(people: vm.cast.isEmpty ? m.cast.map { CastPerson(name: $0, role: nil, photo: nil, personKey: "name:\($0)") } : vm.cast)
                                .padding(.top, 20)
                                .id("cast")
                        }
                        if vm.type == "series" && !m.videos.isEmpty {
                            episodes(proxy: proxy).padding(.top, 24).id("episodes")
                        }
                        streamsSection(streams).padding(.top, 24).id("streams")
                        if !vm.similar.isEmpty {
                            MediaRow(title: "More Like This", items: vm.similar.map(\.meta)) { s in
                                PosterCard(meta: s, badge: vm.similar.first { $0.meta.id == s.id }.map { "\($0.matchPercent)%" })
                            }
                            .padding(.top, 28)
                        }
                        if let (genre, items) = vm.genreFavorites {
                            MediaRow(title: "Top \(genre) Picks", items: items.map(\.meta)) { s in
                                PosterCard(meta: s, badge: items.first { $0.meta.id == s.id }.map { "\($0.matchPercent)%" })
                            }
                            .padding(.top, 12)
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
            .onAppear {
                if section == "episodes" {
                    Task { try? await Task.sleep(nanoseconds: 300_000_000); withAnimation { proxy.scrollTo("episodes", anchor: .top) } }
                }
            }
        }
        .onChange(of: vm.autoPlayed) { _, _ in
            // After an instant start from a poster, Back from the player returns to where the title was picked.
            if leaveAfterAutoPlay { app.back() }
        }
        .onChange(of: vm.autoPlayFailed) { _, _ in app.toast("No cached streams to start right away") }
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ m: Meta, best: RankedStream?, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TitleLogo(meta: m, maxHeight: 120)
            MetaLine(meta: m, matchPercent: vm.matchPercent(m))
            CriticScores(meta: m)
            if !m.genres.isEmpty { Text(m.genres.joined(separator: "  •  ")).font(.system(size: 13)).foregroundStyle(Palette.textSecondary) }
            if let label = vm.episodeLabel() { Text(label).font(.system(size: 15, weight: .bold)) }
            ScrollingText(text: m.description ?? "", maxHeight: 96)
                .frame(maxWidth: 640, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(peopleLines(m), id: \.self) { Text($0).font(.system(size: 12.5)).foregroundStyle(Palette.textMuted).lineLimit(1) }
            }
            FlowLayout(spacing: 10) {
                let playLabel = vm.streamsLoading ? "Finding cached streams…" : best != nil ? (vm.type == "series" ? "Play Episode" : "Play") : "No cached streams"
                ZButton(title: playLabel, icon: "play.fill", primary: true, preferred: true) {
                    if let best { vm.play(best) }
                    else if vm.streamResult?.noStreamAddons == true { app.go(.addons) }
                    else if !vm.streamsLoading { app.toast("No cached streams for this title") }
                }
                .keyboardShortcut(.return, modifiers: [])
                ZButton(title: "Choose Stream", icon: "list.bullet") { withAnimation { proxy.scrollTo("streams", anchor: .top) } }
                ZButton(title: vm.inMyList ? "In My List" : "My List", icon: vm.inMyList ? "checkmark" : "plus") { vm.toggleMyList() }
                IconButton(icon: vm.rating > 0 ? "hand.thumbsup.fill" : "hand.thumbsup", help: vm.rating > 0 ? "Liked" : "Like", active: vm.rating > 0) { vm.rate(vm.rating > 0 ? 0 : 1) }
                IconButton(icon: vm.rating < 0 ? "hand.thumbsdown.fill" : "hand.thumbsdown", help: vm.rating < 0 ? "Disliked" : "Dislike", active: vm.rating < 0) { vm.rate(vm.rating < 0 ? 0 : -1) }
                if !vm.cast.isEmpty || !m.cast.isEmpty {
                    ZButton(title: showCast ? "Hide Cast" : "Cast", icon: "person.2") {
                        withAnimation { showCast.toggle() }
                        if showCast { Task { try? await Task.sleep(nanoseconds: 150_000_000); withAnimation { proxy.scrollTo("cast", anchor: .center) } } }
                    }
                }
                if let t = m.offeredTrailerId {
                    let playing = HeroTrailerState.shared.playingId == t
                    ZButton(title: playing ? "Trailer Full Screen" : "Trailer", icon: "film") { app.playTrailer(t, start: playing ? Int(HeroTrailerState.shared.seconds) : 0) }
                }
                ZMenu(title: m.title, items: { cardMenuItems(m) }) { lit in
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(lit ? 0.26 : 0.14)))
                }
            }
            .padding(.top, 8)
            if let b = bestSummary(best) {
                Text("Best for this Mac: \(b)").font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, pagePad)
        .padding(.top, 64)
    }

    private func peopleLines(_ m: Meta) -> [String] {
        let ex = vm.extras
        let directors = ex.map { $0.directors.map(\.name) }.flatMap { $0.isEmpty ? nil : $0 } ?? Array(m.director.prefix(2))
        return [
            directors.isEmpty ? nil : "Director: \(directors.joined(separator: ", "))",
            ex.flatMap { $0.creators.isEmpty ? nil : "Created by: \($0.creators.map(\.name).joined(separator: ", "))" },
            ex.flatMap { $0.studios.isEmpty ? nil : "Studio: \($0.studios.joined(separator: ", "))" },
            m.cast.isEmpty || ex != nil ? nil : "Starring: \(m.cast.prefix(4).joined(separator: ", "))",
        ].compactMap { $0 }
    }

    // MARK: Episodes

    @ViewBuilder
    private func episodes(proxy: ScrollViewProxy) -> some View {
        let season = vm.selectedSeason
        let list = vm.episodes(season)
        let shown = hoveredEpisode ?? vm.selectedVideo.flatMap { s in list.contains { $0.id == s.id } ? s : nil } ?? list.first
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionTitle(text: "Episodes").padding(.trailing, 8)
                Choices(title: "Season", options: vm.seasons.map { ($0, $0 == 0 ? "Specials" : "Season \($0)") }, current: season) { vm.selectedSeason = $0 }
            }
            .padding(.horizontal, pagePad)
            VStack(alignment: .leading, spacing: 4) {
                if let shown {
                    Text([shown.season.map { "S\($0) E\(shown.episodeNumber)" }, shown.displayTitle, shown.released.map { String($0.prefix(10)) }].compactMap { $0 }.joined(separator: "  ·  "))
                        .font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(shown.synopsis ?? "No summary available for this episode.").font(.system(size: 13.5)).foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: 760, minHeight: 74, alignment: .topLeading)
            .padding(.horizontal, pagePad)
            ScrollViewReader { rowProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(list) { v in
                            EpisodeCard(video: v, selected: v.id == vm.selectedVideo?.id, progress: vm.progress(of: v),
                                        onHover: { h in hoveredEpisode = h ? v : (hoveredEpisode == v ? nil : hoveredEpisode) },
                                        secondary: {
                                            app.showMenu(v.label) {
                                                [ActionItem(label: "Play", icon: "play.fill") { vm.selectEpisode(v, autoPlay: true) },
                                                 ActionItem(label: "Choose Stream", icon: "list.bullet") { vm.selectEpisode(v); withAnimation { proxy.scrollTo("streams", anchor: .top) } }]
                                            }
                                        }) {
                                if app.settings.instantPlay { vm.selectEpisode(v, autoPlay: true) }
                                else {
                                    vm.selectEpisode(v)
                                    withAnimation { proxy.scrollTo("streams", anchor: .top) }
                                }
                            }
                            .id(v.id)
                            .contextMenu {
                                Button("Play") { vm.selectEpisode(v, autoPlay: true) }
                                Button("Choose Stream") { vm.selectEpisode(v); withAnimation { proxy.scrollTo("streams", anchor: .top) } }
                            }
                        }
                    }
                    .padding(.horizontal, pagePad).padding(.vertical, 10)
                }
                .onAppear { if let s = vm.selectedVideo { rowProxy.scrollTo(s.id, anchor: .leading) } }
                .onChange(of: vm.selectedSeason) { _, _ in if let f = list.first { rowProxy.scrollTo(f.id, anchor: .leading) } }
            }
        }
    }

    // MARK: Streams

    @ViewBuilder
    private func streamsSection(_ streams: [RankedStream]) -> some View {
        let r = vm.streamResult
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                SectionTitle(text: "Cached Streams")
                Text(summary(r, shown: streams.count)).font(.system(size: 13)).foregroundStyle(Palette.textMuted).lineLimit(1)
                Spacer()
                if !vm.streamsLoading { Chip(title: "Refresh", icon: "arrow.clockwise") { vm.reloadStreams() } }
            }
            .padding(.horizontal, pagePad)
            if let r, !r.cached.isEmpty { filterBar }
            Group {
                if vm.streamsLoading {
                    hint("Asking your addons for debrid-cached streams…")
                } else if let r {
                    if r.noStreamAddons {
                        VStack(alignment: .leading, spacing: 8) {
                            hint("Install a debrid-enabled stream addon (or link your debrid account) to watch. Only cached results are ever shown.")
                            ZButton(title: "Set Up Streaming", primary: true) { app.go(.addons) }
                        }
                    } else if r.cached.isEmpty {
                        hint(r.totalFound > 0 ? "Found \(r.totalFound) streams, but none are cached on your debrid service yet."
                             : "Your addons returned no streams for this \(vm.type == "series" ? "episode" : "title").")
                    } else if streams.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            hint("No cached streams match these filters.")
                            ZButton(title: "Reset Filters") { vm.updateFilter { $0 = FilterState(sort: $0.sort) } }
                        }
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(streams) { rs in StreamRow(r: rs, externalSubLangs: vm.externalSubLangs) { vm.play(rs) } }
                        }
                    }
                }
            }
            .padding(.horizontal, pagePad)
        }
    }

    /** Multi-select menu for a filter; counts update as you pick. */
    private func showFacet(_ kind: FacetKind) {
        app.showMenu(kind.label) {
            let sel = vm.filter.selected[kind] ?? []
            var items = (vm.facets[kind] ?? []).map { o in
                ActionItem(label: "\(o.label)   \(o.count)", checked: sel.contains(o.value), keepOpen: true) { vm.updateFilter { $0 = $0.toggle(kind, o.value) } }
            }
            if !sel.isEmpty { items.insert(ActionItem(label: "Clear", icon: "xmark", keepOpen: true) { vm.updateFilter { $0 = $0.clear(kind) } }, at: 0) }
            items.append(ActionItem(label: "Done", icon: "checkmark.circle") {})
            return items
        }
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(.system(size: 14)).foregroundStyle(Palette.textSecondary).padding(.vertical, 6)
    }

    private func summary(_ r: StreamLoadResult?, shown: Int) -> String {
        if vm.streamsLoading { return "searching your addons…" }
        guard let r else { return "" }
        if r.noStreamAddons { return "no stream addons installed" }
        return "\(shown) shown · \(r.cached.count) cached · \(r.hiddenUncached) uncached hidden" + (r.failedAddons.isEmpty ? "" : " · failed: \(r.failedAddons.joined(separator: ", "))")
    }

    private static let barFacets: [FacetKind] = [.quality, .audioLang, .subLang, .size, .hdr, .codec, .audio, .channels, .source, .service, .addon]

    private var filterBar: some View {
        let f = vm.filter
        let facets = vm.facets
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    MenuChip(title: "Sort: \(f.sort.label)", heading: "Sort streams") {
                        choiceItems(SortOption.allCases.map { ($0, $0.label) }, current: f.sort) { o in vm.updateFilter { $0.sort = o } }
                    }
                    Chip(title: "Plays well on this device", selected: f.deviceFriendlyOnly) { vm.updateFilter { $0.deviceFriendlyOnly.toggle() } }
                    ForEach(Self.barFacets, id: \.self) { kind in
                        let options = facets[kind] ?? []
                        let sel = f.selected[kind] ?? []
                        if options.count > 1 || !sel.isEmpty {
                            let label = sel.isEmpty ? kind.label
                                : sel.count == 1 ? "\(kind.label): \(options.first { sel.contains($0.value) }?.label.before("  (") ?? sel.first!)"
                                : "\(kind.label): \(sel.count)"
                            Chip(title: label + " ▾", selected: !sel.isEmpty) { showFacet(kind) }
                        }
                    }
                    Chip(title: "Hide CAM", selected: f.hideCam) { vm.updateFilter { $0.hideCam.toggle() } }
                    if f.activeCount > 0 { Chip(title: "Reset filters", icon: "xmark") { vm.updateFilter { $0 = FilterState(sort: $0.sort) } } }
                }
                .padding(.horizontal, pagePad).padding(.vertical, 4)
            }
            let ext = vm.externalSubLangs
            if !ext.isEmpty {
                Text("External subtitles available: " + ext.sorted().prefix(8).map(Languages.displayName).joined(separator: ", ") + (ext.count > 8 ? " +\(ext.count - 8) more" : ""))
                    .font(.system(size: 12)).foregroundStyle(Palette.textMuted).padding(.horizontal, pagePad)
            }
        }
    }
}

private struct EpisodeCard: View {
    let video: Video
    let selected: Bool
    let progress: Double?
    let onHover: (Bool) -> Void
    var secondary: (() -> Void)?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(P.surface)
                    RemoteImage(url: video.thumbnail, maxPixel: 520)
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    Text("E\(video.episodeNumber)" + (selected ? "  ▶ selected" : "")).font(.system(size: 12, weight: .bold)).padding(8)
                        .padding(.bottom, progress != nil ? 4 : 0)
                    if let progress, progress > 0.01 {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.25))
                                Rectangle().fill(P.accent).frame(width: g.size.width * min(1, progress))
                            }
                        }
                        .frame(height: 3)
                    }
                    if hover { Image(systemName: "play.circle.fill").font(.system(size: 36)).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(hover ? Color.white : selected ? P.accent : .clear, lineWidth: hover ? 2.5 : 2))
                .scaleEffect(hover ? 1.04 : 1)
                Text(video.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1).frame(width: 240, alignment: .leading)
                if let r = video.released { Text(String(r.prefix(10))).font(.system(size: 11.5)).foregroundStyle(Palette.textMuted) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.zemu)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h }; onHover(h) }
        .zFocus(activate: action, secondary: secondary, onFocusChange: { h in withAnimation(.easeOut(duration: 0.12)) { hover = h }; onHover(h) }, ring: false)
    }
}

// MARK: - Stream rows

private func hdrLabel(_ s: ParsedStream) -> String? {
    if s.hdr.contains(.dolbyVision) { return s.hdr.count > 1 ? "DV · HDR" : "Dolby Vision" }
    if s.hdr.contains(.hdr10Plus) { return "HDR10+" }
    if s.hdr.contains(.hdr10) { return "HDR" }
    if s.hdr.contains(.hlg) { return "HLG" }
    return nil
}

private func langList(_ codes: [String], multi: Bool) -> String? {
    var names = codes.prefix(4).map(Languages.displayName)
    if multi && codes.count <= 1 { names.append("Multi") }
    if names.isEmpty { return nil }
    return names.joined(separator: ", ") + (codes.count > 4 ? " +\(codes.count - 4)" : "")
}

func bestSummary(_ r: RankedStream?) -> String? {
    guard let s = r?.stream else { return nil }
    return [s.resolutionLabel, hdrLabel(s), s.audio.max { $0.rank < $1.rank }?.label, s.sizeLabel, s.debridService.map { "⚡ \($0)" }]
        .compactMap { $0 }.joined(separator: " · ")
}

@MainActor
private func streamItems(_ s: ParsedStream) -> [ActionItem] {
    var items = [
        ActionItem(label: "Open in External Player", icon: "arrow.up.forward.app") {
            if let u = s.raw.url, !ExternalPlayer.open(url: u, title: s.title, preferred: AppModel.shared.settings.externalPlayer) {
                AppModel.shared.toast("Install IINA or VLC to use an external player")
            }
        },
        ActionItem(label: "Copy Stream Link", icon: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s.raw.url ?? "", forType: .string)
        },
    ]
    if let f = s.raw.behaviorHints?.filename {
        items.append(ActionItem(label: "Copy File Name", icon: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(f, forType: .string) })
    }
    return items
}

struct StreamRow: View {
    let r: RankedStream
    let externalSubLangs: Set<String>
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let s = r.stream
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.resolutionLabel).font(.system(size: 20, weight: .black))
                    if let h = hdrLabel(s) { Text(h).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.imdb) }
                }
                .frame(width: 92, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if r.recommended { Tag(text: "★ BEST FOR THIS MAC", color: Palette.match, filled: true) }
                        else if !r.deviceFriendly { Tag(text: "May not play well", color: Palette.cached) }
                        Text(s.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    }
                    let specs = [
                        s.source == .unknown ? nil : s.source.label,
                        s.codec == .unknown ? nil : (s.tenBit ? "\(s.codec.label) 10-bit" : s.codec.label),
                        s.audio.isEmpty ? nil : s.audio.sorted { $0.rank > $1.rank }.map(\.label).joined(separator: " ") + (s.channels.map { " \($0)" } ?? ""),
                        s.releaseGroup,
                    ].compactMap { $0 }.joined(separator: "  ·  ")
                    if !specs.isEmpty { Text(specs).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary).lineLimit(1) }
                    let subs = langList(s.subtitleLanguages, multi: s.multiSubs).map { "💬 \($0)" } ?? (externalSubLangs.isEmpty ? nil : "💬 External only")
                    Text(["🔊 " + (langList(s.audioLanguages, multi: s.multiAudio) ?? "Original audio"), subs].compactMap { $0 }.joined(separator: "     "))
                        .font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(s.sizeLabel ?? "—").font(.system(size: 15, weight: .bold))
                    Text("⚡ \(s.debridService ?? "Direct")").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.cached)
                    Text(s.addonName + (s.seeders.map { "  ·  👤 \($0)" } ?? "")).font(.system(size: 11.5)).foregroundStyle(Palette.textMuted).lineLimit(1)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(hover ? P.surfaceHigh : P.surface.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(hover ? 0.85 : 0), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.zemu)
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
        .zFocus(activate: action, secondary: { AppModel.shared.showMenu(s.title) { streamItems(s) } }, onFocusChange: { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }, ring: false)
        .contextMenu {
            Button("Play") { action() }
            Button("Open in External Player") {
                if let u = s.raw.url, !ExternalPlayer.open(url: u, title: s.title, preferred: AppModel.shared.settings.externalPlayer) {
                    AppModel.shared.toast("Install IINA or VLC to use an external player")
                }
            }
            Button("Copy Stream Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s.raw.url ?? "", forType: .string)
            }
            if let f = s.raw.behaviorHints?.filename { Button("Copy File Name") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(f, forType: .string) } }
        }
        .help(s.title)
    }
}

// MARK: - Cast

struct CastRow: View {
    let people: [CastPerson]
    var app = AppModel.shared
    @State private var expanded = false

    var body: some View {
        let shown = expanded || people.count <= 9 ? people : Array(people.prefix(8))
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: people.count > 1 ? "Cast  ·  \(people.count)" : "Cast").padding(.horizontal, pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(shown, id: \.self) { p in
                        CastTile(person: p) { app.openPerson(p.personKey ?? "name:\(p.name)") }
                    }
                    if shown.count < people.count {
                        Button { expanded = true } label: {
                            VStack(spacing: 8) {
                                Circle().fill(P.surfaceHigh).frame(width: 96, height: 96)
                                    .overlay(Text("+\(people.count - shown.count)").font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.textMuted))
                                Text("View more").font(.system(size: 12.5, weight: .semibold))
                            }
                        }
                        .buttonStyle(.zemu)
                        .zFocus(activate: { expanded = true }, cornerRadius: 48)
                    }
                }
                .padding(.horizontal, pagePad).padding(.vertical, 8)
            }
        }
    }
}

private struct CastTile: View {
    let person: CastPerson
    let action: () -> Void
    var app = AppModel.shared
    @State private var photo: String?
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(P.surfaceHigh)
                    Text(person.name.split(separator: " ").compactMap { $0.first.map(String.init) }.prefix(2).joined())
                        .font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.textMuted)
                    RemoteImage(url: photo ?? person.photo, maxPixel: 300, alignment: .top).clipShape(Circle())
                }
                .frame(width: 96, height: 96)
                .overlay(Circle().strokeBorder(Color.white.opacity(hover ? 0.9 : 0), lineWidth: 2.5))
                .scaleEffect(hover ? 1.06 : 1)
                Text(person.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                if let r = person.role { Text(r).font(.system(size: 11)).foregroundStyle(Palette.textMuted).lineLimit(1) }
            }
            .frame(width: 108)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zemu)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .zFocus(activate: action, onFocusChange: { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }, ring: false)
        .task {
            // Missing photos are looked up lazily.
            if person.photo == nil { photo = await app.session.freeCast.photoFor(person.name) }
        }
    }
}
