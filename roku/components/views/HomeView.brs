' Port of HomeScreen.kt + HomeViewModel.kt.

sub init()
    m.hero = m.top.findNode("hero")
    m.rows = m.top.findNode("rows")
    m.status = m.top.findNode("status")
    m.notice = m.top.findNode("notice")
    m.noticeText = m.top.findNode("noticeText")
    m.noticeButton = m.top.findNode("noticeButton")
    m.heroTimer = m.top.findNode("heroTimer")
    t = m.global.theme
    m.noticeText.color = t.cached
    setupRowList(m.rows, 1179)
    m.rows.observeField("rowItemFocused", "onItemFocused")
    m.rows.observeField("rowItemSelected", "onItemSelected")
    m.heroTimer.observeField("fire", "onHeroTimer")
    m.noticeButton.observeField("pressed", "onNoticePressed")
    m.top.observeField("focusedChild", "onFocusChange")

    m.catalogRows = []
    m.dailyRows = []
    m.loadedFor = ""
    m.dirty = true
    m.savedKey = ""
    m.rowsTop = 288
    m.status.text = "Loading catalogs…"

    m.global.observeField("addons", "onAddons")
    m.global.observeField("userVersion", "onUserData")
    m.dailyReq = ""
    if m.global.addonsReady then onAddons()
end sub

sub onActive()
    if m.top.active and m.dirty then rebuild()
end sub

sub onFocusChange()
    if m.top.hasFocus()
        if m.rows.content <> invalid and m.rows.content.getChildCount() > 0
            m.rows.setFocus(true)
        else if m.notice.visible
            m.noticeButton.setFocus(true)
        end if
    end if
end sub

' ---- data ----

sub onAddons()
    addons = m.global.addons
    key = ""
    for each a in addons
        key = key + a.transportUrl + "|"
    end for
    hasStreams = false
    for each a in addons
        if addonHasResource(a, "stream") then hasStreams = true
    end for
    m.notice.visible = not hasStreams and m.global.addonsReady
    if key = m.loadedFor then return
    m.loadedFor = key
    loadCatalogs(addons)
    loadDaily()
end sub

sub onUserData()
    m.dirty = true
    loadDaily()
    if m.top.active then rebuild()
end sub

function catalogSpecs(addons as Object) as Object
    specs = []
    cin = findAddon(addons, CINEMETA_ID())
    if cin <> invalid
        b = cin.baseUrl
        add = function(specs as Object, b as String, c as Dynamic, title as String, pr as Integer, extra as Object)
            if c <> invalid then specs.Push({ key: "cin/" + c.type + "/" + c.id + "/" + title, title: title, priority: pr, base: b, type: c.type, id: c.id, extra: extra })
        end function
        mt = findCatalog(cin, "movie", "top")
        st = findCatalog(cin, "series", "top")
        add(specs, b, mt, "Popular Movies", 3, [])
        add(specs, b, st, "Popular Series", 4, [])
        my = findCatalog(cin, "movie", "year")
        yrs = catalogOptions(my, "genre")
        if yrs.Count() > 0 then add(specs, b, my, "New Movies · " + yrs[0], 11, [["genre", yrs[0]]])
        add(specs, b, findCatalog(cin, "movie", "imdbRating"), "Top Rated Movies", 13, [])
        sy = findCatalog(cin, "series", "year")
        yrs = catalogOptions(sy, "genre")
        if yrs.Count() > 0 then add(specs, b, sy, "New Series · " + yrs[0], 15, [["genre", yrs[0]]])
        add(specs, b, findCatalog(cin, "series", "imdbRating"), "Top Rated Series", 16, [])
        i = 0
        for each g in ["Action", "Comedy", "Sci-Fi", "Thriller", "Animation", "Horror", "Romance", "Documentary"]
            if mt <> invalid and arrHas(catalogOptions(mt, "genre"), g) then add(specs, b, mt, g + " Movies", 20 + i, [["genre", g]])
            i = i + 1
        end for
        i = 0
        for each g in ["Drama", "Crime", "Comedy"]
            if st <> invalid and arrHas(catalogOptions(st, "genre"), g) then add(specs, b, st, g + " Series", 30 + i, [["genre", g]])
            i = i + 1
        end for
    end if
    p = 40
    for each a in addons
        if cin = invalid or a.id <> cin.id
            n = 0
            for each c in a.catalogs
                if n < 4 and (c.type = "movie" or c.type = "series") and not catalogNeedsExtra(c)
                    name = c.name
                    if name = "" then name = c.id
                    specs.Push({ key: a.id + "/" + c.type + "/" + c.id, title: name + " · " + a.name, priority: p, base: a.baseUrl, type: c.type, id: c.id, extra: [] })
                    p = p + 1
                    n = n + 1
                end if
            end for
        end if
    end for
    return specs
end function

sub loadCatalogs(addons as Object)
    specs = catalogSpecs(addons)
    if specs.Count() = 0
        m.catalogRows = []
        m.status.text = "Couldn't load any catalogs. Check your connection and installed addons."
        rebuild()
        return
    end if
    m.status.text = "Loading catalogs…"
    m.catalogTask = CreateObject("roSGNode", "CatalogTask")
    m.catalogTask.requests = specs
    m.catalogTask.watched = m.global.watched
    m.catalogTask.observeField("rows", "onCatalogRows")
    m.catalogTask.control = "run"
end sub

sub onCatalogRows(e as Object)
    m.catalogRows = e.getData()
    if m.catalogRows.Count() = 0
        m.status.text = "Couldn't load any catalogs. Check your connection and installed addons."
    else
        m.status.text = ""
    end if
    m.dirty = true
    rebuild()
end sub

sub loadDaily()
    addons = m.global.addons
    cin = findAddon(addons, CINEMETA_ID())
    if cin = invalid then return
    m.dailyReq = "daily-" + tostr(nowSec()) + "-" + tostr(Rnd(100000))
    task = m.top.getScene().callFunc("recommend", {
        action: "daily"
        reqId: m.dailyReq
        cinemeta: cin
        kitsu: findAddon(addons, KITSU_ID())
        profile: tasteProfile()
        history: m.global.history
        myList: m.global.myList
        watched: m.global.watched
    })
    if m.recTask = invalid
        m.recTask = task
        m.recTask.observeField("response", "onRecResponse")
    end if
end sub

sub onRecResponse(e as Object)
    r = e.getData()
    if r = invalid or r.reqId <> m.dailyReq then return
    m.dailyRows = r.rows
    m.dirty = true
    if m.top.active then rebuild()
end sub

' Local rows: Continue Watching, My List, Recently Watched.
function localRows() as Object
    rows = []
    watched = m.global.watched
    history = m.global.history
    cont = CreateObject("roSGNode", "ContentNode")
    seen = {}
    for each e in history
        p = 0
        if toNum(e.d) > 0 then p = toNum(e.ps) / toNum(e.d)
        if ((p >= 0.01 and p <= 0.95) or toNum(e.d) = 0) and not watched.DoesExist(e.i) and not seen.DoesExist(e.i)
            seen[e.i] = true
            n = makeMetaNode(cont, expandMeta(e), "landscape")
            n.progress = p
            n.subtitle = tostr(e.l)
        end if
    end for
    if cont.getChildCount() > 0 then rows.Push({ key: "continue", title: "Continue Watching", priority: 0, content: cont })
    if m.global.myList.Count() > 0
        ml = CreateObject("roSGNode", "ContentNode")
        for each e in m.global.myList
            n = makeMetaNode(ml, expandMeta(e))
            n.watched = watched.DoesExist(e.i)
        end for
        rows.Push({ key: "mylist", title: "My List", priority: 7, content: ml })
    end if
    movies = CreateObject("roSGNode", "ContentNode")
    series = CreateObject("roSGNode", "ContentNode")
    for each e in history
        if e.t = "movie" and movies.getChildCount() < 30
            n = makeMetaNode(movies, expandMeta(e))
            n.watched = watched.DoesExist(e.i)
        else if e.t = "series" and series.getChildCount() < 30
            n = makeMetaNode(series, expandMeta(e), "landscape")
            n.subtitle = tostr(e.l)
        end if
    end for
    if movies.getChildCount() > 0 then rows.Push({ key: "recent-movies", title: "Recently Watched Movies", priority: 6, content: movies })
    if series.getChildCount() > 0 then rows.Push({ key: "recent-series", title: "Recently Watched Series", priority: 6, content: series })
    return rows
end function

sub rebuild()
    m.dirty = false
    all = localRows()
    all.Append(m.dailyRows)
    all.Append(m.catalogRows)
    ' stable sort by priority
    for i = 0 to all.Count() - 1
        all[i].order = all[i].priority * 1000 + i
    end for
    all.SortBy("order")

    ' remember focus by row key + item id
    oldKey = m.savedKey
    watched = m.global.watched
    root = CreateObject("roSGNode", "ContentNode")
    if m.rows.content <> invalid then m.rows.content.removeChildrenIndex(m.rows.content.getChildCount(), 0)
    m.rowKeys = []
    focusRow = 0
    focusItem = 0
    for each r in all
        c = r.content
        c.title = r.title
        if c.getParent() <> invalid then c.getParent().removeChild(c)
        root.appendChild(c)
        m.rowKeys.Push(r.key)
        if oldKey <> ""
            parts = oldKey.Split("|")
            if parts[0] = r.key
                focusRow = m.rowKeys.Count() - 1
                for j = 0 to c.getChildCount() - 1
                    if c.getChild(j).meta.id = parts[1] then focusItem = j
                end for
            end if
        end if
    end for
    ' refresh watched badges on catalog cards
    for i = 0 to root.getChildCount() - 1
        row = root.getChild(i)
        for j = 0 to row.getChildCount() - 1
            it = row.getChild(j)
            w = watched.DoesExist(it.meta.id)
            if it.watched <> w then it.watched = w
        end for
    end for
    m.profile = tasteProfile()
    hadFocus = m.rows.hasFocus()
    if m.notice.visible
        m.rowsTop = 336
    else
        m.rowsTop = 288
    end if
    m.rows.translation = [0, m.rowsTop]
    setRows(m.rows, root)
    if root.getChildCount() > 0
        m.status.text = ""
        if not m.beaconSent = true
            m.top.getScene().signalBeacon("AppLaunchComplete")
            m.beaconSent = true
        end if
        m.rows.jumpToRowItem = [focusRow, focusItem]
        if m.hero.meta = invalid or m.hero.meta.id = invalid then showHero(focusedMeta(m.rows))
        if m.top.active and (hadFocus or m.top.hasFocus()) then m.rows.setFocus(true)
    end if
end sub

' ---- focus / hero ----

sub onItemFocused()
    f = m.rows.rowItemFocused
    if f = invalid or m.rowKeys = invalid or f.Count() < 2 or f[0] < 0 then return
    meta = focusedMeta(m.rows)
    if meta = invalid then return
    m.savedKey = m.rowKeys[f[0]] + "|" + meta.id
    m.pendingHero = meta
    m.heroTimer.control = "stop"
    m.heroTimer.control = "start"
end sub

sub onHeroTimer()
    if m.pendingHero <> invalid then showHero(m.pendingHero)
end sub

sub showHero(meta as Dynamic)
    if meta = invalid then return
    if m.profile = invalid then m.profile = tasteProfile()
    m.hero.match = matchPercent(meta, m.profile)
    m.hero.meta = meta
end sub

sub onItemSelected()
    meta = focusedMeta(m.rows)
    if meta <> invalid then m.top.navigateTo = { to: "details", meta: meta }
end sub

sub onNoticePressed()
    m.top.navigateTo = { to: "addons" }
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "options" and m.rows.hasFocus()
        meta = focusedMeta(m.rows)
        if meta <> invalid then m.top.getScene().callFunc("cardMenu", meta)
        return true
    end if
    if key = "up" and m.rows.hasFocus() and m.notice.visible
        m.noticeButton.setFocus(true)
        return true
    end if
    if key = "down" and m.noticeButton.hasFocus() and m.rows.content <> invalid and m.rows.content.getChildCount() > 0
        m.rows.setFocus(true)
        return true
    end if
    return false
end function
