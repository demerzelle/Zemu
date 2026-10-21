import Foundation

/** Per-profile settings. Missing keys (older files, new options) fall back to the defaults below. */
public struct AppSettings: Codable, Equatable, Sendable {
    public var audioLanguages: [String] = ["en"]
    public var subtitleLanguages: [String] = ["en"]
    public var autoSubtitles = false
    /** Count plain HTTP streams with no debrid markers as cached (off = strict). */
    public var trustDirectLinks = false
    /** 0 = no limit. */
    public var maxSizeGb = 0
    public var useExternalPlayer = false
    /** "IINA", "VLC" or "Infuse": which app "external player" opens. */
    public var externalPlayer = "IINA"
    /** TMDB v3 API key or v4 read token; enables cast photos, studios and filmographies. */
    public var tmdbApiKey = ""
    public var skipIntroButton = true
    /** Muted trailer replaces the hero backdrop after a title stays hovered. */
    public var heroTrailers = true
    public var heroTrailerSound = false
    /** Deprioritize Dolby Vision-only releases (mpv shows DV profile 5 with odd colors). */
    public var avoidDolbyVision = false
    /** Decode video in software instead of VideoToolbox. Turned on automatically if hardware decoding fails. */
    public var preferSoftwareDecoders = false
    /** A theme preset name, or "CUSTOM". */
    public var theme = "CLASSIC"
    public var customAccent: UInt32 = 0xFFE50914
    public var customBackground: UInt32 = 0xFF0A0A0E
    /** An animated theme name. */
    public var dynamicTheme = "NONE"
    /** Manifest id of the addon preferred for title details and the Movies/Series pages ("" = automatic). */
    public var metaProvider = ""
    // Player
    /** An AspectMode name. */
    public var aspectMode = "FIT"
    /** Selecting a title or an episode starts playing right away instead of opening its page. */
    public var instantPlay = false
    public var autoplayNext = true
    /** When a movie (or a series' last episode) ends, count down to a similar title. */
    public var autoplaySimilar = true
    public var autoplayCountdownSec = 10
    public var stillWatchingPrompt = true
    /** Ask after this many episodes autoplay in a row without touching the keyboard or mouse. */
    public var stillWatchingEpisodes = 3
    /** 0...100 */
    public var volume: Double = 100
    /** Keep styled (ASS/SSA) subtitles as authored, e.g. anime signs. Off applies your style to them too. */
    public var keepStyledSubtitles = true
    /** Enter full screen when playback starts. */
    public var playerFullScreen = false
    /** Switch to Picture in Picture when you leave Zemu while a video plays. */
    public var autoPip = true
    /** Pause the video while Zemu isn't the frontmost app (another app or window has focus); resume on return. */
    public var pauseWhenUnfocused = false
    // Subtitle appearance
    public var subtitleScale: Double = 1
    public var subtitleColor: UInt32 = 0xFFFFFFFF
    /** 0 = none, 1 = translucent box, 2 = solid box. */
    public var subtitleBackground = 0
    /** 0 = none, 1 = outline, 2 = drop shadow. */
    public var subtitleEdge = 1
    /** Distance from the bottom, as a fraction of the screen height. */
    public var subtitleBottom: Double = 0.08
    /** Shift in seconds applied to subtitles (positive = later). */
    public var subtitleDelay: Double = 0
    // Notifications
    public var notifyNewEpisodes = true
    // My List layout
    /** A MyListGroup name. */
    public var myListGroup = "TYPE"
    /** A MyListSort name. */
    public var myListSort = "ADDED_NEWEST"
    /** "CLASSIC" or "GLASS" (experimental Liquid Glass look). */
    public var uiStyle = "CLASSIC"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        audioLanguages = v(.audioLanguages, d.audioLanguages)
        subtitleLanguages = v(.subtitleLanguages, d.subtitleLanguages)
        autoSubtitles = v(.autoSubtitles, d.autoSubtitles)
        trustDirectLinks = v(.trustDirectLinks, d.trustDirectLinks)
        maxSizeGb = v(.maxSizeGb, d.maxSizeGb)
        useExternalPlayer = v(.useExternalPlayer, d.useExternalPlayer)
        externalPlayer = v(.externalPlayer, d.externalPlayer)
        tmdbApiKey = v(.tmdbApiKey, d.tmdbApiKey)
        skipIntroButton = v(.skipIntroButton, d.skipIntroButton)
        heroTrailers = v(.heroTrailers, d.heroTrailers)
        heroTrailerSound = v(.heroTrailerSound, d.heroTrailerSound)
        avoidDolbyVision = v(.avoidDolbyVision, d.avoidDolbyVision)
        preferSoftwareDecoders = v(.preferSoftwareDecoders, d.preferSoftwareDecoders)
        theme = v(.theme, d.theme)
        customAccent = v(.customAccent, d.customAccent)
        customBackground = v(.customBackground, d.customBackground)
        dynamicTheme = v(.dynamicTheme, d.dynamicTheme)
        metaProvider = v(.metaProvider, d.metaProvider)
        aspectMode = v(.aspectMode, d.aspectMode)
        instantPlay = v(.instantPlay, d.instantPlay)
        autoplayNext = v(.autoplayNext, d.autoplayNext)
        autoplaySimilar = v(.autoplaySimilar, d.autoplaySimilar)
        autoplayCountdownSec = v(.autoplayCountdownSec, d.autoplayCountdownSec)
        stillWatchingPrompt = v(.stillWatchingPrompt, d.stillWatchingPrompt)
        stillWatchingEpisodes = v(.stillWatchingEpisodes, d.stillWatchingEpisodes)
        volume = v(.volume, d.volume)
        keepStyledSubtitles = v(.keepStyledSubtitles, d.keepStyledSubtitles)
        playerFullScreen = v(.playerFullScreen, d.playerFullScreen)
        autoPip = v(.autoPip, d.autoPip)
        pauseWhenUnfocused = v(.pauseWhenUnfocused, d.pauseWhenUnfocused)
        subtitleScale = v(.subtitleScale, d.subtitleScale)
        subtitleColor = v(.subtitleColor, d.subtitleColor)
        subtitleBackground = v(.subtitleBackground, d.subtitleBackground)
        subtitleEdge = v(.subtitleEdge, d.subtitleEdge)
        subtitleBottom = v(.subtitleBottom, d.subtitleBottom)
        subtitleDelay = v(.subtitleDelay, d.subtitleDelay)
        notifyNewEpisodes = v(.notifyNewEpisodes, d.notifyNewEpisodes)
        myListGroup = v(.myListGroup, d.myListGroup)
        myListSort = v(.myListSort, d.myListSort)
        uiStyle = v(.uiStyle, d.uiStyle)
    }
}
