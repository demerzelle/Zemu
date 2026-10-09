import Foundation

/** Small NSRegularExpression wrapper (Swift Regex has no lookbehind, which the parser relies on). */
struct Rx: @unchecked Sendable {
    let re: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = true) {
        re = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    }

    func contains(_ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    /** Capture groups of the first match at or after UTF-16 offset [from]; "" for groups that didn't take part. */
    func find(_ s: String, from: Int = 0) -> [String]? {
        let ns = s as NSString
        guard from <= ns.length, let m = re.firstMatch(in: s, range: NSRange(location: from, length: ns.length - from)) else { return nil }
        return groups(m, ns)
    }

    func findAll(_ s: String) -> [[String]] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { groups($0, ns) }
    }

    private func groups(_ m: NSTextCheckingResult, _ ns: NSString) -> [String] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}

/**
 * Extracts quality, language and cache information from a Stremio stream object.
 *
 * Debrid addons (Torrentio, Comet, MediaFusion, AIOStreams, TorBox, ...) don't share a schema for
 * this, so it's inferred from the `name`, `description`/`title` and `behaviorHints.filename` text,
 * the same text users read in Stremio.
 */
public enum StreamParser {
    private static let B = "(?<![a-z0-9])"
    private static let E = "(?![a-z0-9])"
    /** Audio tags are often glued to channel counts ("DDP5.1"), so only letters end them. */
    private static let EA = "(?![a-z])"
    private static func rx(_ p: String, end: String = E) -> Rx { Rx("\(B)(?:\(p))\(end)") }

    private static let res2160 = rx("2160p|4k|uhd")
    private static let res1440 = rx("1440p|2k")
    private static let res1080 = rx("1080[pi]|fhd")
    private static let res720 = rx("720p")
    private static let resSd = rx("576p|480p|360p|sd")

    private static let cam = rx("cam|camrip|hdcam|hd-?ts|telesync|telecine|hd-?tc|dvdscr|screener")
    private static let remux = rx("remux|bdremux")
    private static let bluray = rx("blu-?ray|bdrip|brrip|bd25|bd50|bdmv")
    private static let webrip = rx("web-?rip")
    private static let webdl = rx("web-?dl|web")
    private static let hdtv = rx("hdtv|pdtv|dsr|tvrip")
    private static let dvd = rx("dvd-?rip|dvd|dvd5|dvd9")

    private static let dv = rx("dv|dovi|dolby[ .-]?vision")
    private static let hdr10p = Rx("\(B)(?:hdr10\\+|hdr10plus|hdr10p)(?![a-z0-9])")
    private static let hdr = Rx("\(B)(?:hdr(?:10)?)(?![a-z0-9+])")
    private static let hlg = rx("hlg")

    private static let av1 = rx("av1")
    private static let hevc = rx("x265|h\\.?265|hevc")
    private static let avc = rx("x264|h\\.?264|avc")
    private static let tenBit = rx("10-?bit|hi10p")

    private static let atmos = rx("atmos", end: EA)
    private static let truehd = rx("true-?hd", end: EA)
    private static let dtsHd = rx("dts-?hd(?:[ .-]?ma)?|dts-?x|dts-?ma", end: EA)
    private static let dts = rx("dts", end: EA)
    private static let ddp = rx("ddp|dd\\+|e-?ac-?3|dolby[ .]?digital[ .]?plus", end: EA)
    private static let dd = rx("dd|ac-?3|dolby[ .]?digital", end: EA)
    private static let aac = rx("aac", end: EA)
    private static let flac = rx("flac", end: EA)
    private static let opus = rx("opus", end: EA)
    private static let channelsRx = Rx("(?<![0-9])([2578])[ .]([01])(?![0-9])(?!\\s*[gmkt]i?b)")

    private static let sizeRx = Rx("([0-9]+(?:[.,][0-9]+)?)\\s*(tb|tib|gb|gib|mb|mib)(?![a-z])")
    private static let seedersRx = Rx("👤\\s*([0-9]+)|seed(?:er)?s?\\s*:?\\s*([0-9]+)")
    private static let groupRx = Rx("-([A-Za-z0-9]{2,15})(?:\\.[A-Za-z0-9]{2,4})?\\s*$", ignoreCase: false)

    // Case-sensitive on purpose: "[RD+]", "[AD download]", "[TB⚡]".
    private static let serviceTagRx = Rx("(?<![A-Za-z])(RD|AD|PM|DL|TB|OC|ED|PKP|EN)(?=\\s*(?:\\+|⚡|⏳|⬇|download|\\]|☁))", ignoreCase: false)
    private static let serviceNames: [(Rx, String)] = [
        ("real-?debrid", "RD"), ("alldebrid", "AD"), ("premiumize", "PM"), ("debrid-?link", "DL"),
        ("torbox", "TB"), ("offcloud", "OC"), ("easydebrid", "ED"), ("pikpak", "PKP"), ("easynews", "EN"),
    ].map { (Rx($0.0), $0.1) }

    private static let positiveRx = Rx("\\+\\]|⚡|✅|(?<![a-z])(?:cached|instant)(?![a-z])")
    private static let negativeNameRx = Rx("download|⏳|⬇|uncached|not[ _-]?cached")
    private static let negativeDescRx = Rx("⏳|⬇|uncached|not[ _-]?cached")

    private static let anchorRx = Rx("^(?:(?:19|20)\\d{2}|S\\d{1,2}(?:E\\d{1,3})?|\\d{3,4}P|4K)$", ignoreCase: false)
    private static let tokenSplit = try! NSRegularExpression(pattern: "[^A-Za-z0-9+]+")
    private static let multiAudioRx = Rx("multi[ ._-]?audio|dual[ ._-]?audio")
    private static let multiSubRx = Rx("multi[ ._-]?subs?")

    private static func lines(_ s: String) -> [String] {
        s.components(separatedBy: .newlines)
    }

    public static func parse(_ stream: Stream, addonName: String, trustDirectLinks: Bool = false) -> ParsedStream {
        let name = stream.name ?? ""
        let desc = stream.description ?? stream.title ?? ""
        let filename = stream.behaviorHints?.filename ?? ""
        let all = "\(name)\n\(desc)\n\(filename)"
        let descLines = lines(desc).map(\.trimmed).filter { !$0.isEmpty }

        var title = filename
        if title.trimmed.isEmpty { title = descLines.first ?? "" }
        if title.trimmed.isEmpty { title = name.replacingOccurrences(of: "\n", with: " ") }

        let resolution = detectResolution(name) ?? detectResolution(all) ?? 0
        let source: Source =
            cam.contains(all) ? .cam :
            remux.contains(all) ? .remux :
            bluray.contains(all) ? .bluray :
            webrip.contains(all) ? .webrip :
            webdl.contains(all) ? .webDl :
            hdtv.contains(all) ? .hdtv :
            dvd.contains(all) ? .dvd : .unknown

        var hdrSet = Set<HdrFormat>()
        if dv.contains(all) { hdrSet.insert(.dolbyVision) }
        if hdr10p.contains(all) { hdrSet.insert(.hdr10Plus) }
        if hdr.contains(all) { hdrSet.insert(.hdr10) }
        if hlg.contains(all) { hdrSet.insert(.hlg) }

        let codec: VideoCodec = av1.contains(all) ? .av1 : hevc.contains(all) ? .hevc : avc.contains(all) ? .avc : .unknown

        var audio = Set<AudioCodec>()
        if atmos.contains(all) { audio.insert(.atmos) }
        if truehd.contains(all) { audio.insert(.truehd) }
        if dtsHd.contains(all) { audio.insert(.dtsHd) } else if dts.contains(all) { audio.insert(.dts) }
        if ddp.contains(all) { audio.insert(.ddp) } else if dd.contains(all) { audio.insert(.dd) }
        if aac.contains(all) { audio.insert(.aac) }
        if flac.contains(all) { audio.insert(.flac) }
        if opus.contains(all) { audio.insert(.opus) }

        let channels = channelsRx.findAll("\(desc)\n\(filename)")
            .map { "\($0[1]).\($0[2])" }
            .max { Int($0.replacingOccurrences(of: ".", with: ""))! < Int($1.replacingOccurrences(of: ".", with: ""))! }

        let langs = detectLanguages(name: name, descLines: descLines, filename: filename)
        let subsFromField = stream.subtitles.compactMap { Languages.normalize($0.lang) }

        let service = serviceTagRx.find(name)?[1] ?? serviceNames.first { $0.0.contains("\(name)\n\(desc)") }?.1

        let key = stream.url ?? stream.infoHash.map { "\($0):\(stream.fileIdx ?? 0)" } ?? "\(addonName)|\(name)|\(desc)"
        let size = stream.behaviorHints?.videoSize.flatMap { $0 > 0 ? $0 : nil } ?? parseSize("\(desc)\n\(name)")
        let seeders = seedersRx.find(desc).flatMap { m in Int(m[1].isEmpty ? m[2] : m[1]) }

        return ParsedStream(
            raw: stream,
            addonName: addonName,
            key: key,
            title: title,
            resolution: resolution,
            source: source,
            hdr: hdrSet,
            codec: codec,
            tenBit: tenBit.contains(all),
            audio: audio,
            channels: channels,
            audioLanguages: langs.audio,
            multiAudio: langs.multiAudio,
            subtitleLanguages: (langs.subs + subsFromField).distinct(),
            multiSubs: langs.multiSubs,
            sizeBytes: size,
            seeders: seeders,
            releaseGroup: groupRx.find(title)?[1],
            debridService: service,
            isCached: isCached(stream, name: name, desc: desc, trustDirectLinks: trustDirectLinks)
        )
    }

    /**
     * A stream counts as cached only if it has a direct HTTP(S) URL (not a raw torrent) and the
     * addon marked it as cached ("[RD+]", "⚡", "cached", ...) without any "download"/"⏳" marker.
     * Uncached debrid links would start a download on the debrid service instead of playing.
     */
    public static func isCached(_ stream: Stream, name: String, desc: String, trustDirectLinks: Bool) -> Bool {
        guard let url = stream.url, !url.trimmed.isEmpty, url.hasPrefix("https://") || url.hasPrefix("http://") else { return false }
        if negativeNameRx.contains(name) || negativeDescRx.contains(desc) { return false }
        return positiveRx.contains(name) || positiveRx.contains(desc) || trustDirectLinks
    }

    private static func detectResolution(_ text: String) -> Int? {
        if res2160.contains(text) { return 2160 }
        if res1440.contains(text) { return 1440 }
        if res1080.contains(text) { return 1080 }
        if res720.contains(text) { return 720 }
        if resSd.contains(text) { return 480 }
        return nil
    }

    public static func parseSize(_ text: String) -> Int64? {
        let idx = (text as NSString).range(of: "💾").location
        guard let m = (idx != NSNotFound ? sizeRx.find(text, from: idx) : nil) ?? sizeRx.find(text),
              let n = Double(m[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let mult: Double
        switch m[2].lowercased() {
        case "tb", "tib": mult = 1_099_511_627_776
        case "gb", "gib": mult = 1_073_741_824
        default: mult = 1_048_576
        }
        return Int64(n * mult)
    }

    private static func detectLanguages(name: String, descLines: [String], filename: String) -> (audio: [String], subs: [String], multiAudio: Bool, multiSubs: Bool) {
        var audio: [String] = []
        var subs: [String] = []
        var multiAudio = false
        var multiSubs = false
        func add(_ l: String, to list: inout [String]) { if !list.contains(l) { list.append(l) } }

        for line in descLines + lines(name) {
            let flags = Languages.fromFlags(line)
            if flags.isEmpty { continue }
            if line.range(of: "sub", options: .caseInsensitive) != nil { flags.forEach { add($0, to: &subs) } }
            else { flags.forEach { add($0, to: &audio) } }
        }

        for line in (descLines + [filename]).filter({ !$0.trimmed.isEmpty }) {
            if multiAudioRx.contains(line) { multiAudio = true }
            if multiSubRx.contains(line) { multiSubs = true }

            let ns = line as NSString
            var tokens: [String] = []
            var last = 0
            for m in tokenSplit.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location > last { tokens.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)).uppercased()) }
                last = m.range.location + m.range.length
            }
            if last < ns.length { tokens.append(ns.substring(from: last).uppercased()) }

            // Language tokens are only trusted after the year/season/resolution, past the title.
            guard let anchor = tokens.firstIndex(where: { anchorRx.contains($0) }) else { continue }
            for i in (anchor + 1)..<max(anchor + 1, tokens.count) {
                let t = tokens[i]
                let next = i + 1 < tokens.count ? tokens[i + 1] : nil
                if t == "MULTI" || t == "DUAL" {
                    if next == "SUB" || next == "SUBS" { multiSubs = true } else { multiAudio = true }
                } else if Languages.multiSubTokens.contains(t) {
                    multiSubs = true
                } else if let l = Languages.subtitleTokens[t] {
                    add(l, to: &subs)
                } else if let l = Languages.audioTokens[t] {
                    if let next, Languages.genericSubTokens.contains(next) { add(l, to: &subs) } else { add(l, to: &audio) }
                }
            }
        }
        return (audio, subs, multiAudio || audio.count > 1, multiSubs)
    }
}
