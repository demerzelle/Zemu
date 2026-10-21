' Per-profile user data (My List, history, watched, ratings) kept in m.global and the registry.
' Port of UserStore.kt. Render-thread helpers; every change bumps m.global.userVersion.

function pidSection() as String
    return profileSection(m.global.profileId)
end function

sub bumpUser()
    m.global.userVersion = m.global.userVersion + 1
end sub

function inMyList(id as String) as Boolean
    for each e in m.global.myList
        if e.i = id then return true
    end for
    return false
end function

function toggleMyList(meta as Object) as Boolean
    list = m.global.myList
    out = []
    removed = false
    for each e in list
        if e.i = meta.id then removed = true else out.Push(e)
    end for
    if not removed
        out.Unshift(compactMeta(meta))
        out = arrTake(out, 80)
    end if
    m.global.myList = out
    regWrite(pidSection(), "list", out)
    bumpUser()
    if removed
        toast("Removed from My List")
    else
        toast("Added to My List")
    end if
    return not removed
end function

' ---- Watch Later (its own list, shown under My List) ----

function inWatchLater(id as String) as Boolean
    for each e in m.global.watchLater
        if e.i = id then return true
    end for
    return false
end function

function toggleWatchLater(meta as Object) as Boolean
    out = []
    removed = false
    for each e in m.global.watchLater
        if e.i = meta.id then removed = true else out.Push(e)
    end for
    if not removed
        out.Unshift(compactMeta(meta))
        out = arrTake(out, 40)
    end if
    m.global.watchLater = out
    regWrite(pidSection(), "later", out)
    bumpUser()
    if removed then toast("Removed from Watch Later") else toast("Saved to Watch Later")
    return not removed
end function

' Titles whose page was opened, newest first; Search shows them while the box is empty.
' Kept short: Roku's registry is 16 KB for everything. With "shareRecents" on, one list for every profile.
function viewedSection() as String
    if bool(m.global.settings.shareRecents) then return APP_SECTION()
    return pidSection()
end function

function viewedList() as Object
    v = regRead(viewedSection(), "viewed")
    if not isArr(v) then v = []
    return v
end function

sub addViewed(meta as Object)
    out = [compactMeta(meta)]
    for each e in viewedList()
        if e.i <> meta.id then out.Push(e)
    end for
    regWrite(viewedSection(), "viewed", arrTake(out, 18))
end sub

function isWatched(id as String) as Boolean
    return m.global.watched.DoesExist(id)
end function

sub saveWatched(w as Object)
    ids = []
    for each id in w
        ids.Push(id)
    end for
    regWrite(pidSection(), "watched", arrTake(ids, 300))
end sub

sub setWatched(meta as Object, watched as Boolean)
    w = m.global.watched
    if watched then w[meta.id] = true else w.Delete(meta.id)
    m.global.watched = w
    saveWatched(w)
    bumpUser()
end sub

function historyEntry(id as String, videoId = "" as String) as Dynamic
    for each e in m.global.history
        if e.i = id and (videoId = "" or e.v = videoId) then return e
    end for
    ' History keeps one entry per title; older episodes' positions live in the episode map.
    if videoId <> "" and m.global.episodes <> invalid
        ep = m.global.episodes.Lookup(videoId)
        if isArr(ep) then return { i: id, v: videoId, ps: ep[0], d: ep[1] }
    end if
    return invalid
end function

sub removeFromHistory(id as String)
    out = []
    for each e in m.global.history
        if e.i <> id then out.Push(e)
    end for
    m.global.history = out
    regWrite(pidSection(), "hist", out)
    bumpUser()
end sub

sub clearHistory()
    m.global.history = []
    m.global.episodes = {}
    regDelete(pidSection(), "hist")
    regDelete(pidSection(), "eps")
    bumpUser()
end sub

' Saves playback progress (seconds). flush=false only updates memory (cheap, for frequent ticks).
sub recordProgress(meta as Object, videoId as String, label as String, positionSec as Integer, durationSec as Integer, flush = true as Boolean)
    e = compactMeta(meta)
    e.v = videoId
    if label <> "" then e.l = label
    e.ps = positionSec
    e.d = durationSec
    e.u = nowSec()
    out = [e]
    for each h in m.global.history
        if h.i <> meta.id then out.Push(h)
    end for
    out = arrTake(out, 40)
    m.global.history = out
    eps = invalid
    if videoId <> "" and videoId <> meta.id and m.global.episodes <> invalid
        eps = m.global.episodes
        eps[videoId] = [positionSec, durationSec]
        ' Roku's registry is 16 KB per channel, so keep the map small.
        ' shortcut: drops arbitrary entries past 60; fine while the map is only a resume aid.
        if eps.Count() > 60
            extra = eps.Count() - 60
            for each k in eps.Keys()
                if extra > 0 and k <> videoId
                    eps.Delete(k)
                    extra = extra - 1
                end if
            end for
        end if
        m.global.episodes = eps
    end if
    progress = 0
    if durationSec > 0 then progress = positionSec / durationSec
    done = durationSec > 0 and progress > 0.92 and meta.type <> "series"
    if done or (progress >= 0.01 and progress <= 0.9)
        w = m.global.watched
        if done then w[meta.id] = true else w.Delete(meta.id)
        m.global.watched = w
        if flush then saveWatched(w)
    end if
    ' A finished movie leaves Watch Later.
    if done and inWatchLater(meta.id) and flush then toggleWatchLater(meta)
    if flush
        if eps <> invalid then regWrite(pidSection(), "eps", eps)
        regWrite(pidSection(), "hist", out)
        bumpUser()
    end if
end sub

function ratingOf(id as String) as Integer
    r = m.global.ratings.Lookup(id)
    if r = invalid then return 0
    return toInt(r.v)
end function

sub rateTitle(meta as Object, value as Integer)
    r = m.global.ratings
    if value = 0
        r.Delete(meta.id)
    else
        g = ""
        if isArr(meta.genres) then g = joinArr(arrTake(meta.genres, 3), "|")
        r[meta.id] = { v: value, g: g }
    end if
    ' cap at 60 entries
    if r.Count() > 60
        n = 0
        trimmed = {}
        for each k in r
            if n < 60 then trimmed[k] = r[k]
            n = n + 1
        end for
        r = trimmed
    end if
    m.global.ratings = r
    regWrite(pidSection(), "ratings", r)
    bumpUser()
end sub

sub saveUserSettings(s as Object)
    m.global.settings = s
    if not saveSettings(m.global.profileId, s) then toast("Couldn't save settings on this TV")
end sub

sub toast(text as String)
    m.global.toast = text
end sub

' ---- taste profile & % Match (port of Recommender.kt) ----

function tasteProfile() as Object
    w = {}
    i = 0
    ratings = m.global.ratings
    for each e in m.global.history
        r = ratings.Lookup(e.i)
        if r = invalid or toInt(r.v) >= 0
            progress = 0
            if toNum(e.d) > 0 then progress = toNum(e.ps) / toNum(e.d)
            if progress > 1 then progress = 1
            weight = (0.92 ^ i) * (0.5 + progress)
            if tostr(e.g) <> ""
                for each g in e.g.Split("|")
                    w[g] = toNum(w.Lookup(g)) + weight
                end for
            end if
        end if
        i = i + 1
    end for
    for each e in m.global.myList
        if tostr(e.g) <> ""
            for each g in e.g.Split("|")
                w[g] = toNum(w.Lookup(g)) + 0.6
            end for
        end if
    end for
    for each id in ratings
        r = ratings[id]
        if tostr(r.g) <> ""
            for each g in r.g.Split("|")
                if toInt(r.v) > 0 then w[g] = toNum(w.Lookup(g)) + 1.5 else w[g] = toNum(w.Lookup(g)) - 1.0
            end for
        end if
    end for
    positive = {}
    maxW = 0
    for each g in w
        if w[g] > 0
            positive[g] = w[g]
            if w[g] > maxW then maxW = w[g]
        end if
    end for
    seen = {}
    for each e in m.global.history
        seen[e.i] = true
    end for
    for each id in ratings
        if toInt(ratings[id].v) < 0 then seen[id] = true
    end for
    return { weights: positive, max: maxW, seen: seen }
end function

function affinity(profile as Object, genres as Object) as Float
    if profile.weights.Count() = 0 or genres = invalid or genres.Count() = 0 or profile.max <= 0 then return 0
    top = arrTake(genres, 3)
    sum = 0
    for each g in top
        sum = sum + toNum(profile.weights.Lookup(g))
    end for
    v = sum / (profile.max * top.Count())
    if v < 0 then return 0
    if v > 1 then return 1
    return v
end function

function matchPercent(meta as Object, profile as Object) as Integer
    r = toNum(meta.imdbRating)
    if r <= 0 then r = 6.5
    r = r / 10.0
    x = r
    if profile.weights.Count() > 0 then x = 0.55 * affinity(profile, meta.genres) + 0.45 * r
    v = Int(50 + x * 49 + 0.5)
    if v < 50 then v = 50
    if v > 99 then v = 99
    return v
end function

function topGenres(profile as Object, n as Integer) as Object
    list = []
    for each g in profile.weights
        list.Push({ g: g, w: profile.weights[g] })
    end for
    list.SortBy("w", "r")
    out = []
    for each x in arrTake(list, n)
        out.Push(x.g)
    end for
    return out
end function
