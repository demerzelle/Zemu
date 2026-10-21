import SwiftUI
import ZemuCore

// Liquid Glass (Settings → Appearance): pages turn see-through over a blurred copy of the title
// you're looking at, and panels become frosted glass. With it off, these draw the plain theme.
// Rebuilt for the Zemu / Zemu Next merge (the original Glass.swift was lost).

extension View {
    /** A panel or button background: frosted glass in the Liquid Glass look, else [fill]. */
    @MainActor func zSurface<S: InsettableShape>(_ shape: S, fill: Color, interactive: Bool = false) -> some View {
        modifier(SurfaceModifier(shape: shape, fill: fill, interactive: interactive))
    }

    /** Frosted panel behind the hero's title info, only in the Liquid Glass look. */
    @MainActor func zGlassPanel() -> some View {
        modifier(GlassPanelModifier())
    }
}

private struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    let interactive: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content.background {
            if P.glass {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(fill.opacity(P.light ? 0.35 : 0.25))
                    if interactive && hovering { shape.fill(P.ink.opacity(0.08)) }
                    shape.strokeBorder(P.ink.opacity(0.12), lineWidth: 1)
                }
            } else {
                ZStack {
                    shape.fill(fill)
                    if interactive && hovering { shape.fill(P.ink.opacity(0.06)) }
                }
            }
        }
        .onHover { h in if interactive { hovering = h } }
    }
}

private struct GlassPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        if P.glass {
            content
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(P.ink.opacity(0.12), lineWidth: 1))
        } else {
            content
        }
    }
}

/** The window background in the Liquid Glass look: the current title's art, blurred and dimmed. */
struct AmbientBackdrop: View {
    var app = AppModel.shared

    var body: some View {
        ZStack {
            P.base.ignoresSafeArea()
            if let url = app.ambient {
                RemoteImage(url: url, maxPixel: 640)
                    .id(url)
                    .blur(radius: 60, opaque: true)
                    .saturation(1.2)
                    .opacity(P.light ? 0.55 : 0.7)
                    .transition(.opacity)
                    .ignoresSafeArea()
            }
            P.base.opacity(P.light ? 0.35 : 0.45).ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.8), value: app.ambient)
        .allowsHitTesting(false)
    }
}
