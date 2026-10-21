import SwiftUI
import ZemuCore

/** Rounded pill button. Primary uses the accent color. */
struct ZButton: View {
    let title: String
    var icon: String?
    var primary = false
    var small = false
    /** Gets keyboard/gamepad focus first. */
    var preferred = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.z(size: small ? 11 : 13, weight: .bold)) }
                Text(title).font(.z(size: small ? 12 : 14, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, small ? 12 : 18)
            .padding(.vertical, small ? 6 : 9)
            .foregroundStyle(primary ? P.onAccent : .white)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(primary ? P.accent.opacity(hover ? 0.85 : 1) : Color.white.opacity(hover ? 0.24 : 0.14))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .zFocus(activate: action, onFocusChange: { hover = $0 }, preferred: preferred, cornerRadius: 8)
        .scaleEffect(hover ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/** Round icon button with a tooltip. */
struct IconButton: View {
    let icon: String
    let help: String
    var active = false
    var size: CGFloat = 38
    var preferred = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.z(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(active ? P.onAccent : .white)
                .background(Circle().fill(active ? P.accent.opacity(0.9) : Color.white.opacity(hover ? 0.26 : 0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
        .zFocus(activate: action, onFocusChange: { hover = $0 }, preferred: preferred, cornerRadius: size / 2)
        .scaleEffect(hover ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/** Toggleable filter chip. */
struct Chip: View {
    let title: String
    var selected = false
    var icon: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.z(size: 10, weight: .bold)) }
                Text(title).font(.z(size: 12.5, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? P.onAccent : .white)
            .background(Capsule().fill(selected ? P.accent : Color.white.opacity(hover ? 0.2 : 0.1)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .zFocus(activate: action, onFocusChange: { hover = $0 }, cornerRadius: 14)
    }
}

/**
 * A dropdown. The mouse gets the native menu; keyboard and gamepad get the same items as an
 * in-app menu (native menus can't be driven by a controller).
 */
struct ZMenu<MenuLabel: View>: View {
    let title: String
    let items: () -> [ActionItem]
    var preferred = false
    var group: String?
    @ViewBuilder let label: (Bool) -> MenuLabel
    var app = AppModel.shared
    @State private var lit = false

    var body: some View {
        Menu {
            ForEach(items()) { item in
                Button { item.action() } label: {
                    if item.checked == true { Label(item.label, systemImage: "checkmark") }
                    else if let icon = item.icon { Label(item.label, systemImage: icon) }
                    else { Text(item.label) }
                }
            }
        } label: { label(lit) }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { lit = $0 }
            .zFocus(activate: { app.showMenu(title, items) }, onFocusChange: { lit = $0 }, group: group, preferred: preferred, cornerRadius: 14)
    }
}

/** A chip that opens a menu (single choice). */
struct MenuChip: View {
    let title: String
    var selected = false
    /** Menu heading for keyboard/gamepad; defaults to the chip title. */
    var heading: String?
    let items: () -> [ActionItem]

    var body: some View {
        ZMenu(title: heading ?? title, items: items) { lit in
            HStack(spacing: 4) {
                Text(title).font(.z(size: 12.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                Image(systemName: "chevron.down").font(.z(size: 9, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? P.onAccent : .white)
            .background(Capsule().fill(selected ? P.accent : Color.white.opacity(lit ? 0.2 : 0.1)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.12)))
        }
    }
}

/** Single-choice items with a checkmark on the current one. */
func choiceItems<T: Equatable>(_ options: [(T, String)], current: T, pick: @escaping (T) -> Void) -> [ActionItem] {
    options.map { v, label in ActionItem(label: label, checked: v == current) { pick(v) } }
}

struct Tag: View {
    let text: String
    var color: Color = Palette.textSecondary
    var filled = false

    var body: some View {
        Text(text)
            .font(.z(size: 10.5, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(filled ? .black : color)
            .background(RoundedRectangle(cornerRadius: 4).fill(filled ? color : .clear))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(filled ? 0 : 0.8), lineWidth: 1))
    }
}

struct ImdbBadge: View {
    let rating: String?
    var body: some View {
        if let r = rating, let v = Double(r), v > 0 {
            HStack(spacing: 4) {
                Text("IMDb").font(.z(size: 9.5, weight: .black)).foregroundStyle(.black)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Palette.imdb))
                Text(String(format: "%.1f", v)).font(.z(size: 13, weight: .bold))
            }
        }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View { Text(text).font(.z(size: 19, weight: .bold)) }
}

struct CenteredMessage<Action: View>: View {
    let title: String
    var message: String?
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.z(size: 20, weight: .bold))
            if let message { Text(message).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 520) }
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

extension CenteredMessage where Action == EmptyView {
    init(_ title: String, _ message: String? = nil) {
        self.title = title
        self.message = message
        self.action = { EmptyView() }
    }
}

struct MetaLine: View {
    let meta: Meta
    var matchPercent: Int?
    @State private var cert: String?
    @State private var scores: TitleScores?

    var body: some View {
        HStack(spacing: 12) {
            if let m = matchPercent { Text("\(m)% Match").foregroundStyle(Palette.match).font(.z(size: 14, weight: .bold)) }
            if let r = meta.releaseInfo?.nilIfBlank { Text(r).foregroundStyle(Palette.textSecondary) }
            if let r = meta.runtimeLabel { Text(r).foregroundStyle(Palette.textSecondary) }
            if let c = scores?.rated ?? cert { RatingBadge(cert: c) }
            Tag(text: meta.type == "series" ? "SERIES" : "MOVIE")
            ImdbBadge(rating: meta.imdbRating)
            if let rt = scores?.rottenTomatoes {
                // Fresh (60%+) gets the red tomato, rotten the green splat, like the real site.
                Text((rt >= 60 ? "🍅 " : "🤢 ") + "\(rt)%").font(.z(size: 13, weight: .bold))
            }
            if let mc = scores?.metacritic { MetacriticBadge(score: mc) }
        }
        .font(.z(size: 14))
        // The US rating and critic scores load after the line shows (both are remembered).
        .task(id: meta.id) {
            let s = AppModel.shared.session
            cert = nil; scores = nil
            scores = await s.scores.of(meta.imdbId)
            cert = await s.kids.certification(meta)
        }
    }
}

/**
 * A US rating badge, drawn the way it appears on screen: movie ratings as a black-outlined white
 * box with bold black letters, TV ratings as a white-outlined black box.
 */
struct RatingBadge: View {
    let cert: String
    var body: some View {
        let tv = cert.hasPrefix("TV-")
        Text(cert)
            .font(.z(size: 12, weight: .black)).tracking(0.5)
            .foregroundStyle(tv ? .white : .black)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: tv ? 4 : 1).fill(tv ? .black : .white))
            .overlay(RoundedRectangle(cornerRadius: tv ? 4 : 1).strokeBorder(tv ? .white : .black, lineWidth: tv ? 1.5 : 2))
    }
}

/** Metacritic's colored square: green 61+, yellow 40–60, red below 40. */
struct MetacriticBadge: View {
    let score: Int
    var body: some View {
        let color: Color = score >= 61 ? Color(red: 0.4, green: 0.8, blue: 0.2) : score >= 40 ? Color(red: 1, green: 0.8, blue: 0.2) : .red
        Text("\(score)").font(.z(size: 12, weight: .black))
            .foregroundStyle((40...60).contains(score) ? .black : .white)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 3).fill(color))
    }
}

extension Meta {
    /** The trailer to offer, unless trailers are switched off in Settings. */
    @MainActor var playableTrailer: String? { AppModel.shared.settings.trailers ? trailerId : nil }
}

/** The title's logo image, or its name in big type when there's none. */
struct TitleLogo: View {
    let meta: Meta
    var maxHeight: CGFloat = 110
    var maxWidth: CGFloat = 440
    @State private var failed: String?
    @State private var fallback: (id: String, url: String?)?
    @State private var fallbackFailed: String?

    /** The addon's logo, else fanart.tv's or TMDB's; plain text only when none exists or logos are off. */
    private var logo: String? {
        guard AppModel.shared.settings.logoArt else { return nil }
        if failed != meta.id, let l = meta.logoUrl { return l }
        guard fallbackFailed != meta.id, let f = fallback, f.id == meta.id else { return nil }
        return f.url
    }

    var body: some View {
        content.task(id: "\(meta.id)|\(failed == meta.id)") {
            guard AppModel.shared.settings.logoArt, failed == meta.id || meta.logoUrl == nil else { return }
            let url = await AppModel.shared.session.artwork.logo(meta)
            fallback = (meta.id, url)
        }
    }

    @ViewBuilder private var content: some View {
        if let logo {
            RemoteImage(url: logo, maxPixel: 900, contentMode: .fit, alignment: .bottomLeading) {
                if logo == meta.logoUrl, failed != meta.id { failed = meta.id } else { fallbackFailed = meta.id }
            }
                .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .bottomLeading)
                .frame(height: maxHeight, alignment: .bottomLeading)
        } else {
            Text(meta.title)
                .font(.z(size: maxHeight > 90 ? 44 : 34, weight: .black))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: maxWidth * 1.3, alignment: .leading)
        }
    }
}

/** Long text in a fixed-height box that scrolls (with the wheel/trackpad) when it overflows. */
struct ScrollingText: View {
    let text: String
    var maxHeight: CGFloat = 80
    var font: Font = .z(size: 14)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text).font(font).foregroundStyle(Color.white.opacity(0.88)).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/** The options for a title (Android's long-press menu): right-click, O key or Ⓧ. */
@MainActor
func cardMenuItems(_ meta: Meta) -> [ActionItem] {
    let app = AppModel.shared
    let s = app.session.store
    var items: [ActionItem] = [
        ActionItem(label: "Open Details", icon: "info.circle") { app.openDetails(meta) },
        ActionItem(label: "Play", icon: "play.fill") { app.openDetails(meta, play: true) },
    ]
    if meta.type == "series" { items.append(ActionItem(label: "Episodes", icon: "list.number") { app.openDetails(meta, section: "episodes") }) }
    if let t = meta.playableTrailer { items.append(ActionItem(label: "Watch Trailer", icon: "film") { app.playTrailer(t, queue: meta.officialTrailers) }) }
    items.append(ActionItem(label: s.isInMyList(meta.id) ? "Remove from My List" : "Add to My List", icon: s.isInMyList(meta.id) ? "heart.slash" : "heart") { app.toggleMyList(meta) })
    let watched = s.watched.contains(meta.id)
    items.append(ActionItem(label: watched ? "Mark as Unwatched" : "Mark as Watched", icon: watched ? "eye.slash" : "checkmark.circle") { app.setWatched(meta, !watched) })
    if s.history.contains(where: { $0.meta.id == meta.id }) {
        items.append(ActionItem(label: "Remove from History", icon: "clock.arrow.circlepath") { app.removeFromHistory(meta) })
    }
    items.append(ActionItem(label: "Copy Link", icon: "link") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("zemu://details/\(meta.type)/\(meta.id)", forType: .string)
    })
    if meta.isImdb {
        items.append(ActionItem(label: "Open on IMDb", icon: "safari") { NSWorkspace.shared.open(URL(string: "https://www.imdb.com/title/\(meta.imdbId)/")!) })
    }
    return items
}

/** Right-click menu for any title. */
struct CardMenu: View {
    let meta: Meta
    var body: some View {
        ForEach(cardMenuItems(meta)) { item in Button(item.label, action: item.action) }
    }
}

/** Toast messages at the bottom of the window. */
struct ToastStack: View {
    var app = AppModel.shared
    var body: some View {
        VStack(spacing: 8) {
            ForEach(app.toasts) { t in
                Text(t.text)
                    .font(.z(size: 13, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.1)))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 24)
        .frame(maxWidth: 640)
        .allowsHitTesting(false)
    }
}

/** Lays children out left to right, wrapping onto new lines when the width runs out. */
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            lineH = max(lineH, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y + (lineH > 0 ? 0 : 0)), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
