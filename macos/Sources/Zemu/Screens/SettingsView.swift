import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import GameController
import ZemuCore

/** The groups shown in Settings' left-hand list. */
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case ADDONS, PROFILES, PLAYBACK, SUBTITLES, APPEARANCE, BROWSING, SOUNDS, SCREENSAVER, CONTROLS, DEVICE, DATA
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ADDONS: "Accounts & Addons"; case .PROFILES: "Profiles & Kids"; case .PLAYBACK: "Playback"; case .SUBTITLES: "Subtitles"
        case .APPEARANCE: "Appearance"; case .BROWSING: "Browsing"; case .SOUNDS: "Sounds & Notifications"; case .SCREENSAVER: "Screensaver"
        case .CONTROLS: "Keyboard & Controller"; case .DEVICE: "Video & Audio Formats"; case .DATA: "Data & Backup"
        }
    }

    var icon: String {
        switch self {
        case .ADDONS: "puzzlepiece.extension"; case .PROFILES: "person.2"; case .PLAYBACK: "play.rectangle"; case .SUBTITLES: "captions.bubble"
        case .APPEARANCE: "paintpalette"; case .BROWSING: "square.grid.2x2"; case .SOUNDS: "speaker.wave.2"; case .SCREENSAVER: "moon.stars"
        case .CONTROLS: "gamecontroller"; case .DEVICE: "desktopcomputer"; case .DATA: "externaldrive"
        }
    }

    var blurb: String {
        switch self {
        case .ADDONS: "Your debrid service, stream addons, metadata, Trakt and the free keys that add cast, scores and artwork."
        case .PROFILES: "Who's watching, profile pictures, and parental controls for kid profiles."
        case .PLAYBACK: "How videos start and end, skipping intros, which streams are picked, the audio language and the player."
        case .SUBTITLES: "Which subtitles are picked and how they look."
        case .APPEARANCE: "Color themes, animated themes, your own colors, text, size and artwork."
        case .BROWSING: "The rows on Home and trailers."
        case .SOUNDS: "Sound effects and new-episode notifications."
        case .SCREENSAVER: "A slideshow of titles picked for you when Zemu sits idle."
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
                Text(narrow ? "" : "Settings").font(.z(size: 28, weight: .black)).padding(.leading, 12).padding(.bottom, narrow ? 0 : 18)
                ForEach(SettingsCategory.allCases) { c in
                    Button { category = c } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(c == category ? P.accent : .clear).frame(width: 4, height: 18)
                            Image(systemName: c.icon).frame(width: 20)
                            if !narrow {
                                Text(c.label).font(.z(size: 14, weight: c == category ? .bold : .medium))
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
                    Text(category.label).font(.z(size: 22, weight: .bold))
                    Text(category.blurb).font(.z(size: 13)).foregroundStyle(Palette.textSecondary).padding(.bottom, 8)
                    switch category {
                    case .ADDONS: AddonsSettings()
                    case .PROFILES:
                        ProfilesSection().padding(.top, 8)
                        KidsSettingsSection()
                    case .PLAYBACK: PlaybackSettings()
                    case .SUBTITLES: SubtitleSettings()
                    case .APPEARANCE: AppearanceSettings()
                    case .BROWSING: BrowsingSettings()
                    case .SOUNDS: SoundSettings()
                    case .SCREENSAVER: ScreensaverSettings()
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
        // A card per section, so each page reads as a few clear sections.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(P.accent).frame(width: 4, height: 18)
                Text(title).font(.z(size: 16, weight: .bold))
            }
            if let note { Text(note).font(.z(size: 12.5)).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 14) }
            content().padding(.top, 2)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(P.surface.opacity(0.35)))
        .padding(.top, 14)
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
                Text(title).font(.z(size: 14, weight: .semibold))
                Text(description).font(.z(size: 12.5)).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
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
                Text(title).font(.z(size: 14, weight: .semibold))
                Spacer()
                Text(value).font(.z(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                Image(systemName: icon).font(.z(size: 11, weight: .bold)).foregroundStyle(Palette.textMuted)
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
            if let text { Text(text).font(.z(size: 12.5)).foregroundStyle(Palette.cached) }
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
                .font(.z(size: 12.5)).foregroundStyle(providers.isEmpty ? Palette.cached : Palette.textSecondary)
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
        SettingsGroup(title: "Critic scores (OMDb)", note: "A free OMDb key adds Rotten Tomatoes and Metacritic scores, and US ratings for shows too: omdbapi.com → API Key (free, 1,000 lookups a day).") {
            KeyField(placeholder: "OMDb API key", saved: s.omdbApiKey, getKey: "https://www.omdbapi.com/apikey.aspx") { k in update { $0.omdbApiKey = k } }
        }
        SettingsGroup(title: "Artwork (fanart.tv)", note: "A free fanart.tv key finds title logos and backdrops when an addon has none, and powers the screensaver. A TMDB key works for this too.") {
            KeyField(placeholder: "fanart.tv API key", saved: s.fanartApiKey, getKey: "https://fanart.tv/get-an-api-key/") { k in update { $0.fanartApiKey = k } }
        }
        SettingsGroup(title: "Trakt", note: "Syncs your Trakt watchlist with My List (both ways), brings in movies you've watched, and scrobbles what you play. Make a free API app at trakt.tv/oauth/applications (redirect URI: urn:ietf:wg:oauth:2.0:oob) and paste its Client ID and Secret.") {
            TraktSection()
        }
    }

    private func saveKey() {
        let k = tmdbKey
        tmdbKey = ""
        Task { message = await app.session.saveTmdbKey(k) }
    }
}

/** A secret API key: saved keys show only their last four characters. */
private struct KeyField: View {
    let placeholder: String
    let saved: String
    var getKey: String?
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            SecureField(saved.isEmpty ? placeholder : "Key saved (••••\(saved.suffix(4)))", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .zFocusText($text, title: placeholder, focus: { focused = true }, onSubmit: commit)
            ZButton(title: "Save", primary: true, action: commit)
            if !saved.isEmpty { ZButton(title: "Remove") { save("") } }
            if let getKey, let u = URL(string: getKey) { ZButton(title: "Get a Key", icon: "safari") { Links.open(u) } }
        }
    }

    private func commit() {
        let k = text.trimmed
        text = ""
        if !k.isEmpty { save(k) }
    }
}

/** Parental controls: kid profiles, the ratings they may watch and the parent code. */
private struct KidsSettingsSection: View {
    var app = AppModel.shared

    var body: some View {
        let kids = app.profiles.kids
        SettingsGroup(title: "Kid profiles", note: "Kid profiles only show family and kids' titles with the ratings you allow. Leaving one, and opening Settings or Addons there, needs the parent code. Ratings come from OMDb or TMDB when you have a key, else Wikidata (movies) and Kitsu (anime).") {
            ToggleRow(title: "Kid profiles", description: "Shows the Kid profile option when adding or editing a profile.", isOn: kids.enabled) { v in
                if v && kids.pinHash.isEmpty {
                    app.createParentCode { app.profiles.updateKids { $0.enabled = true } }
                } else {
                    app.profiles.updateKids { $0.enabled = v }
                }
            }
            if kids.enabled {
                ForEach([("Movies", Ratings.movie), ("TV", Ratings.tv), ("Other", [Ratings.unrated])], id: \.0) { group, certs in
                    HStack(spacing: 8) {
                        Text(group).font(.z(size: 13, weight: .semibold)).frame(width: 60, alignment: .leading)
                        FlowChips {
                            ForEach(certs, id: \.self) { cert in
                                Chip(title: cert == Ratings.unrated ? "Unrated kids' titles" : cert, selected: kids.allowed.contains(cert)) {
                                    app.profiles.updateKids { k in if k.allowed.contains(cert) { k.allowed.remove(cert) } else { k.allowed.insert(cert) } }
                                }
                            }
                        }
                    }
                }
                ActionRow(title: "Change parent code", value: kids.pinHash.isEmpty ? "Not set" : "••••") { app.createParentCode() }
            }
        }
    }
}

/** Trakt: your API app's keys, then link with a code shown on trakt.tv/activate. */
private struct TraktSection: View {
    var app = AppModel.shared
    @State private var link: TraktLink?
    @State private var status: String?

    var body: some View {
        let s = app.settings
        let trakt = app.session.trakt
        VStack(alignment: .leading, spacing: 10) {
            if !s.traktAccessToken.isEmpty {
                HStack(spacing: 10) {
                    Text("Linked to Trakt").font(.z(size: 14, weight: .semibold))
                    Spacer()
                    ZButton(title: "Sync Now", primary: true) {
                        Task { status = await (try? trakt.sync()) ?? "Sync failed. Check your connection." }
                    }
                    ZButton(title: "Unlink") { trakt.disconnect(); status = nil }
                }
            } else {
                KeyField(placeholder: "Client ID", saved: s.traktClientId) { k in update { $0.traktClientId = k } }
                KeyField(placeholder: "Client Secret", saved: s.traktClientSecret) { k in update { $0.traktClientSecret = k } }
                if trakt.configured {
                    if let l = link {
                        HStack(spacing: 14) {
                            Text(l.userCode).font(.z(size: 26, weight: .black, design: .monospaced)).textSelection(.enabled)
                            Text("Enter this code at \(l.url)").font(.z(size: 13)).foregroundStyle(Palette.textSecondary)
                            ZButton(title: "Open", icon: "safari") { if let u = URL(string: l.url) { Links.open(u) } }
                        }
                        .task(id: l.deviceCode) { await poll(l) }
                    } else {
                        ZButton(title: "Link Trakt", primary: true) {
                            Task {
                                do { link = try await trakt.startLink() } catch { status = "Couldn't reach Trakt: \(error.localizedDescription)" }
                            }
                        }
                    }
                }
            }
        }
        .settingsMessage(status)
    }

    private func poll(_ l: TraktLink) async {
        while !Task.isCancelled, nowMs() < l.expiresAt {
            try? await Task.sleep(nanoseconds: UInt64(max(l.intervalSec, 1)) * 1_000_000_000)
            do {
                if try await app.session.trakt.pollLink(l) { link = nil; status = "Linked. Syncing your watchlist…"; return }
            } catch {
                link = nil; status = error.localizedDescription; return
            }
        }
        if link?.deviceCode == l.deviceCode { link = nil; status = "The code expired. Try again." }
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
                .font(.z(size: 12.5)).foregroundStyle(Palette.textSecondary)
            FlowChips {
                ForEach(DebridService.allCases, id: \.self) { s in Chip(title: s.label, selected: a?.service == s) { linking = s } }
                if let a { ZButton(title: "Unlink \(a.service.label)", small: true) { app.session.unlinkDebrid(); status = "\(a.service.label) unlinked." } }
            }
            if let status { Text(status).font(.z(size: 12.5)).foregroundStyle(Palette.cached) }
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
            Text("Link \(service.label)").font(.z(size: 22, weight: .black))
            HStack(alignment: .top, spacing: 28) {
                if service.codeLogin {
                    VStack(alignment: .leading, spacing: 10) {
                        if let l = login {
                            HStack(spacing: 18) {
                                QRCode(text: l.directUrl).frame(width: 150, height: 150)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Scan with your phone, or").font(.z(size: 13)).foregroundStyle(Palette.textSecondary)
                                    ZButton(title: "Open \(l.url.removingPrefix("https://"))", icon: "safari", small: true) {
                                        NSWorkspace.shared.open(URL(string: l.directUrl)!)
                                    }
                                    Text("and enter").font(.z(size: 13)).foregroundStyle(Palette.textSecondary)
                                    HStack {
                                        Text(l.userCode).font(.z(size: 30, weight: .black, design: .monospaced)).foregroundStyle(P.accent).textSelection(.enabled)
                                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(l.userCode, forType: .string) } label: {
                                            Image(systemName: "doc.on.doc")
                                        }.buttonStyle(.plain).help("Copy code")
                                    }
                                }
                            }
                            let left = max(0, Int(l.expiresAt.timeIntervalSince(now)))
                            Text("Waiting for approval… code refreshes in \(left / 60):\(String(format: "%02d", left % 60))")
                                .font(.z(size: 12)).foregroundStyle(Palette.textMuted)
                        } else if error == nil {
                            Text("Getting a code from \(service.label)…").foregroundStyle(Palette.textSecondary)
                        }
                        if let error { Text(error).font(.z(size: 12.5)).foregroundStyle(Palette.cached) }
                    }
                    .frame(width: 380, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.codeLogin ? "Or use your API key" : "Paste your API key").font(.z(size: 15, weight: .bold))
                    HStack(spacing: 4) {
                        Text("Copy it from").foregroundStyle(Palette.textSecondary)
                        Button(service.keyPage) { NSWorkspace.shared.open(URL(string: "https://\(service.keyPage)")!) }.buttonStyle(.link)
                            .zFocus(activate: { NSWorkspace.shared.open(URL(string: "https://\(service.keyPage)")!) }, cornerRadius: 4)
                    }
                    .font(.z(size: 13))
                    HStack {
                        SecureField("\(service.label) API key", text: $key).textFieldStyle(.roundedBorder).onSubmit(saveKey)
                            .focused($keyFocused)
                            .zFocusText($key, title: "\(service.label) API key", focus: { keyFocused = true }, onSubmit: saveKey)
                        ZButton(title: working ? "Checking…" : "Save", primary: true, action: saveKey)
                    }
                    if !service.codeLogin, let error { Text(error).font(.z(size: 12.5)).foregroundStyle(Palette.cached) }
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
        SettingsGroup(title: "Skipping") {
            ToggleRow(title: "Skip intro button", description: "Show \"Skip intro\" / \"Skip recap\" while they play (community timestamps from TheIntroDB and AniSkip). The next-episode card starts at the credits.", isOn: s.skipIntroButton) { v in update { $0.skipIntroButton = v } }
        }
        SettingsGroup(title: "Cached streams", note: "Catalogs show every title. When you open one, only streams cached on your debrid service are listed.") {
            ToggleRow(title: "Treat direct links as cached", description: "Count plain HTTP streams without debrid markers as instantly playable. Leave off for strict debrid-cached only.", isOn: s.trustDirectLinks) { v in update { $0.trustDirectLinks = v } }
            PickerRow(title: "Maximum file size", options: [0, 5, 10, 20, 40, 80].map { ($0, $0 == 0 ? "No limit" : "\($0) GB") }, value: s.maxSizeGb) { v in update { $0.maxSizeGb = v } }
        }
        SettingsGroup(title: "Audio language", note: "Order matters: the first language is preferred. Also used to rank streams.") {
            LanguagePicker(title: "Preferred audio", selected: s.audioLanguages) { l in update { $0.audioLanguages = l } }
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
            Text(label).font(.z(size: 13)).foregroundStyle(Palette.textSecondary).frame(width: 90, alignment: .leading)
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
        SettingsGroup(title: "Which subtitles", note: "Order matters: the first language is preferred.") {
            LanguagePicker(title: "Preferred subtitles", selected: s.subtitleLanguages) { l in update { $0.subtitleLanguages = l } }
            ToggleRow(title: "Turn on subtitles automatically", description: "Select a subtitle track in your preferred language when playback starts.", isOn: s.autoSubtitles) { v in update { $0.autoSubtitles = v } }
        }
        SettingsGroup(title: "Subtitle appearance", note: "Also available in the player (press C).") {
            SubtitlePreview(settings: s)
            SubtitleStyleEditor()
            ToggleRow(title: "Keep styled subtitles as authored", description: "ASS/SSA subtitles (common for anime) keep their own fonts, colors and signs; only the size follows your setting. Off applies your style to them too.", isOn: s.keepStyledSubtitles) { v in update { $0.keepStyledSubtitles = v } }
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
                .font(.z(size: 20 * settings.subtitleScale, weight: .semibold))
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
                        ThemeSwatch(label: p.label, colors: p.colors, selected: s.theme == p.rawValue) { app.updateLook { $0.theme = p.rawValue } }
                    }
                    ThemeSwatch(label: "Custom", colors: ThemeColors(accent: Color(argb: s.customAccent), background: Color(argb: s.customBackground)), selected: s.theme == ThemePreset.custom) {
                        // Start the custom theme from whatever is showing now.
                        let cur = s.themeColors
                        app.updateLook {
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
        SettingsGroup(title: "Animated themes", note: "Most themes bring their own colors; RGB and Weather keep your color theme. PS2, Acidwave, Cybercore, Graffiti, Liquid Glass, Pocket LCD, 16-Bit, Outer Space, Night Sky, Alien Abduction and Ocean restyle the whole app with a scene, lettering and sounds. After a change, \"Keep changes?\" puts the old look back unless you keep it.") {
            let current = DynamicTheme.of(s.dynamicTheme)
            FlowChips {
                ForEach(DynamicTheme.allCases.filter { !$0.hidden || s.catRaveUnlocked }, id: \.self) { d in
                    Chip(title: d.label, selected: current == d) {
                        app.updateLook {
                            if d == .CATRAVE && $0.dynamicTheme != "CATRAVE" { $0.themeBeforeRave = $0.dynamicTheme }
                            $0.dynamicTheme = d.rawValue
                        }
                    }
                }
            }
            if !current.variants.isEmpty {
                FlowChips {
                    ForEach(current.variants, id: \.0) { key, label in
                        Chip(title: label, selected: s.variant(of: current) == key) { app.updateLook { $0.themeVariants[current.rawValue] = key } }
                    }
                }
            }
        }
        SettingsGroup(title: "Customize colors", note: "Every color the theme uses, for the theme and mode showing now (switch light mode or the theme to edit theirs). Editing a palette keeps the original; Reset puts it back.") {
            ColorCustomizer()
        }
        SettingsGroup(title: "Text and size") {
            HStack(spacing: 16) {
                Text("UI zoom").font(.z(size: 14, weight: .semibold)).frame(width: 110, alignment: .leading)
                Slider(value: Binding(get: { Double(s.uiZoom) }, set: { v in update { $0.uiZoom = Int(v) } }), in: 70...160, step: 5)
                Text("\(s.uiZoom)%").font(.z(size: 13)).monospacedDigit().frame(width: 48)
            }
            HStack(spacing: 16) {
                Text("Text size").font(.z(size: 14, weight: .semibold)).frame(width: 110, alignment: .leading)
                Slider(value: Binding(get: { Double(s.fontSize) }, set: { v in update { $0.fontSize = Int(v) } }), in: 70...160, step: 5)
                Text("\(s.fontSize)%").font(.z(size: 13)).monospacedDigit().frame(width: 48)
            }
            FlowChips {
                Text("Font").font(.z(size: 14, weight: .semibold)).padding(.trailing, 6)
                ForEach(fontChoices, id: \.0) { key, label in
                    Chip(title: key.isEmpty ? "Theme's own" : label, selected: s.font == key) { update { $0.font = key } }
                }
            }
            if s.uiZoom != 100 || s.fontSize != 100 || !s.font.isEmpty {
                ZButton(title: "Reset text and size", small: true) { update { $0.uiZoom = 100; $0.fontSize = 100; $0.font = "" } }
            }
        }
        SettingsGroup(title: "Pictures and logos") {
            ToggleRow(title: "Backdrop pictures", description: "Show the title's picture behind the top of Home, the Movies/Series/Anime pages and title pages.", isOn: s.heroArt) { v in update { $0.heroArt = v } }
            ToggleRow(title: "Title logos", description: "Show titles as their logo artwork. Off writes them out in plain text.", isOn: s.logoArt) { v in update { $0.logoArt = v } }
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
                Text((selected ? "✓ " : "") + label).font(.z(size: 12, weight: .semibold)).lineLimit(1)
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
                Text("No controller connected.").font(.z(size: 13)).foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(controllers, id: \.self) { c in
                    HStack { Image(systemName: "gamecontroller.fill").foregroundStyle(P.accent); Text(c).font(.z(size: 14, weight: .semibold)) }
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
            .font(.z(size: 12, weight: .bold)).foregroundStyle(Palette.textMuted).padding(.horizontal, 16).padding(.vertical, 6)
            ForEach(rows, id: \.0) { r in
                HStack(alignment: .top) {
                    Text(r.0).font(.z(size: 13.5, weight: .semibold)).frame(width: 190, alignment: .leading)
                    Text(r.1).font(.z(size: 13)).foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.2).font(.z(size: 13)).foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider().opacity(0.3)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(P.surface))
        .zFocus(activate: nil, cornerRadius: 10)
    }
}

// MARK: - Browsing, sounds, screensaver

private struct BrowsingSettings: View {
    var app = AppModel.shared
    var body: some View {
        let s = app.settings
        SettingsGroup(title: "Rows", note: "Add rows of your own (a service, a studio, a genre or any addon list) and bring back rows you removed. On a page, drag a row's grip to move it, pin it to keep it, or click the crossed-out eye to remove it.") {
            // Zemu's Movies and Series pages are Browse grids, so only Home has rows to manage for now.
            ForEach([("home", "Home")], id: \.0) { page, label in
                RowsManager(page: page, label: label)
            }
            ToggleRow(title: "Hide watched titles in rows", description: "Keep movies and shows you've finished out of suggestions and categories.", isOn: s.hideWatchedInRows) { v in update { $0.hideWatchedInRows = v } }
        }
        SettingsGroup(title: "Trailers") {
            ToggleRow(title: "Trailers", description: "Off: no trailers anywhere (no autoplay, no Trailer buttons or menu items).", isOn: s.trailers) { v in update { $0.trailers = v } }
            ToggleRow(title: "Autoplay trailers", description: "Play the trailer behind the title after you rest the pointer on it for a few seconds.", isOn: s.heroTrailers) { v in update { $0.heroTrailers = v } }
            ToggleRow(title: "Trailer sound", description: "Play autoplaying trailers with sound. Full-window trailers always have sound.", isOn: s.heroTrailerSound) { v in update { $0.heroTrailerSound = v } }
        }
    }
}

private struct SoundSettings: View {
    var app = AppModel.shared
    var body: some View {
        let s = app.settings
        SettingsGroup(title: "Sounds") {
            ToggleRow(title: "Sound effects", description: "Clicks and blips when you move, select and go back with the keyboard or a controller. Themes with their own look bring their own sounds.", isOn: s.soundEffects) { v in update { $0.soundEffects = v } }
            if s.soundEffects {
                HStack(spacing: 8) {
                    ForEach(SoundFx.packs, id: \.0) { key, label in
                        Chip(title: label, selected: s.soundPack == key) { update { $0.soundPack = key } }
                    }
                }
            }
        }
        SettingsGroup(title: "Notifications") {
            ToggleRow(title: "New episode notifications", description: "Get a notification when a show you watch has a new episode out.", isOn: s.notifyNewEpisodes) { v in
                update { $0.notifyNewEpisodes = v }
                if v { Integrations.shared.requestNotificationPermission() }
            }
        }
    }
}

private struct ScreensaverSettings: View {
    var app = AppModel.shared
    var body: some View {
        let s = app.settings
        SettingsGroup(title: "Screensaver", note: "A slideshow of suggested titles after Zemu sits idle. Any key, click or controller button wakes it; Return plays the title showing. Needs a TMDB or fanart.tv key to find backdrops. Kid profiles have none.") {
            ToggleRow(title: "Screensaver", description: "Off by default.", isOn: s.screensaver) { v in update { $0.screensaver = v } }
            if s.screensaver {
                FlowChips {
                    MenuChip(title: "Start after \(durationLabel(s.screensaverIdleSec))", heading: "Start after") {
                        choiceItems([30, 60, 120, 300, 600, 900, 1800].map { ($0, durationLabel($0)) }, current: s.screensaverIdleSec) { v in update { $0.screensaverIdleSec = v } }
                    }
                    MenuChip(title: "Each title \(durationLabel(s.screensaverImageSec))", heading: "Show each title for") {
                        choiceItems([5, 8, 10, 15, 20, 30, 60].map { ($0, durationLabel($0)) }, current: s.screensaverImageSec) { v in update { $0.screensaverImageSec = v } }
                    }
                    MenuChip(title: "Fade \(String(format: "%.1f", Double(s.screensaverFadeTenths) / 10)) s", heading: "Crossfade") {
                        choiceItems([5, 10, 15, 20, 30, 50].map { ($0, String(format: "%.1f s", Double($0) / 10)) }, current: s.screensaverFadeTenths) { v in update { $0.screensaverFadeTenths = v } }
                    }
                    Chip(title: "Show title", selected: s.screensaverShowTitle) { update { $0.screensaverShowTitle.toggle() } }
                }
            }
        }
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
            Text(title).font(.z(size: 14, weight: .semibold))
            Spacer()
            Text(value).font(.z(size: 13, weight: .bold)).foregroundStyle(ok ? Palette.match : Palette.textMuted)
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

/**
 * Edit the colors of the theme showing now (per light/dark mode), and save or apply named palettes.
 * Editing a preset switches to Custom first, so presets themselves never change.
 */
private struct ColorCustomizer: View {
    var app = AppModel.shared
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        let s = app.settings
        let light = P.light
        let scope = s.colorScope(light: light)
        let scopeName = String(scope.split(separator: "/").first ?? "")
        let roles = ColorRole.allCases.filter { $0 != .scene || s.dynamicTheme != "NONE" }
        VStack(alignment: .leading, spacing: 10) {
            Text("Editing \(themeLabel(scopeName)) · \(light ? "light" : "dark") mode").font(.z(size: 12.5)).foregroundStyle(Palette.textSecondary)
            FlowChips {
                ForEach(roles, id: \.self) { r in
                    VStack(spacing: 4) {
                        ColorPicker("", selection: Binding(get: { value(r) }, set: { c in set(r, c, scope: scope) }), supportsOpacity: false).labelsHidden()
                        Text(r.label + (s.colorOverrides["\(scope)/\(r.rawValue)"] != nil ? " •" : "")).font(.z(size: 11.5))
                    }
                    .padding(8)
                    .zSurface(RoundedRectangle(cornerRadius: 10), fill: P.surface)
                    .contextMenu { Button("Reset \(r.label)") { update { $0.colorOverrides["\(scope)/\(r.rawValue)"] = nil } } }
                }
            }
            HStack(spacing: 10) {
                ZButton(title: "Reset all colors (\(light ? "light" : "dark"))", small: true) {
                    app.updateLook { $0.colorOverrides = $0.colorOverrides.filter { !$0.key.hasPrefix(scope + "/") } }
                }
                ZButton(title: "Save these colors…", small: true) { name = ""; naming = true }
            }
            let saved = s.savedPalettes.filter { $0.theme == nil || $0.theme == scopeName }
            if !saved.isEmpty {
                Text("Saved palettes").font(.z(size: 13, weight: .semibold)).padding(.top, 4)
                FlowChips {
                    ForEach(saved, id: \.self) { p in
                        Button { app.updateLook { s in for (k, v) in p.colors { s.colorOverrides["\(scope)/\(k)"] = v } } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 0) {
                                    ForEach(ColorRole.allCases.compactMap { p.colors[$0.rawValue] }, id: \.self) { Rectangle().fill(Color(argb: $0)).frame(width: 18, height: 22) }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(p.name).font(.z(size: 12, weight: .semibold))
                                Text(p.theme == nil ? "Any theme" : "Only \(themeLabel(scopeName))").font(.z(size: 10.5)).foregroundStyle(Palette.textSecondary)
                            }
                            .padding(8)
                            .zSurface(RoundedRectangle(cornerRadius: 10), fill: P.surface)
                        }
                        .buttonStyle(.plain)
                        .zFocus(activate: { app.updateLook { s in for (k, v) in p.colors { s.colorOverrides["\(scope)/\(k)"] = v } } }, cornerRadius: 10)
                        .contextMenu { Button("Delete \(p.name)") { update { $0.savedPalettes.removeAll { $0 == p } } } }
                    }
                }
            }
        }
        .alert("Save palette", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("For every theme") { save(scopeName: nil, roles: roles) }
            Button("Only for \(themeLabel(scopeName))") { save(scopeName: scopeName, roles: roles) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func value(_ r: ColorRole) -> Color {
        switch r {
        case .accent: P.colors.accent
        case .background: P.base
        case .panel: P.colors.customPanel ?? P.surface
        case .button: P.colors.customButton ?? P.surfaceHigh
        case .text: P.text
        case .scene: Color(argb: app.settings.colorOverrides["\(app.settings.colorScope(light: P.light))/scene"] ?? P.colors.accent.argb)
        }
    }

    private func set(_ r: ColorRole, _ c: Color, scope: String) {
        update { s in
            var scope = scope
            // Editing a preset palette turns it into Custom first, starting from the colors showing now.
            if scope.hasPrefix(s.theme + "/"), s.theme != ThemePreset.custom {
                let cur = s.themeColors
                s.customAccent = cur.accent.argb
                s.customBackground = cur.background.argb
                s.theme = ThemePreset.custom
                scope = s.colorScope(light: P.light)
            }
            s.colorOverrides["\(scope)/\(r.rawValue)"] = c.argb | 0xFF000000
        }
    }

    private func save(scopeName: String?, roles: [ColorRole]) {
        let p = SavedPalette(name: name.trimmed.isEmpty ? "My palette" : String(name.trimmed.prefix(30)), theme: scopeName,
                             colors: Dictionary(uniqueKeysWithValues: roles.map { ($0.rawValue, value($0).argb) }))
        update { s in s.savedPalettes.removeAll { $0.name == p.name && $0.theme == p.theme }; s.savedPalettes.append(p) }
    }

    private func themeLabel(_ scopeName: String) -> String {
        if scopeName.hasPrefix("RETRO-") { return "Cybercore " + (DynamicTheme.RETRO.variants.first { $0.0 == scopeName.dropFirst(6) }?.1 ?? "") }
        return DynamicTheme(rawValue: scopeName)?.label ?? ThemePreset(rawValue: scopeName)?.label ?? "Custom"
    }
}

/** One page's rows: add a row, or restore removed ones. */
private struct RowsManager: View {
    let page: String
    let label: String
    var app = AppModel.shared

    var body: some View {
        let store = app.session.store
        let model = app.session.home
        let hidden = store.hiddenRows(page: page)
        let added = store.addedRows(page: page)
        let known = model.rows
        VStack(alignment: .leading, spacing: 8) {
            ActionRow(title: label, value: "Add a row…", icon: "plus") {
                let current = Set(added.map(\.key))
                app.showMenu("Add a row to \(label)") {
                    model.addableRows(page).filter { !current.contains($0.key) }.map { spec in
                        ActionItem(label: spec.title) { model.addRow(spec, page: page); app.toast("Added \(spec.title) to \(label)") }
                    }
                }
            }
            if !hidden.isEmpty || !added.isEmpty {
                FlowChips {
                    ForEach(added, id: \.key) { spec in
                        Chip(title: spec.title, selected: true, icon: "xmark") { store.hideRow(spec.key, page: page) }.help("Remove this row")
                    }
                    ForEach(hidden, id: \.self) { key in
                        Chip(title: known.first { $0.key == key }?.title ?? key, icon: "arrow.uturn.backward") { store.showRow(key, page: page) }
                            .help("Bring this row back")
                    }
                }
                .padding(.leading, 16)
            }
        }
    }
}

private func durationLabel(_ sec: Int) -> String { sec < 60 ? "\(sec) s" : "\(sec / 60) min" }
