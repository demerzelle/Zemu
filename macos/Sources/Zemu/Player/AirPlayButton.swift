import AVKit
import SwiftUI

/**
 * The system AirPlay picker. macOS routes a specific AVPlayer, so opening the menu switches the
 * player to AVPlayer; if no AirPlay screen ends up in use, it goes back to mpv.
 */
struct AirPlayButton: NSViewRepresentable {
    let p: PlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(p) }

    func makeNSView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.delegate = context.coordinator
        v.isRoutePickerButtonBordered = false
        v.setRoutePickerButtonColor(.white, for: .normal)
        v.setRoutePickerButtonColor(NSColor(P.accent), for: .active)
        v.player = p.airPlayPlayer
        return v
    }

    func updateNSView(_ v: AVRoutePickerView, context: Context) {
        context.coordinator.p = p
        v.player = p.airPlayPlayer
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVRoutePickerViewDelegate {
        var p: PlayerModel
        init(_ p: PlayerModel) { self.p = p }

        func routePickerViewWillBeginPresentingRoutes(_ v: AVRoutePickerView) {
            p.setAirPlay(true)
            v.player = p.airPlayPlayer
        }

        func routePickerViewDidEndPresentingRoutes(_ v: AVRoutePickerView) {
            Task { @MainActor [p] in
                // Give AirPlay a moment to connect before deciding nothing was picked.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if p.airPlayPlayer?.isExternalPlaybackActive != true { p.setAirPlay(false) }
            }
        }
    }
}
