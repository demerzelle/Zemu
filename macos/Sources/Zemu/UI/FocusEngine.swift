import SwiftUI
import AppKit

/**
 * Spatial focus for keyboard and gamepad (macOS has no arrow-key focus like tvOS/Android TV).
 *
 * Every interactive element adds `.zFocus(...)`, which places an invisible anchor view behind it.
 * The engine finds anchors by their on-screen frames, moves focus to the nearest one in the
 * pressed direction, scrolls it into view (`scrollToVisible` scrolls every enclosing scroll view)
 * and activates it. Elements only take part when they're in the active scope (main UI, player,
 * menu, on-screen keyboard) and in the window that has the user's attention.
 */
enum MoveDirection { case up, down, left, right }

@MainActor @Observable
final class FocusToken {
    var isFocused = false
    @ObservationIgnored weak var anchor: NSView?
    @ObservationIgnored var activate: (() -> Void)?
    @ObservationIgnored var secondary: (() -> Void)?
    @ObservationIgnored var onFocusChange: ((Bool) -> Void)?
    /** Lets an element handle a direction itself (e.g. the seek bar scrubs on left/right). */
    @ObservationIgnored var onMove: ((MoveDirection) -> Bool)?
    @ObservationIgnored var scope = "main"
    @ObservationIgnored var group: String?
    /** Gets focus first when nothing in the scope is focused. */
    @ObservationIgnored var preferred = false
    /** Text fields: what the on-screen keyboard edits when activated from a gamepad. */
    @ObservationIgnored var text: Binding<String>?
    @ObservationIgnored var textTitle = ""
    @ObservationIgnored var onSubmit: (() -> Void)?
}

struct FocusScopeKey: EnvironmentKey { static let defaultValue = "main" }
extension EnvironmentValues {
    var zFocusScope: String {
        get { self[FocusScopeKey.self] }
        set { self[FocusScopeKey.self] = newValue }
    }
}

/** Invisible view behind a focusable element; registers it while it's in a window. */
final class FocusAnchorView: NSView {
    weak var token: FocusToken?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let token else { return }
        MainActor.assumeIsolated {
            if window != nil { FocusEngine.shared.register(token) } else { FocusEngine.shared.unregister(token) }
        }
    }
}

private struct FocusAnchor: NSViewRepresentable {
    let token: FocusToken
    func makeNSView(context: Context) -> FocusAnchorView {
        let v = FocusAnchorView()
        v.token = token
        token.anchor = v
        return v
    }
    func updateNSView(_ v: FocusAnchorView, context: Context) {
        v.token = token
        token.anchor = v
    }
}

struct ZFocusModifier: ViewModifier {
    var activate: (() -> Void)?
    var secondary: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onMove: ((MoveDirection) -> Bool)?
    var group: String?
    var preferred = false
    var ring = true
    var cornerRadius: CGFloat = 8
    var text: Binding<String>?
    var textTitle = ""
    var onSubmit: (() -> Void)?

    @State private var token = FocusToken()
    @Environment(\.zFocusScope) private var scope

    func body(content: Content) -> some View {
        token.activate = activate
        token.secondary = secondary
        token.onFocusChange = onFocusChange
        token.onMove = onMove
        token.scope = scope
        token.group = group
        token.preferred = preferred
        token.text = text
        token.textTitle = textTitle
        token.onSubmit = onSubmit
        return content
            .background(FocusAnchor(token: token))
            .overlay {
                if ring && token.isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 3)
                        .padding(-4)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /**
     * Makes this element reachable with arrow keys and a gamepad. [activate] runs on Return / A,
     * [secondary] on O / X (options menu). Set [ring] false when the element shows its own
     * highlight through [onFocusChange].
     */
    func zFocus(
        activate: (() -> Void)?,
        secondary: (() -> Void)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil,
        onMove: ((MoveDirection) -> Bool)? = nil,
        group: String? = nil,
        preferred: Bool = false,
        ring: Bool = true,
        cornerRadius: CGFloat = 8
    ) -> some View {
        modifier(ZFocusModifier(activate: activate, secondary: secondary, onFocusChange: onFocusChange, onMove: onMove,
                                group: group, preferred: preferred, ring: ring, cornerRadius: cornerRadius))
    }

    /** A text field: Return focuses it for typing; a gamepad opens the on-screen keyboard. */
    func zFocusText(_ text: Binding<String>, title: String, focus: @escaping () -> Void, onSubmit: (() -> Void)? = nil, preferred: Bool = false) -> some View {
        modifier(ZFocusModifier(activate: focus, preferred: preferred, cornerRadius: 10, text: text, textTitle: title, onSubmit: onSubmit))
    }

    func zFocusScope(_ scope: String) -> some View { environment(\.zFocusScope, scope) }
}

@MainActor @Observable
final class FocusEngine {
    static let shared = FocusEngine()

    private(set) var focused: FocusToken?
    @ObservationIgnored private var tokens: [ObjectIdentifier: FocusToken] = [:]
    /** Last focus per scope, so leaving a menu or the player returns to where you were. */
    @ObservationIgnored private var remembered: [String: FocusToken] = [:]

    var focusedGroup: String? { focused?.group }

    func register(_ t: FocusToken) { tokens[ObjectIdentifier(t)] = t }

    func unregister(_ t: FocusToken) {
        tokens[ObjectIdentifier(t)] = nil
        if focused === t { focused = nil }
    }

    func clear() {
        if let f = focused { remembered[f.scope] = f }
        set(nil)
    }

    func set(_ t: FocusToken?, scroll: Bool = true) {
        guard focused !== t else { return }
        let old = focused
        old?.isFocused = false
        old?.onFocusChange?(false)
        focused = t
        guard let t else { return }
        t.isFocused = true
        t.onFocusChange?(true)
        remembered[t.scope] = t
        if scroll, let a = t.anchor { scrollIntoView(a) }
    }

    /**
     * Scrolls every enclosing scroll view (row, then page) just enough to show [view] with room
     * around it for neighbors and row titles. SwiftUI's scroll views ignore `scrollToVisible`, so
     * their clip views are moved directly.
     */
    private func scrollIntoView(_ view: NSView) {
        var sv = view.enclosingScrollView
        while let s = sv {
            let clip = s.contentView
            if let doc = s.documentView {
                let r = view.convert(view.bounds, to: clip)
                let vis = clip.bounds
                let mx: CGFloat = min(80, max(0, (vis.width - r.width) / 2))
                let my: CGFloat = min(110, max(0, (vis.height - r.height) / 2))
                var o = vis.origin
                if r.minX - mx < vis.minX { o.x = r.minX - mx } else if r.maxX + mx > vis.maxX { o.x = r.maxX + mx - vis.width }
                if r.minY - my < vis.minY { o.y = r.minY - my } else if r.maxY + my > vis.maxY { o.y = r.maxY + my - vis.height }
                let d = doc.frame
                o.x = max(d.minX, min(o.x, d.maxX - vis.width))
                o.y = max(d.minY, min(o.y, d.maxY - vis.height))
                if abs(o.x - vis.origin.x) > 0.5 || abs(o.y - vis.origin.y) > 0.5 {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.22
                        ctx.allowsImplicitAnimation = true
                        clip.animator().setBoundsOrigin(o)
                    } completionHandler: {
                        s.reflectScrolledClipView(clip)
                    }
                }
            }
            sv = s.enclosingScrollView
        }
    }

    // MARK: Candidates

    /** The window input goes to: an attached sheet, else the key window (never the PiP panel). */
    var targetWindow: NSWindow? {
        let main = PlayerWindow.host
        if let sheet = main?.attachedSheet { return sheet }
        if let key = NSApp.keyWindow, !(key is PiPPanel) { return key }
        return main
    }

    private func isUsable(_ t: FocusToken, scope: String, window: NSWindow?) -> Bool {
        guard let a = t.anchor, let w = a.window, w === window, t.scope == scope, !a.isHiddenOrHasHiddenAncestor else { return false }
        return a.bounds.width > 0 && a.bounds.height > 0
    }

    private func frame(_ t: FocusToken) -> CGRect {
        guard let a = t.anchor else { return .zero }
        // Window coordinates (origin bottom-left), turned into top-left so "down" means larger y.
        let r = a.convert(a.bounds, to: nil)
        let h = a.window?.contentView?.bounds.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    private func isVisible(_ t: FocusToken) -> Bool { !(t.anchor?.visibleRect.isEmpty ?? true) }

    private func candidates(scope: String) -> [FocusToken] {
        let w = targetWindow
        return tokens.values.filter { isUsable($0, scope: scope, window: w) }
    }

    // MARK: Moving

    /** Focuses the scope's preferred element, else the top-left one (outside the sidebar). */
    @discardableResult
    func focusInitial(scope: String) -> Bool {
        if let r = remembered[scope], isUsable(r, scope: scope, window: targetWindow), isVisible(r) {
            set(r)
            return true
        }
        let all = candidates(scope: scope).filter(isVisible)
        let pool = all.filter { $0.group != "sidebar" }.isEmpty ? all : all.filter { $0.group != "sidebar" }
        let pick = pool.first(where: \.preferred) ?? pool.min { a, b in
            let fa = frame(a), fb = frame(b)
            // Same row when centers are within ~20pt.
            return ((fa.midY / 40).rounded(), fa.minX) < ((fb.midY / 40).rounded(), fb.minX)
        }
        set(pick)
        return pick != nil
    }

    /** Re-points focus at a preferred element in [scope] (when a dialog or card appears). */
    func focusPreferred(scope: String, attempt: Int = 0) {
        if let p = candidates(scope: scope).first(where: \.preferred) { set(p); return }
        // Just appeared: wait for it to be laid out (a few frames at most).
        guard attempt < 6 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { self.focusPreferred(scope: scope, attempt: attempt + 1) }
    }

    /** The focused element if it's usable in [scope], else the one last focused there (after a menu closed). */
    private func current(_ scope: String) -> FocusToken? {
        let w = targetWindow
        if let f = focused, isUsable(f, scope: scope, window: w) { return f }
        if let r = remembered[scope], isUsable(r, scope: scope, window: w), isVisible(r) {
            set(r, scroll: false)
            return r
        }
        return nil
    }

    func move(_ dir: MoveDirection, scope: String, allowScroll: Bool = true) {
        guard let cur = current(scope) else {
            focusInitial(scope: scope)
            return
        }
        if cur.onMove?(dir) == true { return }
        let from = frame(cur)
        let curScroll = cur.anchor?.enclosingScrollView
        let inSidebar = cur.group == "sidebar"
        let vertical = dir == .up || dir == .down
        let options = candidates(scope: scope).filter { $0 !== cur }.filter { t in
            // The sidebar is entered with ← only, and ↑/↓ inside it stay inside it.
            if vertical && (t.group == "sidebar") != inSidebar { return false }
            if !vertical && inSidebar && t.group == "sidebar" { return false }
            // Off-screen items are fine within the same scrolling row (they scroll into view).
            return isVisible(t) || (t.anchor?.enclosingScrollView === curScroll && curScroll != nil)
        }.compactMap { t -> (FocusToken, CGFloat)? in
            let f = frame(t)
            let major: CGFloat, minor: CGFloat
            switch dir {
            case .right:
                guard f.midX > from.midX + 2, f.minX > from.minX + 2 else { return nil }
                major = max(0, f.minX - from.maxX); minor = crossGap(f.minY, f.maxY, from.minY, from.maxY)
            case .left:
                guard f.midX < from.midX - 2, f.maxX < from.maxX - 2 else { return nil }
                major = max(0, from.minX - f.maxX); minor = crossGap(f.minY, f.maxY, from.minY, from.maxY)
            case .down:
                guard f.midY > from.midY + 2, f.minY > from.minY + 2 else { return nil }
                major = max(0, f.minY - from.maxY); minor = abs(f.minX - from.minX)
            case .up:
                guard f.midY < from.midY - 2, f.maxY < from.maxY - 2 else { return nil }
                major = max(0, from.minY - f.maxY); minor = abs(f.minX - from.minX)
            }
            // Android's FocusFinder weighting: distance along the move counts 13× the sideways offset.
            return (t, 13 * major * major + minor * minor)
        }
        if let best = options.min(by: { $0.1 < $1.1 }) { set(best.0); return }
        // Nothing that way yet: scroll the enclosing list a step and look again (lazy rows).
        if allowScroll, let a = cur.anchor, scrollStep(from: a, dir) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.move(dir, scope: scope, allowScroll: false) }
        }
    }

    /** Gap across the movement axis; 0 when the two elements overlap (same row/column). */
    private func crossGap(_ aMin: CGFloat, _ aMax: CGFloat, _ bMin: CGFloat, _ bMax: CGFloat) -> CGFloat {
        max(0, max(aMin, bMin) - min(aMax, bMax))
    }

    private func scrollStep(from view: NSView, _ dir: MoveDirection) -> Bool {
        var sv = view.enclosingScrollView
        while let s = sv {
            let clip = s.contentView
            let doc = s.documentView?.frame ?? .zero
            let horizontal = dir == .left || dir == .right
            let canScroll = horizontal ? doc.width > clip.bounds.width + 1 : doc.height > clip.bounds.height + 1
            if canScroll {
                var o = clip.bounds.origin
                let step = (horizontal ? clip.bounds.width : clip.bounds.height) * 0.6
                switch dir {
                case .right: o.x = min(o.x + step, doc.width - clip.bounds.width)
                case .left: o.x = max(o.x - step, 0)
                case .down: o.y = clip.isFlipped ? min(o.y + step, doc.height - clip.bounds.height) : max(o.y - step, 0)
                case .up: o.y = clip.isFlipped ? max(o.y - step, 0) : min(o.y + step, doc.height - clip.bounds.height)
                }
                if o != clip.bounds.origin {
                    clip.scroll(to: o)
                    s.reflectScrolledClipView(clip)
                    return true
                }
            }
            sv = s.enclosingScrollView
        }
        return false
    }

    // MARK: Actions

    /** Activates the focused element. [fromGamepad] text fields open the on-screen keyboard. */
    @discardableResult
    func activate(scope: String, fromGamepad: Bool) -> Bool {
        guard let t = current(scope) else { return false }
        if fromGamepad, let text = t.text {
            AppModel.shared.osk = OSKRequest(title: t.textTitle, text: text, onSubmit: t.onSubmit)
            return true
        }
        t.activate?()
        return true
    }

    @discardableResult
    func secondary(scope: String) -> Bool {
        guard let t = current(scope), let s = t.secondary else { return false }
        s()
        return true
    }

    var focusedIsValid: Bool {
        guard let f = focused, let a = f.anchor else { return false }
        return a.window != nil
    }
}

// MARK: - Action menus

/** One row of a focusable menu. [checked] nil = no checkmark column. */
struct ActionItem: Identifiable {
    let id = UUID()
    var label: String
    var icon: String?
    var checked: Bool?
    /** Multi-select menus stay open after a choice. */
    var keepOpen = false
    var action: () -> Void
}

/** A menu shown in-app (dropdowns and context menus for keyboard and gamepad). Items are re-read on every render. */
struct ActionMenuRequest: Identifiable {
    let id = UUID()
    let title: String
    let items: () -> [ActionItem]
}

struct ActionMenuOverlay: View {
    let request: ActionMenuRequest
    var app = AppModel.shared

    var body: some View {
        let items = request.items()
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { app.actionMenu = nil }
            VStack(alignment: .leading, spacing: 4) {
                Text(request.title).font(.z(size: 17, weight: .bold)).lineLimit(2).padding(.bottom, 6).padding(.horizontal, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            ActionMenuRow(item: item, preferred: i == (items.firstIndex { $0.checked == true } ?? 0)) {
                                item.action()
                                if !item.keepOpen { app.actionMenu = nil }
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 460)
                Text("↑↓ choose · Return / Ⓐ select · Esc / Ⓑ close").font(.z(size: 11)).foregroundStyle(Palette.textMuted).padding(.horizontal, 10).padding(.top, 4)
            }
            .padding(14)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 14).fill(P.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.5), radius: 30)
        }
        .zFocusScope("menu")
        .onAppear { FocusEngine.shared.focusPreferred(scope: "menu") }
    }
}

private struct ActionMenuRow: View {
    let item: ActionItem
    let preferred: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let checked = item.checked {
                    Image(systemName: checked ? "checkmark" : "").font(.z(size: 12, weight: .bold)).frame(width: 16).foregroundStyle(P.accent)
                }
                if let icon = item.icon { Image(systemName: icon).frame(width: 18) }
                Text(item.label).font(.z(size: 14)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.white : .clear))
            .foregroundStyle(hover ? .black : .white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .zFocus(activate: action, onFocusChange: { hover = $0 }, preferred: preferred, ring: false)
    }
}

// MARK: - On-screen keyboard

/** Text entry with a gamepad. */
struct OSKRequest: Identifiable {
    let id = UUID()
    let title: String
    let text: Binding<String>
    let onSubmit: (() -> Void)?
}

struct OnScreenKeyboard: View {
    let request: OSKRequest
    var app = AppModel.shared
    @State private var upper = false
    @State private var symbols = false

    private var rows: [[String]] {
        if symbols { return [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], [".", "-", "_", "/", ":", "@", "?", "=", "&", "#"], ["+", "!", "'", "\"", "(", ")", ",", ";", "%", "~"]] }
        let letters = [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"], ["a", "s", "d", "f", "g", "h", "j", "k", "l", "."], ["z", "x", "c", "v", "b", "n", "m", "-", "/", ":"]]
        return upper ? letters.map { $0.map { $0.uppercased() } } : letters
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(request.title).font(.z(size: 16, weight: .bold))
                Text(request.text.wrappedValue.isEmpty ? " " : request.text.wrappedValue)
                    .font(.z(size: 20, weight: .medium, design: .monospaced)).lineLimit(1).truncationMode(.head)
                    .frame(width: 620, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.5)))
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    HStack(spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.offset) { c, key in
                            KeyCap(label: key, width: 56, preferred: r == 1 && c == 0) { request.text.wrappedValue.append(key) }
                        }
                    }
                }
                HStack(spacing: 6) {
                    KeyCap(label: upper ? "abc" : "ABC", width: 80) { upper.toggle() }
                    KeyCap(label: symbols ? "ABC" : "#+=", width: 80) { symbols.toggle() }
                    KeyCap(label: "space", width: 200) { request.text.wrappedValue.append(" ") }
                    KeyCap(label: "⌫", width: 80) { if !request.text.wrappedValue.isEmpty { request.text.wrappedValue.removeLast() } }
                    KeyCap(label: "Paste", width: 80) { if let s = NSPasteboard.general.string(forType: .string) { request.text.wrappedValue.append(s.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                    KeyCap(label: "Done", width: 80, primary: true) {
                        app.osk = nil
                        request.onSubmit?()
                    }
                }
                Text("Ⓧ backspace · Ⓨ space · Ⓑ close").font(.z(size: 11)).foregroundStyle(Palette.textMuted)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(P.surface))
        }
        .zFocusScope("osk")
        .onAppear { FocusEngine.shared.focusPreferred(scope: "osk") }
    }
}

private struct KeyCap: View {
    let label: String
    var width: CGFloat = 56
    var primary = false
    var preferred = false
    let action: () -> Void
    @State private var lit = false

    var body: some View {
        Button(action: action) {
            Text(label).font(.z(size: 16, weight: .semibold))
                .frame(width: width, height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(lit ? Color.white : primary ? P.accent : Color.white.opacity(0.12)))
                .foregroundStyle(lit ? .black : primary ? P.onAccent : .white)
        }
        .buttonStyle(.plain)
        .onHover { lit = $0 }
        .zFocus(activate: action, onFocusChange: { lit = $0 }, preferred: preferred, ring: false)
    }
}
