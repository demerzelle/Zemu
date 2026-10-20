import SwiftUI

// iOS is touch-first: the Mac's keyboard/gamepad focus engine isn't needed, so the focus
// modifiers the shared screens use are no-ops here. Menus stay as in-app sheets.

enum MoveDirection { case up, down, left, right }

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
}

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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(request.title).font(.system(size: 17, weight: .bold)).lineLimit(2)
                    Spacer()
                    Button { app.actionMenu = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.bottom, 6).padding(.horizontal, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { item in
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
            .background(RoundedRectangle(cornerRadius: 14).fill(P.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.5), radius: 30)
            .padding(16)
        }
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
        .buttonStyle(.plain)
    }
}
