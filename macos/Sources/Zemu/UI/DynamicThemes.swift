import SwiftUI
import ZemuCore

/**
 * Animated themes. Some bring their own colors (Cyberpunk, Halloween, ...); the rest keep the
 * chosen color theme and only add the effect. Effects are drawn above the UI with low opacity and
 * never take clicks.
 */
enum DynamicTheme: String, CaseIterable {
    case NONE, RGB, SNOWFALL, RAIN, LIGHTNING, CYBERPUNK, HALLOWEEN, CHRISTMAS, AURORA, FIREFLIES, MATRIX, SAKURA

    var label: String {
        switch self {
        case .NONE: "Off"; case .RGB: "RGB"; case .SNOWFALL: "Snowfall"; case .RAIN: "Rain"; case .LIGHTNING: "Lightning storm"
        case .CYBERPUNK: "Cyberpunk"; case .HALLOWEEN: "Halloween"; case .CHRISTMAS: "Christmas"; case .AURORA: "Aurora"
        case .FIREFLIES: "Fireflies"; case .MATRIX: "Matrix"; case .SAKURA: "Sakura"
        }
    }

    var palette: (UInt32, UInt32)? {
        switch self {
        case .LIGHTNING: (0xFF8AB4FF, 0xFF06080F); case .CYBERPUNK: (0xFFFF2A6D, 0xFF0B0518); case .HALLOWEEN: (0xFFFF7518, 0xFF0F0710)
        case .CHRISTMAS: (0xFFD42426, 0xFF06120B); case .AURORA: (0xFF34D399, 0xFF050B14); case .FIREFLIES: (0xFFFACC15, 0xFF070A06)
        case .MATRIX: (0xFF22C55E, 0xFF000500); case .SAKURA: (0xFFF472B6, 0xFF120810)
        default: nil
        }
    }

    static func of(_ name: String) -> DynamicTheme { DynamicTheme(rawValue: name) ?? .NONE }

    /** Colors after applying this theme's own palette (if it has one). */
    func apply(to base: ThemeColors) -> ThemeColors {
        guard let p = palette else { return base }
        return ThemeColors(accent: Color(argb: p.0), background: Color(argb: p.1))
    }

    var particleCount: Int {
        switch self {
        case .SNOWFALL, .CHRISTMAS: 90; case .RAIN, .LIGHTNING: 110; case .FIREFLIES: 36
        case .HALLOWEEN: 14; case .MATRIX: 48; case .SAKURA: 40; default: 0
        }
    }
}

private struct Particle {
    var x: Double, y: Double, speed: Double, size: Double, drift: Double, phase: Double
}

private func frac(_ v: Double) -> Double { v - floor(v) }

/** Draws the animated theme. RGB instead cycles the accent color of the whole UI. */
struct DynamicThemeLayer: View {
    let theme: DynamicTheme
    @State private var particles: [Particle] = []
    @State private var start = Date()

    var body: some View {
        if theme == .NONE {
            Color.clear.onAppear { P.accentOverride = nil }
        } else {
            TimelineView(.animation(minimumInterval: theme == .RGB ? 1.0 / 8 : 1.0 / 40)) { tl in
                let t = tl.date.timeIntervalSince(start)
                Canvas { ctx, size in draw(ctx, size, t) }
                    .onChange(of: Int(t * 8)) { _, _ in
                        if theme == .RGB { P.accentOverride = Color(hue: frac(t * 24 / 360), saturation: 0.85, brightness: 1) }
                    }
            }
            .allowsHitTesting(false)
            .onAppear { setup() }
            .onChange(of: theme) { _, _ in setup() }
        }
    }

    private func setup() {
        if theme != .RGB { P.accentOverride = nil }
        var rng = SeededRandom(seed: 42)
        func r() -> Double { Double(rng.next() % 1_000_000) / 1_000_000 }
        particles = (0..<theme.particleCount).map { _ in
            Particle(x: r(), y: r(), speed: 0.4 + r(), size: 0.5 + r(), drift: r() * 2 - 1, phase: r() * 6.28)
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        switch theme {
        case .SNOWFALL, .CHRISTMAS:
            for p in particles {
                let y = frac(p.y + t * 0.05 * p.speed) * h * 1.1 - h * 0.05
                let x = frac(p.x + 0.015 * sin(t + p.phase)) * w
                let r = 1.5 + p.size * 2.6
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.35 + 0.35 * p.size / 1.5)))
            }
            if theme == .CHRISTMAS { christmasLights(ctx, w, t) }
        case .RAIN, .LIGHTNING:
            let color = theme == .RAIN ? Color(argb: 0x55B0C4DE) : Color(argb: 0x448AB4FF)
            for p in particles {
                let y = frac(p.y + t * 1.1 * p.speed) * h
                let x = frac(p.x + t * 0.12) * w
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - 6, y: y + 22 + p.size * 18))
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            if theme == .LIGHTNING {
                // A bolt every few seconds at a seeded random moment.
                let period = 6.5
                let k = floor(t / period)
                var rng = SeededRandom(seed: Int64(k))
                let boltAt = k * period + Double(rng.next() % 1000) / 1000 * 3
                let flash = t >= boltAt ? max(0, 1 - (t - boltAt) * 2.6) : 0
                if flash > 0 {
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.22 * flash)))
                    if flash > 0.75 { bolt(ctx, w, h, Int64(k)) }
                }
            }
        case .CYBERPUNK: cyberpunk(ctx, w, h, t)
        case .HALLOWEEN: halloween(ctx, w, h, t)
        case .AURORA: aurora(ctx, w, h, t)
        case .FIREFLIES:
            for p in particles {
                let a = max(0, min(1, 0.5 + 0.5 * sin(t * 2 + p.phase)))
                let c = CGPoint(x: frac(p.x + 0.02 * sin(t * 0.7 + p.phase) * 10) * w, y: frac(p.y + 0.02 * sin(t * 0.5 + p.phase * 1.3) * 10) * h)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36)), with: .color(Color(argb: 0xFFFACC15).opacity(0.12 * a)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(Color(argb: 0xFFFDE68A).opacity(0.8 * a)))
            }
        case .MATRIX:
            for (i, p) in particles.enumerated() {
                let x = (Double(i) + 0.5) / Double(particles.count) * w
                let head = frac(p.y + t * 0.25 * p.speed) * h * 1.3
                for k in 0..<14 {
                    let y = head - Double(k) * 22
                    if y < 0 { break }
                    ctx.fill(Path(CGRect(x: x, y: y, width: 8, height: 14)), with: .color(Color(argb: 0xFF22C55E).opacity(max(0, 0.35 - Double(k) * 0.025))))
                }
            }
        case .SAKURA:
            for p in particles {
                let c = CGPoint(x: frac(p.x + t * 0.03 * (1 + sin(t + p.phase)) * 0.5) * w, y: frac(p.y + t * 0.04 * p.speed) * h)
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .degrees((t * 60 + p.phase * 57).truncatingRemainder(dividingBy: 360)))
                g.fill(Path(ellipseIn: CGRect(x: -6 * p.size, y: -3.5 * p.size, width: 12 * p.size, height: 7 * p.size)), with: .color(Color(argb: 0xFFF9A8D4).opacity(0.55)))
            }
        case .RGB:
            let colors = (0...6).map { Color(hue: frac((t * 40 + Double($0) * 60) / 360), saturation: 0.9, brightness: 1).opacity(0.55) }
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 3)), with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
            ctx.fill(Path(CGRect(x: 0, y: h - 3, width: w, height: 3)), with: .linearGradient(Gradient(colors: colors.reversed()), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
        case .NONE: break
        }
    }

    private func bolt(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ seed: Int64) {
        var rng = SeededRandom(seed: seed &* 31)
        func r() -> Double { Double(rng.next() % 1000) / 1000 }
        var x = w * (0.3 + r() * 0.5), y = 0.0
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        while y < h * 0.6 {
            x += (r() - 0.5) * 90
            y += 40 + r() * 50
            path.addLine(to: CGPoint(x: x, y: y))
        }
        ctx.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 4)
    }

    private func christmasLights(_ ctx: GraphicsContext, _ w: Double, _ t: Double) {
        let colors = [Color(argb: 0xFFFF3B30), Color(argb: 0xFF34C759), Color(argb: 0xFFFFCC00), Color(argb: 0xFF0A84FF)]
        let n = 26
        for i in 0..<n {
            let fx = (Double(i) + 0.5) / Double(n)
            let c = CGPoint(x: fx * w, y: 10 + 18 * abs(sin(fx * .pi * 6)))
            let on = (Int(t * 2) + i) % 3 != 0
            let col = colors[i % colors.count]
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(col.opacity(on ? 0.9 : 0.25)))
            if on { ctx.fill(Path(ellipseIn: CGRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32)), with: .color(col.opacity(0.18))) }
        }
    }

    private func cyberpunk(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        let pink = Color(argb: 0xFFFF2A6D), cyan = Color(argb: 0xFF05D9E8)
        let top = h * 0.78
        ctx.fill(Path(CGRect(x: 0, y: top, width: w, height: h - top)),
                 with: .linearGradient(Gradient(colors: [.clear, pink.opacity(0.10)]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))
        var y = top + (t * 40).truncatingRemainder(dividingBy: 40)
        while y < h {
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: w, y: y)) }, with: .color(cyan.opacity(0.18)), lineWidth: 1.2)
            y += 40
        }
        let cx = w / 2
        for i in -12...12 {
            ctx.stroke(Path { $0.move(to: CGPoint(x: cx + Double(i) * 30, y: top)); $0.addLine(to: CGPoint(x: cx + Double(i) * 180, y: h)) }, with: .color(pink.opacity(0.16)), lineWidth: 1.2)
        }
        var s = 0.0
        while s < h {
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: s)); $0.addLine(to: CGPoint(x: w, y: s)) }, with: .color(.white.opacity(0.025)), lineWidth: 1)
            s += 4
        }
    }

    private func halloween(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.3)),
                 with: .linearGradient(Gradient(colors: [Color(argb: 0x22FF7518), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.3)))
        let moon = CGPoint(x: w * 0.88, y: h * 0.14)
        ctx.fill(Path(ellipseIn: CGRect(x: moon.x - 180, y: moon.y - 180, width: 360, height: 360)),
                 with: .radialGradient(Gradient(colors: [Color(argb: 0x40FFB347), .clear]), center: moon, startRadius: 0, endRadius: 180))
        ctx.fill(Path(ellipseIn: CGRect(x: moon.x - 46, y: moon.y - 46, width: 92, height: 92)), with: .color(Color(argb: 0x66FFC069)))
        for p in particles {
            let x = frac(p.x + t * 0.05 * p.speed) * w
            let y = frac(p.y + 0.02 * sin(t * 2 + p.phase)) * h * 0.6
            let bw = 14 + p.size * 10
            let flap = sin(t * 9 + p.phase) * 0.6
            var bat = Path()
            bat.move(to: CGPoint(x: x, y: y))
            bat.addQuadCurve(to: CGPoint(x: x - bw, y: y + bw * 0.1), control: CGPoint(x: x - bw * 0.5, y: y - bw * (0.4 + flap)))
            bat.addQuadCurve(to: CGPoint(x: x, y: y + bw * 0.25), control: CGPoint(x: x - bw * 0.5, y: y + bw * 0.05))
            bat.addQuadCurve(to: CGPoint(x: x + bw, y: y + bw * 0.1), control: CGPoint(x: x + bw * 0.5, y: y + bw * 0.05))
            bat.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x + bw * 0.5, y: y - bw * (0.4 + flap)))
            ctx.fill(bat, with: .color(Color(argb: 0x99FF8C2E)))
        }
    }

    private func aurora(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        let bands = [Color(argb: 0xFF34D399), Color(argb: 0xFF22D3EE), Color(argb: 0xFFA78BFA)]
        for (i, c) in bands.enumerated() {
            let base = h * (0.12 + Double(i) * 0.07)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: base))
            var x = 0.0
            while x <= w {
                path.addLine(to: CGPoint(x: x, y: base + sin(x / w * 6 + t * (0.3 + Double(i) * 0.1) + Double(i)) * 40))
                x += 24
            }
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: .zero)
            path.closeSubpath()
            ctx.fill(path, with: .linearGradient(Gradient(colors: [c.opacity(0), c.opacity(0.10)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: base + 60)))
        }
    }
}
