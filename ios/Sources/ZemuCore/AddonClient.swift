import Foundation

/** Thin HTTP client for the Stremio addon protocol: `/{resource}/{type}/{id}[/{extra}].json`. */
public enum AddonClient {
    public static func fetchManifest(_ transportUrl: String) async throws -> (raw: String, manifest: AddonManifest) {
        let raw = try await HTTP.string(transportUrl)
        return (raw, try AddonManifest.parse(raw))
    }

    public static func catalog(_ base: String, type: String, id: String, extra: [String: String] = [:]) async throws -> [Meta] {
        let data = try await HTTP.data(resourceUrl(base, "catalog", type, id, extra))
        return try JSONDecoder().decode(CatalogResponse.self, from: data).metas
            .filter { !$0.id.isEmpty }.distinct(by: \.id)
    }

    /** Catalogs like Cinemeta's `last-videos` answer with `metasDetailed` (full metas incl. videos). */
    public static func catalogDetailed(_ base: String, type: String, id: String, extra: [String: String]) async throws -> [Meta] {
        let data = try await HTTP.data(resourceUrl(base, "catalog", type, id, extra))
        return try JSONDecoder().decode(CatalogDetailedResponse.self, from: data).metasDetailed.filter { !$0.id.isEmpty }
    }

    /** Lists addons from an addon catalog (`/addon_catalog/{type}/{id}.json`). Unparseable entries are skipped. */
    public static func addonCatalog(_ base: String, type: String, id: String) async throws -> [CatalogAddon] {
        let data = try await HTTP.data(resourceUrl(base, "addon_catalog", type, id))
        guard let list = JSONValue.parse(data)?["addons"]?.array else { return [] }
        return list.compactMap { el -> CatalogAddon? in
            guard let url = el["transportUrl"]?.string, let m = el["manifest"], let manifest = try? AddonManifest.from(m) else { return nil }
            return Addon(transportUrl: url, manifest: manifest)
        }.distinct(by: \.transportUrl)
    }

    public static func meta(_ base: String, type: String, id: String) async throws -> Meta? {
        try JSONDecoder().decode(MetaResponse.self, from: try await HTTP.data(resourceUrl(base, "meta", type, id))).meta
    }

    public static func streams(_ base: String, type: String, id: String) async throws -> [Stream] {
        try JSONDecoder().decode(StreamResponse.self, from: try await HTTP.data(resourceUrl(base, "stream", type, id))).streams
    }

    public static func subtitles(_ base: String, type: String, id: String) async throws -> [SubtitleTrack] {
        try JSONDecoder().decode(SubtitlesResponse.self, from: try await HTTP.data(resourceUrl(base, "subtitles", type, id))).subtitles
    }

    public static func resourceUrl(_ base: String, _ resource: String, _ type: String, _ id: String, _ extra: [String: String] = [:]) -> String {
        let idPart = id.urlEncoded.replacingOccurrences(of: "%3A", with: ":")
        let extraPart = extra.isEmpty ? "" : "/" + extra.sorted { $0.key < $1.key }.map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }.joined(separator: "&")
        return "\(base)/\(resource)/\(type.urlEncoded)/\(idPart)\(extraPart).json"
    }

    /** Accepts `stremio://`, bare hosts, and URLs with or without `/manifest.json`. */
    public static func normalizeTransportUrl(_ input: String) -> String {
        var url = input.trimmed
        if url.hasPrefix("stremio://") { url = "https://" + url.removingPrefix("stremio://") }
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") { url = "https://" + url }
        let path = url.before("?")
        if !path.hasSuffix("/manifest.json") {
            let query = url.contains("?") ? "?" + url.after("?") : ""
            var p = path
            while p.hasSuffix("/") { p.removeLast() }
            url = p + "/manifest.json" + query
        }
        return url
    }
}
