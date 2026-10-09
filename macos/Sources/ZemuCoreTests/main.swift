import Foundation
import ZemuCore

// Port of the Android StreamParserTest plus protocol/filter checks. Run with `swift run ZemuCoreTests`.

var failures = 0
var passed = 0

func check(_ ok: Bool, _ what: String, file: String = #file, line: Int = #line) {
    if ok { passed += 1 } else { failures += 1; print("  ✗ \(what)  (line \(line))") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String, line: Int = #line) { check(a == b, "\(what): got \(a), expected \(b)", line: line) }
func test(_ name: String, _ body: () -> Void) {
    let before = failures
    body()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

func parse(_ name: String, _ desc: String, url: String? = "https://cdn.example/file.mkv", filename: String? = nil) -> ParsedStream {
    StreamParser.parse(Stream(name: name, description: desc, url: url, behaviorHints: StreamBehaviorHints(filename: filename)), addonName: "Test")
}

test("torrentio cached stream is fully parsed") {
    let s = parse("[RD+] Torrentio\n4k DV | HDR", "Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX\n👤 120 💾 18.5 GB ⚙️ TorrentGalaxy\nMulti Audio / 🇬🇧 / 🇮🇹")
    check(s.isCached, "cached")
    eq(s.resolution, 2160, "resolution")
    eq(s.source, .webDl, "source")
    check(s.hdr.contains(.dolbyVision) && s.hdr.contains(.hdr10), "DV + HDR10")
    eq(s.codec, .hevc, "codec")
    check(s.audio.contains(.ddp) && s.audio.contains(.atmos), "DDP + Atmos")
    eq(s.channels, "5.1", "channels")
    check(abs(Double(s.sizeBytes!) / 1_073_741_824 - 18.5) < 0.01, "size 18.5 GB")
    eq(s.seeders, 120, "seeders")
    eq(s.releaseGroup, "FLUX", "release group")
    eq(Set(s.audioLanguages), ["en", "it"], "audio languages")
    check(s.multiAudio, "multi audio")
    eq(s.debridService, "RD", "service")
}

test("uncached debrid download is rejected") {
    check(!parse("[RD download] Torrentio\n1080p", "Movie.2023.1080p.WEBRip.x264").isCached, "RD download")
    check(!parse("[RD⬇️] Comet", "Movie.2023.1080p").isCached, "RD ⬇")
    check(!parse("MediaFusion ⏳ RD", "Movie.2023.1080p").isCached, "⏳")
}

test("raw torrent is never cached") {
    check(!StreamParser.parse(Stream(name: "[RD+] Torrentio", infoHash: "abc", fileIdx: 0), addonName: "Test").isCached, "infoHash")
}

test("Comet and other cached markers") {
    check(parse("[RD⚡] Comet 4K", "Movie.2023.2160p.BluRay.REMUX").isCached, "⚡")
    check(parse("[TB+] Torrentio", "Movie.2023.1080p").isCached, "TB+")
    check(parse("AIOStreams", "⚡ Cached · Movie.2023.1080p").isCached, "Cached")
}

test("plain direct link needs opt-in") {
    let stream = Stream(name: "My Server", description: "Movie 1080p", url: "https://example.com/a.mp4")
    check(!StreamParser.parse(stream, addonName: "x").isCached, "strict")
    check(StreamParser.parse(stream, addonName: "x", trustDirectLinks: true).isCached, "trusted")
}

test("size is not mistaken for channels") {
    let s = parse("[RD+] Torrentio\n1080p", "Movie.2020.1080p.BluRay.x264\n💾 5.1 GB")
    eq(s.channels, nil, "channels")
    check(abs(Double(s.sizeBytes!) / 1_073_741_824 - 5.1) < 0.01, "size")
}

test("subtitle and language tokens") {
    let s = parse("[RD+] Torrentio", "Movie.2020.1080p.BluRay.x264.ITA.ENG.ESub-GRP")
    eq(Set(s.audioLanguages), ["it", "en"], "audio")
    check(s.subtitleLanguages.contains("en"), "ESub")
    let subsOnly = parse("[RD+] Torrentio", "Movie.2020.1080p.WEB.ENG.SUBS-GRP")
    check(subsOnly.subtitleLanguages.contains("en"), "ENG SUBS → subs")
    check(!subsOnly.audioLanguages.contains("en"), "ENG SUBS ≠ audio")
}

test("title words before the year are not languages") {
    check(parse("[RD+] Torrentio", "Ben-Hur.1959.1080p.BluRay.x264-GRP").audioLanguages.isEmpty, "Ben-Hur")
    check(!parse("[RD+] Torrentio", "Spanish.Affair.2014.1080p.WEB-DL").audioLanguages.contains("es"), "Spanish Affair")
}

test("remux TrueHD is detected") {
    let s = parse("[AD+] Torrentio\n4k", "Movie.2019.UHD.BluRay.2160p.REMUX.TrueHD.Atmos.7.1.HEVC-GRP\n💾 62.3 GB")
    eq(s.source, .remux, "source")
    check(s.audio.contains(.truehd), "TrueHD")
    eq(s.channels, "7.1", "channels")
    eq(s.debridService, "AD", "service")
}

test("CAM is detected") {
    eq(parse("[RD+] Torrentio", "New.Movie.2025.HDCAM.x264").source, .cam, "source")
}

test("lenient meta decoding") {
    let json = #"{"meta":{"id":"tt1","type":"movie","name":"X","imdbRating":7.4,"genres":"Drama, Crime","director":"A","videos":[{"id":"v","season":"1","episode":2}],"moviedb_id":123}}"#
    let m = try! JSONDecoder().decode(MetaResponseProbe.self, from: Data(json.utf8)).meta
    eq(m.imdbRating, "7.4", "number rating")
    eq(m.genres, ["Drama", "Crime"], "comma genres")
    eq(m.director, ["A"], "string director")
    eq(m.videos.first?.season, 1, "string season")
    eq(m.tmdbId, "123", "numeric tmdb id")
}

test("transport URL normalization and resource URLs") {
    eq(AddonClient.normalizeTransportUrl("stremio://torrentio.strem.fun/abc"), "https://torrentio.strem.fun/abc/manifest.json", "stremio://")
    eq(AddonClient.normalizeTransportUrl("example.com/manifest.json?x=1"), "https://example.com/manifest.json?x=1", "bare host")
    eq(AddonClient.resourceUrl("https://a.b", "stream", "series", "tt1:1:2"), "https://a.b/stream/series/tt1:1:2.json", "stream url")
    eq(AddonClient.resourceUrl("https://a.b", "catalog", "movie", "top", ["genre": "Sci-Fi", "skip": "100"]), "https://a.b/catalog/movie/top/genre=Sci-Fi&skip=100.json", "extras")
    eq(Addon.base(of: "https://x.y/conf/manifest.json?a=b"), "https://x.y/conf", "base")
}

test("ranking prefers preferred language and device-friendly streams") {
    var settings = AppSettings()
    settings.audioLanguages = ["en"]
    let a = parse("[RD+] Torrentio", "Movie.2020.1080p.WEB-DL.x264.ITA-GRP")
    let b = parse("[RD+] Torrentio", "Movie.2020.1080p.WEB-DL.x264.ENG-GRP", url: "https://cdn.example/b.mkv")
    let ranked = StreamFilter.apply([a, b], FilterState(), .permissive, settings, [])
    eq(ranked.first?.stream.key, b.key, "English first")
    check(ranked.first?.recommended == true, "best is recommended")
    let facets = StreamFilter.facets([a, b], FilterState(), .permissive, settings, [])
    eq(facets[.audioLang]?.count, 2, "two audio facets")
}

test("languages normalize") {
    eq(Languages.normalize("eng"), "en", "eng")
    eq(Languages.normalize("pt_BR"), "pt", "pt_BR")
    eq(Languages.normalize("English"), "en", "English")
    eq(Languages.normalize("fre"), "fr", "fre")
    eq(Languages.displayName("it"), "Italian", "display")
}

struct MetaResponseProbe: Decodable { var meta: Meta }

print("\n\(passed) checks passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
