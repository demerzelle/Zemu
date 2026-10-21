import SwiftUI
import UniformTypeIdentifiers
import ZemuCore

struct RootView: View {
    var app = AppModel.shared
    @State private var mouseMonitor: Any?

    var body: some View {
        ZStack {
            if P.glass { AmbientBackdrop() } else if P.scene != .normal {
                ThemeBackdrop(style: P.scene, variant: P.sceneVariant).ignoresSafeArea()
                    .hueRotation(.degrees(P.colors.sceneHueShift))
            } else { P.background.ignoresSafeArea() }
            WindowReader().frame(width: 0, height: 0)
            if app.picking {
                ProfilePicker()
            } else {
                HStack(spacing: 0) {
                    Sidebar()
                    ZStack(alignment: .topLeading) {
                        page
                            .id("\(app.session.profileId)|\(app.section.rawValue)|\(app.stack.count)")
                            .transition(.opacity)
                        if !app.stack.isEmpty {
                            IconButton(icon: "chevron.left", help: "Back (⌘[)", size: 36) { app.back() }
                                .padding(.leading, 20).padding(.top, 34)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .padding(.bottom, P.scene.floorHeight)
                .ignoresSafeArea()
            }
            if P.scene.floorHeight > 0, !themeEffectsPaused {
                StyleFloor(style: P.scene, variant: P.sceneVariant).ignoresSafeArea().zIndex(8)
            }

            if let p = app.player, !app.pip {
                PlayerView(p: p).ignoresSafeArea().transition(.opacity).zIndex(10)
            }
            if let t = app.trailer {
                TrailerOverlay(request: t).ignoresSafeArea().transition(.opacity).zIndex(11).zFocusScope("trailer")
            }
            if let m = app.actionMenu {
                ActionMenuOverlay(request: m).zIndex(14).transition(.opacity)
            }
            if let k = app.osk {
                OnScreenKeyboard(request: k).zIndex(15).transition(.opacity)
            }
            if app.showShortcuts {
                ShortcutsOverlay().ignoresSafeArea().zIndex(16).transition(.opacity)
            }
            if app.showPalette {
                CommandPalette().ignoresSafeArea().zIndex(17).transition(.opacity)
            }
            // Animated theme effects pause while a video or trailer plays and never draw over them.
            if !themeEffectsPaused {
                DynamicThemeLayer(theme: DynamicTheme.of(app.settings.dynamicTheme), variant: P.sceneVariant)
                    // A palette's scene color turns the effect's hues.
                    .hueRotation(.degrees(P.colors.sceneHueShift))
                    .ignoresSafeArea().zIndex(9).transition(.opacity)
            }
            if app.pendingLook != nil {
                KeepChangesPrompt().zIndex(17.5).transition(.opacity)
            }
            if Screensaver.shared.showing {
                ScreensaverView(slides: Screensaver.shared.slides).ignoresSafeArea().zIndex(19).transition(.opacity)
            }
            if let p = app.parentPrompt {
                ParentCodeOverlay(prompt: p).id(p.id).ignoresSafeArea().zIndex(18).transition(.opacity)
            }
            VStack { Spacer(); ToastStack() }.zIndex(13)
        }
        .animation(.easeInOut(duration: 0.2), value: app.player != nil)
        .animation(.easeInOut(duration: 0.15), value: app.actionMenu?.id)
        .animation(.easeInOut(duration: 0.15), value: app.osk?.id)
        .animation(.easeInOut(duration: 0.15), value: app.showShortcuts)
        .animation(.easeInOut(duration: 0.12), value: app.showPalette)
        .animation(.easeInOut(duration: 0.2), value: app.trailer)
        .animation(.easeInOut(duration: 0.4), value: themeEffectsPaused)
        .onChange(of: app.player != nil && !app.pip, initial: true) { _, up in P.videoUp = up }
        .preferredColorScheme(P.light ? .light : .dark)
        .tint(P.accent)
        .foregroundStyle(P.text)
        .sheet(item: Binding(get: { app.configure }, set: { app.configure = $0 })) { ConfigureSheet(request: $0) }
        // Drop or paste an addon link anywhere to install it.
        .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
            guard app.player == nil, let item = providers.first else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in app.handleURL(url) } }
            }
            return true
        }
        .onAppear {
            // Mouse "back" button.
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { e in
                if e.buttonNumber == 3, app.player == nil { app.back(); return nil }
                return e
            }
        }
    }

    /** A video (also in PiP), a full-window trailer or a hero trailer is playing. */
    private var themeEffectsPaused: Bool {
        app.player != nil || app.trailer != nil || HeroTrailerState.shared.playingId != nil
    }

    @ViewBuilder
    private var page: some View {
        if let r = app.route {
            switch r {
            case let .details(type, id, section, play, seed):
                KidsTitleGate(type: type, id: id) { DetailsView(type: type, id: id, section: section, play: play, seed: seed) }
            case let .person(key): PersonView(key: key)
            case let .discover(type, service, label, studio): DiscoverGridView(type: type, service: service, label: label, studio: studio)
            case let .services(type): ServicesView(type: type)
            }
        } else {
            switch app.section {
            case .home: HomeView()
            case .movies: BrowseView(type: "movie")
            case .series: BrowseView(type: "series")
            case .anime: BrowseView(type: "anime")
            case .search: SearchView()
            case .mylist: MyListView()
            case .downloads: DownloadsView()
            case .addons: AddonsView()
            case .settings: SettingsView()
            }
        }
    }
}

/** ⌘K: jump to a page or run a common action by typing part of its name. Keys are routed by InputRouter. */
private struct CommandPalette: View {
    var app = AppModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        let items = app.paletteItems
        ZStack(alignment: .top) {
            Color.black.opacity(0.4).onTapGesture { app.showPalette = false }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Type a command or page…", text: Binding(
                    get: { app.paletteQuery },
                    set: { app.paletteQuery = $0; app.paletteSelection = 0 }
                ))
                .textFieldStyle(.plain)
                .font(.z(size: 18))
                .focused($focused)
                .padding(.horizontal, 10).padding(.vertical, 8)
                Divider().opacity(0.3)
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    Button {
                        app.paletteSelection = i
                        app.paletteRun()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon ?? "circle").frame(width: 20).foregroundStyle(Palette.textSecondary)
                            Text(item.label).font(.z(size: 14))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(i == app.paletteSelection ? P.ink.opacity(0.12) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if items.isEmpty {
                    Text("No matches").font(.z(size: 13)).foregroundStyle(Palette.textMuted).padding(10)
                }
                Text("↑↓ choose · Return run · Esc close").font(.z(size: 11)).foregroundStyle(Palette.textMuted)
                    .padding(.horizontal, 10).padding(.top, 4)
            }
            .padding(14)
            .frame(width: 520)
            .zSurface(RoundedRectangle(cornerRadius: P.glass ? 26 : 14, style: .continuous), fill: P.surface)
            .shadow(color: .black.opacity(P.light ? 0.2 : 0.5), radius: 30)
            .padding(.top, 120)
        }
        .onAppear { focused = true }
    }
}

/** ⌘/ : the keys that do the most, grouped the way the app is organized. */
private struct ShortcutsOverlay: View {
    var app = AppModel.shared

    private static let groups: [(title: String, keys: [(key: String, what: String)])] = [
        ("Navigate", [("⌘1–⌘8", "Switch pages"), ("⌘F", "Search"), ("⌘[", "Back"), ("Arrows", "Move focus"), ("Return", "Select")]),
        ("Playback", [("Space", "Play or pause"), ("← →", "Seek"), ("↑ ↓", "Volume"), ("F", "Full screen"), ("S · A", "Subtitles · audio"), ("N", "Next episode"), ("[ ]", "Speed"), ("⌘S", "Save frame")]),
        ("Window", [("⌘,", "Settings"), ("⌘O", "Open stream URL"), ("⌘⇧V", "Install addon from clipboard"), ("⌘⇧G", "Liquid Glass look"), ("⌘⇧L", "Light mode"), ("⌘⇧P", "Switch profile")]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).onTapGesture { app.showShortcuts = false }
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Keyboard Shortcuts").font(.z(size: 20, weight: .bold))
                    Spacer()
                    Text("Click outside or press ⌘/ to close").font(.z(size: 12)).foregroundStyle(Palette.textMuted)
                }
                HStack(alignment: .top, spacing: 36) {
                    ForEach(Self.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title.uppercased()).font(.z(size: 11, weight: .bold)).tracking(1).foregroundStyle(P.accentText)
                            ForEach(group.keys, id: \.key) { k in
                                HStack(spacing: 12) {
                                    Text(k.key).font(.z(size: 13, weight: .semibold, design: .monospaced))
                                        .frame(width: 96, alignment: .leading)
                                    Text(k.what).font(.z(size: 13)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .zSurface(RoundedRectangle(cornerRadius: P.glass ? 26 : 16, style: .continuous), fill: P.surface)
            .shadow(color: .black.opacity(P.light ? 0.2 : 0.5), radius: 30)
        }
    }
}

/** The left menu: icons, expanding with labels while the pointer is over it. */
private struct Sidebar: View {
    var app = AppModel.shared
    @State private var hovering = false

    private var expanded: Bool { hovering || FocusEngine.shared.focusedGroup == "sidebar" }

    var body: some View {
        let current = app.stack.isEmpty ? app.section : nil
        VStack(alignment: .leading, spacing: 4) {
            Logo(expanded: expanded)
                .frame(height: 30)

                .padding(.leading, 20).padding(.top, 44).padding(.bottom, 26)
            ForEach(Section.allCases) { s in
                SidebarItem(section: s, selected: current == s, expanded: expanded)
            }
            SidebarItem(label: "Surprise Me", icon: "dice.fill", selected: false, expanded: expanded, help: "Play a random title picked for you") { app.surprise() }
            Spacer()
            ProfileButton(expanded: expanded)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        .frame(width: expanded ? 220 : 76, alignment: .leading)
        .frame(maxHeight: .infinity)
        // Liquid Glass: a floating glass panel inset from the window edges.
        .zSurface(RoundedRectangle(cornerRadius: P.glass ? 26 : 0, style: .continuous), fill: P.background.opacity(0.97))
        .padding(P.glass ? 10 : 0)
        .overlay(alignment: .trailing) { if !P.glass { Rectangle().fill(P.ink.opacity(0.05)).frame(width: 1) } }
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovering = h } }
        .animation(.easeOut(duration: 0.18), value: expanded)
        .zIndex(5)
    }
}

/**
 * One page in the sidebar. The current page keeps its accent icon and bar; whatever the pointer
 * (or keyboard/controller focus) is on only gets a highlight until it's clicked.
 */
private struct SidebarItem: View {
    let label: String
    let icon: String
    let selected: Bool
    let expanded: Bool
    let help: String
    let action: () -> Void
    @State private var hover = false

    init(section: Section, selected: Bool, expanded: Bool) {
        label = section.label; icon = section.icon; self.selected = selected; self.expanded = expanded
        help = "\(section.label)  ⌘\((Section.allCases.firstIndex(of: section) ?? 0) + 1)"
        action = { AppModel.shared.go(section) }
    }

    init(label: String, icon: String, selected: Bool, expanded: Bool, help: String, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.selected = selected; self.expanded = expanded; self.help = help; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.z(size: 17, weight: .semibold)).frame(width: 24)
                    .foregroundStyle(selected ? P.accentText : hover ? P.text : Palette.textSecondary)
                if expanded {
                    Text(label)
                        .font(.z(size: 14.5, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected || hover ? P.text : Palette.textSecondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: P.glass ? 14 : 10, style: .continuous).fill(P.ink.opacity(hover ? (P.glass ? 0.16 : P.light ? 0.08 : 0.12) : selected && expanded ? 0.05 : 0)))
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 2).fill(P.accent).frame(width: 3, height: 18).offset(x: -9)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .zFocus(activate: action, onFocusChange: { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } },
                group: "sidebar", ring: false)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(help)
    }
}

private struct ProfileButton: View {
    let expanded: Bool
    var app = AppModel.shared
    var body: some View {
        let p = app.profiles.profile(app.session.profileId) ?? ProfileStore.defaultProfile
        ZMenu(title: "Profile", items: {
            app.profiles.profiles.map { other in ActionItem(label: other.name, checked: other.id == p.id) { app.switchProfile(other.id) } }
                + [ActionItem(label: "Manage Profiles…", icon: "gearshape") { app.go(.settings) }]
        }, group: "sidebar") { _ in
            HStack(spacing: 12) {
                Avatar(avatar: p.avatar, size: 30, corner: 7)
                if expanded { Text(p.name).font(.z(size: 13.5, weight: .semibold)).lineLimit(1) }
            }
            .padding(.leading, 10)
        }
        .help("Profile: \(p.name)")
    }
}

/** The Zemu logo from the app bundle, or a text version when running unbundled. */
private struct Logo: View {
    let expanded: Bool
    @State private var taps: [Date] = []
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let mark = Bundle.main.image(forResource: "logo_mark")
    static let wordmark = Bundle.main.image(forResource: "logo_wordmark")

    var body: some View {
        mark.contentShape(Rectangle()).onTapGesture(perform: tapped)
    }

    @ViewBuilder private var mark: some View {
        if let img = expanded ? Self.wordmark : Self.mark {
            // Drawn as a template so it takes the theme's accent (and follows RGB/animated themes).
            Image(nsImage: img).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(P.accentText)
                // Collapsed menu: a slow pulsing glow in the same color.
                .shadow(color: expanded ? .clear : P.accent.opacity(glowing ? 0.95 : 0.35), radius: glowing ? 9 : 4)
                .frame(maxWidth: expanded ? 150 : 34, alignment: .leading)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { glowing = true }
                }
        } else {
            Text(expanded ? "ZEMU" : "Z").font(.z(size: 26, weight: .black)).foregroundStyle(P.accentText).tracking(2)
        }
    }

    /** The secret: ten clicks on the logo within a few seconds starts a 30-second Cat Rave. */
    private func tapped() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 4 } + [now]
        guard taps.count >= 10 else { return }
        taps = []
        let app = AppModel.shared
        app.session.store.updateSettings {
            $0.catRaveUnlocked = true
            if $0.dynamicTheme != "CATRAVE" { $0.themeBeforeRave = $0.dynamicTheme }
            $0.dynamicTheme = "CATRAVE"
        }
        app.toast("🐱 Cat Rave!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            app.session.store.updateSettings { if $0.dynamicTheme == "CATRAVE" { $0.dynamicTheme = $0.themeBeforeRave } }
        }
    }
}

/** After a theme change: keep it, or it goes back on its own when the countdown runs out. */
private struct KeepChangesPrompt: View {
    var app = AppModel.shared
    @State private var left = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep changes?").font(.z(size: 18, weight: .bold))
            Text("Going back to your previous theme in \(left) s.").font(.z(size: 13)).foregroundStyle(Palette.textSecondary)
            HStack(spacing: 10) {
                ZButton(title: "Keep", primary: true, preferred: true) { app.keepLook() }
                ZButton(title: "Revert") { app.revertLook() }
            }
        }
        .padding(20)
        .zSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: P.surface)
        .shadow(color: .black.opacity(0.4), radius: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(28)
        .task(id: app.lookChanges) {
            left = 15
            while left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                left -= 1
            }
            app.revertLook()
        }
    }
}
