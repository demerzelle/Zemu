import AppKit

/** Hands a stream URL to IINA, VLC or Infuse. */
enum ExternalPlayer {
    static let choices = ["IINA", "VLC", "Infuse"]

    private static let bundleIds = ["IINA": "com.colliderli.iina", "VLC": "org.videolan.vlc", "Infuse": "com.firecore.infuse"]

    static func isInstalled(_ name: String) -> Bool {
        bundleIds[name].flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } != nil
    }

    static var installed: [String] { choices.filter(isInstalled) }

    /** Opens [url] in [preferred] if installed, otherwise the first installed player. False if none is. */
    @discardableResult
    static func open(url: String, title: String, preferred: String) -> Bool {
        let order = [preferred] + choices.filter { $0 != preferred }
        for name in order where isInstalled(name) {
            switch name {
            case "IINA":
                var c = URLComponents(string: "iina://weblink")!
                c.queryItems = [URLQueryItem(name: "url", value: url)]
                if let u = c.url, NSWorkspace.shared.open(u) { return true }
            case "Infuse":
                var c = URLComponents(string: "infuse://x-callback-url/play")!
                c.queryItems = [URLQueryItem(name: "url", value: url)]
                if let u = c.url, NSWorkspace.shared.open(u) { return true }
            default:
                if let app = bundleIds[name].flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }), let u = URL(string: url) {
                    NSWorkspace.shared.open([u], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    return true
                }
            }
        }
        return false
    }
}
