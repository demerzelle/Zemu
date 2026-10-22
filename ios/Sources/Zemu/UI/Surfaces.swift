import SwiftUI

/** How buttons, chips, bars and panels are drawn. Comes from the color theme. */
enum SurfaceStyle { case solid, glass, chrome }

extension View {
    /**
     * A control's background in the theme's material: a flat [fill], Apple's Liquid Glass, or
     * liquid chrome. [prominent] is the primary action (accent-tinted glass, bright chrome).
     */
    func zSurface<S: InsettableShape>(_ shape: S, fill: Color, prominent: Bool = false, interactive: Bool = true) -> some View {
        modifier(SurfaceModifier(shape: shape, fill: fill, prominent: prominent, interactive: interactive))
    }
}

private struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    let prominent: Bool
    let interactive: Bool

    func body(content: Content) -> some View {
        let settings = AppModel.shared.settings
        switch P.style {
        case .solid:
            content.background(shape.fill(fill))
        case .glass:
            let refraction = settings.glassRefraction
            if #available(iOS 26, *) {
                // Apple's glass comes in two strengths: frosted (.regular) and the more see-through,
                // more strongly lensing .clear. Past half way the slider switches to clear.
                let base: Glass = refraction >= 0.5 ? .clear : .regular
                let glass = prominent ? base.tint(P.accent) : base
                content
                    .glassEffect(interactive ? glass.interactive() : glass, in: shape)
                    .overlay(LiquidLayer(kind: .glass, radius: radius, refraction: refraction).clipShape(shape))
            } else {
                content
                    .background(shape.fill(prominent ? P.accent.opacity(0.75) : .clear))
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(LiquidLayer(kind: .glass, radius: radius, refraction: refraction).clipShape(shape))
            }
        case .chrome:
            content.background(LiquidLayer(kind: .chrome(bright: prominent), radius: radius, refraction: settings.chromeRefraction))
        }
    }

    /** The shape's corner radius at a size (capsules and circles: half the short side). */
    private func radius(_ size: CGSize) -> CGFloat {
        if let r = shape as? RoundedRectangle { return min(r.cornerSize.width, min(size.width, size.height) / 2) }
        return min(size.width, size.height) / 2
    }
}

// MARK: - Liquid layers (LiquidShaders.metal)

/** The animated shader surface: liquid chrome, or the lens edge drawn over Liquid Glass. */
private struct LiquidLayer: View {
    enum Kind { case chrome(bright: Bool), glass }
    let kind: Kind
    let radius: (CGSize) -> CGFloat
    let refraction: Double
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                // Wrapped so the shader's float time keeps its precision.
                let t = Float(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
                Rectangle().fill(.white).colorEffect(shader(g.size, t))
            }
        }
        .allowsHitTesting(false)
    }

    private func shader(_ size: CGSize, _ t: Float) -> Shader {
        let common: [Shader.Argument] = [.float2(size), .float(radius(size)), .float(t), .float(scale), .float(refraction)]
        switch kind {
        case .chrome(let bright): return Shader(function: ShaderFunction(library: .default, name: "zemuChrome"), arguments: common + [.float(bright ? 1 : 0)])
        case .glass: return Shader(function: ShaderFunction(library: .default, name: "zemuGlassLens"), arguments: common)
        }
    }
}

// MARK: - Page background

/** What sits behind every page: the theme color, or the moving backdrop glass and chrome refract. */
struct PageBackground: View {
    var body: some View {
        switch P.style {
        case .solid: P.background
        case .glass: LiquidBackdrop(colors: [0xFF0B1230, 0xFF1A0F3D, 0xFF06253F, 0xFF2B1446, 0xFF0A0A18, 0xFF0E2A55, 0xFF120B26, 0xFF051A2E, 0xFF1B1036])
        case .chrome: LiquidBackdrop(colors: [0xFF1A1C20, 0xFF3A3E45, 0xFF0C0D0F, 0xFF2A2D33, 0xFF5B616B, 0xFF16181B, 0xFF0A0B0D, 0xFF2F3339, 0xFF121316])
        }
    }
}

/** A slowly flowing 3×3 mesh gradient, like the iOS 26 wallpapers. */
private struct LiquidBackdrop: View {
    let colors: [UInt32]

    var body: some View {
        if #available(iOS 18, *) {
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate / 6
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + 0.18 * sin(t)), Float(0.5 + 0.14 * cos(t * 1.3))], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: colors.map { Color(argb: $0) })
            }
            .ignoresSafeArea()
        } else {
            LinearGradient(colors: colors.prefix(3).map { Color(argb: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
    }
}
