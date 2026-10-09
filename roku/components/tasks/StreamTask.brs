sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    port = CreateObject("roMessagePort")
    m.top.observeField("request", port)
    m.cache = {}
    m.subsCache = {}
    m.caps = detectCaps()
    m.all = []
    m.ext = []
    m.subs = []
    m.info = invalid
    m.top.observeField("control", port)
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

function opensubsBase() as String
    return "https://opensubtitles-v3.strem.io"
end function

' Free, no-setup subtitle addons for languages OpenSubtitles covers poorly.
function languageFallbacks() as Object
    return {
        es: ["https://stremio.fly.dev", "https://58196d6c26cf-stremio-tusubtitulo.baby-beamup.club"]
        he: ["https://4b139a4b7f94-wizdom-stremio-v2.baby-beamup.club", "https://4b139a4b7f94-ktuvit-stremio.baby-beamup.club"]
        pl: ["https://napisy24-stremio.top"]
    }
end function

sub load(req as Object)
    typ = req.type
    vid = req.videoId
    settings = req.settings
    key = typ + "/" + vid
    m.settings = settings
    cached = m.cache.Lookup(key)
    if not bool(req.force) and cached <> invalid and nowSec() - cached.at < 900
        m.all = cached.all
        m.info = cached.info
        m.ext = cached.ext
        m.subs = cached.subs
        emit(req)
        return
    end if

    addons = req.addons
    targets = addonsFor(addons, "stream", typ, vid)
    if targets.Count() = 0
        m.all = []
        m.ext = []
        m.subs = []
        m.info = { noStreamAddons: true, total: 0, hidden: 0, failed: [] }
        emit(req)
        return
    end if
    subAddons = addonsFor(addons, "subtitles", typ, vid)
    urls = []
    for each a in targets
        urls.Push(resourceUrl(a.baseUrl, "stream", typ, vid))
    end for
    subBases = []
    for each a in subAddons
        subBases.Push(a.baseUrl)
        urls.Push(resourceUrl(a.baseUrl, "subtitles", typ, vid))
    end for
    bodies = httpGetMany(urls, 20000)

    trust = bool(settings.trustDirectLinks)
    all = []
    seen = {}
    total = 0
    hidden = 0
    failed = []
    for i = 0 to targets.Count() - 1
        body = bodies[i]
        parsed = invalid
        if body <> "" then parsed = ParseJson(body)
        if not isAA(parsed) or not isArr(parsed.streams)
            failed.Push(targets[i].name)
        else
            for each s in parsed.streams
                if isAA(s)
                    p = parseStream(s, targets[i].name, trust)
                    total = total + 1
                    if not p.cached
                        hidden = hidden + 1
                    else if not seen.DoesExist(p.key)
                        seen[p.key] = true
                        all.Push(p)
                    end if
                end if
            end for
        end if
    end for

    subs = []
    for j = 0 to subAddons.Count() - 1
        collectSubs(bodies[targets.Count() + j], subs)
    end for
    preferred = settings.subtitleLanguages
    if preferred = invalid or preferred.Count() = 0 then preferred = ["en"]
    covered = false
    for each s in subs
        if arrHas(preferred, s.lang) then covered = true
    end for
    if not covered and startsWith(vid, "tt")
        fb = []
        if not arrHas(subBases, opensubsBase()) then fb.Push(opensubsBase())
        lf = languageFallbacks()
        for each l in preferred
            extra = lf.Lookup(l)
            if extra <> invalid
                for each b in extra
                    if not arrHas(subBases, b) and not arrHas(fb, b) then fb.Push(b)
                end for
            end if
        end for
        if fb.Count() > 0
            fbUrls = []
            for each b in fb
                fbUrls.Push(resourceUrl(b, "subtitles", typ, vid))
            end for
            for each body in httpGetMany(fbUrls, 12000)
                collectSubs(body, subs)
            end for
        end if
    end if
    ext = []
    for each s in subs
        if s.lang <> "" and not arrHas(ext, s.lang) then ext.Push(s.lang)
    end for

    m.all = all
    m.ext = ext
    m.subs = subs
    m.info = { noStreamAddons: false, total: total, hidden: hidden, failed: failed }
    ' Don't cache total failures so a retry actually retries.
    if failed.Count() < targets.Count() then m.cache[key] = { at: nowSec(), all: all, info: m.info, ext: ext, subs: subs }
    emit(req)
end sub

sub collectSubs(body as String, subs as Object)
    if body = "" then return
    parsed = ParseJson(body)
    if not isAA(parsed) or not isArr(parsed.subtitles) then return
    for each s in parsed.subtitles
        if isAA(s) and tostr(s.url) <> ""
            dup = false
            for each x in subs
                if x.url = s.url
                    dup = true
                    exit for
                end if
            end for
            if not dup then subs.Push({ url: s.url, lang: langNormalize(tostr(s.lang)), raw: tostr(s.lang), id: tostr(s.id) })
        end if
    end for
end sub

' Only a couple per preferred language: dead subtitle links slow the player down.
function pickSubtitles(all as Object, preferred as Object) as Object
    langs = preferred
    if langs = invalid or langs.Count() = 0 then langs = ["en"]
    picked = []
    for each l in langs
        n = 0
        for each s in all
            if s.lang = l and n < 2
                picked.Push(s)
                n = n + 1
            end if
        end for
    end for
    if picked.Count() > 0 then return arrTake(picked, 8)
    order = ["en"]
    for each s in all
        if not arrHas(order, s.lang) then order.Push(s.lang)
    end for
    for each l in order
        if picked.Count() >= 4 then exit for
        for each s in all
            if s.lang = l
                picked.Push(s)
                exit for
            end if
        end for
    end for
    return picked
end function

function playable(s as Object) as Object
    label = s.resLabel
    if s.size > 0 then label = label + " · " + formatSize(s.size)
    label = label + " · " + s.addon
    return { url: s.url, headers: s.headers, bingeGroup: s.bingeGroup, label: label, title: s.title, key: s.key, res: s.res }
end function

sub emit(req as Object)
    state = req.filter
    if not isAA(state) then state = defaultFilterState()
    if not isAA(state.selected) then state.selected = {}
    settings = m.settings
    if isAA(req.settings) then settings = req.settings
    ranked = applyFilters(m.all, state, m.caps, settings, m.ext)
    facetMap = computeFacets(m.all, state, m.caps, settings, m.ext)

    content = CreateObject("roSGNode", "ContentNode")
    candidates = []
    for each r in ranked
        s = r.s
        n = content.createChild("StreamNode")
        n.res = s.resLabel
        n.hdr = hdrLabelOf(s)
        if r.recommended
            n.badge = "best"
        else if not r.friendly
            n.badge = "warn"
        end if
        n.name = s.title
        specs = []
        if s.source <> "Unknown" then specs.Push(s.source)
        if s.codec <> "Unknown"
            if s.tenBit then specs.Push(s.codec + " 10-bit") else specs.Push(s.codec)
        end if
        if s.audio.Count() > 0
            a = joinArr(s.audio, " ")
            if s.channels <> "" then a = a + " " + s.channels
            specs.Push(a)
        end if
        if s.group <> "" then specs.Push(s.group)
        n.specs = joinArr(specs, "  ·  ")
        al = langListLabel(s.aLangs, s.multiAudio)
        if al = "" then al = "Original audio"
        n.audioLangs = al
        sl = langListLabel(s.sLangs, s.multiSubs)
        if sl = "" and m.ext.Count() > 0 then sl = "External only"
        n.subLangs = sl
        if s.size > 0 then n.size = formatSize(s.size) else n.size = "—"
        if s.service <> "" then n.service = s.service else n.service = "Direct"
        addonLine = s.addon
        if s.seeders >= 0 then addonLine = addonLine + "  ·  " + tostr(s.seeders) + " seeds"
        n.addon = addonLine
        p = playable(s)
        n.stream = p
        if candidates.Count() < 5 then candidates.Push(p)
    end for

    best = invalid
    bestSummaryText = ""
    if ranked.Count() > 0
        b = ranked[0]
        for each r in ranked
            if r.recommended then b = r
        end for
        best = playable(b.s)
        bestSummaryText = bestSummary(b.s)
    end if
    facetOut = {}
    for each k in facetMap
        facetOut[k] = facetMap[k]
    end for
    m.top.result = {
        reqId: req.reqId
        videoId: req.videoId
        loading: false
        noStreamAddons: m.info.noStreamAddons
        total: m.info.total
        cachedCount: m.all.Count()
        hidden: m.info.hidden
        failed: m.info.failed
        shown: ranked.Count()
        content: content
        facets: facetOut
        extLangs: m.ext
        subs: pickSubtitles(m.subs, settings.subtitleLanguages)
        best: best
        bestSummary: bestSummaryText
        candidates: candidates
        filter: state
    }
end sub

sub handleRequest(req as Dynamic)
    if not isAA(req) or req.action = invalid then return
    if req.action = "load"
        load(req)
    else if req.action = "filter" and m.info <> invalid
        emit(req)
    end if
end sub
