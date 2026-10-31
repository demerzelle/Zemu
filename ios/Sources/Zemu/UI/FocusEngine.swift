import SwiftUI

// iOS is touch-first: the Mac's keyboard/gamepad focus engine isn't needed, so the focus
// modifiers the shared screens use are no-ops there. tvOS maps them onto its focus engine.
// Menus stay as in-app sheets.

enum MoveDirection { case up, down, left, right }

#if os(tvOS)
let tvOS = true
/** The screens are laid out in iPad-sized points; a 1920×1080 TV shows them at 1280×720 × 1.5. */
let tvScale: CGFloat = 1.5

/** tvOS's own plain style draws a big white platter over the UI; this lifts the control instead. */
struct ZemuButtonStyle: ButtonStyle {
    private struct Lift<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            label
                .brightness(focused ? 0.12 : 0)
                .shadow(color: .white.opacity(focused ? 0.55 : 0), radius: 7)
                .scaleEffect(pressed ? 0.96 : focused ? 1.05 : 1)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        Lift(label: configuration.label, pressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ZemuButtonStyle {
    static var zemu: ZemuButtonStyle { .init() }
}

private struct TVFocus: ViewModifier {
    let onFocusChange: ((Bool) -> Void)?
    let onMove: ((MoveDirection) -> Bool)?
    let preferred: Bool
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { onFocusChange?(focused) }
            .onAppear { if preferred { focused = true } }
            .onMoveCommand { dir in
                switch dir {
                case .up: _ = onMove?(.up)
                case .down: _ = onMove?(.down)
                case .left: _ = onMove?(.left)
                case .right: _ = onMove?(.right)
                @unknown default: break
                }
            }
    }
}

extension View {
    func zFocus(
        activate: (() -> Void)?,
        secondary: (() -> Void)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil,
        onMove: ((MoveDirection) -> Bool)? = nil,
        group: String? = nil,
        preferred: Bool = false,
        ring: Bool = true,
        cornerRadius: CGFloat = 8
    ) -> some View { modifier(TVFocus(onFocusChange: onFocusChange, onMove: onMove, preferred: preferred)) }

    func zFocusText(_ text: Binding<String>, title: String, focus: @escaping () -> Void, onSubmit: (() -> Void)? = nil, preferred: Bool = false) -> some View { self }

    func zFocusScope(_ scope: String) -> some View { focusSection() }

    func tvScaled() -> some View {
        font(.system(size: 15)).frame(width: 1920 / tvScale, height: 1080 / tvScale).scaleEffect(tvScale).frame(width: 1920, height: 1080).ignoresSafeArea()
    }
}
#else
let tvOS = false
let tvScale: CGFloat = 1

extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    static var zemu: PlainButtonStyle { .plain }
}

extension View {
    func zFocus(
        activate: (() -> Void)?,
        secondary: (() -> Void)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil,
        onMove: ((MoveDirection) -> Bool)? = nil,
        group: String? = nil,
        preferred: Bool = false,
        ring: Bool = true,
        cornerRadius: CGFloat = 8
    ) -> some View { self }

    func zFocusText(_ text: Binding<String>, title: String, focus: @escaping () -> Void, onSubmit: (() -> Void)? = nil, preferred: Bool = false) -> some View { self }

    func zFocusScope(_ scope: String) -> some View { self }

    func tvScaled() -> some View { self }
}
#endif

// MARK: - Action menus

/** One row of a menu. [checked] nil = no checkmark column. */
struct ActionItem: Identifiable {
    let id = UUID()
    var label: String
    var icon: String?
    var checked: Bool?
    /** Multi-select menus stay open after a choice. */
    var keepOpen = false
    var action: () -> Void
}

/** A menu shown in-app (dropdowns and context menus). Items are re-read on every render. */
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
                #if os(tvOS)
                .focusable(false)
                #endif
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(request.title).font(.system(size: 17, weight: .bold)).lineLimit(2)
                    Spacer()
                    Button { app.actionMenu = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.textMuted)
                    }
                    .buttonStyle(.zemu)
                    .accessibilityLabel("Close")
                }
                .padding(.bottom, 6).padding(.horizontal, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        // By position: items are rebuilt on every render with new ids, and id-based rows
                        // would be torn down each time (RGB's accent redraws 8 times a second).
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            ActionMenuRow(item: item) {
                                item.action()
                                if !item.keepOpen { app.actionMenu = nil }
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 460)
            }
            .padding(14)
            .frame(maxWidth: 380)
            .zSurface(RoundedRectangle(cornerRadius: 14), fill: P.surface, interactive: false)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.5), radius: 30)
            .padding(16)
            .zFocusScope("menu")
        }
        #if os(tvOS)
        .onExitCommand { app.actionMenu = nil }
        #endif
    }
}

private struct ActionMenuRow: View {
    let item: ActionItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let checked = item.checked {
                    Image(systemName: checked ? "checkmark" : "").font(.system(size: 12, weight: .bold)).frame(width: 16).foregroundStyle(P.accent)
                }
                if let icon = item.icon { Image(systemName: icon).frame(width: 18) }
                Text(item.label).font(.system(size: 15)).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zemu)
    }
}
