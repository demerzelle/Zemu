' Persistent storage in the Roku registry.
'
' Roku gives each app ~16 KB of registry in total, so everything here is compact on purpose:
' only addon URLs are stored (manifests live in cachefs:), history/My List keep a few fields per
' title, and lists are capped. Writes check the result and trim old history if space runs out,
' so installing an addon never silently fails.

function APP_SECTION() as String
    return "zemu"
end function

function profileSection(pid as String) as String
    return "zp_" + pid
end function

function regRead(section as String, key as String) as Dynamic
    sec = CreateObject("roRegistrySection", section)
    if not sec.Exists(key) then return invalid
    raw = sec.Read(key)
    if raw = "" then return invalid
    return ParseJson(raw)
end function

function regReadStr(section as String, key as String) as String
    sec = CreateObject("roRegistrySection", section)
    if not sec.Exists(key) then return ""
    return sec.Read(key)
end function

function regWriteRaw(section as String, key as String, raw as String) as Boolean
    sec = CreateObject("roRegistrySection", section)
    if not sec.Write(key, raw) then return false
    if not sec.Flush() then return false
    return sec.Read(key) = raw
end function

' Writes JSON. If the registry is full, trims the active profile's history and watched list and retries.
function regWrite(section as String, key as String, value as Dynamic) as Boolean
    raw = FormatJson(value)
    if regWriteRaw(section, key, raw) then return true
    for attempt = 1 to 4
        if not freeRegistrySpace(section, key) then exit for
        if regWriteRaw(section, key, raw) then return true
    end for
    return false
end function

function regDelete(section as String, key as String)
    sec = CreateObject("roRegistrySection", section)
    sec.Delete(key)
    sec.Flush()
end function

' Frees space by halving the largest trimmable lists (history, then watched, then ratings).
function freeRegistrySpace(section as String, keepKey as String) as Boolean
    for each k in ["hist", "watched", "ratings", "list"]
        if k <> keepKey
            v = regRead(section, k)
            if isArr(v) and v.Count() > 4
                regWriteRaw(section, k, FormatJson(arrTake(v, Int(v.Count() / 2))))
                return true
            else if isAA(v) and v.Count() > 4
                trimmed = {}
                n = 0
                for each id in v
                    if n < v.Count() / 2 then trimmed[id] = v[id]
                    n = n + 1
                end for
                regWriteRaw(section, k, FormatJson(trimmed))
                return true
            end if
        end if
    end for
    return false
end function

' Removes registry sections left by other sideloaded apps (e.g. an earlier port) so Zemu has room.
sub cleanupForeignSections()
    reg = CreateObject("roRegistry")
    for each s in reg.GetSectionList()
        if s <> APP_SECTION() and not startsWith(s, "zp_") then reg.Delete(s)
    end for
    reg.Flush()
end sub

function registrySpaceKb() as Integer
    reg = CreateObject("roRegistry")
    return reg.GetSpaceAvailable() / 1024
end function

' ---- settings ----

function defaultSettings() as Object
    return {
        audioLanguages: ["en"]
        subtitleLanguages: ["en"]
        autoSubtitles: false
        trustDirectLinks: false
        maxSizeGb: 0
        tmdbApiKey: ""
        skipIntroButton: true
        avoidDolbyVision: false
        theme: "CLASSIC"
        dynamicTheme: "NONE"
        customAccent: "39FF14"
        customBackground: "07090A"
        metaProvider: ""
        autoplayNext: true
        autoplaySimilar: true
        autoplayCountdownSec: 10
        stillWatchingPrompt: true
        stillWatchingEpisodes: 3
    }
end function

function loadSettings(pid as String) as Object
    s = defaultSettings()
    saved = regRead(profileSection(pid), "settings")
    if isAA(saved)
        for each k in saved
            if s.DoesExist(k) then s[k] = saved[k]
        end for
    end if
    return s
end function

' Only values that differ from the defaults are written.
function saveSettings(pid as String, settings as Object) as Boolean
    d = defaultSettings()
    diff = {}
    for each k in settings
        if d.DoesExist(k) and FormatJson(settings[k]) <> FormatJson(d[k]) then diff[k] = settings[k]
    end for
    return regWrite(profileSection(pid), "settings", diff)
end function

' ---- profiles ----

function loadProfiles() as Object
    v = regRead(APP_SECTION(), "profiles")
    if isArr(v) and v.Count() > 0 then return v
    return [{ id: "default", name: "Me", avatar: 0 }]
end function

function saveProfiles(list as Object) as Boolean
    return regWrite(APP_SECTION(), "profiles", list)
end function

function activeProfileId() as String
    id = regReadStr(APP_SECTION(), "active")
    if id = "" then return "default"
    return id
end function

' ---- compact title entries (history / My List) ----

' Only stores image URLs that can't be rebuilt from an IMDb id.
function compactMeta(m as Object) as Object
    e = { i: m.id, t: m.type, n: Left(tostr(m.name), 60) }
    isImdb = startsWith(m.id, "tt")
    if not isImdb
        if tostr(m.poster) <> "" then e.p = m.poster
        if tostr(m.background) <> "" and m.background <> m.poster then e.b = m.background
    end if
    if isArr(m.genres) and m.genres.Count() > 0 then e.g = joinArr(arrTake(m.genres, 3), "|")
    if tostr(m.imdbRating) <> "" then e.r = m.imdbRating
    return e
end function

function expandMeta(e as Object) as Object
    id = tostr(e.i)
    m = { id: id, type: tostr(e.t), name: tostr(e.n), poster: tostr(e.p), background: tostr(e.b), genres: [], imdbRating: tostr(e.r), logo: "", description: "", releaseInfo: "", runtime: "" }
    if startsWith(id, "tt")
        imdb = substringBefore(id, ":")
        if m.poster = "" then m.poster = metahub("poster", "small", imdb)
        if m.background = "" then m.background = metahub("background", "medium", imdb)
        m.logo = metahub("logo", "medium", imdb)
    end if
    if m.background = "" then m.background = m.poster
    if tostr(e.g) <> "" then m.genres = e.g.Split("|")
    return m
end function
