' Port of Languages.kt.

function LANG_COMMON() as Object
    return ["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "hi", "ar", "tr", "pl", "nl", "sv", "no", "da", "fi", "el", "he", "cs", "hu", "ro", "uk", "th", "vi", "id", "ta", "te"]
end function

function langNames() as Object
    if m.__langNames = invalid
        m.__langNames = {
            en: "English", es: "Spanish", fr: "French", de: "German", it: "Italian", pt: "Portuguese", ru: "Russian", ja: "Japanese",
            ko: "Korean", zh: "Chinese", hi: "Hindi", ar: "Arabic", tr: "Turkish", pl: "Polish", nl: "Dutch", sv: "Swedish",
            no: "Norwegian", nb: "Norwegian", da: "Danish", fi: "Finnish", el: "Greek", he: "Hebrew", cs: "Czech", hu: "Hungarian",
            ro: "Romanian", uk: "Ukrainian", th: "Thai", vi: "Vietnamese", id: "Indonesian", ta: "Tamil", te: "Telugu", ml: "Malayalam",
            kn: "Kannada", bn: "Bengali", fa: "Persian", bg: "Bulgarian", hr: "Croatian", sr: "Serbian", sk: "Slovak", sl: "Slovenian",
            lt: "Lithuanian", lv: "Latvian", et: "Estonian", ms: "Malay", tl: "Tagalog", ca: "Catalan", eu: "Basque", gl: "Galician",
            is: "Icelandic", mk: "Macedonian", sq: "Albanian", hy: "Armenian", ka: "Georgian", my: "Burmese", cy: "Welsh", ur: "Urdu",
            mr: "Marathi", pa: "Punjabi", gu: "Gujarati", sw: "Swahili", af: "Afrikaans", bs: "Bosnian", be: "Belarusian", kk: "Kazakh",
            km: "Khmer", lo: "Lao", mn: "Mongolian", ne: "Nepali", si: "Sinhala", az: "Azerbaijani", uz: "Uzbek", ga: "Irish", la: "Latin"
        }
    end if
    return m.__langNames
end function

function langName(code as String) as String
    n = langNames().Lookup(code)
    if n = invalid then return UCase(code)
    return n
end function

function iso3Map() as Object
    if m.__iso3 = invalid
        m.__iso3 = {
            eng: "en", spa: "es", fre: "fr", fra: "fr", ger: "de", deu: "de", ita: "it", por: "pt", rus: "ru", jpn: "ja", kor: "ko",
            chi: "zh", zho: "zh", hin: "hi", ara: "ar", tur: "tr", pol: "pl", dut: "nl", nld: "nl", swe: "sv", nor: "no", nob: "no",
            dan: "da", fin: "fi", gre: "el", ell: "el", heb: "he", cze: "cs", ces: "cs", hun: "hu", rum: "ro", ron: "ro", ukr: "uk",
            tha: "th", vie: "vi", ind: "id", tam: "ta", tel: "te", mal: "ml", kan: "kn", ben: "bn", per: "fa", fas: "fa", bul: "bg",
            hrv: "hr", srp: "sr", slo: "sk", slk: "sk", slv: "sl", lit: "lt", lav: "lv", est: "et", may: "ms", msa: "ms", tgl: "tl",
            fil: "tl", cat: "ca", baq: "eu", eus: "eu", glg: "gl", ice: "is", isl: "is", mac: "mk", mkd: "mk", alb: "sq", sqi: "sq",
            arm: "hy", hye: "hy", geo: "ka", kat: "ka", bur: "my", mya: "my", wel: "cy", cym: "cy", urd: "ur", pob: "pt", spn: "es",
            scc: "sr", scr: "hr", bos: "bs", ze: "zh"
        }
    end if
    return m.__iso3
end function

' Normalizes "eng", "en-US", "English", "pt_BR" to a 2-letter code ("" if unknown).
function langNormalize(raw as String) as String
    c = LCase(raw.Trim())
    c = substringBefore(substringBefore(c, "-"), "_")
    if c = "" then return ""
    if Len(c) = 2 then return c
    if Len(c) = 3
        v = iso3Map().Lookup(c)
        if v <> invalid then return v
        return c
    end if
    if m.__byName = invalid
        m.__byName = {}
        names = langNames()
        for each k in names
            m.__byName[LCase(names[k])] = k
        end for
    end if
    v = m.__byName.Lookup(c)
    if v = invalid then return ""
    return v
end function

function countryToLang() as Object
    if m.__c2l = invalid
        m.__c2l = {
            GB: "en", US: "en", AU: "en", CA: "en", IE: "en", NZ: "en", IT: "it", FR: "fr", BE: "fr", ES: "es", MX: "es", AR: "es",
            CO: "es", CL: "es", PE: "es", DE: "de", AT: "de", CH: "de", PT: "pt", BR: "pt", RU: "ru", JP: "ja", KR: "ko", CN: "zh",
            TW: "zh", HK: "zh", IN: "hi", NL: "nl", PL: "pl", TR: "tr", SE: "sv", NO: "no", DK: "da", FI: "fi", GR: "el", CZ: "cs",
            HU: "hu", RO: "ro", UA: "uk", SA: "ar", AE: "ar", EG: "ar", IL: "he", TH: "th", VN: "vi", ID: "id", BG: "bg", HR: "hr",
            RS: "sr", LT: "lt", LV: "lv", EE: "et", SK: "sk", SI: "sl", IR: "fa", MY: "ms", PH: "tl"
        }
    end if
    return m.__c2l
end function

' Languages for each flag emoji (pair of regional-indicator symbols) in text.
function langFromFlags(text as String) as Object
    out = []
    n = Len(text)
    if n < 2 then return out
    c2l = countryToLang()
    i = 1
    while i < n
        a = Asc(Mid(text, i, 1))
        if a >= &h1F1E6 and a <= &h1F1FF
            b = Asc(Mid(text, i + 1, 1))
            if b >= &h1F1E6 and b <= &h1F1FF
                country = Chr(65 + a - &h1F1E6) + Chr(65 + b - &h1F1E6)
                lang = c2l.Lookup(country)
                if lang <> invalid and not arrHas(out, lang) then out.Push(lang)
                i = i + 2
            else
                i = i + 1
            end if
        else
            i = i + 1
        end if
    end while
    return out
end function

' Release-name tokens that indicate an audio language. Ambiguous 3-letter codes are left out on purpose.
function audioTokens() as Object
    if m.__audioTok = invalid
        m.__audioTok = {
            ENG: "en", ENGLISH: "en", ITA: "it", ITALIAN: "it",
            FRE: "fr", FRA: "fr", FRENCH: "fr", TRUEFRENCH: "fr", VFF: "fr", VFQ: "fr", VFI: "fr", VF2: "fr",
            SPA: "es", ESP: "es", SPANISH: "es", CASTELLANO: "es", LATINO: "es",
            GER: "de", GERMAN: "de", DEUTSCH: "de", POR: "pt", PORTUGUESE: "pt", DUBLADO: "pt",
            RUS: "ru", RUSSIAN: "ru", JAP: "ja", JPN: "ja", JAPANESE: "ja", KOR: "ko", KOREAN: "ko",
            CHINESE: "zh", MANDARIN: "zh", CANTONESE: "zh",
            HIN: "hi", HINDI: "hi", TAMIL: "ta", TELUGU: "te", MALAYALAM: "ml", KANNADA: "kn", BENGALI: "bn",
            ARA: "ar", ARABIC: "ar", TUR: "tr", TURKISH: "tr", POL: "pl", POLISH: "pl", DUTCH: "nl", FLEMISH: "nl",
            SWE: "sv", SWEDISH: "sv", NORWEGIAN: "no", DANISH: "da", FINNISH: "fi",
            GREEK: "el", HEB: "he", HEBREW: "he", CZE: "cs", CZECH: "cs",
            HUN: "hu", HUNGARIAN: "hu", ROMANIAN: "ro", UKR: "uk", UKRAINIAN: "uk",
            THAI: "th", VIE: "vi", VIETNAMESE: "vi", INDONESIAN: "id", PERSIAN: "fa", FARSI: "fa"
        }
    end if
    return m.__audioTok
end function

function subtitleTokens() as Object
    if m.__subTok = invalid
        m.__subTok = {
            ESUB: "en", ESUBS: "en", ENGSUB: "en", ENGSUBS: "en", SUBITA: "it", SUBSITA: "it", ITASUB: "it",
            VOSTFR: "fr", STFR: "fr", SUBFRENCH: "fr", SUBESP: "es", SPASUB: "es", HINSUB: "hi", KORSUB: "ko", SUBPT: "pt",
            LEGENDADO: "pt", NLSUB: "nl", NLSUBS: "nl", SWESUB: "sv", NORSUB: "no", DKSUBS: "da", FINSUB: "fi",
            PLSUB: "pl", RUSSUB: "ru", GERSUB: "de"
        }
    end if
    return m.__subTok
end function

function multiSubTokens() as Object
    return { MSUB: true, MSUBS: true, MULTISUB: true, MULTISUBS: true, MULTSUB: true, MULTSUBS: true }
end function

function genericSubTokens() as Object
    return { SUB: true, SUBS: true, SUBBED: true, SUBTITLES: true, SUBTITLED: true }
end function
