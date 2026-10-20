import Foundation

/**
 * A keyboard key, by its key code (the same physical key on any layout), or a controller control.
 * Controller names: A, B, X, Y, L1, R1, L2, R2, Menu, Options, Up, Down, Left, Right and
 * LStickUp, LStickDown, LStickLeft, LStickRight.
 */
public enum InputToken: Codable, Hashable, Sendable {
    case key(UInt16)
    case pad(String)
}

/** Every command a key or controller control can trigger. Movement, selection and player shortcuts all rebind. */
public enum BindableAction: String, CaseIterable, Codable, Sendable {
    case up, down, left, right
    case select, back, secondary, tertiary, prevSection, nextSection
    case scrubBack, scrubForward, menu, view, playPause
    // Player shortcuts (keyboard).
    case togglePlay, seekBack, seekForward, fullScreen, mute, subtitles, audio, subtitleStyle
    case nextEpisode, pip, aspect, subDelayBack, subDelayForward, speedDown, speedUp, speedReset

    /** Player shortcuts only act while the player is showing; everything else is shared with the rest of the app. */
    public var isPlayerShortcut: Bool {
        switch self {
        case .togglePlay, .seekBack, .seekForward, .fullScreen, .mute, .subtitles, .audio, .subtitleStyle,
             .nextEpisode, .pip, .aspect, .subDelayBack, .subDelayForward, .speedDown, .speedUp, .speedReset:
            true
        default: false
        }
    }

    public var label: String {
        switch self {
        case .up: "Move up"
        case .down: "Move down"
        case .left: "Move left"
        case .right: "Move right"
        case .select: "Select / confirm"
        case .back: "Back"
        case .secondary: "Options for a title (X / O)"
        case .tertiary: "Search (Y)"
        case .prevSection: "Previous section"
        case .nextSection: "Next section"
        case .scrubBack: "Seek back (hold to speed up)"
        case .scrubForward: "Seek forward (hold to speed up)"
        case .menu: "Menu / play-pause"
        case .view: "Settings"
        case .playPause: "Play / pause (player)"
        case .togglePlay: "Play / pause (K)"
        case .seekBack: "Back 10 seconds"
        case .seekForward: "Forward 10 seconds"
        case .fullScreen: "Full screen"
        case .mute: "Mute"
        case .subtitles: "Cycle subtitles"
        case .audio: "Cycle audio track"
        case .subtitleStyle: "Subtitle style"
        case .nextEpisode: "Next episode"
        case .pip: "Picture in Picture"
        case .aspect: "Aspect ratio"
        case .subDelayBack: "Subtitles earlier"
        case .subDelayForward: "Subtitles later"
        case .speedDown: "Slower"
        case .speedUp: "Faster"
        case .speedReset: "Normal speed"
        }
    }

    /** Groups for the Settings list. */
    public var group: String {
        switch self {
        case .up, .down, .left, .right, .select, .back, .secondary, .tertiary, .prevSection, .nextSection,
             .scrubBack, .scrubForward, .menu, .view:
            "Browsing"
        case .playPause, .togglePlay, .seekBack, .seekForward, .fullScreen, .mute, .subtitles, .audio, .subtitleStyle,
             .nextEpisode, .pip, .aspect, .subDelayBack, .subDelayForward, .speedDown, .speedUp, .speedReset:
            "Player"
        }
    }

    /** Built-in keys and controls, matching the behavior before remapping existed. */
    public var defaults: [InputToken] {
        switch self {
        case .up: [.key(126), .pad("Up"), .pad("LStickUp")]
        case .down: [.key(125), .pad("Down"), .pad("LStickDown")]
        case .left: [.key(123), .pad("Left"), .pad("LStickLeft")]
        case .right: [.key(124), .pad("Right"), .pad("LStickRight")]
        case .select: [.key(36), .key(76), .pad("A")]
        case .back: [.key(53), .key(51), .pad("B")]
        case .secondary: [.key(31), .pad("X")]
        case .tertiary: [.pad("Y")]
        case .prevSection: [.pad("L1")]
        case .nextSection: [.pad("R1")]
        case .scrubBack: [.pad("L2")]
        case .scrubForward: [.pad("R2")]
        case .menu: [.pad("Menu")]
        case .view: [.pad("Options")]
        case .playPause: [.key(49)]
        case .togglePlay: [.key(40)] // K
        case .seekBack: [.key(38)] // J
        case .seekForward: [.key(37)] // L
        case .fullScreen: [.key(3)] // F
        case .mute: [.key(46)] // M
        case .subtitles: [.key(1)] // S
        case .audio: [.key(0)] // A
        case .subtitleStyle: [.key(8)] // C
        case .nextEpisode: [.key(45)] // N
        case .pip: [.key(17), .key(34)] // T, I
        case .aspect: [.key(35)] // P
        case .subDelayBack: [.key(6)] // Z
        case .subDelayForward: [.key(7)] // X
        case .speedDown: [.key(33)] // [
        case .speedUp: [.key(30)] // ]
        case .speedReset: [.key(24)] // =
        }
    }
}

/**
 * Resolves keys and controls to actions. [overrides] holds only what the user changed, keyed by
 * action name; an action missing from it keeps its defaults. An empty list means "no binding".
 */
public enum KeyBindings {
    public static func tokens(_ action: BindableAction, overrides: [String: [InputToken]]) -> [InputToken] {
        overrides[action.rawValue] ?? action.defaults
    }

    /** The action a key or control triggers, if any. Each token triggers one action. */
    public static func action(for token: InputToken, overrides: [String: [InputToken]]) -> BindableAction? {
        BindableAction.allCases.first { tokens($0, overrides: overrides).contains(token) }
    }

    /**
     * Makes [token] an [action] binding. It's taken away from whatever else used it, so one input
     * never triggers two actions. Returns the new overrides.
     */
    public static func bind(_ token: InputToken, to action: BindableAction, overrides: [String: [InputToken]]) -> [String: [InputToken]] {
        var next = overrides
        for other in BindableAction.allCases where other != action {
            let current = tokens(other, overrides: overrides)
            if current.contains(token) { next[other.rawValue] = current.filter { $0 != token } }
        }
        let own = tokens(action, overrides: overrides)
        if !own.contains(token) { next[action.rawValue] = own + [token] }
        return next
    }

    /** Removes one binding from an action. */
    public static func unbind(_ token: InputToken, from action: BindableAction, overrides: [String: [InputToken]]) -> [String: [InputToken]] {
        var next = overrides
        next[action.rawValue] = tokens(action, overrides: overrides).filter { $0 != token }
        return next
    }

    /** Readable name for a key or control, e.g. "Return", "←", "Space", "K", "Ⓐ". */
    public static func name(_ token: InputToken) -> String {
        switch token {
        case .key(let code): keyNames[code] ?? "Key \(code)"
        case .pad(let p): padNames[p] ?? p
        }
    }

    public static let padNames: [String: String] = [
        "A": "Ⓐ", "B": "Ⓑ", "X": "Ⓧ", "Y": "Ⓨ", "L1": "LB", "R1": "RB", "L2": "LT", "R2": "RT",
        "Menu": "☰", "Options": "⧉", "Up": "D-pad ↑", "Down": "D-pad ↓", "Left": "D-pad ←", "Right": "D-pad →",
        "LStickUp": "Stick ↑", "LStickDown": "Stick ↓", "LStickLeft": "Stick ←", "LStickRight": "Stick →",
    ]

    /** macOS virtual key codes for the keys Zemu can use. */
    public static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 36: "Return", 76: "Enter", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        117: "Forward Delete", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    ]
}
