import Foundation

public enum Languages {
    /** Shown in Settings as preferred-language choices. */
    public static let common = [
        "en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "hi", "ar", "tr", "pl", "nl",
        "sv", "no", "da", "fi", "el", "he", "cs", "hu", "ro", "uk", "th", "vi", "id", "ta", "te",
    ]

    private static let english = Locale(identifier: "en")

    public static func displayName(_ code: String) -> String {
        guard let name = english.localizedString(forLanguageCode: code), name.lowercased() != code.lowercased() else { return code.uppercased() }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static let twoLetter: [String] = Locale.LanguageCode.isoLanguageCodes.map(\.identifier).filter { $0.count == 2 }

    private static let iso3: [String: String] = {
        var m: [String: String] = [:]
        for l in twoLetter {
            if let a3 = Locale.LanguageCode(l).identifier(.alpha3) { m[a3] = l }
        }
        let bibliographic = [
            "fre": "fr", "ger": "de", "chi": "zh", "cze": "cs", "dut": "nl", "gre": "el",
            "per": "fa", "rum": "ro", "slo": "sk", "alb": "sq", "arm": "hy", "baq": "eu",
            "bur": "my", "geo": "ka", "ice": "is", "mac": "mk", "may": "ms", "wel": "cy",
            "pob": "pt", "spn": "es", "scc": "sr", "scr": "hr",
        ]
        return m.merging(bibliographic) { _, b in b }
    }()

    private static let byName: [String: String] = {
        var m: [String: String] = [:]
        for l in twoLetter { if let n = english.localizedString(forLanguageCode: l)?.lowercased() { m[n] = l } }
        return m
    }()

    /** Normalizes "eng", "en-US", "English", "pt_BR" to a 2-letter code. */
    public static func normalize(_ raw: String) -> String? {
        let c = raw.trimmed.lowercased().before("-").before("_")
        switch c.count {
        case 0: return nil
        case 2: return c
        case 3: return iso3[c] ?? c
        default: return byName[c]
        }
    }

    private static let countryToLang: [String: String] = [
        "GB": "en", "US": "en", "AU": "en", "CA": "en", "IE": "en", "NZ": "en",
        "IT": "it", "FR": "fr", "BE": "fr", "ES": "es", "MX": "es", "AR": "es", "CO": "es",
        "CL": "es", "PE": "es", "DE": "de", "AT": "de", "CH": "de", "PT": "pt", "BR": "pt",
        "RU": "ru", "JP": "ja", "KR": "ko", "CN": "zh", "TW": "zh", "HK": "zh", "IN": "hi",
        "NL": "nl", "PL": "pl", "TR": "tr", "SE": "sv", "NO": "no", "DK": "da", "FI": "fi",
        "GR": "el", "CZ": "cs", "HU": "hu", "RO": "ro", "UA": "uk", "SA": "ar", "AE": "ar",
        "EG": "ar", "IL": "he", "TH": "th", "VN": "vi", "ID": "id", "BG": "bg", "HR": "hr",
        "RS": "sr", "LT": "lt", "LV": "lv", "EE": "et", "SK": "sk", "SI": "sl", "IR": "fa",
        "MY": "ms", "PH": "tl",
    ]

    /** Languages for each flag emoji (pairs of regional-indicator symbols) in [text], in order. */
    public static func fromFlags(_ text: String) -> [String] {
        var out: [String] = []
        let cps = text.unicodeScalars.map(\.value)
        var i = 0
        while i < cps.count - 1 {
            let a = cps[i], b = cps[i + 1]
            if (0x1F1E6...0x1F1FF).contains(a) && (0x1F1E6...0x1F1FF).contains(b) {
                let country = String(UnicodeScalar(UInt8(65 + a - 0x1F1E6))) + String(UnicodeScalar(UInt8(65 + b - 0x1F1E6)))
                if let l = countryToLang[country], !out.contains(l) { out.append(l) }
                i += 2
            } else { i += 1 }
        }
        return out
    }

    /**
     * Release-name tokens that indicate an audio language. Ambiguous 3-letter codes that are also
     * common title words (BEN, MAL, TEL, IND, FIN, ...) are left out on purpose.
     */
    public static let audioTokens: [String: String] = [
        "ENG": "en", "ENGLISH": "en",
        "ITA": "it", "ITALIAN": "it",
        "FRE": "fr", "FRA": "fr", "FRENCH": "fr", "TRUEFRENCH": "fr", "VFF": "fr", "VFQ": "fr", "VFI": "fr", "VF2": "fr",
        "SPA": "es", "ESP": "es", "SPANISH": "es", "CASTELLANO": "es", "LATINO": "es",
        "GER": "de", "GERMAN": "de", "DEUTSCH": "de",
        "POR": "pt", "PORTUGUESE": "pt", "DUBLADO": "pt",
        "RUS": "ru", "RUSSIAN": "ru",
        "JAP": "ja", "JPN": "ja", "JAPANESE": "ja",
        "KOR": "ko", "KOREAN": "ko",
        "CHINESE": "zh", "MANDARIN": "zh", "CANTONESE": "zh",
        "HIN": "hi", "HINDI": "hi", "TAMIL": "ta", "TELUGU": "te", "MALAYALAM": "ml", "KANNADA": "kn", "BENGALI": "bn",
        "ARA": "ar", "ARABIC": "ar", "TUR": "tr", "TURKISH": "tr",
        "POL": "pl", "POLISH": "pl", "DUTCH": "nl", "FLEMISH": "nl",
        "SWE": "sv", "SWEDISH": "sv", "NORWEGIAN": "no", "DANISH": "da", "FINNISH": "fi",
        "GREEK": "el", "HEB": "he", "HEBREW": "he", "CZE": "cs", "CZECH": "cs",
        "HUN": "hu", "HUNGARIAN": "hu", "ROMANIAN": "ro", "UKR": "uk", "UKRAINIAN": "uk",
        "THAI": "th", "VIE": "vi", "VIETNAMESE": "vi", "INDONESIAN": "id", "PERSIAN": "fa", "FARSI": "fa",
    ]

    /** Tokens that directly name subtitle languages. */
    public static let subtitleTokens: [String: String] = [
        "ESUB": "en", "ESUBS": "en", "ENGSUB": "en", "ENGSUBS": "en",
        "SUBITA": "it", "SUBSITA": "it", "ITASUB": "it",
        "VOSTFR": "fr", "STFR": "fr", "SUBFRENCH": "fr",
        "SUBESP": "es", "SPASUB": "es", "HINSUB": "hi", "KORSUB": "ko", "SUBPT": "pt", "LEGENDADO": "pt",
        "NLSUB": "nl", "NLSUBS": "nl", "SWESUB": "sv", "NORSUB": "no", "DKSUBS": "da", "FINSUB": "fi",
        "PLSUB": "pl", "RUSSUB": "ru", "GERSUB": "de",
    ]

    public static let multiSubTokens: Set<String> = ["MSUB", "MSUBS", "MULTISUB", "MULTISUBS", "MULTSUB", "MULTSUBS"]
    public static let genericSubTokens: Set<String> = ["SUB", "SUBS", "SUBBED", "SUBTITLES", "SUBTITLED"]
}
