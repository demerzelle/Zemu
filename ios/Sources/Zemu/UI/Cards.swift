import SwiftUI
import ZemuCore

/** Poster (2:3) with hover zoom, IMDb rating, an optional badge ("98%", "3 NEW") and a watched mark. */
struct PosterCard: View {
    let meta: Meta
    var width: CGFloat = 150
    var badge: String?
    var onHover: ((Meta) -> Void)?
    /** Called before the title opens (e.g. Search remembers what you picked). */
    var onSelect: ((Meta) -> Void)?
    var app = AppModel.shared

    @State private var hover = false

    private func select() {
        onSelect?(meta)
        app.open(meta)
    }

    var body: some View {
        let watched = app.session.store.watched.contains(meta.id)
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(P.surface)
                    Text(meta.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.center).padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    RemoteImage(url: meta.posterUrl, maxPixel: 420)
                    if let badge {
                        Text(badge).font(.system(size: 10.5, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .foregroundStyle(badge.hasSuffix("NEW") ? P.onAccent : Palette.match)
                            .background(RoundedRectangle(cornerRadius: 4).fill(badge.hasSuffix("NEW") ? P.accent : Color.black.opacity(0.72)))
                            .padding(6)
                    }
                    if watched {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                            .foregroundStyle(.white, P.accent)
                            .frame(maxWidth: .infinity, alignment: .trailing).padding(6)
                    }
                    if let r = meta.rating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Palette.imdb)
                            Text(String(format: "%.1f", r)).font(.system(size: 10.5, weight: .bold))
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.7)))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(hover ? 0.9 : 0), lineWidth: 2))
                .scaleEffect(hover ? 1.06 : 1)
                .shadow(color: .black.opacity(hover ? 0.5 : 0), radius: 12, y: 6)

                Text(meta.title).font(.system(size: 12.5, weight: .medium)).marquee()
                    .foregroundStyle(hover ? .white : Palette.textSecondary)
                    .frame(width: width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hover = h }
            if h { onHover?(meta) }
        }
        .zFocus(activate: select, secondary: { app.showCardMenu(meta) }, onFocusChange: { h in
            withAnimation(.easeOut(duration: 0.15)) { hover = h }
            if h { onHover?(meta) }
        }, ring: false)
        .contextMenu { CardMenu(meta: meta) }
        .help(meta.title)
    }
}

/** 16:9 card with a progress bar, for Continue Watching and new episodes. */
struct LandscapeCard: View {
    let meta: Meta
    var subtitle: String?
    var progress: Double?
    var width: CGFloat = 280
    var onHover: ((Meta) -> Void)?
    /** Resume playback directly instead of opening the page. */
    var resume: WatchEntry?
    var app = AppModel.shared

    @State private var hover = false

    var body: some View {
        Button {
            if let resume { app.resume(resume) } else { app.open(meta) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(P.surface)
                    RemoteImage(url: meta.backdropUrl, maxPixel: 640)
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta.title).font(.system(size: 14, weight: .bold)).marquee()
                        if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary).marquee() }
                    }
                    .padding(10)
                    .padding(.bottom, progress != nil ? 6 : 0)
                    if let progress {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.25))
                                Rectangle().fill(P.accent).frame(width: g.size.width * max(0.02, min(1, progress)))
                            }
                        }
                        .frame(height: 4)
                    }
                    if hover && resume != nil {
                        Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: width, height: width * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(hover ? 0.9 : 0), lineWidth: 2))
                .scaleEffect(hover ? 1.04 : 1)
                .shadow(color: .black.opacity(hover ? 0.5 : 0), radius: 12, y: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hover = h }
            if h { onHover?(meta) }
        }
        .zFocus(activate: { if let resume { app.resume(resume) } else { app.open(meta) } },
                secondary: { app.showCardMenu(meta) },
                onFocusChange: { h in
                    withAnimation(.easeOut(duration: 0.15)) { hover = h }
                    if h { onHover?(meta) }
                }, ring: false)
        .contextMenu {
            if resume != nil { Button("Resume") { app.resume(resume!) } }
            CardMenu(meta: meta)
        }
    }
}

/**
 * A titled horizontal row. Scrolls with the trackpad/wheel, and shows ‹ › page buttons on hover.
 */
struct MediaRow<Item: Hashable, Content: View>: View {
    let title: String
    let items: [Item]
    var spacing: CGFloat = 14
    var trailing: AnyView?
    /** Called with the leftmost item when the row is scrolled (the hero follows it). */
    var onLead: ((Item) -> Void)?
    @ViewBuilder let content: (Item) -> Content

    @State private var hover = false
    @State private var scrollTo: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: title)
                if let trailing { trailing }
                Spacer()
            }
            .padding(.horizontal, pagePad)
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(items.enumerated()), id: \.element) { i, item in
                            content(item).id(i)
                        }
                    }
                    .padding(.horizontal, pagePad)
                    .padding(.vertical, 12)
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrollTo, anchor: .leading)
                if hover && items.count > 4 {
                    HStack {
                        pageButton("chevron.left") { page(-1) }
                        Spacer()
                        pageButton("chevron.right") { page(1) }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .onHover { hover = $0 }
        .onChange(of: scrollTo) { _, i in
            if let i, items.indices.contains(i) { onLead?(items[i]) }
        }
    }

    private func page(_ dir: Int) {
        let cur = scrollTo ?? 0
        withAnimation(.easeInOut(duration: 0.35)) { scrollTo = max(0, min(items.count - 1, cur + dir * 5)) }
    }

    private func pageButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold))
                .frame(width: 36, height: 64)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.65)))
        }
        .buttonStyle(.plain)
    }
}

/** Poster grid that fills the width and reports when it nears the end (for paging). */
struct PosterGrid<Header: View>: View {
    let items: [Meta]
    var minWidth: CGFloat = 150
    var onNearEnd: (() -> Void)?
    var onHover: ((Meta) -> Void)?
    var badges: [String: String] = [:]
    /** Called with the top-left title as the grid scrolls (the hero follows it). */
    var onLead: ((Meta) -> Void)?
    @ViewBuilder var header: () -> Header
    @State private var lead: String?

    var body: some View {
        ScrollView {
            header()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth, maximum: minWidth + 40), spacing: 18, alignment: .top)], alignment: .leading, spacing: 22) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                    PosterCard(meta: m, width: minWidth, badge: badges[m.id], onHover: onHover)
                        .onAppear { if i >= items.count - 14 { onNearEnd?() } }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, pagePad)
            .padding(.vertical, 12)
            .padding(.bottom, 40)
        }
        .scrollPosition(id: $lead, anchor: .topLeading)
        .onChange(of: lead) { _, id in
            if let m = items.first(where: { $0.id == id }) { onLead?(m) }
        }
    }
}

extension PosterGrid where Header == EmptyView {
    init(items: [Meta], minWidth: CGFloat = 150, onNearEnd: (() -> Void)? = nil, onHover: ((Meta) -> Void)? = nil, badges: [String: String] = [:], onLead: ((Meta) -> Void)? = nil) {
        self.items = items; self.minWidth = minWidth; self.onNearEnd = onNearEnd; self.onHover = onHover; self.badges = badges; self.onLead = onLead
        self.header = { EmptyView() }
    }
}
