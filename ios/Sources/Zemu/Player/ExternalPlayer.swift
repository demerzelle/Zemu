import UIKit

/** Hands a stream URL to VLC, Infuse or Outplayer through their URL schemes. */
@MainActor
enum ExternalPlayer {
    static let choices = ["VLC", "Infuse", "Outplayer"]

    private static func link(_ name: String, _ url: String) -> URL? {
        let enc = url.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url
        switch name {
        case "VLC": return URL(string: "vlc-x-callback://x-callback-url/stream?url=\(enc)")
        case "Infuse": return URL(string: "infuse://x-callback-url/play?url=\(enc)")
        case "Outplayer": return URL(string: "outplayer://\(url)")
        default: return nil
        }
    }

    /** Needs the scheme in Info.plist's LSApplicationQueriesSchemes. */
    static func isInstalled(_ name: String) -> Bool {
        link(name, "https://x").map { UIApplication.shared.canOpenURL($0) } ?? false
    }

    static var installed: [String] { choices.filter(isInstalled) }

    /** Opens [url] in [preferred] if installed, otherwise the first installed player. False if none is. */
    @discardableResult
    static func open(url: String, title: String, preferred: String) -> Bool {
        let order = [preferred] + choices.filter { $0 != preferred }
        for name in order where isInstalled(name) {
            if let u = link(name, url) {
                UIApplication.shared.open(u)
                return true
            }
        }
        return false
    }
}
