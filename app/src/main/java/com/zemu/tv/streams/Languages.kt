package com.zemu.tv.streams

import java.util.Locale

object Languages {
    /** Shown in Settings as preferred-language choices. */
    val common = listOf(
        "en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "hi", "ar", "tr", "pl", "nl",
        "sv", "no", "da", "fi", "el", "he", "cs", "hu", "ro", "uk", "th", "vi", "id", "ta", "te",
    )

    fun displayName(code: String): String {
        val name = Locale(code).getDisplayLanguage(Locale.ENGLISH)
        return if (name.isNullOrBlank() || name.equals(code, ignoreCase = true)) code.uppercase()
        else name.replaceFirstChar { it.titlecase(Locale.ENGLISH) }
    }

    private val iso3: Map<String, String> by lazy {
        Locale.getISOLanguages().mapNotNull { l -> runCatching { Locale(l).isO3Language to l }.getOrNull() }.toMap() +
            mapOf(
                "fre" to "fr", "ger" to "de", "chi" to "zh", "cze" to "cs", "dut" to "nl", "gre" to "el",
                "per" to "fa", "rum" to "ro", "slo" to "sk", "alb" to "sq", "arm" to "hy", "baq" to "eu",
                "bur" to "my", "geo" to "ka", "ice" to "is", "mac" to "mk", "may" to "ms", "wel" to "cy",
                "pob" to "pt", "spn" to "es", "scc" to "sr", "scr" to "hr",
            )
    }

    private val byName: Map<String, String> by lazy {
        Locale.getISOLanguages().associateBy { Locale(it).getDisplayLanguage(Locale.ENGLISH).lowercase() }
    }

    /** Normalizes "eng", "en-US", "English", "pt_BR" to a 2-letter code. */
    fun normalize(raw: String): String? {
        val c = raw.trim().lowercase().substringBefore('-').substringBefore('_')
        return when {
            c.isEmpty() -> null
            c.length == 2 -> c
            c.length == 3 -> iso3[c] ?: c
            else -> byName[c]
        }
    }

    private val countryToLang = mapOf(
        "GB" to "en", "US" to "en", "AU" to "en", "CA" to "en", "IE" to "en", "NZ" to "en",
        "IT" to "it", "FR" to "fr", "BE" to "fr", "ES" to "es", "MX" to "es", "AR" to "es", "CO" to "es",
        "CL" to "es", "PE" to "es", "DE" to "de", "AT" to "de", "CH" to "de", "PT" to "pt", "BR" to "pt",
        "RU" to "ru", "JP" to "ja", "KR" to "ko", "CN" to "zh", "TW" to "zh", "HK" to "zh", "IN" to "hi",
        "NL" to "nl", "PL" to "pl", "TR" to "tr", "SE" to "sv", "NO" to "no", "DK" to "da", "FI" to "fi",
        "GR" to "el", "CZ" to "cs", "HU" to "hu", "RO" to "ro", "UA" to "uk", "SA" to "ar", "AE" to "ar",
        "EG" to "ar", "IL" to "he", "TH" to "th", "VN" to "vi", "ID" to "id", "BG" to "bg", "HR" to "hr",
        "RS" to "sr", "LT" to "lt", "LV" to "lv", "EE" to "et", "SK" to "sk", "SI" to "sl", "IR" to "fa",
        "MY" to "ms", "PH" to "tl",
    )

    /** Languages for each flag emoji (pairs of regional-indicator symbols) in [text]. */
    fun fromFlags(text: String): Set<String> {
        val out = linkedSetOf<String>()
        val cps = text.codePoints().toArray()
        var i = 0
        while (i < cps.size - 1) {
            val a = cps[i]
            val b = cps[i + 1]
            if (a in 0x1F1E6..0x1F1FF && b in 0x1F1E6..0x1F1FF) {
                val country = "${'A' + (a - 0x1F1E6)}${'A' + (b - 0x1F1E6)}"
                countryToLang[country]?.let(out::add)
                i += 2
            } else i++
        }
        return out
    }

    /**
     * Release-name tokens that indicate an audio language. Ambiguous 3-letter codes that are also
     * common title words (BEN, MAL, TEL, IND, FIN, ...) are left out on purpose.
     */
    val audioTokens: Map<String, String> = mapOf(
        "ENG" to "en", "ENGLISH" to "en",
        "ITA" to "it", "ITALIAN" to "it",
        "FRE" to "fr", "FRA" to "fr", "FRENCH" to "fr", "TRUEFRENCH" to "fr", "VFF" to "fr", "VFQ" to "fr", "VFI" to "fr", "VF2" to "fr",
        "SPA" to "es", "ESP" to "es", "SPANISH" to "es", "CASTELLANO" to "es", "LATINO" to "es",
        "GER" to "de", "GERMAN" to "de", "DEUTSCH" to "de",
        "POR" to "pt", "PORTUGUESE" to "pt", "DUBLADO" to "pt",
        "RUS" to "ru", "RUSSIAN" to "ru",
        "JAP" to "ja", "JPN" to "ja", "JAPANESE" to "ja",
        "KOR" to "ko", "KOREAN" to "ko",
        "CHINESE" to "zh", "MANDARIN" to "zh", "CANTONESE" to "zh",
        "HIN" to "hi", "HINDI" to "hi", "TAMIL" to "ta", "TELUGU" to "te", "MALAYALAM" to "ml", "KANNADA" to "kn", "BENGALI" to "bn",
        "ARA" to "ar", "ARABIC" to "ar", "TUR" to "tr", "TURKISH" to "tr",
        "POL" to "pl", "POLISH" to "pl", "DUTCH" to "nl", "FLEMISH" to "nl",
        "SWE" to "sv", "SWEDISH" to "sv", "NORWEGIAN" to "no", "DANISH" to "da", "FINNISH" to "fi",
        "GREEK" to "el", "HEB" to "he", "HEBREW" to "he", "CZE" to "cs", "CZECH" to "cs",
        "HUN" to "hu", "HUNGARIAN" to "hu", "ROMANIAN" to "ro", "UKR" to "uk", "UKRAINIAN" to "uk",
        "THAI" to "th", "VIE" to "vi", "VIETNAMESE" to "vi", "INDONESIAN" to "id", "PERSIAN" to "fa", "FARSI" to "fa",
    )

    /** Tokens that directly name subtitle languages. */
    val subtitleTokens: Map<String, String> = mapOf(
        "ESUB" to "en", "ESUBS" to "en", "ENGSUB" to "en", "ENGSUBS" to "en",
        "SUBITA" to "it", "SUBSITA" to "it", "ITASUB" to "it",
        "VOSTFR" to "fr", "STFR" to "fr", "SUBFRENCH" to "fr",
        "SUBESP" to "es", "SPASUB" to "es", "HINSUB" to "hi", "KORSUB" to "ko", "SUBPT" to "pt", "LEGENDADO" to "pt",
        "NLSUB" to "nl", "NLSUBS" to "nl", "SWESUB" to "sv", "NORSUB" to "no", "DKSUBS" to "da", "FINSUB" to "fi",
        "PLSUB" to "pl", "RUSSUB" to "ru", "GERSUB" to "de",
    )

    val multiSubTokens = setOf("MSUB", "MSUBS", "MULTISUB", "MULTISUBS", "MULTSUB", "MULTSUBS")
    val genericSubTokens = setOf("SUB", "SUBS", "SUBBED", "SUBTITLES", "SUBTITLED")
}
