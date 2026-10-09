import SwiftUI
import ImageIO
import ZemuCore

/** Downsampled, memory-cached image loading on top of HTTP's disk cache. */
actor ImageLoader {
    static let shared = ImageLoader()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 400 << 20
        return c
    }()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func image(_ url: String, maxPixel: Int) async -> NSImage? {
        let key = "\(url)#\(maxPixel)" as NSString
        if let img = cache.object(forKey: key) { return img }
        if let t = inFlight[key as String] { return await t.value }
        let t = Task<NSImage?, Never> {
            let data: Data?
            if url.hasPrefix("file:") {
                data = try? Data(contentsOf: URL(fileURLWithPath: String(url.dropFirst(5)).before("?")))
            } else {
                data = try? await HTTP.data(url)
            }
            guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        inFlight[key as String] = t
        let img = await t.value
        inFlight[key as String] = nil
        if let img { cache.setObject(img, forKey: key, cost: Int(img.size.width * img.size.height * 4)) }
        return img
    }

    /** Warms the cache, e.g. for the next hero backdrop. */
    func prefetch(_ url: String?, maxPixel: Int) {
        guard let url else { return }
        Task { _ = await image(url, maxPixel: maxPixel) }
    }
}

/** An image from a URL that fades in; shows nothing (the background) until loaded or on failure. */
struct RemoteImage: View {
    let url: String?
    var maxPixel: Int = 600
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center
    var onFailure: (() -> Void)?

    @State private var image: NSImage?
    @State private var loadedUrl: String?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: alignment) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
                        .clipped()
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
        }
        .task(id: "\(url ?? "")#\(maxPixel)") {
            guard let url, !url.isEmpty else { image = nil; return }
            if loadedUrl != url { image = nil }
            let img = await ImageLoader.shared.image(url, maxPixel: maxPixel)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) { image = img }
            loadedUrl = url
            if img == nil { onFailure?() }
        }
    }
}
