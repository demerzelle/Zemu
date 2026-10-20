import SwiftUI
import AVFoundation
import ZemuCore

@main
struct ZemuApp: App {
    var app = AppModel.shared
    @Environment(\.scenePhase) private var phase

    init() {
        // Playback keeps going with the silent switch on and in the background (audio).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // stremio:// install links and zemu://details links.
                .onOpenURL { app.handleURL($0) }
        }
        .onChange(of: phase) { _, p in
            if p == .background { app.session.store.saveNow() }
        }
    }
}
