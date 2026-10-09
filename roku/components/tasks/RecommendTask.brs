' Port of Recommender.kt. Persistent task: requests are processed in order; Cinemeta pages are cached
' for the app session so Details pages and Home share the same pools.

sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    port = CreateObject("roMessagePort")
    m.top.observeField("request", port)
    m.pageCache = {}
    handleRequest(m.top.request)
    while true
        msg = Wait(0, port)
        if Type(msg) = "roSGNodeEvent" then handleRequest(msg.getData())
    end while
end sub

' ---- page cache ----

function pageUrl(base as String, typ as String, catalog as String, extra as Object, skip as Integer) as String
    pairs = []
    for each kv in extra
        pairs.Push(kv)
    end for
    if skip > 0 then pairs.Push(["skip", tostr(skip)])
    return resourceUrl(base, "catalog", typ, catalog, pairs)
end function

' Fetches every uncached URL in parallel and stores slim metas per URL.
sub prefetch(urls as Object)
    need = []
    for each u in urls
        if not m.pageCache.DoesExist(u) and not arrHas(need, u) then need.Push(u)
    end for
    if need.Count() = 0 then return
    bodies = httpGetMany(need, 20000, 6)
    for i = 0 to need.Count() - 1
        list = []
        if bodies[i] <> ""
            parsed = ParseJson(bodies[i])
            if isAA(parsed)
                arr = parsed.metas
                if not isArr(arr) then arr = parsed.metasDetailed
                if isArr(arr)
                    for each raw in arr
                        if isAA(raw) and tostr(raw.id) <> "" then list.Push(slimPool(raw, isArr(parsed.metasDetailed)))
                    end for
                end if
            end if
        end if
        m.pageCache[need[i]] = list
    end for
end sub

' Even slimmer than slimMeta: pools hold thousands of titles.
function slimPool(raw as Object, keepVideos as Boolean) as Object
    s = slimMeta(raw)
    if Len(s.description) > 220 then s.description = Left(s.description, 217) + "…"
    if keepVideos and isArr(raw.videos)
        vids = []
        for each v in raw.videos
            if isAA(v) then vids.Push({ id: tostr(v.id), season: toInt(v.season), episode: toInt(v.episode) + toInt(v.number), released: Left(tostr(v.released), 10), thumbnail: tostr(v.thumbnail) })
        end for
        s.videos = vids
    end if
    return s
end function

function cachedPages(urls as Object) as Object
    out = []
    seen = {}
    for each u in urls
        list = m.pageCache.Lookup(u)
        if list <> invalid
            for each x in list
                if not seen.DoesExist(x.id)
                    seen[x.id] = true
                    out.Push(x)
                end if
            end for
        end if
    end for
    return out
end function

function pagesUrls(base as String, typ as String, catalog as String, extra as Object, count as Integer, startSkip = 0 as Integer) as Object
    urls = []
    for i = 0 to count - 1
        urls.Push(pageUrl(base, typ, catalog, extra, startSkip + i * 50))
    end for
    return urls
end function

function poolUrls(base as String, typ as String, genre as String) as Object
    extra = []
    if genre <> "" then extra.Push(["genre", genre])
    urls = pagesUrls(base, typ, "top", extra, 1)
    urls.Append(pagesUrls(base, typ, "imdbRating", extra, 1))
    return urls
end function

function kitsuPoolUrls(kitsu as Dynamic, genre as String) as Object
    if kitsu = invalid then return []
    supported = catalogOptions(findCatalog(kitsu, "anime", "kitsu-anime-popular"), "genre")
    extra = []
    if genre <> "" and arrHas(supported, genre) then extra.Push(["genre", genre])
    return [resourceUrl(kitsu.baseUrl, "catalog", "anime", "kitsu-anime-popular", extra), resourceUrl(kitsu.baseUrl, "catalog", "anime", "kitsu-anime-rating", extra)]
end function

' ---- scoring ----

function similarity(a as Object, b as Object) as Float
    ga = a.genres
    gb = b.genres
    jac = 0
    if ga.Count() > 0 and gb.Count() > 0
        inter = 0
        union = {}
        for each g in ga
            union[g] = true
        end for
        for each g in gb
            if union.DoesExist(g) and arrHas(ga, g) then inter = inter + 1
            union[g] = true
        end for
        jac = inter / union.Count()
    end if
    r = toNum(b.imdbRating)
    if r <= 0 then r = 6
    ya = metaYear(tostr(a.releaseInfo))
    yb = metaYear(tostr(b.releaseInfo))
    ySim = 0.5
    if ya > 0 and yb > 0
        ySim = 1 - Abs(ya - yb) / 30
        if ySim < 0 then ySim = 0
    end if
    people = 0
    pa = {}
    for each p in arrTake(a.cast, 6)
        pa[p] = true
    end for
    for each p in a.director
        pa[p] = true
    end for
    for each p in arrTake(b.cast, 6)
        if pa.DoesExist(p) then people = people + 1
    end for
    for each p in b.director
        if pa.DoesExist(p) then people = people + 1
    end for
    if people > 2 then people = 2
    v = 0.5 * jac + 0.25 * (r / 10) + 0.15 * ySim + people * 0.05
    if v > 1 then v = 1
    return v
end function

function matchFromScore(score as Float) as Integer
    v = Int(55 + score * 44 + 0.5)
    if v < 50 then v = 50
    if v > 99 then v = 99
    return v
end function

function affinityOf(profile as Object, genres as Object) as Float
    if profile.weights.Count() = 0 or genres.Count() = 0 or profile.max <= 0 then return 0
    top = arrTake(genres, 3)
    sum = 0
    for each g in top
        sum = sum + toNum(profile.weights.Lookup(g))
    end for
    v = sum / (profile.max * top.Count())
    if v < 0 then v = 0
    if v > 1 then v = 1
    return v
end function

function matchPct(meta as Object, profile as Object) as Integer
    r = toNum(meta.imdbRating)
    if r <= 0 then r = 6.5
    r = r / 10
    x = r
    if profile.weights.Count() > 0 then x = 0.55 * affinityOf(profile, meta.genres) + 0.45 * r
    v = Int(50 + x * 49 + 0.5)
    if v < 50 then v = 50
    if v > 99 then v = 99
    return v
end function

function topGenresOf(profile as Object, n as Integer) as Object
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

' ---- row building ----

function buildRow(key as String, title as String, priority as Integer, items as Object, matches as Object, watched as Object, style = "poster" as String, subtitles = invalid as Dynamic) as Dynamic
    if items.Count() = 0 then return invalid
    content = CreateObject("roSGNode", "ContentNode")
    content.title = title
    seen = {}
    for i = 0 to items.Count() - 1
        it = items[i]
        if not seen.DoesExist(it.id)
            seen[it.id] = true
            n = content.createChild("MetaNode")
            n.meta = it
            n.style = style
            if matches <> invalid and matches[i] <> invalid then n.badge = tostr(matches[i]) + "%"
            if subtitles <> invalid and subtitles.DoesExist(it.id) then n.subtitle = subtitles[it.id]
            if watched <> invalid then n.watched = watched.DoesExist(it.id)
        end if
    end for
    return { key: key, title: title, priority: priority, style: style, content: content }
end function

function scoredSort(list as Object) as Object
    list.SortBy("score", "r")
    return list
end function

function moreLikeThis(meta as Object, exclude as Object, limit as Integer, cinemeta as Dynamic, kitsu as Dynamic) as Object
    anime = startsWith(meta.id, "kitsu:")
    genres = arrTake(meta.genres, 3)
    if genres.Count() = 0 then genres = [""]
    urls = []
    for each g in genres
        if anime
            urls.Append(kitsuPoolUrls(kitsu, g))
        else if cinemeta <> invalid
            urls.Append(poolUrls(cinemeta.baseUrl, meta.type, g))
        end if
    end for
    prefetch(urls)
    scored = []
    for each c in cachedPages(urls)
        if c.id <> meta.id and not exclude.DoesExist(c.id) then scored.Push({ meta: c, score: similarity(meta, c) })
    end for
    return arrTake(scoredSort(scored), limit)
end function

function rowFromScored(key as String, title as String, priority as Integer, scored as Object, watched as Object) as Dynamic
    items = []
    matches = []
    for each s in scored
        items.Push(s.meta)
        matches.Push(matchFromScore(s.score))
    end for
    return buildRow(key, title, priority, items, matches, watched)
end function

function rowFromPlain(key as String, title as String, priority as Integer, items as Object, profile as Object, watched as Object) as Dynamic
    matches = []
    for each it in items
        matches.Push(matchPct(it, profile))
    end for
    return buildRow(key, title, priority, items, matches, watched)
end function

function similarRows(req as Object) as Object
    meta = req.meta
    exclude = req.exclude
    if exclude = invalid then exclude = {}
    rows = []
    like = moreLikeThis(meta, exclude, 50, req.cinemeta, req.kitsu)
    r = rowFromScored("similar", "More Like This", 0, like, req.watched)
    if r <> invalid then rows.Push(r)
    ' Highly rated titles in the same genre that aren't already shown
    if meta.genres.Count() > 0 and not startsWith(meta.id, "kitsu:") and req.cinemeta <> invalid
        genre = meta.genres[0]
        urls = pagesUrls(req.cinemeta.baseUrl, meta.type, "top", [["genre", genre]], 1)
        urls.Append(pagesUrls(req.cinemeta.baseUrl, meta.type, "imdbRating", [["genre", genre]], 2))
        prefetch(urls)
        shown = {}
        for each s in like
            shown[s.meta.id] = true
        end for
        fav = []
        for each c in cachedPages(urls)
            if c.id <> meta.id and not exclude.DoesExist(c.id) and not shown.DoesExist(c.id) and toNum(c.imdbRating) >= 6.5
                fav.Push({ meta: c, score: similarity(meta, c), rating: toNum(c.imdbRating) })
            end if
        end for
        fav.SortBy("rating", "r")
        r = rowFromScored("genre-favorites", "Top " + genre + " Picks", 1, arrTake(fav, 40), req.watched)
        if r <> invalid then rows.Push(r)
    end if
    return rows
end function

function DEFAULT_SPOTLIGHT() as Object
    return ["Action", "Comedy", "Drama", "Thriller", "Sci-Fi", "Animation", "Horror", "Romance", "Crime", "Adventure", "Fantasy", "Mystery", "Documentary", "Family"]
end function

function dailyRows(req as Object) as Object
    cinemeta = req.cinemeta
    if cinemeta = invalid then return []
    base = cinemeta.baseUrl
    profile = req.profile
    history = req.history
    myList = req.myList
    watched = req.watched
    seed = daySeed()
    rng = newRng(seed)
    seen = profile.seen
    movieGenres = catalogOptions(findCatalog(cinemeta, "movie", "top"), "genre")
    yearOptions = catalogOptions(findCatalog(cinemeta, "movie", "year"), "genre")
    thisYear = Val(Left(dateString(0), 4))
    rows = []

    ' --- work out every page the rows need, then fetch them all in parallel ---
    urls = []
    pickGenres = topGenresOf(profile, 4)
    for each g in pickGenres
        urls.Append(poolUrls(base, "movie", g))
        urls.Append(poolUrls(base, "series", g))
    end for
    recent = []
    recentIds = {}
    for each e in history
        if not recentIds.DoesExist(e.i) and recent.Count() < 12
            recentIds[e.i] = true
            recent.Push(e)
        end if
    end for
    becauseOf = arrTake(shuffled(recent, seed), 2)
    becauseIds = {}
    for each e in becauseOf
        becauseIds[e.i] = true
    end for
    savedSrc = invalid
    for each e in shuffled(myList, seed + 1)
        if not becauseIds.DoesExist(e.i)
            savedSrc = e
            exit for
        end if
    end for
    spotChoices = []
    for each g in topGenresOf(profile, 6)
        if not arrHas(spotChoices, g) then spotChoices.Push(g)
    end for
    for each g in DEFAULT_SPOTLIGHT()
        if not arrHas(spotChoices, g) then spotChoices.Push(g)
    end for
    filtered = []
    for each g in spotChoices
        if movieGenres.Count() = 0 or arrHas(movieGenres, g) then filtered.Push(g)
    end for
    spotlight = ""
    if filtered.Count() > 0 then spotlight = filtered[rng.nextInt(filtered.Count())]
    if spotlight <> ""
        urls.Append(poolUrls(base, "movie", spotlight))
        urls.Append(poolUrls(base, "series", spotlight))
    end if
    gemChoices = topGenresOf(profile, 3)
    if gemChoices.Count() = 0 then gemChoices = DEFAULT_SPOTLIGHT()
    gemGenre = gemChoices[rng.nextInt(gemChoices.Count())]
    if movieGenres.Count() > 0 and not arrHas(movieGenres, gemGenre) then gemGenre = ""
    if gemGenre <> ""
        urls.Append(pagesUrls(base, "movie", "top", [["genre", gemGenre]], 1))
        urls.Append(pagesUrls(base, "movie", "imdbRating", [["genre", gemGenre]], 2, 48))
    end if
    years = []
    for each y in yearOptions
        yv = Val(y)
        if yv >= 1975 and yv <= thisYear - 2 then years.Push(yv)
    end for
    bestYear = 0
    if years.Count() > 0
        bestYear = years[rng.nextInt(years.Count())]
        urls.Append(pagesUrls(base, "movie", "year", [["genre", tostr(bestYear)]], 2))
    end if
    for each t in ["movie", "series"]
        urls.Append(pagesUrls(base, t, "year", [["genre", tostr(thisYear)]], 2))
    end for
    seriesIds = []
    for each e in history
        if e.t = "series" and startsWith(e.i, "tt") and not arrHas(seriesIds, e.i) and seriesIds.Count() < 25 then seriesIds.Push(e.i)
    end for
    lastVideosUrl = ""
    if seriesIds.Count() > 0 and findCatalog(cinemeta, "series", "last-videos") <> invalid
        lastVideosUrl = resourceUrl(base, "catalog", "series", "last-videos", [["lastVideosIds", joinArr(seriesIds, ",")]])
        urls.Push(lastVideosUrl)
    end if
    prefetch(urls)

    ' --- Picked for You Today ---
    if pickGenres.Count() > 0
        pUrls = []
        for each g in pickGenres
            pUrls.Append(poolUrls(base, "movie", g))
            pUrls.Append(poolUrls(base, "series", g))
        end for
        ranked = []
        for each c in cachedPages(pUrls)
            if not seen.DoesExist(c.id)
                r = toNum(c.imdbRating)
                if r <= 0 then r = 6
                ranked.Push({ meta: c, score: 0.6 * affinityOf(profile, c.genres) + 0.4 * (r / 10) })
            end if
        end for
        scoredSort(ranked)
        head = arrTake(ranked, 8)
        tail = []
        for i = 8 to ranked.Count() - 1
            if tail.Count() < 140 then tail.Push(ranked[i])
        end for
        picks = head
        picks.Append(arrTake(shuffled(tail, seed), 40 - head.Count()))
        row = rowFromScored("picks", "Picked for You Today", 2, picks, watched)
        if row <> invalid then rows.Push(row)
    end if

    ' --- Because you watched … ---
    for i = 0 to becauseOf.Count() - 1
        src = expandMetaLite(becauseOf[i])
        like = moreLikeThis(src, seen, 40, cinemeta, req.kitsu)
        pr = 5
        if i > 0 then pr = 9
        row = rowFromScored("because-" + src.id, "Because you watched " + src.name, pr, like, watched)
        if row <> invalid then rows.Push(row)
    end for
    if savedSrc <> invalid
        src = expandMetaLite(savedSrc)
        ex = {}
        for each k in seen
            ex[k] = true
        end for
        for each e in myList
            ex[e.i] = true
        end for
        like = moreLikeThis(src, ex, 40, cinemeta, req.kitsu)
        row = rowFromScored("mylist-" + src.id, "Because you saved " + src.name, 10, like, watched)
        if row <> invalid then rows.Push(row)
    end if

    ' --- Today's Spotlight ---
    if spotlight <> ""
        sUrls = poolUrls(base, "movie", spotlight)
        sUrls.Append(poolUrls(base, "series", spotlight))
        items = []
        for each c in cachedPages(sUrls)
            if not seen.DoesExist(c.id)
                r = toNum(c.imdbRating)
                if r <= 0 then r = 6
                jitter = newRng(seed + hashStr(c.id)).nextFloat()
                items.Push({ meta: c, score: 0.5 * (r / 10) + 0.3 * affinityOf(profile, c.genres) + 0.2 * jitter })
            end if
        end for
        row = rowFromScored("spotlight", "Today's Spotlight: " + spotlight, 6, arrTake(scoredSort(items), 40), watched)
        if row <> invalid then rows.Push(row)
    end if

    ' --- Hidden Gems ---
    if gemGenre <> ""
        popular = {}
        for each c in cachedPages(pagesUrls(base, "movie", "top", [["genre", gemGenre]], 1))
            popular[c.id] = true
        end for
        gems = []
        for each c in cachedPages(pagesUrls(base, "movie", "imdbRating", [["genre", gemGenre]], 2, 48))
            if not popular.DoesExist(c.id) and not seen.DoesExist(c.id) and toNum(c.imdbRating) >= 7.2 then gems.Push(c)
        end for
        row = rowFromPlain("gems", "Hidden Gems: " + gemGenre, 12, arrTake(shuffled(gems, seed + 2), 30), profile, watched)
        if row <> invalid then rows.Push(row)
    end if

    ' --- Best of {year} ---
    if bestYear > 0
        best = []
        for each c in cachedPages(pagesUrls(base, "movie", "year", [["genre", tostr(bestYear)]], 2))
            if toNum(c.imdbRating) >= 6.3
                c.rank = toNum(c.imdbRating)
                best.Push(c)
            end if
        end for
        best.SortBy("rank", "r")
        row = rowFromPlain("year", "Best of " + tostr(bestYear), 14, arrTake(best, 30), profile, watched)
        if row <> invalid then rows.Push(row)
    end if

    ' --- New This Month ---
    cutoff = dateString(45)
    today = dateString(0)
    fresh = []
    fUrls = pagesUrls(base, "movie", "year", [["genre", tostr(thisYear)]], 2)
    fUrls.Append(pagesUrls(base, "series", "year", [["genre", tostr(thisYear)]], 2))
    for each c in cachedPages(fUrls)
        if c.released <> "" and c.released >= cutoff and c.released <= today then fresh.Push(c)
    end for
    fresh.SortBy("released", "r")
    row = rowFromPlain("fresh", "New This Month", 8, arrTake(fresh, 40), profile, watched)
    if row <> invalid then rows.Push(row)

    ' --- New Episodes for You ---
    if lastVideosUrl <> ""
        recentCutoff = dateString(21)
        watchedVideos = {}
        for each e in history
            if tostr(e.v) <> "" then watchedVideos[e.v] = true
        end for
        items = []
        subs = {}
        for each c in cachedPages([lastVideosUrl])
            latest = invalid
            if isArr(c.videos)
                for each v in c.videos
                    if v.released <> "" and v.released <= today
                        if latest = invalid or v.released > latest.released then latest = v
                    end if
                end for
            end if
            if latest <> invalid and latest.released >= recentCutoff and not watchedVideos.DoesExist(latest.id)
                if latest.thumbnail <> "" then c.background = latest.thumbnail
                c.Delete("videos")
                items.Push(c)
                subs[c.id] = "New · S" + tostr(latest.season) + " E" + tostr(latest.episode)
            end if
        end for
        row = buildRow("new-episodes", "New Episodes for You", 1, items, invalid, watched, "landscape", subs)
        if row <> invalid then rows.Push(row)
    end if
    return rows
end function

' History / My List entries → meta-like objects for similarity.
function expandMetaLite(e as Object) as Object
    g = []
    if tostr(e.g) <> "" then g = e.g.Split("|")
    return { id: e.i, type: e.t, name: tostr(e.n), genres: g, imdbRating: tostr(e.r), releaseInfo: "", cast: [], director: [] }
end function

sub handleRequest(req as Dynamic)
    if not isAA(req) or req.action = invalid then return
    if req.action = "daily"
        m.top.response = { reqId: req.reqId, action: "daily", rows: dailyRows(req) }
    else if req.action = "similar"
        m.top.response = { reqId: req.reqId, action: "similar", rows: similarRows(req) }
    end if
end sub
