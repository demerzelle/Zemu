' Port of BrowseScreen.kt + BrowseViewModel.kt.

sub init()
    m.hero = m.top.findNode("hero")
    m.filters = m.top.findNode("filters")
    m.status = m.top.findNode("status")
    m.grid = m.top.findNode("grid")
    m.heroTimer = m.top.findNode("heroTimer")
    m.hero.backdropHeight = 446
    m.grid.observeField("itemFocused", "onFocused")
    m.grid.observeField("itemSelected", "onSelected")
    m.heroTimer.observeField("fire", "onHeroTimer")
    m.top.observeField("focusedChild", "onFocusChange")
    m.task = CreateObject("roSGNode", "BrowseTask")
    m.task.observeField("result", "onResult")
    m.task.control = "run"
    m.f = { catalog: "", section: "series", genre: "", minRating: 0, decade: 0, sort: "DEFAULT" }
    m.catalogs = []
    m.genres = []
    m.reqId = 0
    m.loading = false
    m.ended = false
    m.count = 0
    m.profile = tasteProfile()
end sub

sub onDispose()
    m.task.control = "stop"
end sub

sub onActive()
end sub

sub onFocusChange()
    if m.top.hasFocus()
        if m.grid.content <> invalid and m.grid.content.getChildCount() > 0 and not m.filtersFocused = true then m.grid.setFocus(true) else m.filters.setFocus(true)
    end if
end sub

sub setup()
    t = m.top.browseType
    m.isAnime = t = "anime"
    m.status.text = "Loading…"
    if m.isAnime
        if findAddon(m.global.addons, KITSU_ID()) <> invalid
            setupAnime(findAddon(m.global.addons, KITSU_ID()))
        else
            m.status.text = "Installing the Anime Kitsu addon…"
            at = CreateObject("roSGNode", "AddonTask")
            at.request = { action: "ensureKitsu", current: m.global.addons, profileId: m.global.profileId }
            at.observeField("result", "onKitsu")
            at.control = "run"
            m.kitsuTask = at
        end if
    else
        setupCatalogs()
    end if
end sub

sub onKitsu(e as Object)
    r = e.getData()
    if r.ok and r.addons <> invalid
        m.top.getScene().callFunc("setAddons", { addons: r.addons })
        setupAnime(findAddon(r.addons, KITSU_ID()))
    else
        m.status.text = "Couldn't install the Anime Kitsu addon. Check your connection, or install it from Addons."
    end if
end sub

sub setupCatalogs()
    t = m.top.browseType
    addons = m.global.addons
    preferred = m.global.settings.metaProvider
    pick = invalid
    for each a in addons
        if a.id = preferred and usable(a, t) then pick = a
    end for
    if pick = invalid then pick = findAddon(addons, CINEMETA_ID())
    if pick = invalid
        for each a in addons
            if pick = invalid and usable(a, t) then pick = a
        end for
    end if
    if pick = invalid
        m.status.text = "No catalog provider is installed. Add Cinemeta or another metadata addon in Addons."
        buildFilters()
        return
    end if
    m.addon = pick
    m.catalogs = []
    if pick.id = CINEMETA_ID()
        top = findCatalog(pick, t, "top")
        if top <> invalid then m.catalogs.Push({ id: "top", label: "Popular", paged: true, genres: true })
        if findCatalog(pick, t, "imdbRating") <> invalid then m.catalogs.Push({ id: "imdbRating", label: "Top Rated", paged: true, genres: true })
        m.genres = catalogOptions(top, "genre")
    else
        for each c in pick.catalogs
            if c.type = t and not catalogNeedsExtra(c)
                label = c.name
                if label = "" then label = c.id
                m.catalogs.Push({ id: c.id, label: label, paged: catalogSupportsExtra(c, "skip"), genres: catalogSupportsExtra(c, "genre") })
                if m.genres.Count() = 0 and catalogSupportsExtra(c, "genre") then m.genres = catalogOptions(c, "genre")
            end if
        end for
    end if
    if m.catalogs.Count() > 0 then m.f.catalog = m.catalogs[0].id
    m.f.section = ""
    buildFilters()
    reload()
end sub

function usable(a as Object, t as String) as Boolean
    for each c in a.catalogs
        if c.type = t and not catalogNeedsExtra(c) then return true
    end for
    return false
end function

sub setupAnime(kitsu as Dynamic)
    if kitsu = invalid then return
    m.addon = kitsu
    labels = { "kitsu-anime-trending": "Trending", "kitsu-anime-airing": "Airing Now", "kitsu-anime-popular": "Most Popular", "kitsu-anime-rating": "Top Rated" }
    m.catalogs = []
    for each c in kitsu.catalogs
        if not catalogNeedsExtra(c)
            label = labels.Lookup(c.id)
            if label = invalid then label = c.name.Replace("Kitsu ", "")
            if label = "" then label = c.id
            m.catalogs.Push({ id: c.id, label: label, paged: catalogSupportsExtra(c, "skip"), genres: catalogSupportsExtra(c, "genre"), type: c.type })
            if m.genres.Count() = 0 and catalogSupportsExtra(c, "genre") then m.genres = catalogOptions(c, "genre")
        end if
    end for
    m.f.section = "series"
    m.f.catalog = defaultAnimeCatalog()
    buildFilters()
    reload()
end sub

' Trending isn't paged and holds few movies, so movies start on Most Popular.
function defaultAnimeCatalog() as String
    if m.catalogs.Count() = 0 then return ""
    if m.f.section = "movie"
        for each c in m.catalogs
            if Instr(1, c.id, "popular") > 0 then return c.id
        end for
    end if
    return m.catalogs[0].id
end function

function currentCatalog() as Dynamic
    for each c in m.catalogs
        if c.id = m.f.catalog then return c
    end for
    return invalid
end function

sub reload()
    cat = currentCatalog()
    if cat = invalid or m.addon = invalid then return
    m.reqId = m.reqId + 1
    m.loading = true
    m.status.text = "Loading…"
    m.grid.visible = false
    genre = m.f.genre
    if not cat.genres then genre = ""
    catType = m.top.browseType
    if m.isAnime
        catType = "anime"
        if cat.type <> invalid and cat.type <> "" then catType = cat.type
    end if
    m.task.request = {
        action: "reset", reqId: m.reqId, filters: m.f, profile: m.profile, watched: m.global.watched
        source: { base: m.addon.baseUrl, catalogType: catType, id: cat.id, genre: genre, paged: cat.paged, anime: m.isAnime }
    }
    updateCountLabel()
end sub

sub refilter()
    m.reqId = m.reqId + 1
    m.task.request = { action: "filter", reqId: m.reqId, filters: m.f, profile: m.profile, watched: m.global.watched }
end sub

sub loadMore()
    if m.loading or m.ended then return
    m.loading = true
    m.reqId = m.reqId + 1
    m.task.request = { action: "more", reqId: m.reqId, filters: m.f, profile: m.profile, watched: m.global.watched }
    updateCountLabel()
end sub

sub onResult()
    r = m.task.result
    if r = invalid or r.reqId <> m.reqId then return
    m.loading = false
    m.ended = r.ended
    m.count = r.count
    hadFocus = m.grid.hasFocus()
    idx = m.grid.itemFocused
    m.grid.content = r.content
    n = r.count
    m.grid.visible = n > 0
    if n > 0
        m.status.text = ""
        if idx > 0 and idx < n then m.grid.jumpToItem = idx
        if m.hero.meta = invalid or m.hero.meta.id = invalid then showHero(r.content.getChild(0).meta)
        if hadFocus or (m.top.hasFocus() and not m.filters.isInFocusChain()) then m.grid.setFocus(true)
    else if r.error <> invalid
        m.status.text = r.error
    else if m.ended
        m.status.text = "Nothing matches these filters."
    end if
    updateCountLabel()
    ' Anime movies are sparse in mixed catalogs, so keep paging until the grid has enough.
    if not m.ended and n < 24 and r.fetched > 0 then loadMore()
end sub

' ---- filter chips ----

function ratingLabel(r as Float) as String
    if r <= 0 then return "Any"
    if r = Int(r) then return tostr(Int(r)) + "+"
    return fmt1(r) + "+"
end function

function decadeLabel(d as Integer) as String
    if d = 0 then return "Any"
    if d = -1 then return "Before 1970"
    return tostr(d) + "s"
end function

function sortLabel(s as String) as String
    labels = { DEFAULT: "Default", RATING: "Highest rated", NEWEST: "Newest", OLDEST: "Oldest", MATCH: "Best match for you" }
    return labels[s]
end function

sub buildFilters()
    idx = m.filters.focusIndex
    m.filters.callFunc("clearItems")
    title = CreateObject("roSGNode", "Label")
    t = m.top.browseType
    title.text = "Movies"
    if t = "series" then title.text = "Series"
    if t = "anime" then title.text = "Anime"
    f = CreateObject("roSGNode", "Font")
    f.uri = "font:BoldSystemFontFile"
    f.size = 29
    title.font = f
    title.height = 44
    title.vertAlign = "center"
    m.filters.callFunc("addItem", title)
    if m.isAnime
        addChip("Anime Series", m.f.section = "series", { act: "section", v: "series" })
        addChip("Anime Movies", m.f.section = "movie", { act: "section", v: "movie" })
    end if
    cat = currentCatalog()
    if m.catalogs.Count() <= 2
        for each c in m.catalogs
            addChip(c.label, c.id = m.f.catalog, { act: "catalog", v: c.id })
        end for
    else if cat <> invalid
        addChip(cat.label, false, { act: "catalogs" })
    end if
    if cat <> invalid and cat.genres and m.genres.Count() > 0
        g = m.f.genre
        if g = "" then g = "All"
        addChip("Genre: " + g, m.f.genre <> "", { act: "genre" })
    end if
    addChip("Rating: " + ratingLabel(m.f.minRating), m.f.minRating > 0, { act: "rating" })
    addChip("Decade: " + decadeLabel(m.f.decade), m.f.decade <> 0, { act: "decade" })
    addChip("Sort: " + sortLabel(m.f.sort), m.f.sort <> "DEFAULT", { act: "sort" })
    m.countLabel = CreateObject("roSGNode", "Label")
    cf = CreateObject("roSGNode", "Font")
    cf.uri = "font:SystemFontFile"
    cf.size = 17
    m.countLabel.font = cf
    m.countLabel.color = m.global.theme.textMuted
    m.countLabel.height = 44
    m.countLabel.vertAlign = "center"
    m.filters.callFunc("addItem", m.countLabel)
    updateCountLabel()
    if idx < 1 then idx = 1
    m.filters.focusIndex = idx
end sub

sub updateCountLabel()
    if m.countLabel = invalid then return
    if m.loading then m.countLabel.text = "loading…" else m.countLabel.text = tostr(m.count) + " titles"
    m.countLabel.width = m.countLabel.boundingRect().width + 4
    m.filters.relayout = true
end sub

sub addChip(text as String, on as Boolean, data as Object)
    b = CreateObject("roSGNode", "TvButton")
    b.variant = "chip"
    b.fontSize = 18
    b.text = text
    b.checked = on
    b.data = data
    b.observeField("pressed", "onChip")
    m.filters.callFunc("addItem", b)
end sub

sub onChip(e as Object)
    d = e.getRoSGNode().data
    m.pending = d.act
    if d.act = "section"
        m.f.section = d.v
        m.f.catalog = defaultAnimeCatalog()
        buildFilters()
        reload()
    else if d.act = "catalog"
        m.f.catalog = d.v
        buildFilters()
        reload()
    else if d.act = "catalogs"
        opts = []
        for each c in m.catalogs
            opts.Push({ id: c.id, label: c.label, checked: c.id = m.f.catalog })
        end for
        choose("Catalog", opts)
    else if d.act = "genre"
        opts = [{ id: "", label: "All genres", checked: m.f.genre = "" }]
        for each g in m.genres
            opts.Push({ id: g, label: g, checked: g = m.f.genre })
        end for
        choose("Genre", opts)
    else if d.act = "rating"
        opts = []
        for each r in [0, 6, 7, 7.5, 8]
            opts.Push({ id: tostr(r), label: ratingLabel(r), checked: r = m.f.minRating })
        end for
        choose("Minimum IMDb rating", opts)
    else if d.act = "decade"
        opts = []
        for each dd in [0, 2020, 2010, 2000, 1990, 1980, 1970, -1]
            opts.Push({ id: tostr(dd), label: decadeLabel(dd), checked: dd = m.f.decade })
        end for
        choose("Decade", opts)
    else if d.act = "sort"
        opts = []
        for each s in ["DEFAULT", "RATING", "NEWEST", "OLDEST", "MATCH"]
            opts.Push({ id: s, label: sortLabel(s), checked: s = m.f.sort })
        end for
        choose("Sort", opts)
    end if
end sub

sub choose(title as String, opts as Object)
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = title
    dlg.options = opts
    dlg.observeField("chosen", "onChosen")
    m.top.getScene().callFunc("pushDialog", dlg)
end sub

sub onChosen(e as Object)
    v = e.getData()
    a = m.pending
    if a = "catalogs"
        m.f.catalog = v
        reloadNeeded = true
    else if a = "genre"
        m.f.genre = v
        reloadNeeded = true
    else if a = "rating"
        m.f.minRating = Val(v)
        reloadNeeded = false
    else if a = "decade"
        m.f.decade = toInt(v)
        reloadNeeded = false
    else if a = "sort"
        m.f.sort = v
        reloadNeeded = false
    end if
    buildFilters()
    if reloadNeeded then reload() else refilter()
end sub

' ---- grid ----

sub onFocused()
    i = m.grid.itemFocused
    if m.grid.content = invalid or i < 0 then return
    c = m.grid.content.getChild(i)
    if c = invalid then return
    m.pendingHero = c.meta
    m.heroTimer.control = "stop"
    m.heroTimer.control = "start"
    ' load more two rows before the end
    if i >= m.grid.content.getChildCount() - 14 then loadMore()
end sub

sub onHeroTimer()
    if m.pendingHero <> invalid then showHero(m.pendingHero)
end sub

sub showHero(meta as Object)
    m.hero.match = matchPercent(meta, m.profile)
    m.hero.meta = meta
end sub

sub onSelected()
    c = m.grid.content.getChild(m.grid.itemSelected)
    if c <> invalid then m.top.navigateTo = { to: "details", meta: c.meta }
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "up" and m.grid.hasFocus()
        m.filtersFocused = true
        m.filters.setFocus(true)
        return true
    else if key = "down" and m.filters.isInFocusChain() and m.grid.visible
        m.filtersFocused = false
        m.grid.setFocus(true)
        return true
    else if key = "options" and m.grid.hasFocus()
        c = m.grid.content.getChild(m.grid.itemFocused)
        if c <> invalid then m.top.getScene().callFunc("cardMenu", c.meta)
        return true
    end if
    return false
end function
