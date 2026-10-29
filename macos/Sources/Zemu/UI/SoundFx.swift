import AppKit

/**
 * UI sound effects for keyboard and controller navigation: move, select, hold (options), back.
 * Files live in the app's Resources/sounds/<set>/<event>.wav; themes that restyle the app have
 * their own set, falling back to "default". Off by default (Settings → Appearance).
 */
@MainActor
enum SoundFx {
    enum Event: String { case move, select, hold, back }

    /** Sound packs in Settings, by setting value; "theme" is the theme's own set. */
    static let packs = [("theme", "Theme sounds"), ("wood", "Wood"), ("bubbles", "Bubbles"), ("keys", "Soft keys"), ("cosmic", "Cosmic"), ("retro", "Retro")]

    /** The sound set in use: the theme's, or a pack (pack-<name>). */
    static var set = "default"
    private static var cache: [String: NSSound] = [:]
    private static var lastMove = Date.distantPast

    static func play(_ e: Event) {
        guard AppModel.shared.settings.soundEffects, let sound = sound(e) else { return }
        if e == .move {
            // Holding an arrow repeats fast; keep it a gentle patter.
            guard Date().timeIntervalSince(lastMove) > 0.07 else { return }
            lastMove = Date()
        }
        sound.stop()
        sound.volume = e == .move ? 0.45 : 0.7
        sound.play()
    }

    private static func sound(_ e: Event) -> NSSound? {
        let key = "\(set)/\(e.rawValue)"
        if let s = cache[key] { return s }
        for folder in [set, "default"] {
            if let url = Bundle.main.url(forResource: e.rawValue, withExtension: "wav", subdirectory: "sounds/\(folder)"), let s = NSSound(contentsOf: url, byReference: true) {
                cache[key] = s
                return s
            }
        }
        return nil
    }
}
