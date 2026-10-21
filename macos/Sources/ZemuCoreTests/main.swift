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

test("anime tag: Anime genre and kitsu ids count, Animation alone doesn't") {
    let json = #"{"id":"tt9","type":"series","name":"X","genres":["Animation","Anime"]}"#
    let tagged = try! JSONDecoder().decode(Meta.self, from: Data(json.utf8))
    check(tagged.isAnimeTagged, "Anime genre is anime")
    let animated = try! JSONDecoder().decode(Meta.self, from: Data(#"{"id":"tt8","type":"series","name":"Y","genres":["Animation","Comedy"]}"#.utf8))
    check(!animated.isAnimeTagged, "Animation without Anime is not anime")
    let kitsu = try! JSONDecoder().decode(Meta.self, from: Data(#"{"id":"kitsu:1","type":"series","name":"Z","genres":[]}"#.utf8))
    check(kitsu.isAnimeTagged, "kitsu id is anime")
}

test("settings: PiP is off by default, trailer delay round-trips and defaults") {
    let d = AppSettings()
    check(!d.autoPip, "autoPip defaults to off")
    check(d.heroTrailerDelay == 4, "trailer delay defaults to 4 s")
    var s = AppSettings()
    s.heroTrailerDelay = 6
    let data = try! JSONEncoder().encode(s)
    let back = try! JSONDecoder().decode(AppSettings.self, from: data)
    check(back.heroTrailerDelay == 6, "trailer delay survives encode/decode")
    let old = try! JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    check(old.heroTrailerDelay == 4 && !old.autoPip, "missing keys fall back to defaults")
}

test("anime categories: Kitsu studios parse, years and studios group titles") {
    // Trimmed from GET kitsu.io/api/edge/anime/1376?include=productions.company: only the studio role counts.
    let json = JSONValue.parse(Data(#"{"data":{},"included":[{"id":"3620","type":"mediaProductions","attributes":{"role":"producer"},"relationships":{"company":{"data":{"type":"producers","id":"24"}}}},{"id":"3648","type":"mediaProductions","attributes":{"role":"studio"},"relationships":{"company":{"data":{"type":"producers","id":"5"}}}},{"id":"3649","type":"mediaProductions","attributes":{"role":"licensor"},"relationships":{"company":{"data":{"type":"producers","id":"19"}}}},{"id":"24","type":"producers","attributes":{"name":"VAP"}},{"id":"5","type":"producers","attributes":{"name":"MADHOUSE"}},{"id":"19","type":"producers","attributes":{"name":"Viz Media"}}]}"#.utf8))!
    eq(AnimeCategories.studios(fromKitsu: json), ["MADHOUSE"], "only studio-role companies")
    eq(AnimeCategories.studios(fromKitsu: JSONValue.parse(Data("{}".utf8))!), [], "no included data")

    func anime(_ n: Int, _ year: String) -> Meta { Meta(id: "kitsu:\(n)", type: "series", name: "A\(n)", releaseInfo: year) }
    let pool = (1...4).map { anime($0, "2024") } + (5...6).map { anime($0, "2019") }
    eq(AnimeCategories.yearRows(pool).map(\.title), ["Anime from 2024"], "only years with 4+ titles")
    var studios: [String: [String]] = [:]
    for m in pool.prefix(4) { studios[m.id] = ["MAPPA", "Bones"] }
    for m in pool.suffix(2) { studios[m.id] = ["Bones"] }
    eq(AnimeCategories.studioRows(pool, studios: studios).map(\.title), ["Studio · Bones", "Studio · MAPPA"], "studios by title count")
    eq(AnimeCategories.studioRows(pool, studios: studios).last?.items.count, 4, "MAPPA row holds its four titles")
}

test("anime posters: titled IMDb poster first, Kitsu poster as fallback") {
    let anime = Meta(id: "kitsu:1376", type: "series", imdbIdField: "tt0877057", poster: "https://media.kitsu.app/anime/poster_images/1376/medium.jpg")
    eq(anime.preferredPosterUrl, "https://images.metahub.space/poster/medium/tt0877057/img", "anime with IMDb id prefers the titled poster")
    eq(anime.fallbackPosterUrl, "https://media.kitsu.app/anime/poster_images/1376/medium.jpg", "Kitsu poster is the fallback")
    let noImdb = Meta(id: "kitsu:9", type: "series", poster: "https://media.kitsu.app/anime/poster_images/9/medium.jpg")
    eq(noImdb.preferredPosterUrl, noImdb.posterUrl, "anime without IMDb id uses its own poster")
    check(noImdb.fallbackPosterUrl == nil, "no fallback when there is no titled poster")
    let movie = Meta(id: "tt0388629", type: "movie", poster: "https://cdn.example/movie.jpg")
    eq(movie.preferredPosterUrl, "https://cdn.example/movie.jpg", "non-anime posters are unchanged")
    check(movie.fallbackPosterUrl == nil, "non-anime has no poster fallback")
}

test("key bindings: defaults, rebinding moves an input, unbind, save round-trip") {
    check(KeyBindings.action(for: .key(36), overrides: [:]) == .select, "Return selects by default")
    check(KeyBindings.action(for: .pad("B"), overrides: [:]) == .back, "controller B goes back")
    check(KeyBindings.action(for: .key(40), overrides: [:]) == .togglePlay, "K toggles play in the player")
    let moved = KeyBindings.bind(.key(36), to: .back, overrides: [:])
    check(KeyBindings.action(for: .key(36), overrides: moved) == .back, "Return rebound to back")
    check(!KeyBindings.tokens(.select, overrides: moved).contains(.key(36)), "Return taken from select")
    check(KeyBindings.tokens(.select, overrides: moved).contains(.key(76)), "keypad Enter still selects")
    let added = KeyBindings.bind(.pad("Y"), to: .select, overrides: moved)
    check(KeyBindings.action(for: .pad("Y"), overrides: added) == .select, "added a controller button")
    check(KeyBindings.tokens(.tertiary, overrides: added).isEmpty, "Y moved away from search")
    let removed = KeyBindings.unbind(.key(53), from: .back, overrides: [:])
    check(KeyBindings.action(for: .key(53), overrides: removed) == nil, "Esc unbound")
    var s = AppSettings()
    s.keyBindings = added
    let back = try! JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    check(back.keyBindings == added, "bindings survive encode/decode")
    check(KeyBindings.name(.key(49)) == "Space" && KeyBindings.name(.pad("L1")) == "LB", "readable names")
}

test("anime seasons: names split into show and season, one card per show") {
    func split(_ s: String) -> String { let r = AnimeSeasons.split(s); return "\(r.base)|\(r.season.map(String.init) ?? "-")" }
    eq(split("Boku no Hero Academia 2"), "Boku no Hero Academia|2", "trailing number")
    eq(split("Attack on Titan Season 3 Part 2"), "Attack on Titan|3", "season word, part ignored")
    eq(split("Sousou no Frieren 2nd Season"), "Sousou no Frieren|2", "ordinal season")
    eq(split("Ore dake Level Up na Ken: Season 2 - Arise from the Shadow"), "Ore dake Level Up na Ken|2", "colon subtitle")
    eq(split("Hunter x Hunter (2011)"), "Hunter x Hunter|-", "year is not a season")
    eq(split("Chainsaw Man: Reze-hen"), "Chainsaw Man: Reze-hen|-", "arcs stay separate")

    func kitsu(_ n: Int, _ name: String) -> Meta { Meta(id: "kitsu:\(n)", type: "series", name: name) }
    let cards = AnimeSeasons.collapse([
        kitsu(12268, "Boku no Hero Academia 2"), kitsu(11469, "Boku no Hero Academia"),
        Meta(id: "tt1", type: "movie", name: "Spider 2"), kitsu(13569, "Attack on Titan Season 3"), kitsu(12, "One Piece"),
    ])
    eq(cards.map(\.id), ["kitsu:11469", "tt1", "kitsu:13569", "kitsu:12"], "one card per show, non-anime untouched")
    eq(cards.first?.name, "Boku no Hero Academia", "card shows the show's name")
    eq(cards[2].name, "Attack on Titan", "lone season shows the show's name")
    eq(cards[1].name, "Spider 2", "movies keep their names")
    eq(AnimeSeasons.sorted([kitsu(2, "Show Season 2"), kitsu(1, "Show")]).map(\.id), ["kitsu:1", "kitsu:2"], "seasons in order")
}

test("addon lists: on by default, toggled per list, all-on and all-off") {
    var settings = AppSettings()
    check(settings.catalogEnabled(addonId: "a", type: "movie", catalogId: "top"), "lists are on by default")

    var off = CatalogToggles.set([], addonId: "a", type: "movie", catalogId: "top", enabled: false)
    eq(off, ["a/movie/top"], "turning a list off stores it")
    off = CatalogToggles.set(off, addonId: "a", type: "movie", catalogId: "top", enabled: false)
    eq(off.count, 1, "turning off twice doesn't duplicate")
    settings.disabledCatalogs = off
    check(!settings.catalogEnabled(addonId: "a", type: "movie", catalogId: "top"), "off list is hidden")
    check(settings.catalogEnabled(addonId: "a", type: "series", catalogId: "top"), "same id, other type stays on")
    check(settings.catalogEnabled(addonId: "b", type: "movie", catalogId: "top"), "same list in another addon stays on")
    eq(CatalogToggles.set(off, addonId: "a", type: "movie", catalogId: "top", enabled: true), [], "turning a list back on removes it")

    let lists: [(type: String, id: String)] = [("movie", "top"), ("series", "top")]
    eq(CatalogToggles.setAll([], addonId: "a", lists: lists, enabled: false), ["a/movie/top", "a/series/top"], "hide all")
    eq(CatalogToggles.setAll(["a/movie/top", "b/movie/top"], addonId: "a", lists: lists, enabled: true), ["b/movie/top"], "show all leaves other addons alone")

    let saved = try! JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(AppSettings()))
    eq(saved.disabledCatalogs, [], "settings round-trip with no disabled lists")
    let old = try! JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    eq(old.disabledCatalogs, [], "older profiles without the field keep every list on")
}

test("anime rows: because you watched, genre mash-ups, acclaimed but not mainstream") {
    func show(_ n: Int, _ name: String, _ genres: [String]) -> Meta { Meta(id: "kitsu:\(n)", type: "series", name: name, genres: genres) }
    let pool = [
        show(1, "A", ["Action", "Fantasy"]), show(2, "B", ["Action", "Fantasy", "Comedy"]),
        show(3, "C", ["Action", "Fantasy"]), show(4, "D", ["Action", "Fantasy"]),
        show(5, "E", ["Romance", "Comedy"]), show(6, "F", ["Romance", "Comedy"]),
        show(7, "G", ["Romance", "Comedy"]), show(8, "H", ["Romance", "Comedy", "Hentai"]),
    ]

    let because = AnimeCategories.becauseRow(pool, watched: [show(9, "Watched Show", ["Action", "Fantasy", "Drama"])])
    eq(because?.title, "Because you watched Watched Show", "row named after the watched title")
    eq(because?.items.count, 4, "titles sharing two genres with it")
    eq(AnimeCategories.becauseRow(pool, watched: [show(10, "Odd", [])])?.title, nil, "no row from a title without genres")

    let mash = AnimeCategories.mashUpRows(pool)
    eq(mash.map(\.title), ["Action × Fantasy", "Comedy × Romance"], "the most shared genre pairs, adult tags left out")
    eq(mash.first?.items.count, 4, "pair row holds its titles")

    eq(AnimeCategories.acclaimedRow(rated: Array(pool.prefix(7)), popular: Array(pool.prefix(3)))?.items.map(\.name), ["D", "E", "F", "G"], "rated titles not on the popular list")
    eq(AnimeCategories.acclaimedRow(rated: Array(pool.prefix(2)), popular: [])?.title, nil, "too few titles, no row")
}

test("ratings and kid profiles") {
    eq(Ratings.normalize(" tv-y7-fv "), "TV-Y7", "normalized TV rating")
    check(Ratings.isRating("PG-13") && !Ratings.isRating("Not Rated"), "real ratings only")
    check(Ratings.allows(Ratings.defaultAllowed, cert: "PG", kidsGenre: true), "PG family title allowed")
    check(!Ratings.allows(Ratings.defaultAllowed, cert: "PG", kidsGenre: false), "not a kids' title")
    check(!Ratings.allows(Ratings.defaultAllowed, cert: "R", kidsGenre: true), "R blocked")
    check(Ratings.allows(Ratings.defaultAllowed, cert: "", kidsGenre: true), "unrated kids' show allowed by default")
    eq(KidsSettings.hash("1234"), KidsSettings.hash("1234"), "stable parent code hash")
    check(KidsSettings.hash("1234") != KidsSettings.hash("4321"), "different codes differ")
    let old = try! JSONDecoder().decode(KidsSettings.self, from: Data("{}".utf8))
    eq(old.allowed, Ratings.defaultAllowed, "older files get the default ratings")
}

test("rotating discover rows") {
    let a = Categories.tmdbRows(page: "movie", seed: 7, taste: ["Horror"])
    let b = Categories.tmdbRows(page: "movie", seed: 7, taste: ["Horror"])
    eq(a.map(\.key), b.map(\.key), "same seed, same rows")
    check(a.allSatisfy { $0.type == "movie" && $0.tmdb != nil }, "movie page rows are TMDB movie queries")
    check(a.contains { $0.service != nil } && a.contains { $0.studio != nil }, "has service and studio rows")
    eq(Set(a.map(\.key)).count, a.count, "row keys are unique")
    let home = Categories.tmdbRows(page: "home", seed: 1, taste: [])
    check(Set(home.map(\.type)) == ["movie", "series"], "home mixes movies and series")
    eq(Categories.tmdbRows(page: "anime", seed: 1, taste: []).count, 3, "anime gets its three service rows")
    eq(Tmdb.genreId("series", "Sci-Fi"), 10765, "TV genre id")
}

test("saved stream and settings decode from older files") {
    let l = try! JSONDecoder().decode(LastStream.self, from: Data(#"{"key":"abc","bingeGroup":"g"}"#.utf8))
    eq(l.url, nil, "old saved streams have no file link")
    let s = try! JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    check(s.trailers && s.heroArt && s.logoArt && s.hideWatchedInRows && s.uiZoom == 100, "new switches default on")
}

print("\n\(passed) checks passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
