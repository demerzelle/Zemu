import AVKit
import SwiftUI

/** The system AirPlay picker. Picking a screen is seen by [PlayerModel] as a route change. */
struct AirPlayButton: UIViewRepresentable {
    let p: PlayerModel

    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(P.accent)
        v.prioritizesVideoDevices = true
        return v
    }

    func updateUIView(_ v: AVRoutePickerView, context: Context) {
        v.activeTintColor = UIColor(P.accent)
    }
}
