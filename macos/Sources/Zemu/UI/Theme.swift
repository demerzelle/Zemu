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
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func b(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (b(c.alphaComponent) << 24) | (b(c.redComponent) << 16) | (b(c.greenComponent) << 8) | b(c.blueComponent)
    }

    func mix(_ other: Color, _ t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB,
                     red: a.redComponent + (b.redComponent - a.redComponent) * t,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                     opacity: 1)
    }

    var luminance: Double {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}

/** The colors a theme controls; everything else (text, ratings, badges) stays fixed for legibility. */
struct ThemeColors: Equatable {
    var accent: Color
    var background: Color
    var surface: Color { background.mix(.white, 0.07) }
    var surfaceHigh: Color { background.mix(.white, 0.14) }
}

enum ThemePreset: String, CaseIterable {
    case CLASSIC, CRIMSON, OLED, OCEAN, ARCTIC, EMERALD, PURPLE, ROSE, SUNSET, GOLD, SLATE

    var label: String {
        switch self {
        case .CLASSIC: "Zemu Neon"; case .CRIMSON: "Crimson"; case .OLED: "OLED Black"; case .OCEAN: "Ocean Blue"
        case .ARCTIC: "Arctic"; case .EMERALD: "Emerald"; case .PURPLE: "Royal Purple"; case .ROSE: "Rose"
        case .SUNSET: "Sunset"; case .GOLD: "Gold"; case .SLATE: "Slate"
        }
    }

    var values: (UInt32, UInt32) {
        switch self {
        case .CLASSIC: (0xFF39FF14, 0xFF07090A); case .CRIMSON: (0xFFE50914, 0xFF0A0A0E); case .OLED: (0xFFE50914, 0xFF000000)
        case .OCEAN: (0xFF2F80ED, 0xFF070B14); case .ARCTIC: (0xFF22D3EE, 0xFF0A1218); case .EMERALD: (0xFF10B981, 0xFF06100C)
        case .PURPLE: (0xFF8B5CF6, 0xFF0C0814); case .ROSE: (0xFFEC4899, 0xFF12070D); case .SUNSET: (0xFFF97316, 0xFF120A06)
        case .GOLD: (0xFFEAB308, 0xFF0E0C05); case .SLATE: (0xFF94A3B8, 0xFF0F1115)
        }
    }

    var colors: ThemeColors { ThemeColors(accent: Color(argb: values.0), background: Color(argb: values.1)) }
    static let custom = "CUSTOM"
}

extension AppSettings {
    var themeColors: ThemeColors {
        if theme == ThemePreset.custom { return ThemeColors(accent: Color(argb: customAccent), background: Color(argb: customBackground)) }
        return (ThemePreset(rawValue: theme) ?? .CLASSIC).colors
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

    var background: Color { colors.background }
    var surface: Color { colors.surface }
    var surfaceHigh: Color { colors.surfaceHigh }
    var accent: Color { accentOverride ?? colors.accent }
    /** Text/icon color on top of the accent: black on bright accents (like neon green), white otherwise. */
    var onAccent: Color { accent.luminance > 0.45 ? Color(argb: 0xFF07130A) : .white }

    static let textSecondary = Color(argb: 0xFFB8B8C2)
    static let textMuted = Color(argb: 0xFF80808C)
    static let imdb = Color(argb: 0xFFF5C518)
    static let match = Color(argb: 0xFF46D369)
    static let cached = Color(argb: 0xFFFFC94D)
    static let info = Color(argb: 0xFF5AA9FF)
}

/** Shorthand used across views. */
@MainActor var P: Palette { Palette.shared }
