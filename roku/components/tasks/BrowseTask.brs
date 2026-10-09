sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    port = CreateObject("roMessagePort")
    m.top.observeField("request", port)
    m.top.observeField("control", port)
    m.raw = []
    m.seen = {}
    m.pages = 0
    m.ended = false
    m.filters = {}
    handleRequest(m.top.request)
    while true
        msg = Wait(0, port)
        if Type(msg) = "roSGNodeEvent"
            if msg.getField() = "control"
                if LCase(tostr(msg.getData())) = "stop" then return
            else
                handleRequest(msg.getData())
            end if
        end if
    end while
end sub

sub loadPage()
    s = m.source
    if s = invalid
        m.ended = true
        return
    end if
    extra = []
    if s.genre <> invalid and s.genre <> "" then extra.Push(["genre", s.genre])
    ' Kitsu pages are addressed in steps of 50, Cinemeta by item count.
    skip = m.raw.Count()
    if s.anime then skip = m.pages * 50
    if skip > 0 then extra.Push(["skip", tostr(skip)])
    o = httpGetJson(resourceUrl(s.base, "catalog", s.catalogType, s.id, extra), 20000)
    fresh = 0
    if isAA(o) and isArr(o.metas)
        for each raw in o.metas
            if isAA(raw)
                id = tostr(raw.id)
                if id <> "" and not m.seen.DoesExist(id)
                    m.seen[id] = true
                    m.raw.Push(slimMeta(raw))
                    fresh = fresh + 1
                end if
            end if
        end for
    else
        m.error = "Couldn't load this catalog. Check your connection."
    end if
    m.pages = m.pages + 1
    if fresh = 0 or not s.paged or m.pages >= 8 then m.ended = true
end sub

sub emit(req as Object)
    f = m.filters
    profile = req.profile
    watched = req.watched
    if watched = invalid then watched = {}
    list = []
    for each x in m.raw
        ok = true
        if f.section <> invalid and f.section <> "" and x.type <> f.section then ok = false
        if ok and toNum(f.minRating) > 0 and toNum(x.imdbRating) < toNum(f.minRating) then ok = false
        if ok and f.decade <> invalid and f.decade <> 0
            y = metaYear(x.releaseInfo)
            if f.decade = -1
                ok = y > 0 and y < 1970
            else
                ok = y >= f.decade and y < f.decade + 10
            end if
        end if
        if ok
            x.sk = 0
            if f.sort = "RATING" then x.sk = toNum(x.imdbRating)
            if f.sort = "NEWEST" then x.sk = metaYear(x.releaseInfo)
            if f.sort = "OLDEST"
                y = metaYear(x.releaseInfo)
                if y = 0 then y = 99999
                x.sk = y
            end if
            if f.sort = "MATCH" and profile <> invalid then x.sk = matchOf(x, profile)
            list.Push(x)
        end if
    end for
    if f.sort = "RATING" or f.sort = "NEWEST" or f.sort = "MATCH"
        list.SortBy("sk", "r")
    else if f.sort = "OLDEST"
        list.SortBy("sk")
    end if
    content = CreateObject("roSGNode", "ContentNode")
    for each x in list
        n = content.createChild("MetaNode")
        x.Delete("sk")
        n.meta = x
        n.watched = watched.DoesExist(x.id)
    end for
    err = m.error
    m.error = invalid
    m.top.result = { reqId: req.reqId, content: content, count: list.Count(), fetched: m.raw.Count(), ended: m.ended, error: err }
end sub

function matchOf(meta as Object, profile as Object) as Integer
    r = toNum(meta.imdbRating)
    if r <= 0 then r = 6.5
    r = r / 10
    x = r
    if profile.weights.Count() > 0 and profile.max > 0 and meta.genres.Count() > 0
        top = arrTake(meta.genres, 3)
        sum = 0
        for each g in top
            sum = sum + toNum(profile.weights.Lookup(g))
        end for
        a = sum / (profile.max * top.Count())
        if a > 1 then a = 1
        if a < 0 then a = 0
        x = 0.55 * a + 0.45 * r
    end if
    return Int(50 + x * 49 + 0.5)
end function

sub handleRequest(req as Dynamic)
    if not isAA(req) or req.action = invalid then return
    if isAA(req.filters) then m.filters = req.filters
    if req.action = "reset"
        m.raw = []
        m.seen = {}
        m.pages = 0
        m.ended = false
        m.source = req.source
        loadPage()
    else if req.action = "more"
        if not m.ended then loadPage()
    end if
    emit(req)
end sub
