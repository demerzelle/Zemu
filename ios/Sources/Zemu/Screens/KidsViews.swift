import SwiftUI
import ZemuCore

/** Number pad for the 4-digit parent code. */
struct ParentCodePad: View {
    let title: String
    var message: String?
    let onDismiss: () -> Void
    /** True when the code is accepted. */
    let onCode: (String) -> Bool
    @State private var code = ""
    @State private var wrong = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(title).font(.system(size: 22, weight: .bold))
                if let message { Text(message).font(.system(size: 14)).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center) }
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(i < code.count ? P.accent : Color.white.opacity(0.2)).frame(width: 16, height: 16)
                    }
                }
                if wrong { Text("That's not it. Try again.").font(.system(size: 13)).foregroundStyle(Palette.cached) }
                VStack(spacing: 8) {
                    ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]], id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(row, id: \.self) { key in
                                if key.isEmpty { Color.clear.frame(width: 64, height: 40) } else { digit(key) }
                            }
                        }
                    }
                }
                ZButton(title: "Cancel", action: onDismiss)
            }
            .padding(26)
            .frame(maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: 18).fill(P.surface))
        }
        #if os(tvOS)
        .onExitCommand(perform: onDismiss)
        #endif
    }

    private func digit(_ key: String) -> some View {
        ZButton(title: key, preferred: key == "5") { press(key) }.frame(width: 64)
    }

    private func press(_ key: String) {
        if key == "⌫" { if !code.isEmpty { code.removeLast() }; return }
        guard code.count < 4 else { return }
        code += key
        wrong = false
        if code.count == 4, !onCode(code) { wrong = true; code = "" }
    }
}

/** A new parent code, entered twice. */
struct CreateParentCode: View {
    let onDismiss: () -> Void
    let onDone: () -> Void
    var app = AppModel.shared
    @State private var first: String?

    var body: some View {
        if let first {
            ParentCodePad(title: "Enter it again", onDismiss: onDismiss) { code in
                guard code == first else { return false }
                app.profiles.updateKids { $0.pinHash = KidsSettings.hash(code) }
                onDone()
                return true
            }
            .id("again")
        } else {
            ParentCodePad(title: "Create a parent code", message: "4 digits. It's needed to leave a kid profile or open Settings there.", onDismiss: onDismiss) { code in
                first = code
                return true
            }
            .id("first")
        }
    }
}

/** In Kids Mode, [content] (Settings, addons) shows only after the parent code. */
struct ParentLock<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var app = AppModel.shared
    @State private var unlocked = false

    var body: some View {
        if !app.profiles.kidsOn || unlocked {
            content()
        } else {
            CenteredMessage(title: "Grown-ups only", message: "This part of the app needs the parent code in Kids Mode.") {
                ZButton(title: "Enter Parent Code", primary: true, preferred: true, action: ask)
            }
            .onAppear(perform: ask)
        }
    }

    private func ask() {
        app.parentPrompt = ParentPrompt(title: "Parent code") { unlocked = true }
    }
}

/** In Kids Mode, a title above the allowed rating shows a lock (a parent can let it through). */
struct KidsTitleGate<Content: View>: View {
    let type: String
    let id: String
    @ViewBuilder let content: () -> Content
    var app = AppModel.shared
    @State private var unlocked = false
    @State private var allowed: Bool?

    var body: some View {
        if !app.profiles.kidsOn || unlocked || allowed == true {
            content()
        } else {
            ZStack {
                if allowed == nil {
                    Text("Checking the rating…").foregroundStyle(Palette.textSecondary)
                } else {
                    CenteredMessage(title: "Not for Kids Mode", message: "This title isn't a kids' title or its rating isn't allowed. Ask a grown-up.") {
                        ZButton(title: "Parent Code", primary: true, preferred: true) {
                            app.parentPrompt = ParentPrompt(title: "Let this one play?") { unlocked = true }
                        }
                    }
                }
            }
            .task(id: id) { allowed = await app.session.kids.allowed(Meta(id: id, type: type)) }
        }
    }
}

/** Hides a title's card when Kids Mode doesn't allow it. */
struct KidsGated: ViewModifier {
    let meta: Meta
    var app = AppModel.shared

    func body(content: Content) -> some View {
        if app.session.kids.safe([meta]).isEmpty { EmptyView() } else { content }
    }
}

/** Settings → Profiles: what kid profiles may watch and the parent code. */
struct KidsSettingsSection: View {
    var app = AppModel.shared
    @State private var changingCode = false

    var body: some View {
        let kids = app.profiles.kids
        SettingsGroup(title: "Kid profiles", note: "Only family and kids' titles show on a kid profile, limited to the ratings you allow. Leaving one or opening Settings needs the parent code.") {
            FlowLayout(spacing: 8) {
                ForEach(Ratings.movie + Ratings.tv + [Ratings.unrated], id: \.self) { r in
                    Chip(title: r == Ratings.unrated ? "Unrated" : r, selected: kids.allowed.contains(r)) {
                        app.profiles.updateKids { k in
                            if k.allowed.contains(r) { k.allowed.remove(r) } else { k.allowed.insert(r) }
                        }
                    }
                }
            }
            ZButton(title: kids.pinHash.isEmpty ? "Create Parent Code" : "Change Parent Code", icon: "lock") { changingCode = true }
        }
        .fullScreenOverlay(isPresented: changingCode) {
            CreateParentCode(onDismiss: { changingCode = false }, onDone: { changingCode = false; app.toast("Parent code saved") })
        }
    }
}

extension View {
    /** A sheet that fills the TV or iPad, for the number pad over Settings. */
    func fullScreenOverlay<C: View>(isPresented: Bool, @ViewBuilder content: @escaping () -> C) -> some View {
        sheet(isPresented: Binding(get: { isPresented }, set: { _ in })) { content().tvScaled() }
    }
}

/** Rotten Tomatoes and Metacritic, when an OMDb key is set. */
struct CriticScores: View {
    let meta: Meta
    var app = AppModel.shared
    @State private var scores: TitleScores?

    var body: some View {
        HStack(spacing: 14) {
            if let rt = scores?.rottenTomatoes { Text("Rotten Tomatoes \(rt)%") }
            if let mc = scores?.metacritic { Text("Metacritic \(mc)") }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Palette.textSecondary)
        .task(id: meta.id) { scores = await app.session.scores.of(meta.imdbId) }
    }
}

/** Settings → Trakt: your API app, linking with a code, sync. */
struct TraktSection: View {
    var app = AppModel.shared
    @State private var clientId = ""
    @State private var secret = ""
    @State private var link: TraktLink?
    @State private var status: String?

    var body: some View {
        let trakt = app.session.trakt
        SettingsGroup(title: "Trakt", note: "Syncs your watchlist with My List, brings in movies you've watched, scrobbles what you play, and shows friends' picks. Make a free API app at trakt.tv/oauth/applications, then enter its Client ID and Secret.") {
            if trakt.connected {
                Text("Linked to Trakt").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.cached)
                HStack(spacing: 10) {
                    ZButton(title: "Sync Now", primary: true) { sync(trakt) }
                    ZButton(title: "Unlink") { trakt.disconnect(); status = nil }
                }
            } else if let link {
                HStack(spacing: 18) {
                    QRCode(text: "\(link.url)/\(link.userCode)").frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scan, or open \(link.url.removingPrefix("https://")) and enter").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        Text(link.userCode).font(.system(size: 30, weight: .black, design: .monospaced)).foregroundStyle(P.accent)
                    }
                }
                .task(id: link.deviceCode) { await poll(link, trakt) }
            } else if trakt.configured {
                HStack(spacing: 10) {
                    ZButton(title: "Link Trakt", primary: true) {
                        Task {
                            do { link = try await trakt.startLink(); status = nil }
                            catch { status = "Couldn't reach Trakt: \(error.localizedDescription)" }
                        }
                    }
                    ZButton(title: "Change API App") { app.session.store.updateSettings { $0.traktClientId = ""; $0.traktClientSecret = "" } }
                }
            } else {
                HStack {
                    TextField("Client ID", text: $clientId).textFieldStyle(.roundedBorder)
                    SecureField("Client Secret", text: $secret).textFieldStyle(.roundedBorder)
                    ZButton(title: "Save", primary: true) {
                        let id = clientId.trimmed, s = secret.trimmed
                        guard !id.isEmpty, !s.isEmpty else { return }
                        app.session.store.updateSettings { $0.traktClientId = id; $0.traktClientSecret = s }
                        clientId = ""; secret = ""
                    }
                }
            }
            if let status { Text(status).font(.system(size: 12.5)).foregroundStyle(Palette.cached) }
        }
    }

    private func sync(_ trakt: Trakt) {
        Task {
            do { status = try await trakt.sync(); try await trakt.refreshFriends() }
            catch { status = "Sync failed: \(error.localizedDescription)" }
        }
    }

    private func poll(_ link: TraktLink, _ trakt: Trakt) async {
        while !Task.isCancelled, nowMs() < link.expiresAt {
            try? await Task.sleep(nanoseconds: UInt64(link.intervalSec) * 1_000_000_000)
            do {
                if try await trakt.pollLink(link) { self.link = nil; status = "Linked. Syncing…"; return }
            } catch {
                self.link = nil
                status = error.localizedDescription
                return
            }
        }
        if !Task.isCancelled { self.link = nil; status = "The code expired. Try again." }
    }
}

/** Settings: a free OMDb key adds critic scores. */
struct OmdbSection: View {
    var app = AppModel.shared
    @State private var key = ""

    var body: some View {
        let saved = app.settings.omdbApiKey
        SettingsGroup(title: "Critic scores (OMDb)", note: "A free key adds Rotten Tomatoes and Metacritic scores: omdbapi.com → API Key (1,000 lookups a day).") {
            HStack {
                SecureField(saved.isEmpty ? "OMDb API key" : "Key saved (••••\(saved.suffix(4)))", text: $key).textFieldStyle(.roundedBorder)
                ZButton(title: "Save", primary: true) {
                    let k = key.trimmed
                    guard !k.isEmpty else { return }
                    app.session.store.updateSettings { $0.omdbApiKey = k }
                    key = ""
                }
                if !saved.isEmpty { ZButton(title: "Remove") { app.session.store.updateSettings { $0.omdbApiKey = "" } } }
            }
        }
    }
}
