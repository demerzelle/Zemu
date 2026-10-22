// Liquid Chrome and Liquid Glass surfaces for SwiftUI (colorEffect shaders, drawn per pixel of
// the control only). Lengths are in points; `size` is the control's size, `radius` its corner
// radius, `scale` the display scale (anti-aliasing), `time` seconds, `refraction` 0…1 (the
// Settings slider): how far the surface bends the light it reflects or lets through.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace zemu {

// Distance to a rounded rectangle centred on the origin (negative inside).
static float roundedRect(float2 p, float2 half_, float r) {
    float2 q = abs(p) - half_ + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Unit vector pointing out of the shape at p (the distance field's gradient).
static float2 outwardNormal(float2 p, float2 half_, float r) {
    const float e = 0.3;
    float2 g = float2(roundedRect(p + float2(e, 0), half_, r) - roundedRect(p - float2(e, 0), half_, r),
                      roundedRect(p + float2(0, e), half_, r) - roundedRect(p - float2(0, e), half_, r));
    return g / max(length(g), 1e-4);
}

// Slowly flowing surface: three wave trains at different angles, each bent by the previous,
// so the folds drift and merge like a liquid rather than scrolling.
static float liquid(float2 q, float t) {
    float2 a = q;
    float h = 0.0;
    h += 0.55 * sin(dot(a, float2(1.10, 0.35)) + t * 0.42);
    a += 0.30 * float2(cos(h * 2.0 + t * 0.21), sin(h * 1.7 - t * 0.17));
    h += 0.30 * sin(dot(a, float2(-0.45, 1.30)) * 1.6 - t * 0.33 + 1.7);
    a += 0.20 * float2(sin(h * 2.6 + 0.4), cos(h * 2.2 - t * 0.12));
    h += 0.15 * sin(dot(a, float2(1.70, -1.05)) * 2.3 + t * 0.27 + 4.1);
    return h;
}

// What polished metal reflects for a surface tilt n: a bright sky above a dark floor with a
// hard horizon between them, plus a soft side light. `shift` moves the horizon (dispersion).
static float studio(float2 n, float shift) {
    float horizon = n.y * 2.6 + 0.35 * n.x + shift;
    float sky = smoothstep(-0.10, 0.06, -horizon);            // the hard horizon line
    float glow = 0.55 * exp(-horizon * horizon * 3.0);        // light pooled at the horizon
    float side = 0.30 * smoothstep(0.2, 1.4, dot(n, float2(0.85, -0.5)));
    return clamp(0.08 + 0.75 * sky + glow + side, 0.0, 1.2);
}

} // namespace zemu

[[ stitchable ]] half4 zemuChrome(float2 position, half4 color, float2 size, float radius, float time,
                                  float scale, float refraction, float bright) {
    using namespace zemu;
    const float2 half_ = size * 0.5;
    const float r = min(radius, min(half_.x, half_.y));
    const float2 p = position - half_;
    const float px = 1.0 / max(scale, 1.0);

    float d = roundedRect(p, half_ - 0.5, r);
    float alpha = clamp(0.5 - d / px, 0.0, 1.0);
    if (alpha <= 0.0) return half4(0.0);

    // Tilt of the surface. Domed: flat in the middle, curving away toward the edges.
    float2 across = p / half_;
    float2 n = float2(across.x * abs(across.x) * 0.25, across.y * abs(across.y) * (0.55 + 0.6 * refraction));

    // Flowing folds, deeper with more refraction.
    float2 q = p / size.y * 1.3;
    const float e = 0.015;
    float2 slope = float2(liquid(q + float2(e, 0), time) - liquid(q - float2(e, 0), time),
                          liquid(q + float2(0, e), time) - liquid(q - float2(0, e), time)) / (2.0 * e);
    n -= slope * (0.06 + 0.26 * refraction);

    // Bevel: the last few points fall away steeply to the edge.
    float inside = -d;
    float bevelWidth = clamp(size.y * 0.16, 2.0, 7.0);
    float bevel = clamp(1.0 - inside / bevelWidth, 0.0, 1.0);
    n += outwardNormal(p, half_ - 0.5, r) * bevel * bevel * (1.2 + 1.2 * refraction);

    // Bright chrome sees the sky on its face; dark chrome sees the floor (white labels on it).
    float base = bright > 0.5 ? -0.9 : 1.05;

    // Dispersion: red, green and blue see the horizon a little apart, so every highlight edge
    // fringes into colour. Stronger at the bevel and with more refraction.
    float spread = (0.02 + 0.10 * refraction) * (0.3 + 2.2 * bevel);
    float3 rgb = float3(studio(n, base - spread), studio(n, base), studio(n, base + spread));
    float lum = dot(rgb, float3(0.299, 0.587, 0.114));
    rgb = lum + (rgb - lum) * (1.0 + 0.9 * refraction); // bring the fringes' colour back up

    // Deep blue-black shadows, cool mid-tones, like chrome reflecting a night studio.
    float3 shadow = float3(0.025, 0.035, 0.075);
    rgb = shadow + (1.0 - shadow) * clamp(rgb, 0.0, 1.0);
    rgb += float3(-0.02, 0.0, 0.05) * lum * (1.0 - lum) * 4.0;

    // Specular rim right on the edge.
    float rim = clamp(1.0 - inside / (1.8 * px + 0.6), 0.0, 1.0);
    rgb = mix(rgb, float3(1.0), rim * 0.8);

    rgb = clamp(rgb, 0.0, 1.0);
    if (bright < 0.5) rgb -= 0.18 * rgb * rgb; // keep dark chrome from glaring behind labels
    return half4(half3(rgb * alpha), half(alpha));
}

// Drawn over the system's Liquid Glass: the lens at its edge. Light bends hardest where the
// glass curves away, so the edge gets a bright bevel, a dark band just inside it and colour
// fringes (warm outside, cool inside). Transparent elsewhere, so the real glass shows through.
[[ stitchable ]] half4 zemuGlassLens(float2 position, half4 color, float2 size, float radius, float time,
                                     float scale, float refraction) {
    using namespace zemu;
    const float2 half_ = size * 0.5;
    const float r = min(radius, min(half_.x, half_.y));
    const float2 p = position - half_;
    const float px = 1.0 / max(scale, 1.0);

    float d = roundedRect(p, half_ - 0.5, r);
    float coverage = clamp(0.5 - d / px, 0.0, 1.0);
    if (coverage <= 0.0 || refraction <= 0.001) return half4(0.0);

    float inside = -d;
    float lens = clamp(size.y * (0.14 + 0.16 * refraction), 3.0, 14.0); // how far in the edge bends
    float k = clamp(1.0 - inside / lens, 0.0, 1.0);                     // 1 at the edge, 0 past the lens

    // Where the edge faces the light (top-left) it glints; the opposite edge catches a dimmer
    // reflection. The light drifts a little so the glass feels alive.
    float2 out_ = outwardNormal(p, half_ - 0.5, r);
    float2 light = normalize(float2(-0.55 + 0.15 * sin(time * 0.35), -0.85));
    float facing = dot(out_, light);
    float glint = pow(clamp(facing, 0.0, 1.0), 2.0) + 0.35 * pow(clamp(-facing, 0.0, 1.0), 2.0);

    float3 rgb = 0.0;
    float a = 0.0;

    // Bright bevel line hugging the edge.
    float edge = pow(k, 3.0);
    rgb += float3(1.0) * edge * (0.25 + 0.75 * glint) * (0.5 + 0.5 * refraction);
    a += edge * (0.15 + 0.6 * glint) * (0.5 + 0.5 * refraction);

    // Dispersion: three bands across the lens, red nearest the edge, blue innermost.
    float band = (1.0 - k) * 3.0; // 0 at the edge … 3 at the lens' inner side
    float3 fringe = float3(exp(-pow(band - 0.55, 2.0) * 9.0),
                           exp(-pow(band - 1.00, 2.0) * 9.0),
                           exp(-pow(band - 1.45, 2.0) * 9.0));
    float fringeA = refraction * (0.06 + 0.22 * glint) * step(0.001, k);
    rgb += fringe * fringeA;
    a += max(fringe.r, max(fringe.g, fringe.b)) * fringeA * 0.6;

    // The dark band inside the bevel, where the lens bends the background away.
    float shade = exp(-pow(band - 2.2, 2.0) * 4.0) * step(0.001, k);
    a += shade * 0.3 * refraction;

    a = clamp(a, 0.0, 0.9) * coverage;
    rgb = clamp(rgb, 0.0, 1.0) * coverage;
    return half4(half3(rgb), half(a));
}
