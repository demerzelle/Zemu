import SwiftUI
import UniformTypeIdentifiers
import ZemuCore

/** Premade avatars: a gradient tile with an emoji. */
enum AvatarPresets {
    struct Preset { let emoji: String; let from: UInt32; let to: UInt32 }
    static let all: [Preset] = [
        .init(emoji: "😎", from: 0xFFE50914, to: 0xFF7F0A12), .init(emoji: "🦊", from: 0xFFF97316, to: 0xFF9A3412), .init(emoji: "🐼", from: 0xFF64748B, to: 0xFF1E293B),
        .init(emoji: "🐯", from: 0xFFF59E0B, to: 0xFFB45309), .init(emoji: "🐸", from: 0xFF22C55E, to: 0xFF15803D), .init(emoji: "🐙", from: 0xFFEC4899, to: 0xFF9D174D),
        .init(emoji: "🦄", from: 0xFFA855F7, to: 0xFF6B21A8), .init(emoji: "🐶", from: 0xFFD97706, to: 0xFF78350F), .init(emoji: "🐱", from: 0xFF06B6D4, to: 0xFF0E7490),
        .init(emoji: "👾", from: 0xFF6366F1, to: 0xFF3730A3), .init(emoji: "🤖", from: 0xFF94A3B8, to: 0xFF334155), .init(emoji: "👻", from: 0xFF8B5CF6, to: 0xFF4C1D95),
        .init(emoji: "🎮", from: 0xFF10B981, to: 0xFF065F46), .init(emoji: "🍿", from: 0xFFEF4444, to: 0xFF991B1B), .init(emoji: "🚀", from: 0xFF3B82F6, to: 0xFF1E3A8A),
        .init(emoji: "⚡", from: 0xFFEAB308, to: 0xFF854D0E), .init(emoji: "🌸", from: 0xFFF472B6, to: 0xFFBE185D), .init(emoji: "🧙", from: 0xFF7C3AED, to: 0xFF2E1065),
    ]
}

struct Avatar: View {
    let avatar: String
    var size: CGFloat
    var corner: CGFloat?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner ?? size / 6, style: .continuous)
        if avatar.hasPrefix("file:") {
            RemoteImage(url: avatar, maxPixel: 400).frame(width: size, height: size).background(Color.gray.opacity(0.3)).clipShape(shape)
        } else {
            let i = min(max(Int(avatar.removingPrefix("preset:")) ?? 0, 0), AvatarPresets.all.count - 1)
            let p = AvatarPresets.all[i]
            shape.fill(LinearGradient(colors: [Color(argb: p.from), Color(argb: p.to)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(Text(p.emoji).font(.system(size: size * 0.48)))
        }
    }
}

/** "Who's watching?", shown at launch when more than one profile exists. */
struct ProfilePicker: View {
    var app = AppModel.shared
    @State private var hover: String?

    var body: some View {
        ZStack {
            P.background.ignoresSafeArea()
            VStack(spacing: 40) {
                Text("Who's watching?").font(.system(size: 44, weight: .black))
                HStack(spacing: 36) {
                    ForEach(app.profiles.profiles) { p in
                        Button { app.switchProfile(p.id) } label: {
                            VStack(spacing: 14) {
                                Avatar(avatar: p.avatar, size: 140, corner: 22)
                                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(hover == p.id ? 1 : 0), lineWidth: 4))
                                    .scaleEffect(hover == p.id ? 1.08 : 1)
                                Text(p.name).font(.system(size: 17)).foregroundStyle(hover == p.id ? .white : Palette.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h ? p.id : (hover == p.id ? nil : hover) } }
                        .zFocus(activate: { app.switchProfile(p.id) },
                                onFocusChange: { h in withAnimation(.easeOut(duration: 0.12)) { hover = h ? p.id : (hover == p.id ? nil : hover) } },
                                preferred: p.id == app.session.profileId, ring: false)
                    }
                }
                Text("Manage profiles in Settings  ·  ⇧⌘P switches profile").font(.system(size: 13)).foregroundStyle(Palette.textMuted)
            }
        }
        .onAppear { FocusEngine.shared.focusPreferred(scope: "main") }
    }
}

/** Settings → Profiles: switch, add, edit, delete. */
struct ProfilesSection: View {
    var app = AppModel.shared
    @State private var editing: Profile?
    @State private var adding = false

    var body: some View {
        let store = app.profiles
        let current = app.session.profileId
        VStack(alignment: .leading, spacing: 12) {
            Text("Each profile has its own addons, history, My List, likes, recommendations and settings. With more than one profile, Zemu asks who's watching at launch.")
                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            HStack(alignment: .top, spacing: 20) {
                ForEach(store.profiles) { p in
                    Button { editing = p } label: {
                        VStack(spacing: 6) {
                            Avatar(avatar: p.avatar, size: 90, corner: 18)
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(p.id == current ? P.accent : .clear, lineWidth: 3))
                            Text(p.name).font(.system(size: 13, weight: p.id == current ? .bold : .regular)).lineLimit(1)
                            if p.id == current { Text("Current").font(.system(size: 11)).foregroundStyle(P.accent) }
                        }
                        .frame(width: 104)
                    }
                    .buttonStyle(.plain)
                    .zFocus(activate: { editing = p }, secondary: {
                        app.showMenu(p.name) { [ActionItem(label: "Switch to \(p.name)", icon: "person.crop.circle") { app.switchProfile(p.id) },
                                               ActionItem(label: "Edit…", icon: "pencil") { editing = p }] }
                    }, cornerRadius: 18)
                    .contextMenu {
                        Button("Switch to \(p.name)") { app.switchProfile(p.id) }
                        Button("Edit…") { editing = p }
                    }
                }
                Button { adding = true } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.textMuted, lineWidth: 2).frame(width: 90, height: 90)
                            .overlay(Image(systemName: "plus").font(.system(size: 30)).foregroundStyle(Palette.textSecondary))
                        Text("Add profile").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                    .frame(width: 104)
                }
                .buttonStyle(.plain)
                .zFocus(activate: { adding = true }, cornerRadius: 18)
            }
            if store.profiles.count > 1 {
                HStack(spacing: 12) {
                    ZButton(title: "Switch Profile", icon: "person.2") { app.picking = true }
                    Toggle("Open last used profile at launch", isOn: Binding(get: { store.skipPicker }, set: { store.setSkipPicker($0) }))
                        .toggleStyle(.switch)
                        .zFocus(activate: { store.setSkipPicker(!store.skipPicker) })
                }
            }
        }
        .sheet(isPresented: $adding) {
            ProfileEditor(title: "Add Profile", initial: Profile(id: "", name: "", avatar: "preset:\(store.profiles.count % AvatarPresets.all.count)"), canDelete: false)
        }
        .sheet(item: $editing) { p in
            ProfileEditor(title: "Edit Profile", initial: p, canDelete: p.id != ProfileStore.defaultId && p.id != current)
        }
    }
}

private struct ProfileEditor: View {
    let title: String
    let initial: Profile
    let canDelete: Bool
    var app = AppModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = ""
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Avatar(avatar: avatar, size: 72)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 20, weight: .black))
                    TextField("Profile name", text: $name).textFieldStyle(.roundedBorder).frame(width: 280)
                        .focused($nameFocused)
                        .zFocusText($name, title: "Profile name", focus: { nameFocused = true }, preferred: true)
                        .onChange(of: name) { _, n in if n.count > 20 { name = String(n.prefix(20)) } }
                }
            }
            Text("Choose a picture").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 10), count: 9), spacing: 10) {
                ForEach(AvatarPresets.all.indices, id: \.self) { i in
                    let v = "preset:\(i)"
                    Button { avatar = v } label: {
                        Avatar(avatar: v, size: 58, corner: 12)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(avatar == v ? P.accent : .clear, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .zFocus(activate: { avatar = v }, cornerRadius: 12)
                }
            }
            HStack {
                ZButton(title: "Choose Photo…", icon: "photo") { pickPhoto() }
                Text("Or drop an image on the picture above.").font(.system(size: 12)).foregroundStyle(Palette.textMuted)
            }
            HStack(spacing: 10) {
                ZButton(title: "Save", primary: true) { save() }.keyboardShortcut(.defaultAction)
                ZButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if canDelete { ZButton(title: "Delete Profile", icon: "trash") { confirmDelete = true } }
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(P.surface)
        .onAppear { name = initial.name; avatar = initial.avatar }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in setPhoto(url) } }
            }
            return true
        }
        .alert("Delete \(initial.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { app.profiles.delete(initial.id); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the profile's addons, history, My List and settings.") }
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { setPhoto(url) }
    }

    private func setPhoto(_ url: URL) {
        // New profiles get their id on save; use a temporary one for the file and rename then.
        let id = initial.id.isEmpty ? "new-\(UUID().uuidString.prefix(6))" : initial.id
        if let v = app.profiles.saveAvatarImage(id, from: url) { avatar = v } else { app.toast("That file isn't an image Zemu can read.") }
    }

    private func save() {
        if initial.id.isEmpty {
            app.profiles.add(name: name.trimmed, avatar: avatar)
        } else {
            var p = initial
            p.name = name.trimmed.isEmpty ? initial.name : name.trimmed
            p.avatar = avatar
            app.profiles.update(p)
        }
        dismiss()
    }
}
