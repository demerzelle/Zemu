import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import GameController
import ZemuCore

/** The groups shown in Settings' left-hand list. */
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case ADDONS, PROFILES, PLAYBACK, STREAMS, SUBTITLES, APPEARANCE, CONTROLS, DEVICE, DATA
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ADDONS: "Addons & Accounts"; case .PROFILES: "Profiles"; case .PLAYBACK: "Playback"; case .STREAMS: "Streams & Languages"
        case .SUBTITLES: "Subtitles"; case .APPEARANCE: "Appearance"; case .CONTROLS: "Keyboard & Controller"; case .DEVICE: "This Mac"; case .DATA: "Data & Backup"
        }
    }

    var icon: String {
        switch self {
        case .ADDONS: "puzzlepiece.extension"; case .PROFILES: "person.2"; case .PLAYBACK: "play.rectangle"; case .STREAMS: "line.3.horizontal.decrease.circle"
        case .SUBTITLES: "captions.bubble"; case .APPEARANCE: "paintpalette"; case .CONTROLS: "gamecontroller"; case .DEVICE: "desktopcomputer"; case .DATA: "externaldrive"
        }
    }

    var blurb: String {
        switch self {
        case .ADDONS: "Your debrid service, stream addons, title details and cast info."
        case .PROFILES: "Who's watching, pictures and the profile picker."
        case .PLAYBACK: "Instant play, autoplay, players and decoding."
        case .STREAMS: "Which cached streams are shown and preferred."
        case .SUBTITLES: "How subtitles look and the skip-intro button."
        case .APPEARANCE: "Color themes, animated themes, trailers and notifications."
        case .CONTROLS: "Zemu works entirely with a keyboard or a game controller (Xbox, PlayStation, MFi)."
        case .DEVICE: "What this Mac can play, used for \"Best for this Mac\"."
        case .DATA: "Export or restore this profile, and clear history."
        }
    }
}

struct SettingsView: View {
    var app = AppModel.shared
    @State private var category = SettingsCategory.ADDONS

    var body: some View {
        GeometryReader { geo in
        // Narrow windows: the category list shrinks to icons.
        let narrow = geo.size.width < 820
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(narrow ? "" : "Settings").font(.system(size: 28, weight: .black)).padding(.leading, 12).padding(.bottom, narrow ? 0 : 18)
                ForEach(SettingsCategory.allCases) { c in
                    Button { category = c } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(c == category ? P.accent : .clear).frame(width: 4, height: 18)
                            Image(systemName: c.icon).frame(width: 20)
                            if !narrow {
                                Text(c.label).font(.system(size: 14, weight: c == category ? .bold : .medium))
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 9)
                        .foregroundStyle(c == category ? .white : Palette.textSecondary)
                        .background(RoundedRectangle(cornerRadius: 8).fill(c == category ? P.surfaceHigh : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Moving onto a category shows it, like the TV's settings.
                    .zFocus(activate: { category = c }, onFocusChange: { if $0 { category = c } }, preferred: c == category)
                    .help(c.label)
                }
            }
            .frame(width: narrow ? 52 : 250)
            .padding(.top, 40)
            .padding(.leading, narrow ? 10 : 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.label).font(.system(size: 22, weight: .bold))
                    Text(category.blurb).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).padding(.bottom, 8)
                    switch category {
                    case .ADDONS: AddonsSettings()
                    case .PROFILES: ProfilesSection().padding(.top, 8)
                    case .PLAYBACK: PlaybackSettings()
                    case .STREAMS: StreamsSettings()
                    case .SUBTITLES: SubtitleSettings()
                    case .APPEARANCE: AppearanceSettings()
                    case .CONTROLS: ControlsSettings()
                    case .DEVICE: DeviceSettings()
                    case .DATA: DataSettings()
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, narrow ? 16 : 32)
                .padding(.vertical, 44)
            }
        }
        }
        .background(P.background)
    }
}

// MARK: - Building blocks

/** A labelled group inside a category. */
struct SettingsGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 16, weight: .bold))
            if let note { Text(note).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
            content()
        }
        .padding(.top, 20)
    }
}

struct ToggleRow: View {
    let title: String
    let description: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(description).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: set)).toggleStyle(.switch).labelsHidden().tint(P.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(P.surface))
        .zFocus(activate: { set(!isOn) }, cornerRadius: 10)
    }
}

struct PickerRow<T: Hashable>: View {
    let title: String
    let options: [(T, String)]
    let value: T
    let set: (T) -> Void

    var body: some View {
        ActionRow(title: title, value: options.first { $0.0 == value }?.1 ?? "", icon: "chevron.up.chevron.down") {
            AppModel.shared.showMenu(title) { choiceItems(options, current: value, pick: set) }
        }
    }
}

struct ActionRow: View {
    let title: String
    var value: String = ""
    var icon: String = "chevron.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(value).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 10).fill(P.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zFocus(activate: action, cornerRadius: 10)
    }
}

private extension View {
    func settingsMessage(_ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            self
            if let text { Text(text).font(.system(size: 12.5)).foregroundStyle(Palette.cached) }
        }
    }
}

/** Shorthand for writing settings. */
@MainActor private func update(_ t: (inout AppSettings) -> Void) {
    let before = AppModel.shared.settings
    AppModel.shared.session.store.updateSettings(t)
    if before.trustDirectLinks != AppModel.shared.settings.trustDirectLinks { AppModel.shared.session.streams.invalidate() }
}

// MARK: - Addons & accounts

private struct AddonsSettings: View {
    var app = AppModel.shared
    @State private var tmdbKey = ""
    @State private var message: String?
    @FocusState private var keyFocused: Bool

    var body: some View {
        let s = app.settings
        let addons = app.session.addons.addons
        SettingsGroup(title: "Debrid account") { DebridSection() }
        SettingsGroup(title: "Stream addons", note: "Zemu uses Stremio addons. Install a debrid-enabled one (AIOStreams, Torrentio, Comet, MediaFusion, …). Only cached streams are shown.") {
            ActionRow(title: "Manage addons", value: "\(addons.count) installed · \(addons.filter { $0.manifest.hasResource("stream") }.count) with streams") { app.go(.addons) }
        }
        SettingsGroup(title: "Metadata provider") {
            let providers = addons.filter { a in a.manifest.hasResource("meta") || a.manifest.catalogs.contains { ["movie", "series"].contains($0.type) } }
            Text(providers.isEmpty ? "No metadata provider installed: catalogs and title details won't load. Install Cinemeta or another metadata addon."
                 : "Used first for title details and the Movies and Series pages. Others fill in when it has nothing.")
                .font(.system(size: 12.5)).foregroundStyle(providers.isEmpty ? Palette.cached : Palette.textSecondary)
            FlowChips {
                Chip(title: "Automatic", selected: s.metaProvider.isEmpty || !providers.contains { $0.manifest.id == s.metaProvider }) { update { $0.metaProvider = "" } }
                ForEach(providers) { a in Chip(title: a.manifest.name, selected: s.metaProvider == a.manifest.id) { update { $0.metaProvider = a.manifest.id } } }
            }
        }
        SettingsGroup(title: "Cast & studio info (TMDB)", note: "A free TMDB API key adds cast photos, studios and each actor's other titles: themoviedb.org → Settings → API. Without one, cast comes from TVmaze, Wikidata and IMDb.") {
            HStack(spacing: 10) {
                SecureField(s.tmdbApiKey.isEmpty ? "TMDB API key or read access token" : "Key saved (••••\(s.tmdbApiKey.suffix(4)))", text: $tmdbKey)
                    .textFieldStyle(.roundedBorder)
                    .focused($keyFocused)
                    .onSubmit(saveKey)
                    .zFocusText($tmdbKey, title: "TMDB API key", focus: { keyFocused = true }, onSubmit: saveKey)
                ZButton(title: "Save", primary: true, action: saveKey)
                if !s.tmdbApiKey.isEmpty { ZButton(title: "Remove") { Task { message = await app.session.saveTmdbKey("") } } }
                ZButton(title: "Get a Key", icon: "safari") { NSWorkspace.shared.open(URL(string: "https://www.themoviedb.org/settings/api")!) }
            }
            .settingsMessage(message)
        }
    }

    private func saveKey() {
        let k = tmdbKey
        tmdbKey = ""
        Task { message = await app.session.saveTmdbKey(k) }
    }
}

/** Wrapping row of chips. */
struct FlowChips<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { content() }.padding(.vertical, 4) }
    }
}

/** Link a debrid account by approving a code on the service's site, or by pasting its API key. */
private struct DebridSection: View {
    var app = AppModel.shared
    @State private var linking: DebridService?
    @State private var status: String?

    var body: some View {
        let a = app.session.store.debrid
        VStack(alignment: .leading, spacing: 10) {
            Text(a != nil ? "Linked to \(a!.service.label). Torrentio is set up with this account, so cached streams show up on every title. Pick another service to switch."
                 : "Link your debrid account and Zemu sets up a stream addon with it. Pick your service, then approve with a code or paste your API key.")
                .font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
            FlowChips {
                ForEach(DebridService.allCases, id: \.self) { s in Chip(title: s.label, selected: a?.service == s) { linking = s } }
                if let a { ZButton(title: "Unlink \(a.service.label)", small: true) { app.session.unlinkDebrid(); status = "\(a.service.label) unlinked." } }
            }
            if let status { Text(status).font(.system(size: 12.5)).foregroundStyle(Palette.cached) }
        }
        .sheet(item: $linking) { s in
            LinkDebridSheet(service: s) { msg in status = msg; linking = nil }
        }
    }
}

extension DebridService: Identifiable { public var id: String { rawValue } }

private struct LinkDebridSheet: View {
    let service: DebridService
    let onDone: (String?) -> Void
    var app = AppModel.shared
    @State private var login: DeviceLogin?
    @State private var error: String?
    @State private var key = ""
    @State private var now = Date()
    @State private var working = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Link \(service.label)").font(.system(size: 22, weight: .black))
            HStack(alignment: .top, spacing: 28) {
                if service.codeLogin {
                    VStack(alignment: .leading, spacing: 10) {
                        if let l = login {
                            HStack(spacing: 18) {
                                QRCode(text: l.directUrl).frame(width: 150, height: 150)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Scan with your phone, or").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                    ZButton(title: "Open \(l.url.removingPrefix("https://"))", icon: "safari", small: true) {
                                        NSWorkspace.shared.open(URL(string: l.directUrl)!)
                                    }
                                    Text("and enter").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                    HStack {
                                        Text(l.userCode).font(.system(size: 30, weight: .black, design: .monospaced)).foregroundStyle(P.accent).textSelection(.enabled)
                                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(l.userCode, forType: .string) } label: {
                                            Image(systemName: "doc.on.doc")
                                        }.buttonStyle(.plain).help("Copy code")
                                    }
                                }
                            }
                            let left = max(0, Int(l.expiresAt.timeIntervalSince(now)))
                            Text("Waiting for approval… code refreshes in \(left / 60):\(String(format: "%02d", left % 60))")
                                .font(.system(size: 12)).foregroundStyle(Palette.textMuted)
                        } else if error == nil {
                            Text("Getting a code from \(service.label)…").foregroundStyle(Palette.textSecondary)
                        }
                        if let error { Text(error).font(.system(size: 12.5)).foregroundStyle(Palette.cached) }
                    }
                    .frame(width: 380, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.codeLogin ? "Or use your API key" : "Paste your API key").font(.system(size: 15, weight: .bold))
                    HStack(spacing: 4) {
                        Text("Copy it from").foregroundStyle(Palette.textSecondary)
                        Button(service.keyPage) { NSWorkspace.shared.open(URL(string: "https://\(service.keyPage)")!) }.buttonStyle(.link)
                            .zFocus(activate: { NSWorkspace.shared.open(URL(string: "https://\(service.keyPage)")!) }, cornerRadius: 4)
                    }
                    .font(.system(size: 13))
                    HStack {
                        SecureField("\(service.label) API key", text: $key).textFieldStyle(.roundedBorder).onSubmit(saveKey)
                            .focused($keyFocused)
                            .zFocusText($key, title: "\(service.label) API key", focus: { keyFocused = true }, onSubmit: saveKey)
                        ZButton(title: working ? "Checking…" : "Save", primary: true, action: saveKey)
                    }
                    if !service.codeLogin, let error { Text(error).font(.system(size: 12.5)).foregroundStyle(Palette.cached) }
                }
                .frame(minWidth: 320)
            }
            HStack {
                Spacer()
                ZButton(title: "Cancel", preferred: true) { onDone(nil) }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: service.codeLogin ? 820 : 520)
        .background(P.surface)
        .task(id: service) { await codeLoop() }
        .task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000); now = Date() } }
    }

    private func codeLoop() async {
        guard service.codeLogin else { return }
        while !Task.isCancelled {
            do {
                let l = try await DebridAuth.start(service)
                login = l
                error = nil
                while Date() < l.expiresAt && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(l.interval * 1e9))
                    do {
                        if let account = try await l.check() {
                            onDone(await app.session.linkDebrid(account))
                            return
                        }
                    } catch { self.error = error.localizedDescription }
                }
                // Code expired: get a fresh one.
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
    }

    private func saveKey() {
        let k = key.trimmed
        guard !k.isEmpty, !working else { return }
        working = true
        Task {
            if await DebridAuth.verify(service, key: k) {
                onDone(await app.session.linkDebrid(DebridAccount(service: service, token: k)))
            } else {
                error = "\(service.label) didn't accept that key. Copy it from \(service.keyPage)."
            }
            working = false
        }
    }
}

struct QRCode: View {
    let text: String
    var body: some View {
        if let img = Self.make(text) {
            Image(nsImage: img).interpolation(.none).resizable().padding(8).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    static func make(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

// MARK: - Playback

private struct PlaybackSettings: View {
    var app = AppModel.shared
    var body: some View {
        let s = app.settings
        SettingsGroup(title: "Starting playback") {
            ToggleRow(title: "Instant play", description: "Selecting a movie, a show or an episode starts it right away with the best cached stream (the one you used last time when it's still cached). Shows resume where you left off.", isOn: s.instantPlay) { v in update { $0.instantPlay = v } }
            ToggleRow(title: "Full screen when playing", description: "Enter full screen automatically when a video starts.", isOn: s.playerFullScreen) { v in update { $0.playerFullScreen = v } }
            ToggleRow(title: "Picture in Picture when switching apps", description: "Leaving Zemu while a video plays moves it into a small floating window above your other apps; coming back restores it. You can also press T or the PiP button in the player.", isOn: s.autoPip) { v in update { $0.autoPip = v } }
            ToggleRow(title: "Pause when Zemu isn't focused", description: "Clicking another app or window pauses the video, and coming back resumes it. Replaces Picture in Picture when switching apps; a Picture in Picture window you open yourself keeps playing.", isOn: s.pauseWhenUnfocused) { v in update { $0.pauseWhenUnfocused = v } }
        }
        SettingsGroup(title: "When something ends") {
            ToggleRow(title: "Autoplay next episode", description: "Near the end of an episode, count down and start the next one.", isOn: s.autoplayNext) { v in update { $0.autoplayNext = v } }
            ToggleRow(title: "Play something similar", description: "After a movie or a series finale, count down to a recommended title you haven't seen.", isOn: s.autoplaySimilar) { v in update { $0.autoplaySimilar = v } }
            if s.autoplayNext || s.autoplaySimilar {
                PickerRow(title: "Countdown", options: [5, 10, 15, 20, 30].map { ($0, "\($0) seconds") }, value: s.autoplayCountdownSec) { v in update { $0.autoplayCountdownSec = v } }
            }
            if s.autoplayNext {
                ToggleRow(title: "Ask \"Are you still watching?\"", description: "Pause and check in after several episodes play without touching the keyboard or mouse.", isOn: s.stillWatchingPrompt) { v in update { $0.stillWatchingPrompt = v } }
                if s.stillWatchingPrompt {
                    PickerRow(title: "Ask after", options: [2, 3, 4, 5, 6, 8].map { ($0, "\($0) episodes in a row") }, value: s.stillWatchingEpisodes) { v in update { $0.stillWatchingEpisodes = v } }
                }
            }
        }
        SettingsGroup(title: "Player", note: MPV.available ? "Built-in player: mpv (\(MPV.libraryPath ?? "")). It plays MKV, HEVC, AV1, DTS, TrueHD and styled subtitles." : "mpv isn't available, so the built-in player uses AVPlayer (MP4/HLS only). Install mpv (brew install mpv) or use an external player for MKV streams.") {
            ToggleRow(title: "Use external player", description: "Open streams in IINA, VLC or Infuse instead of the built-in player.", isOn: s.useExternalPlayer) { v in update { $0.useExternalPlayer = v } }
            PickerRow(title: "External player", options: ExternalPlayer.choices.map { ($0, ExternalPlayer.isInstalled($0) ? $0 : "\($0) (not installed)") }, value: s.externalPlayer) { v in update { $0.externalPlayer = v } }
            ToggleRow(title: "Prefer software decoding", description: "Slower, but can play files VideoToolbox rejects. Turned on automatically if needed.", isOn: s.preferSoftwareDecoders) { v in update { $0.preferSoftwareDecoders = v } }
            ToggleRow(title: "Avoid Dolby Vision-only releases", description: "Rank DV-only files lower. mpv shows Dolby Vision profile 5 with off colors on most Macs.", isOn: s.avoidDolbyVision) { v in update { $0.avoidDolbyVision = v } }
        }
    }
}

// MARK: - Streams

private struct StreamsSettings: View {
    var app = AppModel.shared
    var body: some View {
        let s = app.settings
        SettingsGroup(title: "Cached streams", note: "Catalogs show every title. When you open one, only streams cached on your debrid service are listed.") {
            ToggleRow(title: "Treat direct links as cached", description: "Count plain HTTP streams without debrid markers as instantly playable. Leave off for strict debrid-cached only.", isOn: s.trustDirectLinks) { v in update { $0.trustDirectLinks = v } }
            PickerRow(title: "Maximum file size", options: [0, 5, 10, 20, 40, 80].map { ($0, $0 == 0 ? "No limit" : "\($0) GB") }, value: s.maxSizeGb) { v in update { $0.maxSizeGb = v } }
        }
        SettingsGroup(title: "Languages", note: "Order matters: the first language is preferred. Used to rank streams and pick audio and subtitle tracks.") {
            LanguagePicker(title: "Preferred audio", selected: s.audioLanguages) { l in update { $0.audioLanguages = l } }
            LanguagePicker(title: "Preferred subtitles", selected: s.subtitleLanguages) { l in update { $0.subtitleLanguages = l } }
            ToggleRow(title: "Turn on subtitles automatically", description: "Select a subtitle track in your preferred language when playback starts.", isOn: s.autoSubtitles) { v in update { $0.autoSubtitles = v } }
        }
    }
}

private struct LanguagePicker: View {
    let title: String
    let selected: [String]
    let set: ([String]) -> Void

    var body: some View {
        ActionRow(title: title, value: selected.map(Languages.displayName).joined(separator: ", ").nilIfBlank ?? "Any") {
            // Re-read the saved list on every render so the order numbers stay right.
            let isAudio = title.contains("audio")
            AppModel.shared.showMenu(title) {
                let current = isAudio ? AppModel.shared.settings.audioLanguages : AppModel.shared.settings.subtitleLanguages
                return (current + Languages.common).distinct().map { code in
                    let i = current.firstIndex(of: code)
                    return ActionItem(label: Languages.displayName(code) + (i.map { "   #\($0 + 1)" } ?? ""), checked: i != nil, keepOpen: true) {
                        set(i != nil ? current.filter { $0 != code } : current + [code])
                    }
                }
            }
        }
    }
}

// MARK: - Subtitles

enum SubtitleStyleOptions {
    static let sizes: [(Double, String)] = [(0.75, "Small"), (1, "Normal"), (1.3, "Large"), (1.6, "Extra large"), (2, "Huge")]
    static let colors: [(UInt32, String)] = [(0xFFFFFFFF, "White"), (0xFFFFEB3B, "Yellow"), (0xFF80DEEA, "Cyan"), (0xFFA5D6A7, "Green"), (0xFFF48FB1, "Pink"), (0xFFBDBDBD, "Grey")]
    static let backgrounds: [(Int, String)] = [(0, "None"), (1, "Translucent box"), (2, "Solid box")]
    static let edges: [(Int, String)] = [(0, "None"), (1, "Outline"), (2, "Drop shadow")]
    static let positions: [(Double, String)] = [(0.03, "Bottom"), (0.08, "Normal"), (0.15, "Raised"), (0.25, "High")]
}

/** Rows of choices for subtitle size, color, background, edge and position. Changes apply live. */
struct SubtitleStyleEditor: View {
    var app = AppModel.shared
    var onChange: () -> Void = {}

    var body: some View {
        let s = app.settings
        VStack(alignment: .leading, spacing: 6) {
            row("Size", SubtitleStyleOptions.sizes, s.subtitleScale) { v in update { $0.subtitleScale = v } }
            row("Color", SubtitleStyleOptions.colors, s.subtitleColor) { v in update { $0.subtitleColor = v } }
            row("Background", SubtitleStyleOptions.backgrounds, s.subtitleBackground) { v in update { $0.subtitleBackground = v } }
            row("Edge", SubtitleStyleOptions.edges, s.subtitleEdge) { v in update { $0.subtitleEdge = v } }
            row("Position", SubtitleStyleOptions.positions, s.subtitleBottom) { v in update { $0.subtitleBottom = v } }
        }
    }

    private func row<T: Equatable>(_ label: String, _ options: [(T, String)], _ current: T, _ pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).frame(width: 90, alignment: .leading)
            ForEach(options.indices, id: \.self) { i in
                Chip(title: options[i].1, selected: options[i].0 == current) { pick(options[i].0); onChange() }
            }
        }
    }
}

private struct SubtitleSettings: View {
    var app = AppModel.shared
    var body: some View {
        let s = app.settings
        SettingsGroup(title: "Subtitle appearance", note: "Also available in the player (press C).") {
            SubtitlePreview(settings: s)
            SubtitleStyleEditor()
            ToggleRow(title: "Keep styled subtitles as authored", description: "ASS/SSA subtitles (common for anime) keep their own fonts, colors and signs; only the size follows your setting. Off applies your style to them too.", isOn: s.keepStyledSubtitles) { v in update { $0.keepStyledSubtitles = v } }
        }
        SettingsGroup(title: "Skipping") {
            ToggleRow(title: "Skip intro button", description: "Show \"Skip intro\" / \"Skip recap\" while they play (community timestamps from TheIntroDB and AniSkip). The next-episode card starts at the credits.", isOn: s.skipIntroButton) { v in update { $0.skipIntroButton = v } }
        }
    }
}

/** A sample line drawn with the chosen subtitle style. */
private struct SubtitlePreview: View {
    let settings: AppSettings
    var body: some View {
        let color = Color(argb: settings.subtitleColor)
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(argb: 0xFF3A4A5A), Color(argb: 0xFF6A5A3A)], startPoint: .leading, endPoint: .trailing)
            Text("This is how subtitles will look.")
                .font(.system(size: 20 * settings.subtitleScale, weight: .semibold))
                .foregroundStyle(color)
                .shadow(color: .black, radius: settings.subtitleEdge == 1 ? 1.5 : 0)
                .shadow(color: .black.opacity(settings.subtitleEdge == 2 ? 0.9 : 0), radius: 2, x: 2, y: 2)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(settings.subtitleBackground == 0 ? .clear : .black.opacity(settings.subtitleBackground == 1 ? 0.6 : 1)))
                .padding(.bottom, 8 + settings.subtitleBottom * 120)
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    var app = AppModel.shared
    var body: some View {
        let s = app.settings
        SettingsGroup(title: "Color theme") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ThemePreset.allCases, id: \.self) { p in
                        ThemeSwatch(label: p.label, colors: p.colors, selected: s.theme == p.rawValue) { update { $0.theme = p.rawValue } }
                    }
                    ThemeSwatch(label: "Custom", colors: ThemeColors(accent: Color(argb: s.customAccent), background: Color(argb: s.customBackground)), selected: s.theme == ThemePreset.custom) {
                        // Start the custom theme from whatever is showing now.
                        let cur = s.themeColors
                        update {
                            if $0.theme != ThemePreset.custom { $0.customAccent = cur.accent.argb; $0.customBackground = cur.background.argb }
                            $0.theme = ThemePreset.custom
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            if s.theme == ThemePreset.custom {
                HStack(spacing: 28) {
                    ColorPicker("Accent", selection: Binding(get: { Color(argb: s.customAccent) }, set: { c in update { $0.customAccent = c.argb | 0xFF000000 } }), supportsOpacity: false)
                    ColorPicker("Background", selection: Binding(get: { Color(argb: s.customBackground) }, set: { c in
                        // Backgrounds stay dark so white text is always readable.
                        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
                        let darkened = Color(hue: ns.hueComponent, saturation: ns.saturationComponent, brightness: min(ns.brightnessComponent, 0.22))
                        update { $0.customBackground = darkened.argb | 0xFF000000 }
                    }), supportsOpacity: false)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(P.surface))
            }
        }
        SettingsGroup(title: "Animated themes", note: "Halloween, Christmas, Cyberpunk and the other effect themes bring their own colors. RGB, Snowfall and Rain keep your color theme.") {
            FlowChips {
                ForEach(DynamicTheme.allCases, id: \.self) { d in Chip(title: d.label, selected: s.dynamicTheme == d.rawValue) { update { $0.dynamicTheme = d.rawValue } } }
            }
        }
        SettingsGroup(title: "Trailers") {
            ToggleRow(title: "Autoplay trailers", description: "Play the trailer behind the title after you rest the pointer on it for a few seconds.", isOn: s.heroTrailers) { v in update { $0.heroTrailers = v } }
            ToggleRow(title: "Trailer sound", description: "Play autoplaying trailers with sound. Full-window trailers always have sound.", isOn: s.heroTrailerSound) { v in update { $0.heroTrailerSound = v } }
        }
        SettingsGroup(title: "Notifications") {
            ToggleRow(title: "New episode notifications", description: "Get a notification when a show you watch has a new episode out.", isOn: s.notifyNewEpisodes) { v in
                update { $0.notifyNewEpisodes = v }
                if v { Integrations.shared.requestNotificationPermission() }
            }
        }
    }
}

private struct ThemeSwatch: View {
    let label: String
    let colors: ThemeColors
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(colors.accent).frame(width: 20, height: 20)
                    Circle().fill(colors.surfaceHigh).frame(width: 20, height: 20)
                    Circle().fill(colors.surface).frame(width: 20, height: 20)
                }
                RoundedRectangle(cornerRadius: 3).fill(colors.accent).frame(height: 6)
                Text((selected ? "✓ " : "") + label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .padding(12)
            .frame(width: 128)
            .background(RoundedRectangle(cornerRadius: 12).fill(hover ? colors.surfaceHigh : colors.background))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? colors.accent : Color.white.opacity(hover ? 0.6 : 0.12), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .zFocus(activate: action, onFocusChange: { hover = $0 }, cornerRadius: 12)
    }
}

// MARK: - Keyboard & controller

private struct ControlsSettings: View {
    @State private var controllers: [String] = []

    private let browse: [(String, String, String)] = [
        ("Move", "Arrow keys", "D-pad / left stick"),
        ("Select", "Return / Space", "Ⓐ / ✕"),
        ("Back", "Esc / Delete", "Ⓑ / ○"),
        ("Options for a title", "O / right-click", "Ⓧ / □"),
        ("Search", "⌘F", "Ⓨ / △"),
        ("Previous / next page", "⌘1 … ⌘8", "LB / RB"),
        ("Settings", "⌘,", "View / Share"),
        ("Type text", "Keyboard", "Ⓐ on a text field opens the on-screen keyboard"),
    ]
    private let player: [(String, String, String)] = [
        ("Play / pause", "Space / K", "Ⓐ (also opens the controls) / ☰"),
        ("Seek", "← → (hold to speed up), J / L", "D-pad ← →, LT / RT; LB / RB ±10 s"),
        ("Controls", "Return opens, ↓ / Esc hides", "D-pad ↑ / Ⓐ opens, Ⓑ hides"),
        ("Volume", "↑ ↓, M mute", ""),
        ("Subtitles / audio", "S / A, C style, Z X delay", "Ⓧ / Ⓨ"),
        ("Picture in Picture", "T", "View / Share"),
        ("Full screen", "F, double-click", ""),
        ("Skip intro / next episode", "Return", "Ⓐ"),
        ("Leave player", "Esc", "Ⓑ"),
    ]

    var body: some View {
        SettingsGroup(title: "Controllers", note: "Xbox, PlayStation, Switch Pro and MFi controllers work over Bluetooth or USB. Pair them in System Settings → Bluetooth.") {
            if controllers.isEmpty {
                Text("No controller connected.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(controllers, id: \.self) { c in
                    HStack { Image(systemName: "gamecontroller.fill").foregroundStyle(P.accent); Text(c).font(.system(size: 14, weight: .semibold)) }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(P.surface))
                }
            }
        }
        .task {
            while !Task.isCancelled {
                controllers = GCController.controllers().map { $0.vendorName ?? "Controller" }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        SettingsGroup(title: "Browsing") { table(browse) }
        SettingsGroup(title: "Player") { table(player) }
    }

    private func table(_ rows: [(String, String, String)]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("").frame(width: 190, alignment: .leading)
                Text("Keyboard").frame(maxWidth: .infinity, alignment: .leading)
                Text("Controller").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textMuted).padding(.horizontal, 16).padding(.vertical, 6)
            ForEach(rows, id: \.0) { r in
                HStack(alignment: .top) {
                    Text(r.0).font(.system(size: 13.5, weight: .semibold)).frame(width: 190, alignment: .leading)
                    Text(r.1).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.2).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider().opacity(0.3)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(P.surface))
        .zFocus(activate: nil, cornerRadius: 10)
    }
}

// MARK: - This Mac

private struct DeviceSettings: View {
    var app = AppModel.shared
    var body: some View {
        let caps = app.session.capabilities
        SettingsGroup(title: "Video output") {
            infoRow("Best resolution for your displays", caps.maxResolution >= 2160 ? "4K" : "\(caps.maxResolution)p", true)
        }
        SettingsGroup(title: "Formats and engines") {
            ForEach(DeviceCaps.summary(caps), id: \.0) { label, ok in infoRow(label, ok ? "✓ Supported" : "✗ Not supported", ok) }
            if let v = MPV.version { infoRow("mpv version", v, true) }
        }
    }

    private func infoRow(_ title: String, _ value: String, _ ok: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(ok ? Palette.match : Palette.textMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(P.surface))
    }
}

// MARK: - Data

private struct DataSettings: View {
    var app = AppModel.shared
    @State private var message: String?
    @State private var confirmClear = false

    var body: some View {
        SettingsGroup(title: "Backup", note: "Everything in this profile (addons, debrid link, history, My List, likes and settings) as one JSON file. Keep it private: it contains your debrid token and API keys.") {
            HStack(spacing: 10) {
                ZButton(title: "Export Profile…", icon: "square.and.arrow.up", action: export)
                ZButton(title: "Import Profile…", icon: "square.and.arrow.down", action: importData)
                ZButton(title: "Show Data Folder", icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.support]) }
            }
            .settingsMessage(message)
        }
        SettingsGroup(title: "History") {
            ActionRow(title: "Clear watch history", value: "Resets Continue Watching and recommendations", icon: "trash") { confirmClear = true }
        }
        .alert("Clear watch history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { app.session.store.clearHistory(); message = "Watch history cleared" }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Zemu \(app.profiles.profile(app.session.profileId)?.name ?? "Profile").json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try app.session.store.exportData().write(to: url)
            message = "Exported to \(url.lastPathComponent)"
        } catch { message = "Couldn't export: \(error.localizedDescription)" }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try app.session.store.importData(try Data(contentsOf: url))
            app.session.store.saveNow()
            // Rebuild the session so addons and everything else reload from the imported data.
            app.reloadSession()
            app.toast("Profile imported")
        } catch { message = "Couldn't import: \(error.localizedDescription)" }
    }
}
