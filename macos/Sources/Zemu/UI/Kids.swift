import SwiftUI
import ZemuCore

/** The 4-digit parent code pad: [check] gets each full code and says whether it was right. */
struct ParentPrompt: Identifiable {
    let id = UUID()
    let title: String
    var message: String?
    let check: (String) -> Bool
}

extension AppModel {
    /** Runs [then] right away, or after the parent code while a kid profile is in use. */
    func whenParent(_ title: String, then: @escaping () -> Void) {
        guard profiles.kidsOn else { then(); return }
        parentPrompt = ParentPrompt(title: title, message: "Enter the parent code") { [weak self] code in
            guard self?.profiles.checkParentCode(code) == true else { return false }
            then()
            return true
        }
    }

    /** A new parent code, entered twice; [then] runs once it's saved. */
    func createParentCode(then: @escaping () -> Void = {}) {
        parentPrompt = ParentPrompt(title: "Create a parent code", message: "4 digits. It's needed to leave a kid profile or open Settings there.") { [weak self] first in
            Task { @MainActor in
                self?.parentPrompt = ParentPrompt(title: "Enter it again") { again in
                    guard again == first else { return false }
                    self?.profiles.updateKids { $0.pinHash = KidsSettings.hash(again) }
                    then()
                    return true
                }
            }
            return true
        }
    }
}

/** Number pad for the parent code. Number keys, Delete and Esc work too. */
struct ParentCodeOverlay: View {
    let prompt: ParentPrompt
    var app = AppModel.shared
    @State private var code = ""
    @State private var wrong = false
    @State private var shake: CGFloat = 0
    @State private var monitor: Any?

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).onTapGesture { close() }
            VStack(spacing: 0) {
                Text("🔒  \(prompt.title)").font(.z(size: 20, weight: .bold))
                if let m = prompt.message { Text(m).font(.z(size: 13)).foregroundStyle(Palette.textSecondary).padding(.top, 6) }
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(i < code.count ? P.accent : .clear)
                            .overlay(Circle().strokeBorder(i < code.count ? P.accent : Palette.textMuted, lineWidth: 2))
                            .frame(width: 18, height: 18)
                    }
                }
                .padding(.vertical, 18)
                .offset(x: shake)
                Text(wrong ? "Wrong code, try again" : " ").font(.z(size: 13)).foregroundStyle(P.accentText)
                VStack(spacing: 10) {
                    ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "✕"]], id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(row, id: \.self) { k in
                                Button { press(k) } label: {
                                    Text(k).font(.z(size: 22, weight: .bold)).frame(width: 72, height: 52)
                                        .zSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), fill: P.ink.opacity(0.12), interactive: true)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .zFocus(activate: { press(k) }, preferred: k == "1", cornerRadius: 12)
                            }
                        }
                    }
                }
                .padding(.top, 12)
            }
            .padding(26)
            .frame(width: 380)
            .zSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), fill: P.surface)
            .shadow(color: .black.opacity(0.5), radius: 30)
        }
        .zFocusScope("parent")
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                if let c = e.charactersIgnoringModifiers, c.count == 1, c.first!.isNumber { press(c); return nil }
                if e.keyCode == 51 { press("⌫"); return nil }
                if e.keyCode == 53 { close(); return nil }
                return e
            }
            FocusEngine.shared.focusPreferred(scope: "parent")
        }
        .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) } }
    }

    private func press(_ k: String) {
        switch k {
        case "⌫": code = String(code.dropLast())
        case "✕": close()
        default:
            guard code.count < 4 else { return }
            code += k
            wrong = false
            guard code.count == 4 else { return }
            let entered = code
            let current = prompt.id
            if prompt.check(entered) {
                // A follow-up prompt (enter it again) may have replaced this one.
                if app.parentPrompt?.id == current { app.parentPrompt = nil }
            } else {
                wrong = true
                code = ""
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) { shake = 14 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation { shake = 0 } }
            }
        }
    }

    private func close() { app.parentPrompt = nil }
}

/** In Kids Mode, a title above the allowed rating shows a lock (a parent can let it through). */
struct KidsTitleGate<Content: View>: View {
    let type: String
    let id: String
    @ViewBuilder let content: () -> Content
    var app = AppModel.shared
    @State private var ok: Bool?
    @State private var unlocked = false

    var body: some View {
        if !app.profiles.kidsOn || unlocked || ok == true {
            content()
        } else {
            Group {
                if ok == nil {
                    Text("Checking the rating…").foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CenteredMessage(title: "🙈 Not for Kids Mode", message: "This title isn't a kids' title or its rating isn't allowed. Ask a grown-up.") {
                        ZButton(title: "Parent code", primary: true, preferred: true) { app.whenParent("Let this one play?") { unlocked = true } }
                    }
                }
            }
            .task(id: id) { ok = await app.session.kids.allowed(Meta(id: id, type: type)) }
        }
    }
}
