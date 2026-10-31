import SwiftUI
import UIKit

// The screens are shared with the Mac app (../macos). These names let the AppKit idioms they use
// (images, colors, clipboard, opening links) compile unchanged on iOS.

typealias NSImage = UIImage
typealias NSColor = UIColor
typealias NSSize = CGSize

extension Image {
    init(nsImage: UIImage) { self.init(uiImage: nsImage) }
}

extension UIImage {
    convenience init(cgImage: CGImage, size: CGSize) { self.init(cgImage: cgImage) }
}

extension Bundle {
    func image(forResource name: String) -> UIImage? { UIImage(named: name, in: self, with: nil) }
}

enum CompatColorSpace { case sRGB }

extension UIColor {
    func usingColorSpace(_ space: CompatColorSpace) -> UIColor? { self }
    private var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
    var redComponent: CGFloat { rgba.0 }
    var greenComponent: CGFloat { rgba.1 }
    var blueComponent: CGFloat { rgba.2 }
    var alphaComponent: CGFloat { rgba.3 }
    private var hsb: (CGFloat, CGFloat, CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }
    var hueComponent: CGFloat { hsb.0 }
    var saturationComponent: CGFloat { hsb.1 }
    var brightnessComponent: CGFloat { hsb.2 }
}

/** UIPasteboard behind the NSPasteboard calls the shared screens make. */
@MainActor
final class NSPasteboard {
    enum PasteboardType { case string }
    static let general = NSPasteboard()
    func clearContents() {}
    #if os(tvOS)
    // tvOS has no clipboard; this only carries text around inside the app.
    private var text: String?
    func setString(_ s: String, forType: PasteboardType) { text = s }
    func string(forType: PasteboardType) -> String? { text }
    #else
    func setString(_ s: String, forType: PasteboardType) { UIPasteboard.general.string = s }
    func string(forType: PasteboardType) -> String? { UIPasteboard.general.string }
    #endif
}

@MainActor
final class NSWorkspace {
    static let shared = NSWorkspace()
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard UIApplication.shared.canOpenURL(url) || url.scheme?.hasPrefix("http") == true else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
