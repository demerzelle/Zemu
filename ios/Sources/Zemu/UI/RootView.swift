import SwiftUI
import UniformTypeIdentifiers
import ZemuCore

struct RootView: View {
    var app = AppModel.shared
    /** iPhone (and narrow iPad split view): tab bar at the bottom instead of the sidebar. */
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            PageBackground().ignoresSafeArea()
            if app.picking {
                ProfilePicker().disabled(app.parentPrompt != nil)
            } else if !tvOS, sizeClass == .compact {
                VStack(spacing: 0) {
                    content
                    TabBar()
                }
            } else {
                HStack(spacing: 0) {
                    Sidebar().zFocusScope("sidebar").zIndex(5)
                    content.zFocusScope("content")
                }
                .ignoresSafeArea()
                .disabled(tvOverlayOpen)
            }

            if let p = app.player {
                PlayerView(p: p).disabled(app.actionMenu != nil && tvOS).transition(.opacity).zIndex(10)
            }
            #if !os(tvOS)
            if let t = app.trailer {
                TrailerOverlay(request: t).ignoresSafeArea().transition(.opacity).zIndex(11)
            }
            #endif
            if let m = app.actionMenu {
                ActionMenuOverlay(request: m).zIndex(14).transition(.opacity)
            }
            if let prompt = app.parentPrompt {
                ParentCodePad(title: prompt.title, message: "Enter the parent code", onDismiss: { app.parentPrompt = nil }) { code in
                    guard app.profiles.checkParentCode(code) else { return false }
                    app.parentPrompt = nil
                    prompt.unlocked()
                    return true
                }
                .zIndex(15)
            }
            DynamicThemeLayer(theme: DeviceCaps.isLowEnd ? .NONE : DynamicTheme.of(app.settings.dynamicTheme)).ignoresSafeArea().allowsHitTesting(false).zIndex(12)
            VStack { Spacer(); ToastStack() }.zIndex(13)
        }
        .animation(.easeInOut(duration: 0.2), value: app.player != nil)
        .animation(.easeInOut(duration: 0.15), value: app.actionMenu?.id)
        .animation(.easeInOut(duration: 0.2), value: app.trailer)
        .tvScaled()
        #if os(tvOS)
        // Menu goes back; on the top page it's left to the system, which returns to the Home screen.
        .onExitCommand(perform: app.stack.isEmpty ? nil : { app.back() })
        #endif
        .preferredColorScheme(.dark)
        .tint(P.accent)
        .foregroundStyle(.white)
        .sheet(item: Binding(get: { app.configure }, set: { app.configure = $0 })) { ConfigureSheet(request: $0).tvScaled() }
        // Drop an addon link anywhere (iPad) to install it.
        .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
            guard app.player == nil, let item = providers.first else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in app.handleURL(url) } }
            }
            return true
        }
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            page
                .id("\(app.session.profileId)|\(app.section.rawValue)|\(app.stack.count)")
                .transition(.opacity)
            if !app.stack.isEmpty {
                IconButton(icon: "chevron.left", help: "Back", size: 36) { app.back() }
                    .padding(.leading, 16).padding(.top, sizeClass == .compact ? 8 : 34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        #if !os(tvOS)
        // Swipe right from the left edge goes back, like a navigation stack.
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.startLocation.x < 40, v.translation.width > 80, abs(v.translation.height) < 60 { app.back() }
        }, including: app.stack.isEmpty ? .subviews : .all)
        #endif
    }

    /** Focus can't leave an overlay on tvOS unless what's under it is disabled. */
    private var tvOverlayOpen: Bool { tvOS && (app.player != nil || app.actionMenu != nil || app.parentPrompt != nil) }

    @ViewBuilder
    private var page: some View {
        if let r = app.route {
            switch r {
            case let .details(type, id, section, play, seed):
                KidsTitleGate(type: type, id: id) { DetailsView(type: type, id: id, section: section, play: play, seed: seed) }
            case let .person(key): PersonView(key: key)
            }
        } else {
            switch app.section {
            case .home: HomeView()
            case .movies: BrowseView(type: "movie")
            case .series: BrowseView(type: "series")
            case .anime: BrowseView(type: "anime")
            case .search: SearchView()
            case .mylist: MyListView()
            case .addons: ParentLock { AddonsView() }
            case .settings: ParentLock { SettingsView() }
            }
        }
    }
}

/** iPhone: every page as an icon along the bottom. */
private struct TabBar: View {
    var app = AppModel.shared

    var body: some View {
        let current = app.stack.isEmpty ? app.section : nil
        if P.style == .solid { bar(current) } else { floatingBar(current) }
    }

    /** Glass and chrome: a floating capsule over the content, like the iOS 26 tab bar. */
    private func floatingBar(_ current: Section?) -> some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases) { s in
                Button { app.go(s) } label: {
                    Image(systemName: s.icon).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(current == s ? (P.style == .chrome ? P.onAccent : P.accent) : .white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if current == s { Capsule().fill(P.style == .chrome ? AnyShapeStyle(LinearGradient(colors: [.white, Color(argb: 0xFFB9BEC6)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.16))).padding(.horizontal, 2).padding(.vertical, 4) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.zemu)
                .accessibilityLabel(s.label)
                .accessibilityAddTraits(current == s ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .zSurface(Capsule(), fill: P.surface, interactive: false)
        .padding(.horizontal, 12).padding(.bottom, 2).padding(.top, 6)
    }

    private func bar(_ current: Section?) -> some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases) { s in
                Button { app.go(s) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: s.icon).font(.system(size: 18, weight: .semibold))
                        Text(s.label).font(.system(size: 9.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(current == s ? P.accent : Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.zemu)
                .accessibilityLabel(s.label)
                .accessibilityAddTraits(current == s ? .isSelected : [])
            }
        }
        .padding(.top, 6)
        .background(P.background.opacity(0.97).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}

/** The left menu (iPad): icons, expanding with labels while the pointer is over it. */
private struct Sidebar: View {
    var app = AppModel.shared
    @State private var hovering = false

    /** Which item has remote focus; the sidebar opens over the page while one does. */
    @State private var focused: String?
    private var expanded: Bool { hovering || focused != nil }

    private func focusChanged(_ label: String, _ on: Bool) {
        // No animation: focus aims at frames mid-flight otherwise, and quick presses land on the page.
        if on { focused = label } else if focused == label { focused = nil }
    }

    var body: some View {
        let current = app.stack.isEmpty ? app.section : nil
        VStack(alignment: .leading, spacing: 4) {
            Logo(expanded: expanded && !tvOS)
                .frame(height: 30)
                .padding(.leading, 20).padding(.top, 44).padding(.bottom, 26)
            ForEach(Section.allCases) { s in
                SidebarItem(icon: s.icon, label: s.label, selected: current == s, expanded: expanded, onFocus: { focusChanged(s.label, $0) }) { app.go(s) }
            }
            SidebarItem(icon: "dice.fill", label: "Surprise me", selected: false, expanded: expanded, onFocus: { focusChanged("Surprise me", $0) }) { app.surprise() }
            Spacer()
            ProfileButton(expanded: expanded && !tvOS)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        // On TV the focusable part never widens (wide buttons overlap the page's posters and
        // pull focus onto them), so only the panel and labels behind it grow.
        .frame(width: expanded && !tvOS ? 220 : 76, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(alignment: .leading) {
            (P.style == .solid ? AnyShapeStyle(P.background.opacity(0.97)) : AnyShapeStyle(.ultraThinMaterial))
                .asRectangle()
                .frame(width: expanded ? 220 : 76)
                .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1) }
                .allowsHitTesting(false)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovering = h } }
        .animation(tvOS ? nil : .easeOut(duration: 0.18), value: expanded)
    }
}

/**
 * One page in the sidebar. The current page keeps its accent icon and bar; whatever the pointer
 * (or keyboard/controller focus) is on only gets a highlight until it's clicked.
 */
private struct SidebarItem: View {
    let icon: String
    let label: String
    let selected: Bool
    let expanded: Bool
    var onFocus: (Bool) -> Void = { _ in }
    let action: () -> Void
    @State private var hover = false

    /** The icon sets the button's size; the highlight and label are drawn past it without affecting focus. */
    private var tvLabel: some View {
        Image(systemName: icon).font(.system(size: 17, weight: .semibold)).frame(width: 24, height: 24)
            .foregroundStyle(selected ? P.accent : hover ? .white : Palette.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hover ? 0.12 : selected && expanded ? 0.05 : 0))
                    .frame(width: expanded ? 196 : 52)
            }
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    if selected { RoundedRectangle(cornerRadius: 2).fill(P.accent).frame(width: 3, height: 18).offset(x: -9) }
                    if expanded {
                        Text(label).font(.system(size: 14.5, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected || hover ? .white : Palette.textSecondary)
                            .lineLimit(1).fixedSize().offset(x: 52)
                    }
                }
            }
    }

    var body: some View {
        Button(action: action) {
            if tvOS { tvLabel } else { HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).frame(width: 24)
                    .foregroundStyle(selected ? P.accent : hover ? .white : Palette.textSecondary)
                if expanded {
                    Text(label)
                        .font(.system(size: 14.5, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? .white : hover ? .white : Palette.textSecondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hover ? 0.12 : selected && expanded ? 0.05 : 0)))
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 2).fill(P.accent).frame(width: 3, height: 18).offset(x: -9)
                }
            }
            .contentShape(Rectangle())
            }
        }
        .buttonStyle(.zemu)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .zFocus(activate: action, onFocusChange: { h in withAnimation(.easeOut(duration: 0.12)) { hover = h }; onFocus(h) },
                group: "sidebar", ring: false)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(label)
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
                if expanded { Text(p.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1) }
            }
            .padding(.leading, 10)
        }
        .help("Profile: \(p.name)")
    }
}

extension AnyShapeStyle {
    func asRectangle() -> some View { Rectangle().fill(self) }
}

/** The Zemu logo from the app bundle, or a text version when running unbundled. */
private struct Logo: View {
    let expanded: Bool
    static let mark = Bundle.main.image(forResource: "logo_mark")
    static let wordmark = Bundle.main.image(forResource: "logo_wordmark")

    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if expanded, let img = Self.wordmark {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 150, alignment: .leading)
        } else if !expanded, let img = Self.mark {
            // White mark tinted with the theme's accent, with a slow pulsing glow in the same color.
            Image(nsImage: img).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(P.accent)
                .shadow(color: P.accent.opacity(glowing ? 0.95 : 0.35), radius: glowing ? 9 : 4)
                .frame(maxWidth: 34, alignment: .leading)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { glowing = true }
                }
        } else {
            Text(expanded ? "ZEMU" : "Z").font(.system(size: 26, weight: .black)).foregroundStyle(P.accent).tracking(2)
        }
    }
}
