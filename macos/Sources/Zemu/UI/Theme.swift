import SwiftUI
import ZemuCore

extension Color {
    init(argb: UInt32) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xFF) / 255,
                  green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255,
                  opacity: Double((argb >> 24) & 0xFF) / 255)
    }

    var argb: UInt32 {
        let c = rgb()
        func b(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (b(c.a) << 24) | (b(c.r) << 16) | (b(c.g) << 8) | b(c.b)
    }

    func mix(_ other: Color, _ t: Double) -> Color {
        let a = rgb()
        let o = other.rgb()
        return Color(.sRGB,
                     red: a.r + (o.r - a.r) * t,
                     green: a.g + (o.g - a.g) * t,
                     blue: a.b + (o.b - a.b) * t,
                     opacity: 1)
    }

    var luminance: Double {
        let c = rgb()
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }
}

/** The colors a theme controls; everything else (text, ratings, badges) stays fixed for legibility. */
struct ThemeColors: Equatable {
    var accent: Color
    var background: Color
    /** Your own picks from Settings → Appearance → Customize colors (nil = derived). */
    var customBase: Color?
    var customPanel: Color?
    var customButton: Color?
    var customText: Color?
    /** Accessibility: pure black and white, full-strength text and a bold outline on what's focused. */
    var highContrast = false
    /** Degrees the animated theme's scene turns its hues (Customize colors → Animated scene). */
    var sceneHueShift: Double = 0
    /** Themes that are always light (Cybercore, Pocket LCD) or always dark (16-Bit); nil follows Settings. */
    var forcedLight: Bool?
    var surface: Color { customPanel ?? background.mix(.white, 0.07) }
    var surfaceHigh: Color { customButton ?? background.mix(.white, 0.14) }
}

/** Colors the user can set per theme and per light/dark mode. */
enum ColorRole: String, CaseIterable {
    case accent, background, panel, button, text, scene
    var label: String {
        switch self {
        case .accent: "Accent"; case .background: "Background"; case .panel: "Panels & rows"
        case .button: "Buttons"; case .text: "Text"; case .scene: "Animated scene"
        }
    }
}

enum ThemePreset: String, CaseIterable {
    case CLASSIC, CRIMSON, OLED, HIGH_CONTRAST, OCEAN, ARCTIC, EMERALD, PURPLE, ROSE, SUNSET, GOLD, SLATE, Y2K

    var label: String {
        switch self {
        case .CLASSIC: "Zemu Neon"; case .CRIMSON: "Crimson"; case .OLED: "OLED Black"; case .HIGH_CONTRAST: "High Contrast"; case .OCEAN: "Ocean Blue"
        case .ARCTIC: "Arctic"; case .EMERALD: "Emerald"; case .PURPLE: "Royal Purple"; case .ROSE: "Rose"
        case .SUNSET: "Sunset"; case .GOLD: "Gold"; case .SLATE: "Slate"; case .Y2K: "Y2K"
        }
    }

    var values: (UInt32, UInt32) {
        switch self {
        case .CLASSIC: (0xFF39FF14, 0xFF07090A); case .CRIMSON: (0xFFE50914, 0xFF0A0A0E); case .OLED: (0xFFE6E6E6, 0xFF000000); case .HIGH_CONTRAST: (0xFFFFE600, 0xFF000000)
        case .OCEAN: (0xFF2F80ED, 0xFF070B14); case .ARCTIC: (0xFF22D3EE, 0xFF0A1218); case .EMERALD: (0xFF10B981, 0xFF06100C)
        case .PURPLE: (0xFF8B5CF6, 0xFF0C0814); case .ROSE: (0xFFEC4899, 0xFF12070D); case .SUNSET: (0xFFF97316, 0xFF120A06)
        case .GOLD: (0xFFEAB308, 0xFF0E0C05); case .SLATE: (0xFF94A3B8, 0xFF0F1115); case .Y2K: (0xFFFF4FD8, 0xFF0E0A2E)
        }
    }

    var colors: ThemeColors {
        var c = ThemeColors(accent: Color(argb: values.0), background: Color(argb: values.1))
        switch self {
        // Pure black: OLED pixels switch off.
        case .OLED: c.customPanel = .black; c.customButton = Color(argb: 0xFF121212)
        // Black and white with a bright yellow focus.
        case .HIGH_CONTRAST: c.customPanel = .black; c.customButton = Color(argb: 0xFF1F1F1F); c.customText = .white; c.highContrast = true
        default: break
        }
        return c
    }

    /** Stays dark in light mode (a white OLED theme makes no sense). */
    var alwaysDark: Bool { self == .OLED || self == .HIGH_CONTRAST }
    static let custom = "CUSTOM"
}

extension AppSettings {
    var themeColors: ThemeColors {
        if theme == ThemePreset.custom { return ThemeColors(accent: Color(argb: customAccent), background: Color(argb: customBackground)) }
        return (ThemePreset(rawValue: theme) ?? .CLASSIC).colors
    }

    /** The palette's light mode is off (OLED, High Contrast). */
    var alwaysDark: Bool { ThemePreset(rawValue: theme)?.alwaysDark == true }

    /** Which colors your edits change: an animated theme with its own palette, else your palette. */
    func colorScope(light: Bool) -> String {
        let d = DynamicTheme.of(dynamicTheme)
        let v = variant(of: d)
        // Each Cybercore desktop keeps its own colors.
        let name = d == .RETRO ? "RETRO-\(d.resolveVariant(v))" : d.palette(v) != nil ? d.rawValue : theme
        return "\(name)/\(light ? "light" : "dark")"
    }

    /** The chosen sub-theme of [d] (weather kind, holiday, Cybercore desktop). */
    func variant(of d: DynamicTheme) -> String { themeVariants[d.rawValue] ?? d.variants.first?.0 ?? "" }

    /** Everything applied: palette, animated theme and your exact colors for this mode. */
    func resolvedColors(light: Bool) -> ThemeColors {
        let d = DynamicTheme.of(dynamicTheme)
        let own = d.apply(to: themeColors, variant: variant(of: d))
        var c = own
        let scope = colorScope(light: light)
        func get(_ r: ColorRole) -> Color? { colorOverrides["\(scope)/\(r.rawValue)"].map { Color(argb: $0) } }
        if let v = get(.accent) { c.accent = v }
        if let v = get(.background) { c.customBase = v; c.background = v }
        if let v = get(.panel) { c.customPanel = v }
        if let v = get(.button) { c.customButton = v }
        if let v = get(.text) { c.customText = v }
        if let v = get(.scene) { c.sceneHueShift = Double(v.hsb().h - own.accent.hsb().h) * 360 }
        return c
    }
}

/**
 * App colors. Reads go through Observation, so changing the theme redraws every screen without
 * threading colors through each view.
 */
@MainActor @Observable
final class Palette {
    static let shared = Palette()

    var colors = ThemePreset.CLASSIC.colors
    /** RGB animated theme: overrides the accent while it cycles. */
    var accentOverride: Color?
    /** Experimental Liquid Glass look: page backgrounds turn see-through over the ambient artwork. */
    var glass = false
    /** Light mode chosen in Settings: a pale version of the theme's background with dark text. */
    var lightMode = false
    /** Settings → Appearance: size of everything (1 = 100%), extra text size, and the font. */
    var zoom: CGFloat = 1
    var textScale: CGFloat = 1
    var fontFamily = ""
    /** The full-window player is up; it (and menus over it) always stay dark. */
    var videoUp = false
    var light: Bool { lightMode && !videoUp }

    /** The theme background, or in light mode a near-white tinted with a touch of the accent. */
    var base: Color { colors.customBase ?? (light ? Color(argb: 0xFFF4F4F7).mix(colors.accent, 0.05) : colors.background) }
    /** Pages turn see-through over a whole-app theme's scene (and over Liquid Glass's artwork). */
    var background: Color { glass ? base.opacity(light ? 0.45 : 0.32) : scene != .normal ? base.opacity(0.3) : base }
    /** The animated theme's whole-app style and sub-theme. */
    var scene = SceneStyle.normal
    var sceneVariant = ""
    var surface: Color { glass ? ink.opacity(light ? 0.06 : 0.08) : colors.customPanel ?? base.mix(light ? .black : .white, light ? 0.05 : 0.07) }
    var surfaceHigh: Color { glass ? ink.opacity(light ? 0.12 : 0.16) : colors.customButton ?? base.mix(light ? .black : .white, light ? 0.10 : 0.14) }
    var accent: Color { accentOverride ?? colors.accent }
    /** Text/icon color on top of the accent: black on bright accents (like neon green), white otherwise. */
    var onAccent: Color { accent.luminance > 0.45 ? Color(argb: 0xFF07130A) : .white }
    /** Primary text and icons. */
    var text: Color { videoUp ? .white : colors.customText ?? (light ? Color(argb: 0xFF141418) : .white) }
    /** The contrast color for hover fills, outlines and focus rings (white on dark, black on light). */
    var ink: Color { light ? .black : .white }
    /** Accent used as text on the page background (bright accents like neon green get darker in light mode). */
    var accentText: Color { light && accent.luminance > 0.55 ? accent.mix(.black, 0.35) : accent }

    static var textSecondary: Color { P.colors.highContrast ? P.text : P.light ? Color(argb: 0xFF4A4A55) : Color(argb: 0xFFB8B8C2) }
    static var textMuted: Color { P.colors.highContrast ? Color(argb: 0xFFDDDDDD) : P.light ? Color(argb: 0xFF77777F) : Color(argb: 0xFF80808C) }
    static let imdb = Color(argb: 0xFFF5C518)
    static var match: Color { P.light ? Color(argb: 0xFF1E9E4A) : Color(argb: 0xFF46D369) }
    static var cached: Color { P.light ? Color(argb: 0xFFAD7400) : Color(argb: 0xFFFFC94D) }
    static var info: Color { P.light ? Color(argb: 0xFF1F6FD1) : Color(argb: 0xFF5AA9FF) }
}

extension Font {
    /**
     * The app's text: the size scaled by UI zoom and text size, in the font picked in Settings
     * (else the system font). Reads Palette, so changing either redraws everything.
     */
    @MainActor static func z(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let s = size * P.zoom * P.textScale
        switch P.fontFamily.isEmpty ? P.scene.font(P.sceneVariant) : P.fontFamily {
        case "SERIF": return .system(size: s, weight: weight, design: .serif)
        case "MONO": return .system(size: s, weight: weight, design: .monospaced)
        case "ROUNDED": return .system(size: s, weight: weight, design: .rounded)
        case "CONDENSED": return .custom("Avenir Next Condensed", size: s).weight(weight)
        case "CURSIVE": return .custom("Bradley Hand", size: s).weight(weight)
        case "PIXEL": return .custom("Pixelify Sans", size: s).weight(weight)
        default: return .system(size: s, weight: weight, design: design)
        }
    }
}

/** Fonts for Settings → Appearance (key, label); "" = the system font. */
let fontChoices = [("", "System"), ("SERIF", "Serif"), ("MONO", "Monospace"), ("ROUNDED", "Rounded"), ("CONDENSED", "Condensed"), ("CURSIVE", "Handwritten"), ("PIXEL", "Pixel")]

/** Registers the bundled pixel font once. */
@MainActor func registerBundledFonts() {
    if let url = Bundle.main.url(forResource: "pixelify_sans", withExtension: "ttf") {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/** Shorthand used across views. */
@MainActor var P: Palette { Palette.shared }
