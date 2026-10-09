import SwiftUI
import ZemuCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running the bare binary (swift run) still shows up as a normal app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
        MainActor.assumeIsolated { InputRouter.shared.start() }
        // Leaving Zemu while a video plays moves it to Picture in Picture; coming back restores it.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let app = AppModel.shared
                if app.settings.autoPip, let p = app.player, p.isPlaying, !app.pip, PlayerWindow.host?.isMiniaturized == false {
                    app.enterPiP(auto: true)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if AppModel.shared.autoEnteredPiP { AppModel.shared.exitPiP() }
            }
        }
    }

    /** stremio:// install links and zemu://details links. */
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { urls.forEach(AppModel.shared.handleURL) }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MainActor.assumeIsolated { Integrations.shared.dockMenu() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.player?.close()
            AppModel.shared.session.store.saveNow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct ZemuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var app = AppModel.shared

    var body: some Scene {
        Window("Zemu", id: "main") {
            RootView()
                .frame(minWidth: 360, minHeight: 260)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands { ZemuCommands() }

        MenuBarExtra("Zemu", systemImage: "play.tv") {
            MenuBarContent()
        }
    }
}

@MainActor
private func openStreamURL() {
    let alert = NSAlert()
    alert.messageText = "Open Stream URL"
    alert.informativeText = "Play a direct video link (MKV, MP4, HLS…) in the built-in player."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
    field.placeholderString = "https://…"
    if let clip = NSPasteboard.general.string(forType: .string), clip.hasPrefix("http") { field.stringValue = clip }
    alert.accessoryView = field
    alert.addButton(withTitle: "Play")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    if alert.runModal() == .alertFirstButtonReturn { AppModel.shared.playURL(field.stringValue) }
}

private struct ZemuCommands: Commands {
    var app = AppModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { app.go(.settings) }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Stream URL…") { openStreamURL() }.keyboardShortcut("o")
            Button("Install Addon from Clipboard") {
                guard let s = NSPasteboard.general.string(forType: .string) else { return }
                Task { app.toast(await app.session.handlePastedText(s)) }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            ForEach(Section.allCases) { s in
                Button(s.label) { app.go(s) }.keyboardShortcut(s.shortcut)
            }
            Divider()
            Button("Search") { app.go(.search) }.keyboardShortcut("f")
            Button("Back") { app.back() }.keyboardShortcut("[")
                .disabled(app.stack.isEmpty)
        }
        CommandMenu("Playback") {
            let p = app.player
            Button(p?.isPlaying == true ? "Pause" : "Play") { p?.togglePlay() }.disabled(p == nil)
            Button("Back 10 Seconds") { p?.seekBy(-10_000) }.disabled(p == nil)
            Button("Forward 10 Seconds") { p?.seekBy(10_000) }.disabled(p == nil)
            Button("Next Episode") { p?.playNextNow() }.disabled(p?.upNext == nil)
            Divider()
            Button("Cycle Audio Track") { p?.cycleAudio() }.disabled(p == nil)
            Button("Cycle Subtitles") { p?.cycleSubtitles() }.disabled(p == nil)
            Button("Cycle Picture Size") { p?.cycleAspect() }.disabled(p == nil)
            Button("Save Frame") { p?.saveFrame() }.keyboardShortcut("s").disabled(p == nil)
            Divider()
            Button(app.pip ? "Exit Picture in Picture" : "Picture in Picture") { app.pip ? app.exitPiP() : app.enterPiP() }.disabled(p == nil)
            Button("Stop") { p?.close() }.keyboardShortcut(".").disabled(p == nil)
            Divider()
            Text("Keys: Space play · ←/→ seek · ↑/↓ volume · Return controls · F full screen · S subtitles · A audio · C subtitle style · T Picture in Picture · Z/X subtitle delay · [ ] speed")
        }
        CommandMenu("Profile") {
            Button("Switch Profile…") { app.picking = true }.keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            ForEach(app.profiles.profiles) { p in
                Button(p.name) { app.switchProfile(p.id) }
            }
        }
    }
}

/** Menu bar extra: Continue Watching and new episodes at a glance. */
private struct MenuBarContent: View {
    var app = AppModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let entries = Array(app.session.inProgress.prefix(8))
        if entries.isEmpty {
            Text("Nothing in progress")
        } else {
            Text("Continue Watching")
            ForEach(entries, id: \.meta.id) { e in
                Button([e.meta.title, e.label].compactMap { $0 }.joined(separator: " · ") + "  \(Int(e.progress * 100))%") {
                    show()
                    app.resume(e)
                }
            }
        }
        let fresh = app.session.newEpisodes.items.prefix(5)
        if !fresh.isEmpty {
            Divider()
            Text("New Episodes")
            ForEach(Array(fresh), id: \.meta.id) { item in
                Button("\(item.meta.title) · \(item.badge)") {
                    show()
                    app.openDetails(item.meta, section: "episodes")
                }
            }
        }
        Divider()
        Button("Open Zemu") { show() }
        Button("Quit Zemu") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
