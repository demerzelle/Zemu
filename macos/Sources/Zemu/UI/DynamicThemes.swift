import SwiftUI
import ZemuCore

/** Whole-app looks that go beyond colors: a backdrop scene, lettering, sounds. */
enum SceneStyle {
    case normal, ps2, acid, ethereal, retro, graffiti, liquid, catrave, space, ocean, night, alien, pocket, sixteen

    /** The sound set (Resources/sounds/<set>). */
    var soundSet: String {
        switch self {
        case .ps2: "ps2"; case .acid: "acidwave"; case .retro: "cybercore"; case .graffiti: "graffiti"; case .liquid: "liquid"
        case .ethereal, .night: "ethereal"; case .catrave: "catrave"; case .space, .alien: "space"; case .ocean: "ocean"
        case .pocket: "pocket"; case .sixteen: "sixteen"; case .normal: "default"
        }
    }

    /** The style's own font (a key of fontChoices); "" = system. */
    func font(_ variant: String) -> String {
        switch self {
        case .acid, .alien: "MONO"
        case .ethereal, .night: "SERIF"
        case .retro: variant == "KAWAII" ? "CURSIVE" : variant == "XP" ? "" : "MONO"
        case .graffiti: "CONDENSED"
        case .catrave: "CURSIVE"
        case .pocket, .sixteen: "PIXEL"
        default: ""
        }
    }

    /** Height of the style's bottom strip (taskbar or floor); pages end above it. */
    var floorHeight: CGFloat {
        switch self { case .retro: 34; case .pocket: 30; case .sixteen: 40; default: 0 }
    }
}

/**
 * Animated themes. Some bring their own colors; the rest keep your palette and only add an effect.
 * Several restyle the whole app with a scene behind it. Variants are sub-themes (key, label).
 */
enum DynamicTheme: String, CaseIterable {
    case NONE, RGB, WEATHER, HOLIDAYS, CYBERPUNK, FIREFLIES, MATRIX, SAKURA, ETHEREAL, Y2K, ACIDWAVE, RETRO, GRAFFITI, LIQUID,
         POCKET, SIXTEEN, CATRAVE, SPACE, NIGHT_SKY, ALIEN, OCEAN

    var label: String {
        switch self {
        case .NONE: "Off"; case .RGB: "RGB"; case .WEATHER: "Weather"; case .HOLIDAYS: "Holidays"; case .CYBERPUNK: "Cyberpunk"
        case .FIREFLIES: "Fireflies"; case .MATRIX: "Matrix"; case .SAKURA: "Sakura"; case .ETHEREAL: "Ethereal · Aurora"
        case .Y2K: "PS2 · Y2K"; case .ACIDWAVE: "Acidwave"; case .RETRO: "Cybercore"; case .GRAFFITI: "Graffiti"; case .LIQUID: "Liquid Glass"
        case .POCKET: "Pocket LCD"; case .SIXTEEN: "16-Bit"; case .CATRAVE: "Cat Rave"; case .SPACE: "Outer Space"; case .NIGHT_SKY: "Night Sky"
        case .ALIEN: "Alien Abduction"; case .OCEAN: "Ocean"
        }
    }

    /** Only listed once unlocked (the Cat Rave: click the logo ten times). */
    var hidden: Bool { self == .CATRAVE }

    var style: SceneStyle {
        switch self {
        case .ETHEREAL: .ethereal; case .Y2K: .ps2; case .ACIDWAVE: .acid; case .RETRO: .retro; case .GRAFFITI: .graffiti; case .LIQUID: .liquid
        case .POCKET: .pocket; case .SIXTEEN: .sixteen; case .CATRAVE: .catrave; case .SPACE: .space; case .NIGHT_SKY: .night
        case .ALIEN: .alien; case .OCEAN: .ocean; default: .normal
        }
    }

    var variants: [(String, String)] {
        switch self {
        case .WEATHER: [("SNOW", "Snow"), ("RAIN", "Rain"), ("STORM", "Thunderstorm"), ("FOG", "Fog"), ("SUNNY", "Sunny")]
        case .HOLIDAYS: [("AUTO", "Auto (today's holiday)")] + Holiday.allCases.map { ($0.rawValue, $0.label) }
        case .RETRO: [("CLASSIC", "Classic"), ("KAWAII", "Kawaii"), ("XP", "XP")]
        default: []
        }
    }

    /** "AUTO" holidays become today's (or the next) holiday. */
    func resolveVariant(_ v: String) -> String {
        if self == .HOLIDAYS && (v == "AUTO" || v.isEmpty) { return Holiday.today().rawValue }
        return v.isEmpty ? (variants.first?.0 ?? "") : v
    }

    /** This theme's own accent and background for [variant], or nil to keep your palette. */
    func palette(_ variant: String = "") -> (UInt32, UInt32)? {
        switch self {
        case .WEATHER: return resolveVariant(variant) == "STORM" ? (0xFF8AB4FF, 0xFF06080F) : nil
        case .HOLIDAYS: let h = Holiday(rawValue: resolveVariant(variant)) ?? .CHRISTMAS; return (h.accent, h.background)
        case .CYBERPUNK: return (0xFFFF2A6D, 0xFF0B0518)
        case .FIREFLIES: return (0xFFFACC15, 0xFF070A06)
        case .MATRIX: return (0xFF22C55E, 0xFF000500)
        case .SAKURA: return (0xFFF472B6, 0xFF120810)
        case .ETHEREAL: return (0xFFC4B5FD, 0xFF0A0918)
        case .Y2K: return (0xFF6FB4FF, 0xFF00020A)
        case .ACIDWAVE: return (0xFFC8FF00, 0xFF0A0A0B)
        case .GRAFFITI: return (0xFFFF2E88, 0xFF161616)
        case .LIQUID: return (0xFF0A84FF, 0xFF0B1226)
        case .POCKET: return (0xFF0F380F, 0xFF9BBC0F)
        case .SIXTEEN: return (0xFFB8A9F0, 0xFF101848)
        case .CATRAVE: return (0xFFFF00E6, 0xFF07000F)
        case .SPACE: return (0xFF8AB4FF, 0xFF0B1030)
        case .NIGHT_SKY: return (0xFFFFE8A3, 0xFF0A1028)
        case .ALIEN: return (0xFF7CFF6B, 0xFF07100C)
        case .OCEAN: return (0xFF4FE3C1, 0xFF0C4A70)
        case .RETRO, .NONE, .RGB: return nil
        }
    }

    /** Old theme names map to where their effect lives now. */
    private static let renamed = ["SNOWFALL": "WEATHER", "RAIN": "WEATHER", "LIGHTNING": "WEATHER", "HALLOWEEN": "HOLIDAYS", "CHRISTMAS": "HOLIDAYS", "AURORA": "ETHEREAL"]
    static func of(_ name: String) -> DynamicTheme { DynamicTheme(rawValue: renamed[name] ?? name) ?? .NONE }

    /** Colors after applying this theme's own palette (if it has one). */
    func apply(to base: ThemeColors, variant: String = "") -> ThemeColors {
        func c(_ v: UInt32) -> Color { Color(argb: v) }
        switch self {
        case .RETRO:
            // Desktops and windows are light: dark text, like the real thing.
            let (accent, desk, window, text): (UInt32, UInt32, UInt32, UInt32) = switch resolveVariant(variant) {
            case "KAWAII": (0xFFFF5FB8, 0xFFFFD6EC, 0xFFFFF4FA, 0xFF5A2346)
            case "XP": (0xFF2459D6, 0xFF3A7BD5, 0xFFECE9D8, 0xFF111111)
            default: (0xFF000080, 0xFF008080, 0xFFC0C0C0, 0xFF000000)
            }
            return ThemeColors(accent: c(accent), background: c(desk), customBase: c(desk), customPanel: c(window), customButton: c(window), customText: c(text), forcedLight: true)
        case .POCKET:
            return ThemeColors(accent: c(0xFF0F380F), background: c(0xFF9BBC0F), customBase: c(0xFF9BBC0F), customPanel: c(0xFF8BAC0F),
                               customButton: c(0xFF8BAC0F), customText: c(0xFF0F380F), forcedLight: true)
        case .SIXTEEN:
            return ThemeColors(accent: c(0xFFB8A9F0), background: c(0xFF101848), customBase: c(0xFF101848), customPanel: c(0xFF182890),
                               customButton: c(0xFF2A2F7A), customText: .white, forcedLight: false)
        default:
            guard let p = palette(variant) else { return base }
            return ThemeColors(accent: c(p.0), background: c(p.1))
        }
    }

    /** The effect drawn above the UI: "SNOW", "RAIN", "HALLOWEEN", "MATRIX", … */
    func effect(_ variant: String) -> String {
        switch self {
        case .WEATHER, .HOLIDAYS: resolveVariant(variant)
        default: rawValue
        }
    }
}

/** Holidays for the Holidays theme, each with its own colors and effect. */
enum Holiday: String, CaseIterable {
    case NEWYEAR, LUNAR, VALENTINE, STPATRICK, EASTER, JULY4, HALLOWEEN, DIWALI, THANKSGIVING, HANUKKAH, CHRISTMAS

    var label: String {
        switch self {
        case .NEWYEAR: "New Year"; case .LUNAR: "Lunar New Year"; case .VALENTINE: "Valentine's Day"; case .STPATRICK: "St. Patrick's Day"
        case .EASTER: "Easter"; case .JULY4: "Fourth of July"; case .HALLOWEEN: "Halloween"; case .DIWALI: "Diwali"
        case .THANKSGIVING: "Thanksgiving"; case .HANUKKAH: "Hanukkah"; case .CHRISTMAS: "Christmas"
        }
    }

    var accent: UInt32 {
        switch self {
        case .NEWYEAR: 0xFFFFD166; case .LUNAR: 0xFFFF3B30; case .VALENTINE: 0xFFFF4D8D; case .STPATRICK: 0xFF2ECC71; case .EASTER: 0xFFB39DFF
        case .JULY4: 0xFF3B82F6; case .HALLOWEEN: 0xFFFF7518; case .DIWALI: 0xFFFFA62B; case .THANKSGIVING: 0xFFD97706; case .HANUKKAH: 0xFF5DA9FF
        case .CHRISTMAS: 0xFFD42426
        }
    }

    var background: UInt32 {
        switch self {
        case .NEWYEAR: 0xFF07060F; case .LUNAR: 0xFF140405; case .VALENTINE: 0xFF14060C; case .STPATRICK: 0xFF04120A; case .EASTER: 0xFF0E0B16
        case .JULY4: 0xFF070A16; case .HALLOWEEN: 0xFF0F0710; case .DIWALI: 0xFF120802; case .THANKSGIVING: 0xFF120A04; case .HANUKKAH: 0xFF050A18
        case .CHRISTMAS: 0xFF06120B
        }
    }

    private static let diwali = [2025: "2025-10-20", 2026: "2026-11-08", 2027: "2027-10-29", 2028: "2028-10-17", 2029: "2029-11-05", 2030: "2030-10-26"]
    private static let hanukkah = [2025: "2025-12-14", 2026: "2026-12-04", 2027: "2027-12-24", 2028: "2028-12-12", 2029: "2029-12-01", 2030: "2030-12-20"]
    private static let lunar = [2025: "2025-01-29", 2026: "2026-02-17", 2027: "2027-02-06", 2028: "2028-01-26", 2029: "2029-02-13", 2030: "2030-02-03"]

    /** The holiday around [date] (a few days either side), else the next one coming up. */
    static func today(_ date: Date = Date()) -> Holiday {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: date)
        let y = cal.component(.year, from: day)
        let windows = Self.windows(y) + Self.windows(y + 1)
        if let w = windows.first(where: { $0.1.contains(day) }) { return w.0 }
        return windows.filter { $0.1.lowerBound > day }.min { $0.1.lowerBound < $1.1.lowerBound }?.0 ?? .CHRISTMAS
    }

    private static func windows(_ y: Int) -> [(Holiday, ClosedRange<Date>)] {
        let cal = Calendar(identifier: .gregorian)
        func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }
        func parse(_ s: String?) -> Date? {
            guard let s else { return nil }
            let p = s.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) : nil
        }
        func around(_ x: Date, _ before: Int, _ after: Int) -> ClosedRange<Date> {
            cal.date(byAdding: .day, value: -before, to: x)!...cal.date(byAdding: .day, value: after, to: x)!
        }
        // Fourth Thursday of November.
        let nov1 = d(11, 1)
        let wd = cal.component(.weekday, from: nov1)
        let thanksgiving = cal.date(byAdding: .day, value: (5 - wd + 7) % 7 + 21, to: nov1)!
        let diwali = parse(Self.diwali[y]) ?? d(11, 1), hanukkah = parse(Self.hanukkah[y]) ?? d(12, 10), lunar = parse(Self.lunar[y]) ?? d(2, 1)
        // More specific holidays first, so they win where windows overlap.
        return [
            (.DIWALI, around(diwali, 3, 3)), (.HANUKKAH, around(hanukkah, 0, 7)), (.VALENTINE, around(d(2, 14), 7, 0)),
            (.LUNAR, around(lunar, 7, 10)), (.STPATRICK, around(d(3, 17), 7, 0)), (.EASTER, around(easter(y), 7, 1)),
            (.JULY4, around(d(7, 4), 6, 0)), (.THANKSGIVING, around(thanksgiving, 10, 2)), (.HALLOWEEN, d(10, 1)...d(10, 31)),
            (.CHRISTMAS, d(12, 1)...d(12, 26)), (.NEWYEAR, d(12, 27)...d(12, 31)), (.NEWYEAR, d(1, 1)...d(1, 7)),
        ]
    }

    /** Gregorian Easter Sunday (anonymous algorithm). */
    static func easter(_ y: Int) -> Date {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: month, day: day))!
    }
}

// MARK: - Drawing helpers

struct ThemeParticle {
    var x: Double, y: Double, speed: Double, size: Double, drift: Double, phase: Double, kind: Int
}

func frac(_ v: Double) -> Double { v - floor(v) }

/** Seeded particles, the same every time for a seed. */
func themeParticles(_ n: Int, seed: Int64 = 42) -> [ThemeParticle] {
    var rng = SeededRandom(seed: seed)
    func r() -> Double { Double(rng.next() % 1_000_000) / 1_000_000 }
    return (0..<n).map { _ in ThemeParticle(x: r(), y: r(), speed: 0.4 + r(), size: 0.5 + r(), drift: r() * 2 - 1, phase: r() * 6.28, kind: Int(rng.next() % 4)) }
}

/** A small seeded random source for scene layout. */
struct SceneRandom {
    private var rng: SeededRandom
    init(_ seed: Int) { rng = SeededRandom(seed: Int64(seed)) }
    mutating func next() -> Double { Double(rng.next() % 1_000_000) / 1_000_000 }
    mutating func int(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
}

extension GraphicsContext {
    func circle(_ c: CGPoint, _ r: Double, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }
    func glow(_ c: CGPoint, _ r: Double, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
             with: .radialGradient(Gradient(colors: [color, .clear]), center: c, startRadius: 0, endRadius: r))
    }
    func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: Double = 1, round: Bool = false) {
        stroke(Path { $0.move(to: a); $0.addLine(to: b) }, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt))
    }
    func rect(_ r: CGRect, _ color: Color) { fill(Path(r), with: .color(color)) }
    func rotated(_ degrees: Double, around c: CGPoint, _ draw: (GraphicsContext) -> Void) {
        var g = self
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(degrees))
        g.translateBy(x: -c.x, y: -c.y)
        draw(g)
    }
}

// MARK: - Effects above the UI

/** Draws the animated theme's effect over the app. RGB and the Cat Rave instead cycle the accent color. */
struct DynamicThemeLayer: View {
    let theme: DynamicTheme
    var variant = ""
    @State private var start = Date()

    private var effect: String { theme.effect(variant) }

    private var particleCount: Int {
        switch effect {
        case "SNOW", "CHRISTMAS": 90; case "RAIN", "STORM": 110; case "FIREFLIES", "SUNNY": 36; case "HALLOWEEN": 14; case "MATRIX": 48
        case "SAKURA", "THANKSGIVING", "STPATRICK": 40; case "VALENTINE", "EASTER", "HANUKKAH", "DIWALI", "LUNAR", "ETHEREAL": 34
        case "CATRAVE": 80; case "SPACE": 40; case "OCEAN": 30; default: 0
        }
    }

    var body: some View {
        if theme == .NONE {
            Color.clear.onAppear { P.accentOverride = nil }
        } else {
            let cycles = theme == .RGB || theme == .CATRAVE
            let particles = themeParticles(particleCount)
            TimelineView(.animation(minimumInterval: theme == .RGB ? 1.0 / 6 : 1.0 / 30)) { tl in
                let t = tl.date.timeIntervalSince(start)
                Canvas { ctx, size in draw(ctx, size, t, particles) }
                    .onChange(of: Int(t * 12)) { _, _ in
                        if cycles { P.accentOverride = Color(hue: frac(t * (theme == .CATRAVE ? 150 : 24) / 360), saturation: 0.85, brightness: 1) }
                    }
            }
            .allowsHitTesting(false)
            .onAppear { if !cycles { P.accentOverride = nil } }
            .onChange(of: theme) { _, _ in if !cycles { P.accentOverride = nil } }
            .overlay(alignment: .bottomTrailing) { if theme == .Y2K { Ps2Legend().padding(.trailing, 28).padding(.bottom, 14) } }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ ps: [ThemeParticle]) {
        let w = size.width, h = size.height
        // Particle positions for this moment, by how each effect moves.
        func pos(_ p: ThemeParticle) -> CGPoint {
            switch effect {
            case "SNOW", "CHRISTMAS": CGPoint(x: frac(p.x + 0.015 * sin(t + p.phase)) * w, y: frac(p.y + t * 0.05 * p.speed) * h)
            case "RAIN", "STORM": CGPoint(x: frac(p.x + t * 0.12) * w, y: frac(p.y + t * 1.1 * p.speed) * h)
            case "FIREFLIES", "SUNNY": CGPoint(x: frac(p.x + 0.2 * sin(t * 0.07 + p.phase)) * w, y: frac(p.y + 0.2 * sin(t * 0.05 + p.phase * 1.3)) * h)
            case "HALLOWEEN": CGPoint(x: frac(p.x + t * 0.05 * p.speed) * w, y: frac(p.y + 0.02 * sin(t * 2 + p.phase)) * h * 0.6)
            case "MATRIX": CGPoint(x: p.x * w, y: frac(p.y + t * 0.25 * p.speed) * h * 1.3)
            case "SAKURA", "THANKSGIVING", "STPATRICK": CGPoint(x: frac(p.x + t * 0.015 * (1 + sin(t + p.phase))) * w, y: frac(p.y + t * 0.04 * p.speed) * h)
            case "VALENTINE", "EASTER", "HANUKKAH", "DIWALI", "LUNAR", "ETHEREAL": CGPoint(x: frac(p.x + 0.01 * sin(t + p.phase)) * w, y: frac(p.y - t * 0.035 * p.speed) * h)
            case "CATRAVE": CGPoint(x: frac(p.x + 0.04 * sin(t * 3 + p.phase)) * w, y: frac(p.y + t * 0.12 * p.speed) * h)
            case "OCEAN": CGPoint(x: frac(p.x + 0.01 * sin(t * 2 + p.phase)) * w, y: frac(p.y - t * 0.06 * p.speed) * h)
            default: CGPoint(x: p.x * w, y: p.y * h)
            }
        }
        switch effect {
        case "SNOW", "CHRISTMAS":
            for p in ps { ctx.circle(pos(p), 1.5 + p.size * 2.6, .white.opacity(0.35 + 0.35 * p.size / 1.5)) }
            if effect == "CHRISTMAS" { christmasLights(ctx, w, t) }
        case "RAIN", "STORM":
            let color = effect == "RAIN" ? Color(argb: 0x55B0C4DE) : Color(argb: 0x448AB4FF)
            for p in ps { let c = pos(p); ctx.line(c, CGPoint(x: c.x - 6, y: c.y + 22 + p.size * 18), color, 1.6, round: true) }
            if effect == "STORM" {
                // A bolt every few seconds at a seeded random moment.
                let period = 6.5, k = floor(t / period)
                var rng = SceneRandom(Int(k))
                let boltAt = k * period + rng.next() * 3
                let flash = t >= boltAt ? max(0, 1 - (t - boltAt) * 2.6) : 0
                if flash > 0 {
                    ctx.rect(CGRect(origin: .zero, size: size), .white.opacity(0.22 * flash))
                    if flash > 0.75 { bolt(ctx, w, h, Int(k)) }
                }
            }
        case "FOG":
            for i in 0..<4 {
                let y = h * (0.2 + Double(i) * 0.2)
                let dx = (t * (8 + Double(i) * 5)).truncatingRemainder(dividingBy: w)
                for x in [dx - w, dx] {
                    let r = CGRect(x: x, y: y - h * 0.12, width: w, height: h * 0.24)
                    ctx.fill(Path(ellipseIn: r), with: .radialGradient(Gradient(colors: [.white.opacity(0.10), .clear]), center: CGPoint(x: r.midX, y: y), startRadius: 0, endRadius: w * 0.45))
                }
            }
        case "SUNNY":
            let o = CGPoint(x: w * 0.92, y: -h * 0.1)
            for i in 0..<7 {
                let a = (100 + Double(i) * 11 + sin(t * 0.2 + Double(i)) * 3) * .pi / 180
                let end = CGPoint(x: o.x + cos(a) * max(w, h) * 1.3, y: o.y + sin(a) * max(w, h) * 1.3)
                ctx.stroke(Path { $0.move(to: o); $0.addLine(to: end) }, with: .linearGradient(Gradient(colors: [Color(argb: 0x33FFE7A3), .clear]), startPoint: o, endPoint: end), lineWidth: 60 + Double(i) * 10)
            }
            for p in ps { ctx.circle(pos(p), 1.5 + p.size, Color(argb: 0x66FFF3C4)) }
        case "FIREFLIES":
            for p in ps {
                let a = max(0, min(1, 0.5 + 0.5 * sin(t * 2 + p.phase))), c = pos(p)
                ctx.circle(c, 18, Color(argb: 0xFFFACC15).opacity(0.12 * a))
                ctx.circle(c, 3, Color(argb: 0xFFFDE68A).opacity(0.8 * a))
            }
        case "HALLOWEEN": halloween(ctx, w, h, t, ps.map(pos), ps)
        case "MATRIX":
            for (i, p) in ps.enumerated() {
                let x = (Double(i) + 0.5) / Double(ps.count) * w, head = pos(p).y
                for k in 0..<14 {
                    let y = head - Double(k) * 22
                    if y < 0 { break }
                    ctx.rect(CGRect(x: x, y: y, width: 8, height: 14), Color(argb: 0xFF22C55E).opacity(max(0, 0.35 - Double(k) * 0.025)))
                }
            }
        case "SAKURA":
            for p in ps {
                let c = pos(p)
                ctx.rotated((t * 60 + p.phase * 57).truncatingRemainder(dividingBy: 360), around: c) {
                    $0.fill(Path(ellipseIn: CGRect(x: c.x - 6 * p.size, y: c.y - 3.5 * p.size, width: 12 * p.size, height: 7 * p.size)), with: .color(Color(argb: 0xFFF9A8D4).opacity(0.55)))
                }
            }
        case "THANKSGIVING":
            let tones: [UInt32] = [0x88D97706, 0x88B45309, 0x88EA580C, 0x889A3412]
            for p in ps {
                let c = pos(p)
                ctx.rotated((t * 50 + p.phase * 57).truncatingRemainder(dividingBy: 360), around: c) {
                    $0.fill(Path(ellipseIn: CGRect(x: c.x - 9 * p.size, y: c.y - 4 * p.size, width: 18 * p.size, height: 8 * p.size)), with: .color(Color(argb: tones[p.kind % 4])))
                }
            }
        case "STPATRICK":
            for p in ps {
                let c = pos(p), r = 4 + p.size * 3
                ctx.rotated(t * 30 + p.phase * 57, around: c) { g in
                    for i in 0..<3 { let a = Double(i) * 2.094; g.circle(CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r), r, Color(argb: 0x6632C66B)) }
                    g.line(c, CGPoint(x: c.x, y: c.y + r * 2.4), Color(argb: 0x6632C66B), 2)
                }
            }
        case "VALENTINE": for p in ps { heart(ctx, pos(p), 6 + p.size * 6, Color(argb: p.kind % 2 == 0 ? 0x66FF4D8D : 0x55FFB3CF)) }
        case "EASTER":
            let pastel: [UInt32] = [0x77F9A8D4, 0x77A7F3D0, 0x77BFDBFE, 0x77FDE68A]
            for p in ps {
                let c = pos(p), ew = 10 + p.size * 6
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - ew / 2, y: c.y - ew * 0.65, width: ew, height: ew * 1.3)), with: .color(Color(argb: pastel[p.kind % 4])))
                ctx.line(CGPoint(x: c.x - ew / 2.4, y: c.y), CGPoint(x: c.x + ew / 2.4, y: c.y), .white.opacity(0.4), 2)
            }
        case "HANUKKAH": sparkles(ctx, ps.map(pos), ps, Color(argb: 0xFFBFDBFE)); menorah(ctx, h, t)
        case "DIWALI": sparkles(ctx, ps.map(pos), ps, Color(argb: 0xFFFFC56B)); diyas(ctx, w, h, t)
        case "LUNAR": sparkles(ctx, ps.map(pos), ps, Color(argb: 0xFFFFD166)); lanterns(ctx, w, t)
        case "ETHEREAL": sparkles(ctx, ps.map(pos), ps, Color(argb: 0xFFE9E4FF))
        case "NEWYEAR": fireworks(ctx, w, h, t, [Color(argb: 0xFFFFD166), Color(argb: 0xFFFFF4C2), Color(argb: 0xFFE6C3FF)])
        case "JULY4": fireworks(ctx, w, h, t, [Color(argb: 0xFFEF4444), .white, Color(argb: 0xFF3B82F6)])
        case "CYBERPUNK": cyberpunk(ctx, w, h, t)
        case "RGB":
            let colors = (0...6).map { Color(hue: frac((t * 40 + Double($0) * 60) / 360), saturation: 0.9, brightness: 1).opacity(0.55) }
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 3)), with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
            ctx.fill(Path(CGRect(x: 0, y: h - 3, width: w, height: 3)), with: .linearGradient(Gradient(colors: colors.reversed()), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
        case "Y2K":
            // CRT scanlines (one path) and a soft vignette.
            var lines = Path(), y = 0.0
            while y < h { lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: w, y: y)); y += 3 }
            ctx.stroke(lines, with: .color(.black.opacity(0.09)), lineWidth: 1)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.35)]), center: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endRadius: max(w, h) * 0.75))
        case "ACIDWAVE": acidOverlay(ctx, w, h, t)
        case "CATRAVE": catRaveOverlay(ctx, w, h, t, ps.map(pos), ps)
        case "SPACE":
            for p in ps {
                let a = 0.35 + 0.65 * ((sin(t * (1.5 + p.speed) + p.phase) + 1) / 2), c = pos(p), r = 1.5 + p.size * 2
                ctx.circle(c, r, .white.opacity(a))
                if p.kind == 0 {
                    ctx.line(CGPoint(x: c.x - r * 3, y: c.y), CGPoint(x: c.x + r * 3, y: c.y), .white.opacity(a * 0.6), 1.2)
                    ctx.line(CGPoint(x: c.x, y: c.y - r * 3), CGPoint(x: c.x, y: c.y + r * 3), .white.opacity(a * 0.6), 1.2)
                }
            }
        case "OCEAN":
            for p in ps {
                let c = pos(p), r = 4 + p.size * 9
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.35)), lineWidth: 1.6)
                ctx.circle(CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), r * 0.25, .white.opacity(0.5))
            }
        default: break
        }
    }

    private func bolt(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ seed: Int) {
        var r = SceneRandom(seed &* 31)
        var x = w * (0.3 + r.next() * 0.5), y = 0.0
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        while y < h * 0.6 {
            x += (r.next() - 0.5) * 90
            y += 40 + r.next() * 50
            path.addLine(to: CGPoint(x: x, y: y))
        }
        ctx.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 4)
    }

    private func christmasLights(_ ctx: GraphicsContext, _ w: Double, _ t: Double) {
        let colors: [UInt32] = [0xFFFF3B30, 0xFF34C759, 0xFFFFCC00, 0xFF0A84FF]
        for i in 0..<26 {
            let fx = (Double(i) + 0.5) / 26
            let c = CGPoint(x: fx * w, y: 10 + 18 * abs(sin(fx * .pi * 6)))
            let on = (Int(t * 2) + i) % 3 != 0
            let col = Color(argb: colors[i % 4])
            ctx.circle(c, 6, col.opacity(on ? 0.9 : 0.25))
            if on { ctx.circle(c, 16, col.opacity(0.18)) }
        }
    }

    private func cyberpunk(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        let pink = Color(argb: 0xFFFF2A6D), cyan = Color(argb: 0xFF05D9E8)
        let top = h * 0.78
        ctx.fill(Path(CGRect(x: 0, y: top, width: w, height: h - top)), with: .linearGradient(Gradient(colors: [.clear, pink.opacity(0.10)]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))
        var y = top + (t * 40).truncatingRemainder(dividingBy: 40)
        while y < h { ctx.line(CGPoint(x: 0, y: y), CGPoint(x: w, y: y), cyan.opacity(0.18), 1.2); y += 40 }
        for i in -12...12 { ctx.line(CGPoint(x: w / 2 + Double(i) * 30, y: top), CGPoint(x: w / 2 + Double(i) * 180, y: h), pink.opacity(0.16), 1.2) }
        var lines = Path(), s = 0.0
        while s < h { lines.move(to: CGPoint(x: 0, y: s)); lines.addLine(to: CGPoint(x: w, y: s)); s += 4 }
        ctx.stroke(lines, with: .color(.white.opacity(0.025)), lineWidth: 1)
    }

    private func halloween(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double, _ at: [CGPoint], _ ps: [ThemeParticle]) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.3)), with: .linearGradient(Gradient(colors: [Color(argb: 0x22FF7518), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.3)))
        let moon = CGPoint(x: w * 0.88, y: h * 0.14)
        ctx.glow(moon, 180, Color(argb: 0x40FFB347))
        ctx.circle(moon, 46, Color(argb: 0x66FFC069))
        for (c, p) in zip(at, ps) {
            let bw = 14 + p.size * 10, flap = sin(t * 9 + p.phase) * 0.6
            var bat = Path()
            bat.move(to: c)
            bat.addQuadCurve(to: CGPoint(x: c.x - bw, y: c.y + bw * 0.1), control: CGPoint(x: c.x - bw * 0.5, y: c.y - bw * (0.4 + flap)))
            bat.addQuadCurve(to: CGPoint(x: c.x, y: c.y + bw * 0.25), control: CGPoint(x: c.x - bw * 0.5, y: c.y + bw * 0.05))
            bat.addQuadCurve(to: CGPoint(x: c.x + bw, y: c.y + bw * 0.1), control: CGPoint(x: c.x + bw * 0.5, y: c.y + bw * 0.05))
            bat.addQuadCurve(to: c, control: CGPoint(x: c.x + bw * 0.5, y: c.y - bw * (0.4 + flap)))
            ctx.fill(bat, with: .color(Color(argb: 0x99FF8C2E)))
        }
    }

    /** A burst every ~1.4 s at a random spot, sparks flying out and fading. */
    private func fireworks(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double, _ colors: [Color]) {
        for k in 0..<3 {
            let period = 1.4, local = t + Double(k) * 0.47
            let n = Int(local / period), age = local.truncatingRemainder(dividingBy: period) / period
            var r = SceneRandom(n * 7 + k)
            let c = CGPoint(x: w * (0.15 + r.next() * 0.7), y: h * (0.1 + r.next() * 0.35))
            let color = colors[r.int(colors.count)]
            for i in 0..<26 {
                let a = Double(i) / 26 * 6.283, d = age * min(w, h) * 0.18
                ctx.circle(CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d + age * age * 40), 2.5, color.opacity((1 - age) * 0.8))
            }
        }
    }

    private func heart(_ ctx: GraphicsContext, _ c: CGPoint, _ r: Double, _ color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y + r * 0.9))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - r * 0.4), control1: CGPoint(x: c.x - r * 1.6, y: c.y - r * 0.2), control2: CGPoint(x: c.x - r * 0.6, y: c.y - r * 1.3))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + r * 0.9), control1: CGPoint(x: c.x + r * 0.6, y: c.y - r * 1.3), control2: CGPoint(x: c.x + r * 1.6, y: c.y - r * 0.2))
        ctx.fill(p, with: .color(color))
    }

    private func sparkles(_ ctx: GraphicsContext, _ at: [CGPoint], _ ps: [ThemeParticle], _ color: Color) {
        for (c, p) in zip(at, ps) {
            let a = 0.4 + 0.6 * max(0, sin(p.phase + Double(c.y) / 50))
            ctx.circle(c, 8 * p.size, color.opacity(0.18 * a))
            ctx.circle(c, 1.6 * p.size, color.opacity(0.8 * a))
        }
    }

    /** A small menorah glowing at the bottom left: nine flickering candles. */
    private func menorah(_ ctx: GraphicsContext, _ h: Double, _ t: Double) {
        let baseY = h - 30, x0 = 60.0
        ctx.line(CGPoint(x: x0, y: baseY), CGPoint(x: x0 + 200, y: baseY), Color(argb: 0x88D4AF37), 4)
        for i in 0..<9 {
            let x = x0 + Double(i) * 25, top = baseY - (i == 4 ? 70 : 52)
            ctx.line(CGPoint(x: x, y: baseY), CGPoint(x: x, y: top), Color(argb: 0x99E5E7EB), 6)
            let f = 0.8 + 0.2 * sin(t * 11 + Double(i))
            ctx.circle(CGPoint(x: x, y: top - 8), 12 * f, Color(argb: 0x55FFD166))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: top - 15 * f, width: 6, height: 12 * f)), with: .color(Color(argb: 0xCCFFC145)))
        }
    }

    /** A row of diya lamps along the bottom, flames flickering. */
    private func diyas(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        for i in 0..<9 {
            let x = w * (Double(i) + 0.5) / 9, y = h - 22
            var bowl = Path()
            bowl.addArc(center: CGPoint(x: x, y: y), radius: 18, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            ctx.fill(bowl, with: .color(Color(argb: 0x99B45309)))
            let f = 0.8 + 0.25 * sin(t * 9 + Double(i) * 1.7)
            ctx.circle(CGPoint(x: x, y: y - 16), 22 * f, Color(argb: 0x44FFA62B))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 26 * f, width: 8, height: 16 * f)), with: .color(Color(argb: 0xDDFFD166)))
        }
    }

    /** Red lanterns hanging along the top, swinging gently. */
    private func lanterns(_ ctx: GraphicsContext, _ w: Double, _ t: Double) {
        for i in 0..<6 {
            let x = w * (0.08 + Double(i) * 0.17)
            ctx.rotated(sin(t * 1.2 + Double(i)) * 6, around: CGPoint(x: x, y: 0)) { g in
                g.line(CGPoint(x: x, y: 0), CGPoint(x: x, y: 40), Color(argb: 0x88FFD166), 2)
                g.fill(Path(ellipseIn: CGRect(x: x - 26, y: 40, width: 52, height: 44)), with: .color(Color(argb: 0xAAE11D2E)))
                g.rect(CGRect(x: x - 12, y: 36, width: 24, height: 6), Color(argb: 0xAAFFD166))
                g.rect(CGRect(x: x - 12, y: 82, width: 24, height: 6), Color(argb: 0xAAFFD166))
                g.line(CGPoint(x: x, y: 88), CGPoint(x: x, y: 108), Color(argb: 0x88FFD166), 2)
            }
        }
    }

    /** Corner registration marks and an occasional one-line glitch in the accent. */
    private func acidOverlay(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        let a = P.accent, m = 18.0, l = 26.0
        for (p, d) in [(CGPoint(x: m, y: m), (1.0, 1.0)), (CGPoint(x: w - m, y: m), (-1.0, 1.0)), (CGPoint(x: m, y: h - m), (1.0, -1.0)), (CGPoint(x: w - m, y: h - m), (-1.0, -1.0))] {
            ctx.line(p, CGPoint(x: p.x + l * d.0, y: p.y), a.opacity(0.7), 2)
            ctx.line(p, CGPoint(x: p.x, y: p.y + l * d.1), a.opacity(0.7), 2)
        }
        if t.truncatingRemainder(dividingBy: 5) < 0.12 {
            var r = SceneRandom(Int(t / 5))
            let y = r.next() * h
            ctx.rect(CGRect(x: 0, y: y, width: w, height: 3), a.opacity(0.35))
            ctx.rect(CGRect(x: w * 0.2, y: y + 5, width: w * 0.5, height: 2), Color(argb: 0xFFFF2BD6).opacity(0.25))
        }
    }

    /** Confetti, sweeping lasers, a strobe pulse on the beat and cats bopping along the bottom. */
    private func catRaveOverlay(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double, _ at: [CGPoint], _ ps: [ThemeParticle]) {
        let beat = frac(t * 2.13)
        ctx.rect(CGRect(x: 0, y: 0, width: w, height: h), Color(hue: frac(t * 150 / 360), saturation: 1, brightness: 1).opacity(0.10 * (1 - beat)))
        for i in 0..<4 {
            let o = CGPoint(x: w * (0.2 + Double(i) * 0.2), y: h)
            let a = (250 + sin(t * (1.1 + Double(i) * 0.3)) * 35) * .pi / 180
            ctx.line(o, CGPoint(x: o.x + cos(a) * h * 1.4, y: o.y + sin(a) * h * 1.4), Color(hue: frac((t * 90 + Double(i) * 90) / 360), saturation: 1, brightness: 1).opacity(0.35), 3)
        }
        for (c, p) in zip(at, ps) { ctx.rect(CGRect(x: c.x, y: c.y, width: 6 * p.size, height: 3 * p.size), Color(hue: frac((p.phase * 57 + t * 200) / 360), saturation: 0.9, brightness: 1).opacity(0.7)) }
        for i in 0..<7 {
            let bob = abs(sin((t * 2.13 + Double(i) * 0.5) * .pi)) * 22
            catFace(ctx, CGPoint(x: w * (Double(i) + 0.5) / 7, y: h - 40 - bob), 26, Color(hue: frac((t * 120 + Double(i) * 51) / 360), saturation: 0.7, brightness: 1).opacity(0.85))
        }
    }
}

/** A cat face: round head, pointy ears, eyes. */
func catFace(_ ctx: GraphicsContext, _ c: CGPoint, _ r: Double, _ color: Color) {
    for s in [-1.0, 1.0] {
        var ear = Path()
        ear.move(to: CGPoint(x: c.x + s * r * 0.9, y: c.y - r * 0.3))
        ear.addLine(to: CGPoint(x: c.x + s * r * 0.7, y: c.y - r * 1.25))
        ear.addLine(to: CGPoint(x: c.x + s * r * 0.2, y: c.y - r * 0.8))
        ear.closeSubpath()
        ctx.fill(ear, with: .color(color))
    }
    ctx.circle(c, r, color)
    ctx.circle(CGPoint(x: c.x - r * 0.38, y: c.y - r * 0.1), r * 0.14, .black.opacity(0.75))
    ctx.circle(CGPoint(x: c.x + r * 0.38, y: c.y - r * 0.1), r * 0.14, .black.opacity(0.75))
    ctx.circle(CGPoint(x: c.x, y: c.y + r * 0.2), r * 0.1, Color(argb: 0xFFFF8FB1))
    for s in [-1.0, 1.0] {
        for k in [-0.1, 0.15] {
            ctx.line(CGPoint(x: c.x + s * r * 0.25, y: c.y + r * (0.25 + k)), CGPoint(x: c.x + s * r * 1.15, y: c.y + r * (0.15 + k * 2)), .black.opacity(0.5), 1.5)
        }
    }
}

/** The PlayStation button legend: Return is ✕ (enter), Esc is ○, O is △ (options). */
private struct Ps2Legend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach([(2, 0xFF7CB2EE, "Enter"), (1, 0xFFFF6B6B, "Back"), (0, 0xFF40E0A0, "Options")] as [(Int, UInt32, String)], id: \.0) { kind, color, label in
                HStack(spacing: 6) {
                    Canvas { ctx, size in psGlyph(ctx, kind, CGPoint(x: size.width / 2, y: size.height / 2), size.width / 2, Color(argb: color), 2.5) }.frame(width: 16, height: 16)
                    Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.45)))
    }
}

/** A face-button glyph: 0 triangle, 1 circle, 2 cross, 3 square. */
func psGlyph(_ ctx: GraphicsContext, _ kind: Int, _ c: CGPoint, _ r: Double, _ color: Color, _ stroke: Double) {
    switch kind {
    case 0:
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x + r * 0.9, y: c.y + r * 0.65)); p.addLine(to: CGPoint(x: c.x - r * 0.9, y: c.y + r * 0.65)); p.closeSubpath()
        ctx.stroke(p, with: .color(color), lineWidth: stroke)
    case 1: ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.85, y: c.y - r * 0.85, width: r * 1.7, height: r * 1.7)), with: .color(color), lineWidth: stroke)
    case 2:
        ctx.line(CGPoint(x: c.x - r * 0.75, y: c.y - r * 0.75), CGPoint(x: c.x + r * 0.75, y: c.y + r * 0.75), color, stroke)
        ctx.line(CGPoint(x: c.x + r * 0.75, y: c.y - r * 0.75), CGPoint(x: c.x - r * 0.75, y: c.y + r * 0.75), color, stroke)
    default: ctx.stroke(Path(CGRect(x: c.x - r * 0.7, y: c.y - r * 0.7, width: r * 1.4, height: r * 1.4)), with: .color(color), lineWidth: stroke)
    }
}
