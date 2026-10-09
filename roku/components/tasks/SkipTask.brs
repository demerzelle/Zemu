sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    p = m.top.params
    meta = p.meta
    vid = tostr(p.videoId)
    kitsuId = ""
    if startsWith(vid, "kitsu:")
        kitsuId = substringBefore(Mid(vid, 7), ":")
    else if startsWith(meta.id, "kitsu:")
        kitsuId = substringBefore(Mid(meta.id, 7), ":")
    end if
    if kitsuId <> ""
        parts = vid.Split(":")
        ep = 1
        if parts.Count() > 2 then ep = toInt(parts[2])
        if ep = 0 then ep = toInt(p.episode)
        if ep = 0 then ep = 1
        m.top.segments = aniSkip(kitsuId, ep, toInt(p.durationSec))
    else
        m.top.segments = introDb(meta, p.season, p.episode, toInt(p.durationSec))
    end if
end sub

function introDb(meta as Object, season as Dynamic, episode as Dynamic, durationSec as Integer) as Object
    idParam = ""
    if tostr(meta.tmdbId) <> ""
        idParam = "tmdb_id=" + meta.tmdbId
    else if startsWith(tostr(meta.imdbId), "tt")
        idParam = "imdb_id=" + meta.imdbId
    end if
    if idParam = "" then return []
    url = "https://api.theintrodb.org/v3/media?" + idParam
    if meta.type = "series" and season <> invalid and episode <> invalid and toInt(season) >= 0 then url = url + "&season=" + tostr(season) + "&episode=" + tostr(episode)
    if durationSec > 0 then url = url + "&duration_ms=" + tostr(durationSec) + "000"
    o = httpGetJson(url, 10000)
    if not isAA(o) then return []
    out = []
    for each kind in ["intro", "recap", "credits", "preview"]
        arr = o.Lookup(kind)
        if isArr(arr)
            for each s in arr
                if isAA(s)
                    st = toNum(s.start_ms) / 1000
                    en = -1
                    if s.end_ms <> invalid then en = toNum(s.end_ms) / 1000
                    if en < 0 or en > st then out.Push({ type: kind, start: st, end: en })
                end if
            end for
        end if
    end for
    out.SortBy("start")
    return out
end function

function aniSkip(kitsuId as String, episode as Integer, durationSec as Integer) as Object
    o = httpGetJson("https://kitsu.io/api/edge/anime/" + kitsuId + "/mappings?filter%5BexternalSite%5D=myanimelist/anime", 10000)
    mal = ""
    if isAA(o) and isArr(o.data) and o.data.Count() > 0 and isAA(o.data[0].attributes) then mal = tostr(o.data[0].attributes.externalId)
    if mal = "" then return []
    r = httpGetJson("https://api.aniskip.com/v2/skip-times/" + mal + "/" + tostr(episode) + "?types=op&types=ed&types=recap&types=mixed-op&types=mixed-ed&episodeLength=" + tostr(durationSec), 10000)
    if not isAA(r) or not bool(r.found) or not isArr(r.results) then return []
    out = []
    for each x in r.results
        if isAA(x) and isAA(x.interval)
            t = tostr(x.skipType)
            kind = ""
            if t = "op" or t = "mixed-op" then kind = "intro"
            if t = "ed" or t = "mixed-ed" then kind = "credits"
            if t = "recap" then kind = "recap"
            if kind <> "" then out.Push({ type: kind, start: toNum(x.interval.startTime), end: toNum(x.interval.endTime) })
        end if
    end for
    out.SortBy("start")
    return out
end function
