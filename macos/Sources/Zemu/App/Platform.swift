import SwiftUI
import AppKit

/** Opens web pages (key signup pages, Trakt activation) in the default browser. */
enum Links {
    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

extension Color {
    /** sRGB components, 0…1. */
    func rgb() -> (r: Double, g: Double, b: Double, a: Double) {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    /** Hue, saturation and brightness, 0…1. */
    func hsb() -> (h: Double, s: Double, b: Double) {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }
}
