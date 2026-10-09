' Stremio addon protocol helpers (github.com/Stremio/stremio-addon-sdk/tree/master/docs/api).
' Port of Manifest.kt, AddonClient.kt and MetaExt.kt.

function CINEMETA_ID() as String
    return "com.linvo.cinemeta"
end function

function KITSU_ID() as String
    return "community.anime.kitsu"
end function

function KITSU_URL() as String
    return "https://anime-kitsu.strem.fun/manifest.json"
end function

function DEFAULT_ADDONS() as Object
    return ["https://v3-cinemeta.strem.io/manifest.json", "https://opensubtitles-v3.strem.io/manifest.json"]
end function

' Accepts stremio://, bare hosts, and URLs with or without /manifest.json.
function normalizeTransportUrl(input as String) as String
    url = input.Trim()
    if startsWith(LCase(url), "stremio://") then url = "https://" + Mid(url, 11)
    if not startsWith(LCase(url), "http://") and not startsWith(LCase(url), "https://") then url = "https://" + url
    path = substringBefore(url, "?")
    query = substringAfter(url, "?", "")
    if not endsWith(path, "/manifest.json")
        url = trimEndChar(path, "/") + "/manifest.json"
        if query <> "" then url = url + "?" + query
    end if
    return url
end function

function addonBaseUrl(transportUrl as String) as String
    b = substringBefore(transportUrl, "?")
    if endsWith(b, "/manifest.json") then b = Left(b, Len(b) - Len("/manifest.json"))
    return trimEndChar(b, "/")
end function

' extra: array of [key, value] pairs (order matters for some addons).
function resourceUrl(base as String, resource as String, typ as String, id as String, extra = invalid as Dynamic) as String
    idPart = urlEnc(id).Replace("%3A", ":")
    extraPart = ""
    if extra <> invalid and extra.Count() > 0
        parts = []
        for each kv in extra
            parts.Push(urlEnc(kv[0]) + "=" + urlEnc(kv[1]))
        end for
        extraPart = "/" + joinArr(parts, "&")
    end if
    return base + "/" + resource + "/" + urlEnc(typ) + "/" + idPart + extraPart + ".json"
end function

function stripHtml(s as String) as String
    re = CreateObject("roRegex", "<[^>]+>", "")
    ws = CreateObject("roRegex", "\s+", "")
    return ws.ReplaceAll(re.ReplaceAll(s, ""), " ").Trim()
end function

' Reduces a raw manifest to the fields Zemu uses. Returns invalid if it has no id.
function compactManifest(o as Dynamic, transportUrl as String) as Dynamic
    if not isAA(o) then return invalid
    id = tostr(o.id)
    if id = "" then return invalid
    resources = []
    if isArr(o.resources)
        for each r in o.resources
            if isStr(r)
                resources.Push({ name: r, types: invalid, idPrefixes: invalid })
            else if isAA(r) and tostr(r.name) <> ""
                rt = invalid
                rp = invalid
                if isArr(r.types) then rt = strList(r.types)
                if isArr(r.idPrefixes) then rp = strList(r.idPrefixes)
                resources.Push({ name: r.name, types: rt, idPrefixes: rp })
            end if
        end for
    end if
    catalogs = []
    if isArr(o.catalogs)
        for each c in o.catalogs
            if isAA(c)
                extras = []
                if isArr(c.extra)
                    for each e in c.extra
                        if isAA(e) then extras.Push({ name: tostr(e.name), isRequired: bool(e.isRequired), options: strList(e.options) })
                    end for
                end if
                ' legacy fields
                for each n in strList(c.extraRequired)
                    extras.Push({ name: n, isRequired: true, options: [] })
                end for
                for each n in strList(c.extraSupported)
                    found = false
                    for each e in extras
                        if e.name = n then found = true
                    end for
                    if not found then extras.Push({ name: n, isRequired: false, options: [] })
                end for
                catalogs.Push({ type: tostr(c.type), id: tostr(c.id), name: tostr(c.name), extra: extras })
            end if
        end for
    end if
    addonCatalogs = []
    if isArr(o.addonCatalogs)
        for each c in o.addonCatalogs
            if isAA(c) then addonCatalogs.Push({ type: tostr(c.type), id: tostr(c.id), name: tostr(c.name) })
        end for
    end if
    hints = o.behaviorHints
    name = tostr(o.name)
    if name = "" then name = id
    idPrefixes = invalid
    if isArr(o.idPrefixes) then idPrefixes = strList(o.idPrefixes)
    desc = stripHtml(tostr(o.description))
    if Len(desc) > 400 then desc = Left(desc, 400) + "…"
    return {
        id: id
        name: name
        version: tostr(o.version)
        description: desc
        logo: tostr(o.logo)
        types: strList(o.types)
        idPrefixes: idPrefixes
        resources: resources
        catalogs: catalogs
        addonCatalogs: addonCatalogs
        configurable: isAA(hints) and bool(hints.configurable)
        configurationRequired: isAA(hints) and bool(hints.configurationRequired)
        transportUrl: transportUrl
        baseUrl: addonBaseUrl(transportUrl)
    }
end function

function addonHasResource(a as Object, resource as String) as Boolean
    for each r in a.resources
        if r.name = resource then return true
    end for
    return false
end function

function addonSupports(a as Object, resource as String, typ as String, id as Dynamic) as Boolean
    res = invalid
    for each r in a.resources
        if r.name = resource
            res = r
            exit for
        end if
    end for
    if res = invalid then return false
    types = res.types
    if types = invalid then types = a.types
    if types.Count() > 0 and not arrHas(types, typ) then return false
    prefixes = res.idPrefixes
    if prefixes = invalid then prefixes = a.idPrefixes
    if id <> invalid and prefixes <> invalid and prefixes.Count() > 0
        ok = false
        for each p in prefixes
            if startsWith(id, p)
                ok = true
                exit for
            end if
        end for
        if not ok then return false
    end if
    return true
end function

function addonsFor(addons as Object, resource as String, typ as String, id as Dynamic) as Object
    out = []
    for each a in addons
        if addonSupports(a, resource, typ, id) then out.Push(a)
    end for
    return out
end function

function findAddon(addons as Object, id as String) as Dynamic
    for each a in addons
        if a.id = id then return a
    end for
    return invalid
end function

function findCatalog(addon as Dynamic, typ as String, id as String) as Dynamic
    if addon = invalid then return invalid
    for each c in addon.catalogs
        if c.type = typ and c.id = id then return c
    end for
    return invalid
end function

function catalogNeedsExtra(c as Object) as Boolean
    for each e in c.extra
        if e.isRequired then return true
    end for
    return false
end function

function catalogSupportsExtra(c as Object, name as String) as Boolean
    for each e in c.extra
        if e.name = name then return true
    end for
    return false
end function

function catalogOptions(c as Dynamic, name as String) as Object
    if c = invalid then return []
    for each e in c.extra
        if e.name = name then return e.options
    end for
    return []
end function

' ---- metas ----

function metaImdbId(m as Object) as String
    id = tostr(m.id)
    if startsWith(id, "tt") then return substringBefore(id, ":")
    alt = tostr(m.imdb_id)
    if startsWith(alt, "tt") then return alt
    return substringBefore(id, ":")
end function

function metaYear(releaseInfo as String) as Integer
    re = CreateObject("roRegex", "\d{4}", "")
    mm = re.Match(releaseInfo)
    if mm.Count() = 0 then return 0
    return Val(mm[0])
end function

function runtimeLabel(raw as String) as String
    if raw = "" or Instr(1, raw, "h") > 0 then return raw
    re = CreateObject("roRegex", "\d+", "")
    mm = re.Match(raw)
    if mm.Count() = 0 then return raw
    mins = Val(mm[0])
    if mins >= 60 then return tostr(Int(mins / 60)) + "h " + tostr(mins MOD 60) + "m"
    return tostr(mins) + "m"
end function

function metahub(kind as String, size as String, imdb as String) as String
    return "https://images.metahub.space/" + kind + "/" + size + "/" + imdb + "/img"
end function

' Reduces a raw meta to the fields cards and pages need (keeps memory low on the TV).
' Pass full=true on Details to keep videos, cast, director, etc.
function slimMeta(o as Object, full = false as Boolean) as Object
    id = tostr(o.id)
    isImdb = startsWith(id, "tt")
    imdb = metaImdbId(o)
    poster = tostr(o.poster)
    if poster = "" and isImdb then poster = metahub("poster", "small", imdb)
    bg = tostr(o.background)
    if bg = "" and isImdb then bg = metahub("background", "medium", imdb)
    if bg = "" then bg = poster
    logo = tostr(o.logo)
    if logo = "" and isImdb then logo = metahub("logo", "medium", imdb)
    desc = tostr(o.description)
    if not full and Len(desc) > 360 then desc = Left(desc, 357) + "…"
    rating = tostr(o.imdbRating)
    if toNum(rating) <= 0 then rating = ""
    released = tostr(o.released)
    m = {
        id: id
        type: tostr(o.type)
        name: tostr(o.name)
        poster: poster
        background: bg
        logo: logo
        description: desc
        releaseInfo: tostr(o.releaseInfo)
        released: Left(released, 10)
        imdbRating: rating
        runtime: tostr(o.runtime)
        genres: arrTake(strList(o.genres), 6)
        tmdbId: tostr(o.moviedb_id)
        imdbId: imdb
    }
    if m.type = "" then m.type = "movie"
    if full
        m.cast = arrTake(strList(o.cast), 12)
        m.director = arrTake(strList(o.director), 3)
        vids = []
        if isArr(o.videos)
            for each v in o.videos
                if isAA(v)
                    ep = toInt(v.episode)
                    if ep = 0 then ep = toInt(v.number)
                    title = tostr(v.title)
                    if title = "" then title = tostr(v.name)
                    if title = "" then title = "Episode " + tostr(ep)
                    syn = tostr(v.overview)
                    if syn = "" then syn = tostr(v.description)
                    season = -1
                    if v.season <> invalid then season = toInt(v.season)
                    vids.Push({ id: tostr(v.id), title: title, season: season, episode: ep, released: Left(tostr(v.released), 10), thumbnail: tostr(v.thumbnail), overview: syn })
                end if
            end for
        end if
        m.videos = vids
    else
        m.cast = arrTake(strList(o.cast), 6)
        m.director = arrTake(strList(o.director), 2)
    end if
    return m
end function

' Video id to probe when checking whether a title has cached streams.
function probeVideoId(m as Object) as String
    if m.type = "series" and startsWith(m.id, "tt") and Instr(1, m.id, ":") = 0 then return m.id + ":1:1"
    return m.id
end function
