import Foundation

/**
 * Kitsu lists each season of a show as its own title ("Attack on Titan", "Attack on Titan Season 2").
 * Anime catalogs show one card per show instead, and its other seasons stay one step away on its page.
 */
public enum AnimeSeasons {
    /** Name without its season marker, and the season it names (nil when the name has none). */
    public static func split(_ name: String) -> (base: String, season: Int?) {
        var s = name.trimmingCharacters(in: .whitespaces)
        if let m = match(#"^(.*?)\s*\(\d{4}\)\s*$"#, s) { s = m[1] }
        let markers = [
            #"^(.*?)[\s:,]+season\s+(\d{1,2})\b.*$"#,
            #"^(.*?)\s+(\d{1,2})(?:st|nd|rd|th)\s+season\b.*$"#,
            #"^(.*?)\s+(\d{1,2})$"#,
        ]
        for pattern in markers {
            if let m = match(pattern, s), let n = Int(m[2]) {
                return (m[1].trimmingCharacters(in: .whitespaces), n)
            }
        }
        return (s, nil)
    }

    /** Titles that belong to one show share a key. Non-anime titles are their own key. */
    public static func groupKey(_ meta: Meta) -> String {
        guard meta.isAnime else { return meta.id }
        let base = split(meta.title).base.lowercased()
        return base.isEmpty ? meta.id : "anime:" + base
    }

    /** One card per show. The lowest season stands for the show; non-anime titles are left alone. */
    public static func collapse(_ metas: [Meta]) -> [Meta] {
        var groups: [String: [Meta]] = [:]
        for m in metas where m.isAnime { groups[groupKey(m), default: []].append(m) }

        var emitted: Set<String> = []
        var out: [Meta] = []
        for m in metas {
            guard m.isAnime else { out.append(m); continue }
            let key = groupKey(m)
            guard !emitted.contains(key) else { continue }
            emitted.insert(key)
            let members = groups[key] ?? [m]
            guard let rep = members.min(by: { (split($0.title).season ?? 1) < (split($1.title).season ?? 1) }) else { continue }
            let parts = split(rep.title)
            var card = rep
            // Show the show's name, not "… Season 2", when the card stands for several seasons or names one.
            if members.count > 1 || parts.season != nil, !parts.base.isEmpty { card.name = parts.base }
            out.append(card)
        }
        return out
    }

    /** Seasons in order, specials (season 0) first, unmarked titles as season 1. */
    public static func sorted(_ metas: [Meta]) -> [Meta] {
        metas.stableSorted { (split($0.title).season ?? 1) < (split($1.title).season ?? 1) }
    }

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}
