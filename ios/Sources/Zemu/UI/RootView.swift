import SwiftUI
import UniformTypeIdentifiers
import ZemuCore

struct RootView: View {
    var app = AppModel.shared
    /** iPhone (and narrow iPad split view): tab bar at the bottom instead of the sidebar. */
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            P.background.ignoresSafeArea()
            if app.picking {
                ProfilePicker()
            } else if sizeClass == .compact {
                VStack(spacing: 0) {
                    content
                    TabBar()
                }
            } else {
                HStack(spacing: 0) {
                    Sidebar()
                    content
                }
                .ignoresSafeArea()
            }

            if let p = app.player {
                PlayerView(p: p).transition(.opacity).zIndex(10)
            }
            if let t = app.trailer {
                TrailerOverlay(request: t).ignoresSafeArea().transition(.opacity).zIndex(11)
            }
            if let m = app.actionMenu {
                ActionMenuOverlay(request: m).zIndex(14).transition(.opacity)
            }
            DynamicThemeLayer(theme: DynamicTheme.of(app.settings.dynamicTheme)).ignoresSafeArea().allowsHitTesting(false).zIndex(12)
            VStack { Spacer(); ToastStack() }.zIndex(13)
        }
        .animation(.easeInOut(duration: 0.2), value: app.player != nil)
        .animation(.easeInOut(duration: 0.15), value: app.actionMenu?.id)
        .animation(.easeInOut(duration: 0.2), value: app.trailer)
        .preferredColorScheme(.dark)
        .tint(P.accent)
        .foregroundStyle(.white)
        .sheet(item: Binding(get: { app.configure }, set: { app.configure = $0 })) { ConfigureSheet(request: $0) }
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
        // Swipe right from the left edge goes back, like a navigation stack.
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.startLocation.x < 40, v.translation.width > 80, abs(v.translation.height) < 60 { app.back() }
        }, including: app.stack.isEmpty ? .subviews : .all)
    }

    @ViewBuilder
    private var page: some View {
        if let r = app.route {
            switch r {
            case let .details(type, id, section, play, seed): DetailsView(type: type, id: id, section: section, play: play, seed: seed)
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
            case .addons: AddonsView()
            case .settings: SettingsView()
            }
        }
    }
}

/** iPhone: every page as an icon along the bottom. */
private struct TabBar: View {
    var app = AppModel.shared

    var body: some View {
        let current = app.stack.isEmpty ? app.section : nil
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
                .buttonStyle(.plain)
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

    private var expanded: Bool { hovering }

    var body: some View {
        let current = app.stack.isEmpty ? app.section : nil
        VStack(alignment: .leading, spacing: 4) {
            Logo(expanded: expanded)
                .frame(height: 30)
                .padding(.leading, 20).padding(.top, 44).padding(.bottom, 26)
            ForEach(Section.allCases) { s in
                SidebarItem(section: s, selected: current == s, expanded: expanded)
            }
            Spacer()
            ProfileButton(expanded: expanded)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        .frame(width: expanded ? 220 : 76, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(P.background.opacity(0.97))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1) }
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
    let section: Section
    let selected: Bool
    let expanded: Bool
    var app = AppModel.shared
    @State private var hover = false

    var body: some View {
        Button { app.go(section) } label: {
            HStack(spacing: 14) {
                Image(systemName: section.icon).font(.system(size: 17, weight: .semibold)).frame(width: 24)
                    .foregroundStyle(selected ? P.accent : hover ? .white : Palette.textSecondary)
                if expanded {
                    Text(section.label)
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
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .zFocus(activate: { app.go(section) }, onFocusChange: { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } },
                group: "sidebar", ring: false)
        .accessibilityLabel(section.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(section.label)
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

/** The Zemu logo from the app bundle, or a text version when running unbundled. */
private struct Logo: View {
    let expanded: Bool
    static let mark = Bundle.main.image(forResource: "logo_mark")
    static let wordmark = Bundle.main.image(forResource: "logo_wordmark")

    var body: some View {
        if let img = expanded ? Self.wordmark : Self.mark {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: expanded ? 150 : 34, alignment: .leading)
        } else {
            Text(expanded ? "ZEMU" : "Z").font(.system(size: 26, weight: .black)).foregroundStyle(P.accent).tracking(2)
        }
    }
}
