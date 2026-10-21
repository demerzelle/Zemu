import SwiftUI
import ZemuCore

/**
 * The scene behind the app for whole-app themes (PS2, Outer Space, Cybercore desktops, …). Pages
 * turn see-through while one is on, so it shows between the panels.
 */
struct ThemeBackdrop: View {
    let style: SceneStyle
    let variant: String
    @State private var start = Date()

    private var fps: Double {
        switch style {
        case .ps2, .sixteen: 15; case .retro: 4; case .pocket: 8; case .acid, .graffiti: 1; default: 24
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / fps)) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                switch style {
                case .ps2: ps2(ctx, size, t)
                case .acid: acid(ctx, size)
                case .ethereal: ethereal(ctx, size, t)
                case .retro: retro(ctx, size, t)
                case .graffiti: graffiti(ctx, size)
                case .liquid: liquid(ctx, size, t)
                case .catrave: catrave(ctx, size, t)
                case .space: space(ctx, size, t)
                case .night: night(ctx, size, t)
                case .alien: alien(ctx, size, t)
                case .ocean: ocean(ctx, size, t)
                case .pocket: pocket(ctx, size, t)
                case .sixteen: sixteen(ctx, size, t)
                case .normal: break
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func vgrad(_ ctx: GraphicsContext, _ r: CGRect, _ colors: [Color]) {
        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.minX, y: r.maxY)))
    }

    // MARK: PS2 · Y2K

    /** Glowing translucent towers rise and fall out of a blue fog; specks drift up; faint button shapes float by. */
    private func ps2(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height, light = P.light, glow = Color(argb: 0xFF6FB4FF)
        vgrad(ctx, CGRect(origin: .zero, size: size), light ? [Color(argb: 0xFFDCE6FA), Color(argb: 0xFFB4C8F0)] : [Color(argb: 0xFF000106), Color(argb: 0xFF02092A)])
        let horizon = h * 0.66
        vgrad(ctx, CGRect(x: 0, y: horizon - h * 0.2, width: w, height: h), [.clear, glow.opacity(light ? 0.25 : 0.18), .clear])
        for row in 0...2 {
            let depth = 1 - Double(row) * 0.28, n = 7 + row * 5
            let tw = w / Double(n) * 0.36 * depth
            for i in 0..<n {
                let seed = Double((i * 53 + row * 97) % 89) / 89
                let x = (Double(i) + 0.5) / Double(n) * w + (seed - 0.5) * tw * 2
                let grow = 0.7 + 0.3 * sin(t * (0.18 + seed * 0.25) + seed * 6.28)
                let th = h * (0.12 + 0.38 * seed) * depth * grow, base = horizon + Double(row) * 3, a = 0.14 + 0.22 * depth
                vgrad(ctx, CGRect(x: x - tw / 2, y: base - th, width: tw, height: th + 4), [.white.opacity(a * 1.4), glow.opacity(a), glow.opacity(0)])
            }
        }
        for k in 0..<26 {
            var r = SceneRandom(k * 31)
            let speed = 0.02 + r.next() * 0.04, y0 = r.next()
            let y = (1 - frac(t * speed + y0)) * h, x = r.next() * w + sin(t * 0.5 + Double(k)) * 3
            ctx.rect(CGRect(x: x, y: y, width: 2, height: 2), .white.opacity(0.35 + 0.4 * r.next()))
        }
        let shapes: [UInt32] = [0xFF40E0A0, 0xFFFF6B6B, 0xFF7CB2EE, 0xFFF58AE6]
        for (i, c) in shapes.enumerated() {
            let x = (frac((Double(i) * 0.27 + 0.08 + t * 0.006) / 1.1) * 1.1 - 0.05) * w
            let y = h * (0.16 + 0.1 * Double(i)) + sin(t * 0.3 + Double(i) * 1.7) * 4 * 5
            ctx.rotated(t * 8 * (i % 2 == 0 ? 1 : -1), around: CGPoint(x: x, y: y)) { psGlyph($0, i, CGPoint(x: x, y: y), h * 0.045, Color(argb: c).opacity(0.35), 4) }
        }
    }

    // MARK: Acidwave

    /** A technical sheet: fine grid, a huge stencil word, hazard stripes and a barcode. */
    private func acid(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height, accent = P.accent, ink = P.text
        ctx.rect(CGRect(origin: .zero, size: size), P.base)
        var grid = Path(), x = 0.0
        while x < w { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: h)); x += 48 }
        var y = 0.0
        while y < h { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y)); y += 48 }
        ctx.stroke(grid, with: .color(ink.opacity(0.045)), lineWidth: 1)
        ctx.rotated(90, around: CGPoint(x: w - 40, y: 40)) {
            $0.draw(Text("ZEMU//SIG").font(.system(size: 150, weight: .black, design: .monospaced)).foregroundStyle(accent.opacity(0.07)), at: CGPoint(x: w - 40, y: 40), anchor: .topLeading)
        }
        let bandY = h - 26
        var sx = -40.0
        while sx < w * 0.38 {
            var p = Path()
            p.move(to: CGPoint(x: sx, y: bandY + 26)); p.addLine(to: CGPoint(x: sx + 16, y: bandY)); p.addLine(to: CGPoint(x: sx + 32, y: bandY)); p.addLine(to: CGPoint(x: sx + 16, y: bandY + 26)); p.closeSubpath()
            ctx.fill(p, with: .color(accent.opacity(0.18)))
            sx += 34
        }
        let bx = w - 260
        var r = SceneRandom(7), px = bx
        while px < bx + 150 { let bw = 1 + Double(r.int(4)); ctx.rect(CGRect(x: px, y: h - 70, width: bw, height: 40), ink.opacity(0.22)); px += bw + 2 + Double(r.int(3)) }
        ctx.draw(Text("FEED 07 · ACQ ACTIVE · UPLINK OK").font(.system(size: 10, design: .monospaced)).foregroundStyle(ink.opacity(0.35)), at: CGPoint(x: bx - 120, y: h - 22), anchor: .topLeading)
    }

    // MARK: Ethereal

    /** Deep twilight with slow aurora curtains, drifting light orbs and faint stars. */
    private func ethereal(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height, light = P.light
        vgrad(ctx, CGRect(origin: .zero, size: size), light ? [Color(argb: 0xFFF3EEFF), Color(argb: 0xFFE2F3FF), Color(argb: 0xFFFBEFFF)] : [Color(argb: 0xFF07061A), Color(argb: 0xFF1A1240), Color(argb: 0xFF0B1A2E)])
        var r = SceneRandom(3)
        for i in 0..<80 {
            let a = (0.15 + 0.4 * r.next()) * (0.6 + 0.4 * sin(t + Double(i)))
            ctx.circle(CGPoint(x: r.next() * w, y: r.next() * h * 0.6), 1.2, .white.opacity(a))
        }
        let bands: [UInt32] = [0xFF8B5CF6, 0xFF22D3EE, 0xFFF472B6, 0xFF34D399]
        for (i, c) in bands.enumerated() {
            let base = h * (0.15 + Double(i) * 0.09)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: base))
            var x = 0.0
            while x <= w { path.addLine(to: CGPoint(x: x, y: base + sin(x / w * 5 + t * (0.15 + Double(i) * 0.05) + Double(i)) * 60)); x += 24 }
            path.addLine(to: CGPoint(x: w, y: 0)); path.addLine(to: .zero); path.closeSubpath()
            ctx.fill(path, with: .linearGradient(Gradient(colors: [Color(argb: c).opacity(0), Color(argb: c).opacity(light ? 0.14 : 0.22)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: base + 80)))
        }
        for i in 0..<6 {
            let c = CGPoint(x: w * (0.1 + frac(Double(i) * 0.19 + t * 0.01) * 0.8), y: h * (0.55 + 0.3 * sin(t * 0.2 + Double(i))))
            ctx.glow(c, 180, Color(argb: bands[i % 4]).opacity(0.18))
        }
    }

    // MARK: Cybercore

    /** The desktop: Classic teal, Kawaii pastel hearts and clouds, or XP's blue sky and green hill. */
    private func retro(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        switch variant {
        case "KAWAII":
            vgrad(ctx, CGRect(origin: .zero, size: size), [Color(argb: 0xFFFFD6EC), Color(argb: 0xFFE9D9FF)])
            let step = 64.0
            var y = 0.0, row = 0
            while y < h {
                var x = row % 2 == 0 ? 0 : step / 2
                while x < w {
                    if (Int(x / step) + row) % 3 == 0 {
                        ctx.circle(CGPoint(x: x, y: y), 3, .white.opacity(0.55))
                    } else {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y + 4))
                        p.addCurve(to: CGPoint(x: x, y: y - 2), control1: CGPoint(x: x - 8, y: y - 2), control2: CGPoint(x: x - 3, y: y - 7))
                        p.addCurve(to: CGPoint(x: x, y: y + 4), control1: CGPoint(x: x + 3, y: y - 7), control2: CGPoint(x: x + 8, y: y - 2))
                        ctx.fill(p, with: .color(Color(argb: 0x66FF7CC8)))
                    }
                    x += step
                }
                y += step / 1.6; row += 1
            }
            for i in 0..<3 {
                let cx = (t * 6 + Double(i) * 420).truncatingRemainder(dividingBy: w + 300) - 150, cy = h * (0.15 + Double(i) * 0.2)
                for (dx, dy) in [(0.0, 0.0), (30, -14), (60, 0), (30, 10)] { ctx.circle(CGPoint(x: cx + dx, y: cy + dy), 26, .white.opacity(0.8)) }
            }
        case "XP":
            vgrad(ctx, CGRect(x: 0, y: 0, width: w, height: h * 0.7), [Color(argb: 0xFF2E6FD8), Color(argb: 0xFF6FA8F0), Color(argb: 0xFFB8D8F8)])
            ctx.rect(CGRect(x: 0, y: h * 0.7, width: w, height: h * 0.3), Color(argb: 0xFFB8D8F8))
            for i in 0..<4 {
                let cx = (t * 4 + Double(i) * 500).truncatingRemainder(dividingBy: w + 400) - 200
                ctx.fill(Path(ellipseIn: CGRect(x: cx, y: h * (0.12 + Double(i) * 0.08), width: 260, height: 50)), with: .color(.white.opacity(0.75)))
            }
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: h * 0.72))
            hill.addCurve(to: CGPoint(x: w, y: h * 0.7), control1: CGPoint(x: w * 0.3, y: h * 0.52), control2: CGPoint(x: w * 0.7, y: h * 0.62))
            hill.addLine(to: CGPoint(x: w, y: h)); hill.addLine(to: CGPoint(x: 0, y: h)); hill.closeSubpath()
            ctx.fill(hill, with: .linearGradient(Gradient(colors: [Color(argb: 0xFF6CC24A), Color(argb: 0xFF2F8A1F)]), startPoint: CGPoint(x: 0, y: h * 0.55), endPoint: CGPoint(x: 0, y: h)))
        default:
            ctx.rect(CGRect(origin: .zero, size: size), Color(argb: 0xFF008080))
        }
    }

    // MARK: Graffiti

    /** A subway wall: dark bricks, layered tags with drips, a big bubble-letter piece. */
    private func graffiti(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height, accent = P.accent
        ctx.rect(CGRect(origin: .zero, size: size), Color(argb: 0xFF1A1A1A))
        let bw = 120.0, bh = 44.0
        var row = 0, y = 0.0
        while y < h {
            var x = row % 2 == 0 ? 0 : -bw / 2
            while x < w {
                let shade = 0.10 + 0.05 * Double(((Int(x) * 7 + row * 13) % 5 + 5) % 5) / 5
                ctx.rect(CGRect(x: x + 3, y: y + 3, width: bw - 6, height: bh - 6), Color(argb: 0xFF7A3B2E).opacity(shade + 0.12))
                x += bw
            }
            y += bh; row += 1
        }
        var r = SceneRandom(11)
        let paints = [accent, Color(argb: 0xFF00E5FF), Color(argb: 0xFFFFE600), Color(argb: 0xFF39FF14), .white]
        for _ in 0..<9 {
            let c = paints[r.int(paints.count)].opacity(0.32)
            let x0 = r.next() * w, y0 = r.next() * h
            var p = Path()
            p.move(to: CGPoint(x: x0, y: y0))
            for _ in 0..<4 {
                p.addCurve(to: CGPoint(x: x0 + r.next() * 260, y: y0 + r.next() * 30 - 15),
                           control1: CGPoint(x: x0 + r.next() * 180 - 40, y: y0 - r.next() * 80),
                           control2: CGPoint(x: x0 + r.next() * 220, y: y0 + r.next() * 60))
            }
            ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: 6 + r.next() * 6, lineCap: .round))
            for _ in 0..<3 { let dx = x0 + r.next() * 200; ctx.line(CGPoint(x: dx, y: y0), CGPoint(x: dx, y: y0 + 20 + r.next() * 70), c, 3, round: true) }
        }
        let at = CGPoint(x: w * 0.45, y: h * 0.52)
        ctx.rotated(-8, around: CGPoint(x: w * 0.6, y: h * 0.65)) { g in
            let font = Font.system(size: 190, weight: .black).width(.condensed)
            g.draw(Text("ZEMU").font(font).foregroundStyle(.black.opacity(0.35)), at: CGPoint(x: at.x + 8, y: at.y + 8), anchor: .topLeading)
            g.draw(Text("ZEMU").font(font).foregroundStyle(accent.opacity(0.18)), at: at, anchor: .topLeading)
        }
    }

    // MARK: Liquid Glass

    /** A vivid, slowly flowing wallpaper for the glass to sit on. */
    private func liquid(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height, light = P.light
        ctx.rect(CGRect(origin: .zero, size: size), light ? Color(argb: 0xFFEFF3FA) : Color(argb: 0xFF060914))
        let blobs: [UInt32] = [0xFF0A84FF, 0xFFBF5AF2, 0xFFFF9F0A, 0xFF30D5C8, 0xFFFF375F]
        for (i, c) in blobs.enumerated() {
            let d = Double(i)
            let center = CGPoint(x: w * (0.5 + 0.38 * sin(t * (0.05 + d * 0.013) + d * 1.3)), y: h * (0.5 + 0.36 * sin(t * (0.04 + d * 0.011) + d * 2.1)))
            ctx.glow(center, max(w, h) * (0.32 + 0.05 * d), Color(argb: c).opacity(light ? 0.35 : 0.55))
        }
    }

    // MARK: Cat Rave

    /** A dark dance floor: a spinning disco ball, sweeping spotlights and a pulsing grid. */
    private func catrave(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        ctx.rect(CGRect(origin: .zero, size: size), Color(argb: 0xFF07000F))
        let beat = frac(t * 2.13), horizon = h * 0.7
        for i in -14...14 {
            ctx.line(CGPoint(x: w / 2 + Double(i) * 40, y: horizon), CGPoint(x: w / 2 + Double(i) * 260, y: h), Color(hue: frac((t * 60 + Double(i) * 12 + 360) / 360), saturation: 1, brightness: 1).opacity(0.25), 2)
        }
        var y = horizon, gap = 8.0
        while y < h { ctx.line(CGPoint(x: 0, y: y), CGPoint(x: w, y: y), Color(argb: 0xFFFF00E6).opacity(0.25 * (1 - beat) + 0.08), 2); y += gap; gap *= 1.35 }
        for i in 0..<3 {
            let top = CGPoint(x: w * (0.25 + Double(i) * 0.25), y: 0)
            let bx = top.x + sin(t * (0.8 + Double(i) * 0.3) + Double(i)) * 0.5 * w * 0.5
            var p = Path()
            p.move(to: top); p.addLine(to: CGPoint(x: bx - 140, y: h)); p.addLine(to: CGPoint(x: bx + 140, y: h)); p.closeSubpath()
            ctx.fill(p, with: .linearGradient(Gradient(colors: [Color(hue: frac((t * 80 + Double(i) * 120) / 360), saturation: 0.8, brightness: 1).opacity(0.22), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        }
        let c = CGPoint(x: w / 2, y: 70)
        ctx.line(CGPoint(x: c.x, y: 0), CGPoint(x: c.x, y: c.y - 44), .gray, 2)
        ctx.circle(c, 44, Color(argb: 0xFFB0B0C8))
        for row in -3...3 {
            for col in 0..<10 {
                let ang = Double(col) / 10 * 6.283 + t * 1.5
                guard sin(ang) >= 0 else { continue }
                let x = c.x + cos(ang) * 44 * cos(Double(row) * 0.4)
                ctx.rect(CGRect(x: x - 4, y: c.y + Double(row) * 11 - 4, width: 7, height: 7), Color(hue: frac((Double(col) * 36 + t * 200) / 360), saturation: 0.3, brightness: 1))
            }
        }
        catFace(ctx, CGPoint(x: w * 0.12, y: h * 0.4 + sin(t * 4) * 20), 60, Color(hue: frac(t * 100 / 360), saturation: 0.6, brightness: 1).opacity(0.3))
        catFace(ctx, CGPoint(x: w * 0.88, y: h * 0.4 + sin(t * 4 + 1.5) * 20), 60, Color(hue: frac((t * 100 + 180) / 360), saturation: 0.6, brightness: 1).opacity(0.3))
    }

    // MARK: Outer Space

    /** Nebulas, a turning galaxy, twinkling stars, a ringed planet, a moon and a rocket on a loop. */
    private func space(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height, m = min(w, h)
        vgrad(ctx, CGRect(origin: .zero, size: size), [Color(argb: 0xFF05071A), Color(argb: 0xFF0B1030), Color(argb: 0xFF1B1446)])
        for (i, n) in [(0.3, 0.3, UInt32(0x55B57BFF)), (0.62, 0.7, 0x4430C8D8), (0.15, 0.55, 0x40FF7AC6)].enumerated() {
            ctx.glow(CGPoint(x: w * (n.0 + 0.03 * sin(t * 0.05 + Double(i))), y: h * n.1), m * 0.45, Color(argb: n.2))
        }
        let g = CGPoint(x: w * 0.66, y: h * 0.16)
        ctx.rotated(t * 2, around: g) { gc in
            for arm in 0..<2 {
                for k in 0..<40 {
                    let a = Double(k) * 0.25 + Double(arm) * .pi, d = Double(k) * 2.6
                    gc.circle(CGPoint(x: g.x + cos(a) * d, y: g.y + sin(a) * d * 0.55), 2.4 - Double(k) * 0.04, .white.opacity(0.5 - Double(k) * 0.011))
                }
            }
            gc.glow(g, 22, Color(argb: 0xFFFFF4D6))
        }
        var r = SceneRandom(5)
        for i in 0..<140 {
            let tw = 0.5 + 0.5 * sin(t * Double(1 + i % 5) + Double(i))
            let a = (0.2 + 0.5 * r.next()) * (0.6 + 0.4 * tw)
            let rad = 1 + r.next() * 1.4
            ctx.circle(CGPoint(x: r.next() * w, y: r.next() * h), rad, .white.opacity(a))
        }
        let p = CGPoint(x: w * 0.84, y: h * 0.22)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 95, y: p.y - 95, width: 190, height: 190)),
                 with: .radialGradient(Gradient(colors: [Color(argb: 0xFFFFB86B), Color(argb: 0xFFE0663B)]), center: CGPoint(x: p.x - 30, y: p.y - 30), startRadius: 0, endRadius: 140))
        ctx.rotated(-18, around: p) { $0.stroke(Path(ellipseIn: CGRect(x: p.x - 170, y: p.y - 26, width: 340, height: 52)), with: .color(Color(argb: 0xFFFFE0A8).opacity(0.8)), lineWidth: 9) }
        let mo = CGPoint(x: w * 0.12, y: h * 0.8)
        ctx.circle(mo, 70, Color(argb: 0xFFD9DDE8))
        ctx.circle(CGPoint(x: mo.x - 20, y: mo.y - 15), 14, Color(argb: 0xFFB8BECC))
        ctx.circle(CGPoint(x: mo.x + 25, y: mo.y + 20), 9, Color(argb: 0xFFB8BECC))
        let a = t * 0.15
        let c = CGPoint(x: w * (0.5 + 0.32 * cos(a)), y: h * (0.5 + 0.28 * sin(a)))
        let heading = atan2(0.28 * cos(a), -0.32 * sin(a)) * 180 / .pi + 90
        ctx.rotated(heading, around: c) { g in
            var body = Path()
            body.move(to: CGPoint(x: c.x, y: c.y - 50)); body.addLine(to: CGPoint(x: c.x + 18, y: c.y + 20)); body.addLine(to: CGPoint(x: c.x - 18, y: c.y + 20)); body.closeSubpath()
            g.fill(body, with: .color(Color(argb: 0xFFF2F2F2)))
            g.circle(CGPoint(x: c.x, y: c.y - 12), 8, Color(argb: 0xFF5AB8FF))
            for s in [-1.0, 1.0] {
                var fin = Path()
                fin.move(to: CGPoint(x: c.x + s * 18, y: c.y + 20)); fin.addLine(to: CGPoint(x: c.x + s * 30, y: c.y + 34)); fin.addLine(to: CGPoint(x: c.x + s * 12, y: c.y + 20)); fin.closeSubpath()
                g.fill(fin, with: .color(Color(argb: 0xFFE5484D)))
            }
            g.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y + 22, width: 18, height: 22 + sin(t * 30) * 6)), with: .color(Color(argb: 0xFFFFB13B)))
        }
    }

    // MARK: Night Sky

    /** A deep blue dusk over hills and pines: moon, aurora, twinkling stars and shooting stars. */
    private func night(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        vgrad(ctx, CGRect(origin: .zero, size: size), [Color(argb: 0xFF040817), Color(argb: 0xFF0A1630), Color(argb: 0xFF1C2A55), Color(argb: 0xFF3A3466)])
        for i in 0..<2 {
            let base = h * (0.28 + Double(i) * 0.08)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: base))
            var x = 0.0
            while x <= w { path.addLine(to: CGPoint(x: x, y: base + sin(x / 180 + t * 0.4 + Double(i)) * 30)); x += 24 }
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [Color(argb: 0x5544FFAA), .clear]), startPoint: CGPoint(x: 0, y: base - 60), endPoint: CGPoint(x: 0, y: base + 80)), lineWidth: 70)
        }
        var r = SceneRandom(11)
        for i in 0..<220 {
            let tw = 0.5 + 0.5 * sin(t * (0.8 + Double(i % 7) * 0.4) + Double(i))
            let a = (0.15 + 0.6 * r.next()) * tw, rad = 0.8 + r.next() * 1.6
            ctx.circle(CGPoint(x: r.next() * w, y: r.next() * h * 0.75), rad, .white.opacity(a))
        }
        for i in 0..<2 {
            let cycle = (t + Double(i) * 3.7).truncatingRemainder(dividingBy: 7) / 1.1
            guard cycle < 1 else { continue }
            let start = CGPoint(x: w * (0.2 + 0.5 * frac(Double(i) * 0.37 + floor(t / 7) * 0.29)), y: h * (0.08 + Double(i) * 0.1))
            let head = CGPoint(x: start.x + cycle * 420, y: start.y + cycle * 160), tail = CGPoint(x: head.x - 140, y: head.y - 53)
            ctx.stroke(Path { $0.move(to: tail); $0.addLine(to: head) }, with: .linearGradient(Gradient(colors: [.clear, .white]), startPoint: tail, endPoint: head), lineWidth: 3)
        }
        let m = CGPoint(x: w * 0.82, y: h * 0.2)
        ctx.glow(m, 230, Color(argb: 0x55FFE8A3))
        ctx.circle(m, 70, Color(argb: 0xFFFFF3CF))
        ctx.circle(CGPoint(x: m.x - 22, y: m.y - 10), 13, Color(argb: 0xFFEADFB8))
        ctx.circle(CGPoint(x: m.x + 20, y: m.y + 22), 8, Color(argb: 0xFFEADFB8))
        func hill(_ color: UInt32, _ top: Double, _ amp: Double, _ period: Double) {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: h))
            var x = 0.0
            while x <= w { p.addLine(to: CGPoint(x: x, y: top + sin(x / period) * amp)); x += 20 }
            p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
            ctx.fill(p, with: .color(Color(argb: color)))
        }
        hill(0xFF141C38, h * 0.76, 40, 260)
        hill(0xFF0A0F22, h * 0.86, 26, 170)
        var pr = SceneRandom(3)
        for _ in 0..<26 {
            let x = pr.next() * w, th = 60 + pr.next() * 90, b = h * 0.88 + sin(x / 170) * 26
            var tree = Path()
            tree.move(to: CGPoint(x: x, y: b - th)); tree.addLine(to: CGPoint(x: x + th * 0.28, y: b)); tree.addLine(to: CGPoint(x: x - th * 0.28, y: b)); tree.closeSubpath()
            ctx.fill(tree, with: .color(Color(argb: 0xFF060914)))
        }
    }

    // MARK: Alien Abduction

    /** A moonlit farm at night; a flying saucer sweeps its beam and lifts a cow, then lets it down. */
    private func alien(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        vgrad(ctx, CGRect(origin: .zero, size: size), [Color(argb: 0xFF02050C), Color(argb: 0xFF07121F), Color(argb: 0xFF10261F)])
        var r = SceneRandom(21)
        for i in 0..<160 {
            let tw = 0.5 + 0.5 * sin(t * Double(1 + i % 4) + Double(i))
            let a = (0.2 + 0.5 * r.next()) * tw, rad = 0.8 + r.next() * 1.3
            ctx.circle(CGPoint(x: r.next() * w, y: r.next() * h * 0.7), rad, .white.opacity(a))
        }
        let ground = h * 0.8
        ctx.rect(CGRect(x: 0, y: ground, width: w, height: h - ground), Color(argb: 0xFF0C1E14))
        for i in 0..<9 { ctx.line(CGPoint(x: 0, y: ground + Double(i) * 18), CGPoint(x: w, y: ground + Double(i) * 26), Color(argb: 0xFF143022), 2) }
        let barn = CGPoint(x: w * 0.1, y: ground)
        ctx.rect(CGRect(x: barn.x, y: barn.y - 120, width: 170, height: 120), Color(argb: 0xFF3A1414))
        var roof = Path()
        roof.move(to: CGPoint(x: barn.x - 12, y: barn.y - 120)); roof.addLine(to: CGPoint(x: barn.x + 85, y: barn.y - 190)); roof.addLine(to: CGPoint(x: barn.x + 182, y: barn.y - 120)); roof.closeSubpath()
        ctx.fill(roof, with: .color(Color(argb: 0xFF2A0E0E)))
        ctx.rect(CGRect(x: barn.x + 70, y: barn.y - 100, width: 30, height: 30), Color(argb: 0xFFFFD27A))
        var fx = w * 0.3
        while fx < w * 0.95 { ctx.rect(CGRect(x: fx, y: ground - 30, width: 5, height: 34), Color(argb: 0xFF1E3A2A)); fx += 60 }
        ctx.rect(CGRect(x: w * 0.3, y: ground - 22, width: w * 0.65, height: 4), Color(argb: 0xFF1E3A2A))
        let ux = w * (0.6 + 0.12 * sin(t * 0.25)), uy = h * 0.3 + sin(t * 1.2) * 10, beam = 0.55 + 0.25 * sin(t * 2)
        var cone = Path()
        cone.move(to: CGPoint(x: ux - 40, y: uy + 20)); cone.addLine(to: CGPoint(x: ux + 40, y: uy + 20)); cone.addLine(to: CGPoint(x: ux + 150, y: ground + 10)); cone.addLine(to: CGPoint(x: ux - 150, y: ground + 10)); cone.closeSubpath()
        ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(argb: 0xFF9BFF7A).opacity(0.67 * beam), Color(argb: 0x229BFF7A)]), startPoint: CGPoint(x: 0, y: uy), endPoint: CGPoint(x: 0, y: ground)))
        ctx.fill(Path(ellipseIn: CGRect(x: ux - 160, y: ground - 6, width: 320, height: 30)), with: .color(Color(argb: 0x559BFF7A)))
        let lift = (sin(t * 0.35) + 1) / 2, cy = ground - 20 - lift * (ground - uy - 90)
        ctx.rotated(sin(t * 1.5) * 12, around: CGPoint(x: ux, y: cy)) { g in
            g.fill(Path(ellipseIn: CGRect(x: ux - 34, y: cy - 18, width: 68, height: 36)), with: .color(.white))
            g.circle(CGPoint(x: ux - 8, y: cy - 4), 9, .black)
            g.circle(CGPoint(x: ux + 16, y: cy + 4), 7, .black)
            g.fill(Path(ellipseIn: CGRect(x: ux + 26, y: cy - 26, width: 26, height: 22)), with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: ux + 38, y: cy - 16, width: 14, height: 10)), with: .color(Color(argb: 0xFFFFB3C1)))
            for lx in [-24.0, -10, 10, 22] { g.rect(CGRect(x: ux + lx, y: cy + 14, width: 6, height: 18), .white) }
        }
        ctx.fill(Path(ellipseIn: CGRect(x: ux - 120, y: uy - 10, width: 240, height: 40)), with: .linearGradient(Gradient(colors: [Color(argb: 0xFFDCE3EA), Color(argb: 0xFF6E7A86)]), startPoint: CGPoint(x: 0, y: uy - 10), endPoint: CGPoint(x: 0, y: uy + 26)))
        ctx.fill(Path(ellipseIn: CGRect(x: ux - 52, y: uy - 50, width: 104, height: 60)), with: .radialGradient(Gradient(colors: [Color(argb: 0xCCB8FFE0), Color(argb: 0x667CFF6B)]), center: CGPoint(x: ux, y: uy - 20), startRadius: 0, endRadius: 60))
        for i in 0..<7 {
            let on = (Int(t * 6) + i) % 7 < 2
            ctx.circle(CGPoint(x: ux - 90 + Double(i) * 30, y: uy + 12), 6, on ? Color(argb: 0xFF7CFF6B) : Color(argb: 0xFF2C5A30))
        }
    }

    // MARK: Ocean

    /** Sunbeams through blue water, swaying seaweed and fish swimming both ways. */
    private func ocean(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        vgrad(ctx, CGRect(origin: .zero, size: size), [Color(argb: 0xFF2A9BD1), Color(argb: 0xFF0C4A70), Color(argb: 0xFF062B45)])
        for i in 0..<5 {
            let x = w * (0.1 + Double(i) * 0.2) + sin(t * 0.3 + Double(i)) * 40
            var ray = Path()
            ray.move(to: CGPoint(x: x - 30, y: 0)); ray.addLine(to: CGPoint(x: x + 30, y: 0)); ray.addLine(to: CGPoint(x: x + 160, y: h)); ray.addLine(to: CGPoint(x: x + 40, y: h)); ray.closeSubpath()
            ctx.fill(ray, with: .color(.white.opacity(0.05)))
        }
        ctx.rect(CGRect(x: 0, y: h * 0.93, width: w, height: h * 0.07), Color(argb: 0xFFD9C38C))
        for i in 0..<9 {
            let bx = w * (0.04 + Double(i) * 0.12)
            var weed = Path(), y = h * 0.94, k = 0
            weed.move(to: CGPoint(x: bx, y: y))
            while y > h * (0.68 + Double(i % 3) * 0.05) {
                y -= 20; k += 1
                weed.addLine(to: CGPoint(x: bx + sin(t * 1.3 + Double(i) + Double(k) * 0.5) * 14, y: y))
            }
            ctx.stroke(weed, with: .color(Color(argb: 0xFF2E9E6A)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }
        let colors: [UInt32] = [0xFFFFB13B, 0xFFFF6B9A, 0xFF7CFFCB, 0xFFFFE066]
        for i in 0..<6 {
            let d = Double(i), dir = i % 2 == 0 ? 1.0 : -1.0
            let k = (t * (0.025 + d * 0.006) + d * 0.17).truncatingRemainder(dividingBy: 1.3) - 0.15
            let x = (dir > 0 ? k : 1 - k) * w, y = h * (0.18 + d * 0.11) + sin(t * 1.5 + d) * 12
            let s = 0.8 + Double(i % 3) * 0.3, col = Color(argb: colors[i % 4])
            ctx.fill(Path(ellipseIn: CGRect(x: x - 30 * s, y: y - 16 * s, width: 60 * s, height: 32 * s)), with: .color(col))
            var tail = Path()
            tail.move(to: CGPoint(x: x - dir * 26 * s, y: y)); tail.addLine(to: CGPoint(x: x - dir * 50 * s, y: y - 16 * s)); tail.addLine(to: CGPoint(x: x - dir * 50 * s, y: y + 16 * s)); tail.closeSubpath()
            ctx.fill(tail, with: .color(col))
            ctx.circle(CGPoint(x: x + dir * 16 * s, y: y - 4 * s), 3.5 * s, .black)
        }
    }

    // MARK: Consoles

    /** Handheld LCD: pale green screen, dot grid, drifting clouds and falling blocks. */
    private func pocket(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height, px = 3.0
        let c0 = Color(argb: 0xFF0F380F), c2 = Color(argb: 0xFF8BAC0F), c3 = Color(argb: 0xFF9BBC0F)
        ctx.rect(CGRect(origin: .zero, size: size), c3)
        var grid = Path(), gx = 0.0
        while gx < w { grid.move(to: CGPoint(x: gx, y: 0)); grid.addLine(to: CGPoint(x: gx, y: h)); gx += px * 2 }
        ctx.stroke(grid, with: .color(c2.opacity(0.35)), lineWidth: 1)
        for i in 0..<3 {
            let x = (t * 10 * Double(i + 1) + Double(i) * 300).truncatingRemainder(dividingBy: w + 200) - 100
            Sprites.cloud.draw(ctx, CGPoint(x: x, y: h * (0.08 + Double(i) * 0.1)), px, ["w": c2])
        }
        let well = w - px * 30
        let shapes = [[(0, 0), (1, 0), (2, 0), (1, 1)], [(0, 0), (1, 0), (0, 1), (1, 1)], [(0, 0), (0, 1), (0, 2), (1, 2)]]
        for i in 0..<3 {
            let y = (t * 40 + Double(i) * 220).truncatingRemainder(dividingBy: h + 100) - 50
            for (cx, cy) in shapes[i] {
                let o = CGPoint(x: well + Double(i) * px * 8 + Double(cx) * px * 4, y: y + Double(cy) * px * 4)
                ctx.rect(CGRect(x: o.x, y: o.y, width: px * 4, height: px * 4), c0)
                ctx.rect(CGRect(x: o.x + px, y: o.y + px, width: px * 2, height: px * 2), c2)
            }
        }
    }

    /** 16-bit side-scroller: banded sky, parallax hills, star blocks and spinning coins. */
    private func sixteen(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height, px = 4.0
        let bands: [UInt32] = [0xFF2848B8, 0xFF3860D0, 0xFF4878E0, 0xFF6090E8, 0xFF80A8F0, 0xFFA0C0F8]
        let bh = h * 0.7 / Double(bands.count)
        for (i, c) in bands.enumerated() { ctx.rect(CGRect(x: 0, y: Double(i) * bh, width: w, height: bh + 1), Color(argb: c)) }
        ctx.rect(CGRect(x: 0, y: h * 0.7, width: w, height: h * 0.3), Color(argb: 0xFFA0C0F8))
        for i in 0..<4 {
            let x = (t * (8 + Double(i) * 4) + Double(i) * 380).truncatingRemainder(dividingBy: w + 300) - 150
            Sprites.cloud.draw(ctx, CGPoint(x: x, y: h * (0.06 + Double(i) * 0.08)), px, ["w": .white])
        }
        func hills(_ color: UInt32, _ base: Double, _ amp: Double, _ speed: Double, _ period: Double) {
            let shift = (t * speed).truncatingRemainder(dividingBy: period)
            var x = -period
            while x < w + period {
                ctx.fill(Path(ellipseIn: CGRect(x: x - shift, y: base - amp, width: period, height: amp * 2)), with: .color(Color(argb: color)))
                x += period * 0.8
            }
            ctx.rect(CGRect(x: 0, y: base, width: w, height: h - base), Color(argb: color))
        }
        hills(0xFF3A9A80, h * 0.62, h * 0.12, 6, w * 0.35)
        hills(0xFF48B848, h * 0.74, h * 0.07, 16, w * 0.22)
        for i in 0..<4 {
            let x = w * (0.3 + Double(i) * 0.13)
            Sprites.starBlock.draw(ctx, CGPoint(x: x, y: h * 0.48), px, Sprites.sixteenPalette)
            Sprites.coin[(Int(t * 6) + i) % 2].draw(ctx, CGPoint(x: x + px * 2, y: h * 0.4 + sin(t * 3 + Double(i)) * px * 2), px, Sprites.sixteenPalette)
        }
    }
}

/** Pixel art from text: each character is one pixel, looked up in a palette ('.' is see-through). */
struct Sprite {
    let rows: [[Character]]
    var w: Int { rows.map(\.count).max() ?? 0 }
    var h: Int { rows.count }
    init(_ rows: String...) { self.rows = rows.map(Array.init) }

    func draw(_ ctx: GraphicsContext, _ at: CGPoint, _ px: Double, _ colors: [Character: Color], flip: Bool = false) {
        let width = w
        for (y, row) in rows.enumerated() {
            for x in 0..<width {
                let i = flip ? width - 1 - x : x
                guard i < row.count, let c = colors[row[i]] else { continue }
                ctx.fill(Path(CGRect(x: at.x + Double(x) * px, y: at.y + Double(y) * px, width: px + 0.5, height: px + 0.5)), with: .color(c))
            }
        }
    }
}

/** Sprites for the console scenes (original, generic characters). */
enum Sprites {
    static let hero = [
        Sprite("...kkkk.", "..kcccck", ".kcccccck", ".kksssk.", ".ksksksk", ".kssssk.", "..kksk..", ".kcccck.", "kscccsk.", "kscccsk.", ".kpppk..", ".kp.pk..", "kk...kk."),
        Sprite("...kkkk.", "..kcccck", ".kcccccck", ".kksssk.", ".ksksksk", ".kssssk.", "..kksk..", ".kcccck.", "kscccsk.", "kscccsk.", ".kpppk..", "..kpk...", "..kkk..."),
    ]
    static let slime = Sprite("...kkkk...", "..kggggk..", ".kgwggggk.", "kgwwggkgk.", "kggggggggk", "kgkggggkgk", ".kkkkkkkk.")
    static let coin = [Sprite(".kkk.", "kyyyk", "kywyk", "kyyyk", "kywyk", "kyyyk", ".kkk."), Sprite(".k.", "kyk", "kwk", "kyk", "kwk", "kyk", ".k.")]
    static let starBlock = Sprite("kkkkkkkkkk", "kyyyyyyyyk", "kyyykyyyyk", "kyykwkyyyk", "kykwwwkyyk", "kyykwkyyyk", "kyyykyyyyk", "kyyyyyyyyk", "kkkkkkkkkk")
    static let cloud = Sprite("....wwww......", "..wwwwwwww.ww.", ".wwwwwwwwwwwww", "wwwwwwwwwwwwww", ".wwwwwwwwwwww.")

    static let sixteenPalette: [Character: Color] = [
        "k": Color(argb: 0xFF181028), "c": Color(argb: 0xFFE04040), "s": Color(argb: 0xFFFFC890), "p": Color(argb: 0xFF3050C8),
        "g": Color(argb: 0xFF50D060), "w": .white, "y": Color(argb: 0xFFFFD040),
    ]
    static let pocketPalette: [Character: Color] = [
        "k": Color(argb: 0xFF0F380F), "c": Color(argb: 0xFF306230), "s": Color(argb: 0xFF8BAC0F), "p": Color(argb: 0xFF306230),
        "g": Color(argb: 0xFF8BAC0F), "w": Color(argb: 0xFF9BBC0F), "y": Color(argb: 0xFF8BAC0F),
    ]
}

/**
 * The bottom strip of Cybercore (taskbar) and the console themes (floor), with the console
 * characters walking along its top edge. Drawn above everything; pages end above it.
 */
struct StyleFloor: View {
    let style: SceneStyle
    let variant: String
    @State private var start = Date()

    var body: some View {
        let floor = style.floorHeight
        TimelineView(.animation(minimumInterval: style == .retro ? 1 : style == .pocket ? 1.0 / 8 : 1.0 / 15)) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let top = size.height - floor
                switch style {
                case .retro: taskbar(ctx, CGRect(x: 0, y: top, width: size.width, height: floor))
                case .pocket:
                    let px = 3.0
                    ctx.rect(CGRect(x: 0, y: top, width: size.width, height: floor), Color(argb: 0xFF306230))
                    var bx = 0.0
                    while bx < size.width {
                        ctx.rect(CGRect(x: bx, y: top, width: px, height: floor), Color(argb: 0xFF0F380F))
                        ctx.rect(CGRect(x: bx, y: top + px * 8, width: px * 8, height: px), Color(argb: 0xFF0F380F))
                        bx += px * 8
                    }
                    ctx.rect(CGRect(x: 0, y: top, width: size.width, height: px), Color(argb: 0xFF0F380F))
                    // Hero walks across; slime bounces; coins spin.
                    let heroX = (t * 30).truncatingRemainder(dividingBy: size.width + 100) - 50
                    Sprites.hero[Int(t * 4) % 2].draw(ctx, CGPoint(x: heroX, y: top - Double(Sprites.hero[0].h) * px), px, Sprites.pocketPalette)
                    let hop = abs(sin(t * 3)) * px * 10
                    Sprites.slime.draw(ctx, CGPoint(x: size.width * 0.7, y: top - Double(Sprites.slime.h) * px - hop), px, Sprites.pocketPalette)
                    for i in 0..<5 { Sprites.coin[(Int(t * 3) + i) % 2].draw(ctx, CGPoint(x: size.width * (0.25 + Double(i) * 0.08), y: top - px * 18), px, Sprites.pocketPalette) }
                case .sixteen:
                    let px = 4.0
                    ctx.rect(CGRect(x: 0, y: top, width: size.width, height: floor), Color(argb: 0xFFC07838))
                    ctx.rect(CGRect(x: 0, y: top, width: size.width, height: px * 3), Color(argb: 0xFF50D060))
                    ctx.rect(CGRect(x: 0, y: top + px * 3, width: size.width, height: px), Color(argb: 0xFF2E9A3C))
                    var bx = -(t * 40).truncatingRemainder(dividingBy: px * 12)
                    while bx < size.width { ctx.rect(CGRect(x: bx, y: top + px * 4, width: px, height: floor), Color(argb: 0xFF8A5020)); bx += px * 12 }
                    ctx.rect(CGRect(x: 0, y: top + px * 10, width: size.width, height: px), Color(argb: 0xFF8A5020))
                    // The hero runs and hops now and then; a slime patrols.
                    let heroX = (t * 70).truncatingRemainder(dividingBy: size.width + 120) - 60
                    let phase = t.truncatingRemainder(dividingBy: 3) / 0.6
                    let jump = phase < 1 ? sin(phase * .pi) * px * 18 : 0
                    Sprites.hero[Int(t * 8) % 2].draw(ctx, CGPoint(x: heroX, y: top - Double(Sprites.hero[0].h) * px - jump), px, Sprites.sixteenPalette)
                    let slimeX = size.width * 0.15 + sin(t * 0.8) * size.width * 0.08
                    Sprites.slime.draw(ctx, CGPoint(x: slimeX, y: top - Double(Sprites.slime.h) * px), px, Sprites.sixteenPalette, flip: cos(t * 0.8) < 0)
                default: break
                }
            }
        }
        .allowsHitTesting(false)
    }

    /** Windows 98, Luna XP or Kawaii taskbar with a Start button and a clock. */
    private func taskbar(_ ctx: GraphicsContext, _ r: CGRect) {
        let clock = Date().formatted(date: .omitted, time: .shortened)
        switch variant {
        case "KAWAII":
            ctx.rect(r, Color(argb: 0xFFFFB8DE))
            ctx.line(CGPoint(x: 0, y: r.minY), CGPoint(x: r.width, y: r.minY), .white, 2)
            ctx.rect(CGRect(x: 4, y: r.minY + 4, width: 96, height: r.height - 8), Color(argb: 0xFFFF7CC8))
            ctx.draw(Text("♡ start").font(.custom("Bradley Hand", size: 16).bold()).foregroundStyle(.white), at: CGPoint(x: 20, y: r.midY), anchor: .leading)
            ctx.rect(CGRect(x: r.width - 100, y: r.minY + 4, width: 96, height: r.height - 8), Color(argb: 0xFFFFD6EC))
        case "XP":
            ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(argb: 0xFF3F8CF3), Color(argb: 0xFF245EDC), Color(argb: 0xFF1941A5)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            let start = CGRect(x: 0, y: r.minY, width: 108, height: r.height)
            ctx.fill(Path(start), with: .linearGradient(Gradient(colors: [Color(argb: 0xFF5EC55E), Color(argb: 0xFF3C9B3C), Color(argb: 0xFF2E7D2E)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            let q = 7.0
            for (i, c) in [UInt32(0xFFF65314), 0xFF7CBB00, 0xFF00A1F1, 0xFFFFBB00].enumerated() {
                ctx.rect(CGRect(x: 8 + Double(i % 2) * (q + 1), y: r.minY + 9 + Double(i / 2) * (q + 1), width: q, height: q), Color(argb: c))
            }
            ctx.draw(Text("start").font(.system(size: 18, weight: .bold).italic()).foregroundStyle(.white), at: CGPoint(x: 28, y: r.midY), anchor: .leading)
            ctx.fill(Path(CGRect(x: r.width - 100, y: r.minY, width: 100, height: r.height)), with: .linearGradient(Gradient(colors: [Color(argb: 0xFF14A0F0), Color(argb: 0xFF0B77D6)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
        default:
            ctx.rect(r, Color(argb: 0xFFC0C0C0))
            ctx.line(CGPoint(x: 0, y: r.minY + 1), CGPoint(x: r.width, y: r.minY + 1), Color(argb: 0xFFDFDFDF), 2)
            ctx.line(CGPoint(x: 0, y: r.minY + 3), CGPoint(x: r.width, y: r.minY + 3), .white, 2)
            let b = CGRect(x: 4, y: r.minY + 4, width: 72, height: r.height - 8)
            bevel(ctx, b, raised: true)
            let q = 5.0
            for (i, c) in [UInt32(0xFFFF0000), 0xFF00C000, 0xFF0000FF, 0xFFFFFF00].enumerated() {
                ctx.rect(CGRect(x: b.minX + 5 + Double(i % 2) * (q + 1), y: b.minY + 6 + Double(i / 2) * (q + 1), width: q, height: q), Color(argb: c))
            }
            ctx.draw(Text("Start").font(.system(size: 14, weight: .bold)).foregroundStyle(.black), at: CGPoint(x: b.minX + 19, y: b.midY), anchor: .leading)
            bevel(ctx, CGRect(x: r.width - 96, y: r.minY + 4, width: 92, height: r.height - 8), raised: false)
        }
        ctx.draw(Text(clock).font(.system(size: 13)).foregroundStyle(variant == "XP" ? .white : .black), at: CGPoint(x: r.width - 84, y: r.midY), anchor: .leading)
    }

    /** A Windows 98 bevel: light top/left and dark bottom/right edges (reversed when sunken). */
    private func bevel(_ ctx: GraphicsContext, _ r: CGRect, raised: Bool) {
        ctx.rect(r, Color(argb: 0xFFC0C0C0))
        let lightEdge: Color = raised ? .white : Color(argb: 0xFF808080), dark: Color = raised ? Color(argb: 0xFF404040) : .white
        ctx.line(CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), lightEdge, 2)
        ctx.line(CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), lightEdge, 2)
        ctx.line(CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY), dark, 2)
        ctx.line(CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), dark, 2)
    }
}
