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
    /** Seconds the pointer must rest on a title before its trailer starts (with autoplay on). */
    public var heroTrailerDelay: Double = 4
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
    public var autoPip = false
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
    /** "DARK", "LIGHT" or "SYSTEM" (follow macOS). */
    public var appearance = "DARK"
    /** Remapped keys and controls, by BindableAction name. Actions not listed keep their defaults. */
    public var keyBindings: [String: [InputToken]] = [:]
    /** Addon catalogs turned off, as "manifestId/type/catalogId". Everything else is shown. */
    public var disabledCatalogs: [String] = []

    /** OMDb key (free at omdbapi.com): Rotten Tomatoes and Metacritic scores, US ratings. */
    public var omdbApiKey = ""
    /** Your Trakt API app (trakt.tv/oauth/applications) and the tokens from linking this Mac. */
    public var traktClientId = ""
    public var traktClientSecret = ""
    public var traktAccessToken = ""
    public var traktRefreshToken = ""
    public var traktExpiresAt = Int64(0)
    /** fanart.tv personal API key, for screensaver backdrops and missing title logos. */
    public var fanartApiKey = ""
    /** Off: no trailers anywhere (no autoplay, no Trailer buttons or menu items). */
    public var trailers = true
    /** Off: no backdrop pictures behind the title at the top of Home, Browse and Details. */
    public var heroArt = true
    /** Off: titles are written out in plain text instead of their logo artwork. */
    public var logoArt = true
    /** Size of everything on screen, in percent (posters, text, icons). */
    public var uiZoom = 100
    /** Font for all text: a key of FontChoice, "" = the theme's own. */
    public var font = ""
    /** Text size in percent, on top of uiZoom. */
    public var fontSize = 100
    /** Sub-theme per animated theme (e.g. WEATHER to "RAIN", HOLIDAYS to "AUTO"). */
    public var themeVariants = [String: String]()
    /** Full-screen slideshow of library backdrops after the app sits idle. */
    public var screensaver = false
    public var screensaverIdleSec = 60
    public var screensaverImageSec = 10
    /** Crossfade between screensaver titles, in tenths of a second. */
    public var screensaverFadeTenths = 15
    /** Show the title's logo (or name) and the "Watch now" hint on the screensaver. */
    public var screensaverShowTitle = true
    /** Clicks and blips when moving, selecting and going back (themed). Off by default on Mac. */
    public var soundEffects = false
    /** Streaming services you subscribe to (TMDB provider id to name); empty = show the popular ones. */
    public var myServices = [String: String]()
    /** Leave titles you've watched out of suggestion and category rows. */
    public var hideWatchedInRows = true
    /** Prefer SDH (deaf / hard of hearing) subtitle tracks. */
    public var preferSdh = false
    /** Per-theme color overrides: "<theme>/<dark|light>/<role>" to ARGB. */
    public var colorOverrides = [String: UInt32]()
    /** Palettes you saved and named (Settings → Theme → Customize colors). */
    public var savedPalettes = [SavedPalette]()
    /** Found the secret (click the logo ten times). */
    public var catRaveUnlocked = false
    /** The animated theme to return to when the 30-second Cat Rave ends. */
    public var themeBeforeRave = "NONE"

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
        heroTrailerDelay = v(.heroTrailerDelay, d.heroTrailerDelay)
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
        appearance = v(.appearance, d.appearance)
        keyBindings = v(.keyBindings, d.keyBindings)
        disabledCatalogs = v(.disabledCatalogs, d.disabledCatalogs)
        omdbApiKey = v(.omdbApiKey, d.omdbApiKey)
        traktClientId = v(.traktClientId, d.traktClientId)
        traktClientSecret = v(.traktClientSecret, d.traktClientSecret)
        traktAccessToken = v(.traktAccessToken, d.traktAccessToken)
        traktRefreshToken = v(.traktRefreshToken, d.traktRefreshToken)
        traktExpiresAt = v(.traktExpiresAt, d.traktExpiresAt)
        fanartApiKey = v(.fanartApiKey, d.fanartApiKey)
        trailers = v(.trailers, d.trailers)
        heroArt = v(.heroArt, d.heroArt)
        logoArt = v(.logoArt, d.logoArt)
        uiZoom = v(.uiZoom, d.uiZoom)
        font = v(.font, d.font)
        fontSize = v(.fontSize, d.fontSize)
        themeVariants = v(.themeVariants, d.themeVariants)
        screensaver = v(.screensaver, d.screensaver)
        screensaverIdleSec = v(.screensaverIdleSec, d.screensaverIdleSec)
        screensaverImageSec = v(.screensaverImageSec, d.screensaverImageSec)
        screensaverFadeTenths = v(.screensaverFadeTenths, d.screensaverFadeTenths)
        screensaverShowTitle = v(.screensaverShowTitle, d.screensaverShowTitle)
        soundEffects = v(.soundEffects, d.soundEffects)
        myServices = v(.myServices, d.myServices)
        hideWatchedInRows = v(.hideWatchedInRows, d.hideWatchedInRows)
        preferSdh = v(.preferSdh, d.preferSdh)
        colorOverrides = v(.colorOverrides, d.colorOverrides)
        savedPalettes = v(.savedPalettes, d.savedPalettes)
        catRaveUnlocked = v(.catRaveUnlocked, d.catRaveUnlocked)
        themeBeforeRave = v(.themeBeforeRave, d.themeBeforeRave)
    }
}

/** A palette you named: the color overrides it applies, for one theme or every theme ([theme] nil). */
public struct SavedPalette: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var theme: String?
    public var colors: [String: UInt32]
    public init(name: String, theme: String?, colors: [String: UInt32]) { self.name = name; self.theme = theme; self.colors = colors }
}
