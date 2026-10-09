' Port of DetailsScreen.kt + DetailsViewModel.kt.

sub init()
    m.hero = m.top.findNode("hero")
    m.page = m.top.findNode("page")
    m.header = m.top.findNode("header")
    m.logo = m.top.findNode("logo")
    m.titleText = m.top.findNode("titleText")
    m.metaLine = m.top.findNode("metaLine")
    m.genres = m.top.findNode("genres")
    m.episodeLabel = m.top.findNode("episodeLabel")
    m.episodeSyn = m.top.findNode("episodeSyn")
    m.desc = m.top.findNode("desc")
    m.people = m.top.findNode("people")
    m.buttons = m.top.findNode("buttons")
    m.bestLine = m.top.findNode("bestLine")
    m.episodesSection = m.top.findNode("episodesSection")
    m.seasons = m.top.findNode("seasons")
    m.episodes = m.top.findNode("episodes")
    m.epSummaryTitle = m.top.findNode("epSummaryTitle")
    m.epSummary = m.top.findNode("epSummary")
    m.streamsSection = m.top.findNode("streamsSection")
    m.streamsSummary = m.top.findNode("streamsSummary")
    m.filterBar = m.top.findNode("filterBar")
    m.extSubs = m.top.findNode("extSubs")
    m.streamsHint = m.top.findNode("streamsHint")
    m.hintButton = m.top.findNode("hintButton")
    m.streamList = m.top.findNode("streamList")
    m.similar = m.top.findNode("similar")
    m.loading = m.top.findNode("loading")
    m.scrollAnim = m.top.findNode("scrollAnim")
    m.scrollInterp = m.top.findNode("scrollInterp")
    m.page.visible = false
    m.scrollY = 0

    setupRowList(m.similar, 1280)
    m.similar.observeField("rowItemSelected", "onSimilarSelected")
    m.episodes.observeField("rowItemSelected", "onEpisodeSelected")
    m.episodes.observeField("rowItemFocused", "onEpisodeFocused")
    m.episodes.observeField("focusedChild", "onEpisodesFocus")
    m.streamList.observeField("itemSelected", "onStreamSelected")
    m.hintButton.observeField("pressed", "onHintPressed")
    m.logo.observeField("loadStatus", "onLogo")
    m.top.observeField("focusedChild", "onFocusChange")
    m.global.observeField("userVersion", "onUserData")

    m.streamTask = CreateObject("roSGNode", "StreamTask")
    m.streamTask.observeField("result", "onStreams")
    m.streamTask.control = "run"
    m.reqId = 0
    m.streams = invalid
    m.streamsLoading = false
    if m.global.streamFilter = invalid then m.global.addFields({ streamFilter: defaultFilterState() })
end sub

sub onDispose()
    if m.streamTask <> invalid then m.streamTask.control = "stop"
    if m.metaTask <> invalid then m.metaTask.control = "stop"
end sub

sub onActive()
    if m.top.active
        ' coming back from the player: progress/watched changed
        if m.full <> invalid then refreshButtons()
    end if
end sub

sub onFocusChange()
    if m.top.hasFocus()
        if m.lastFocus <> invalid then m.lastFocus.setFocus(true) else if m.page.visible then m.buttons.setFocus(true)
    end if
end sub

' ---- meta ----

sub onMetaParam()
    meta = m.top.meta
    if meta = invalid then return
    if meta.background <> invalid and meta.background <> "" then m.hero.meta = meta
    m.metaTask = CreateObject("roSGNode", "MetaTask")
    m.metaTask.type = meta.type
    m.metaTask.metaId = meta.id
    m.metaTask.addons = m.global.addons
    m.metaTask.preferred = m.global.settings.metaProvider
    m.metaTask.observeField("meta", "onFullMeta")
    m.metaTask.observeField("failed", "onMetaFailed")
    m.metaTask.control = "run"
end sub

sub onMetaFailed()
    m.loading.text = "Couldn't load this title. The metadata addon didn't respond."
end sub

sub onFullMeta()
    full = m.metaTask.meta
    if full = invalid then return
    ' Cinemeta metas can come back without a type for anime ids
    if full.type = "" then full.type = m.top.meta.type
    m.full = full
    m.isSeries = full.type = "series" and full.videos.Count() > 0
    m.hero.meta = full
    m.loading.visible = false
    m.page.visible = true
    m.profile = tasteProfile()
    renderHeader()
    buildButtons()
    if m.isSeries
        buildSeasons()
        last = historyEntry(full.id)
        video = invalid
        if last <> invalid
            for each v in full.videos
                if v.id = last.v then video = v
            end for
        end if
        if video = invalid
            for each v in full.videos
                if v.season > 0 and (video = invalid or v.season < video.season or (v.season = video.season and v.episode < video.episode)) then video = v
            end for
        end if
        if video = invalid then video = full.videos[0]
        selectEpisode(video, false)
    else
        loadStreams(full.id, false)
    end if
    layoutPage()
    m.buttons.setFocus(true)
    m.lastFocus = m.buttons
    if m.top.section = "episodes" and m.isSeries then focusSection("episodes")

    seen = {}
    for each e in m.global.history
        seen[e.i] = true
    end for
    m.recReq = "similar-" + full.id + "-" + tostr(Rnd(100000))
    task = m.top.getScene().callFunc("recommend", {
        action: "similar", reqId: m.recReq, meta: full, exclude: seen, watched: m.global.watched
        cinemeta: findAddon(m.global.addons, CINEMETA_ID()), kitsu: findAddon(m.global.addons, KITSU_ID())
    })
    m.recTask = task
    task.observeField("response", "onSimilar")
end sub

sub onLogo()
    if m.logo.loadStatus = "failed"
        m.logo.visible = false
        m.titleText.visible = true
        layoutPage()
    else if m.logo.loadStatus = "ready"
        fitLogo(m.logo, 560, 160, 0)
    end if
end sub

sub renderHeader()
    f = m.full
    m.titleText.text = f.name
    if f.logo <> ""
        m.logo.uri = f.logo
        m.logo.visible = true
        m.titleText.visible = false
    else
        m.logo.visible = false
        m.titleText.visible = true
    end if
    m.metaLine.meta = f
    m.metaLine.match = matchPercent(f, m.profile)
    m.genres.text = joinArr(f.genres, "  •  ")
    m.desc.text = f.description
    lines = []
    if f.director.Count() > 0 then lines.Push("Director: " + joinArr(arrTake(f.director, 2), ", "))
    if f.cast.Count() > 0 then lines.Push("Starring: " + joinArr(arrTake(f.cast, 4), ", "))
    m.people.text = joinArr(lines, Chr(10))
end sub

sub buildButtons()
    m.buttons.callFunc("clearItems")
    m.playBtn = makeButton("Finding cached streams…", "pkg:/images/ic_play.png", "button", true)
    m.chooseBtn = makeButton("Choose stream", "", "button", false)
    m.listBtn = makeButton("My List", "pkg:/images/ic_add.png", "button", false)
    m.likeBtn = makeButton("", "pkg:/images/ic_thumbup.png", "icon", false)
    m.dislikeBtn = makeButton("", "pkg:/images/ic_thumbdown.png", "icon", false)
    for each b in [m.playBtn, m.chooseBtn, m.listBtn, m.likeBtn, m.dislikeBtn]
        m.buttons.callFunc("addItem", b)
    end for
    m.playBtn.observeField("pressed", "onPlayPressed")
    m.chooseBtn.observeField("pressed", "onChoosePressed")
    m.listBtn.observeField("pressed", "onListPressed")
    m.likeBtn.observeField("pressed", "onLikePressed")
    m.dislikeBtn.observeField("pressed", "onDislikePressed")
    refreshButtons()
end sub

function makeButton(text as String, icon as String, variant as String, primary as Boolean) as Object
    b = CreateObject("roSGNode", "TvButton")
    b.variant = variant
    b.icon = icon
    b.text = text
    b.primary = primary
    return b
end function

sub refreshButtons()
    if m.full = invalid or m.listBtn = invalid then return
    if inMyList(m.full.id)
        m.listBtn.text = "In My List"
        m.listBtn.icon = "pkg:/images/ic_check.png"
    else
        m.listBtn.text = "My List"
        m.listBtn.icon = "pkg:/images/ic_add.png"
    end if
    r = ratingOf(m.full.id)
    m.likeBtn.checked = r > 0
    m.dislikeBtn.checked = r < 0
    if m.streamsLoading
        m.playBtn.text = "Finding cached streams…"
    else if m.streams <> invalid and m.streams.best <> invalid
        if m.isSeries then m.playBtn.text = "Play episode" else m.playBtn.text = "Play"
        if resumeSec() > 0 then m.playBtn.text = "Resume"
    else
        m.playBtn.text = "No cached streams"
    end if
end sub

sub onUserData()
    refreshButtons()
end sub

' ---- layout & sections ----

sub layoutPage()
    y = 0
    if m.logo.visible
        if m.logo.loadStatus = "ready" then fitLogo(m.logo, 560, 160, 0)
        y = 160
    else
        m.titleText.translation = [0, 0]
        y = m.titleText.boundingRect().height
    end if
    y = y + 19
    m.metaLine.translation = [0, y]
    y = y + 34
    if m.genres.text <> ""
        m.genres.translation = [0, y]
        y = y + 30
    end if
    if m.episodeLabel.text <> ""
        y = y + 6
        m.episodeLabel.translation = [0, y]
        m.episodeLabel.visible = true
        y = y + 30
        if m.episodeSyn.text <> ""
            m.episodeSyn.translation = [0, y]
            m.episodeSyn.visible = true
            y = y + m.episodeSyn.boundingRect().height + 4
        else
            m.episodeSyn.visible = false
        end if
    else
        m.episodeLabel.visible = false
        m.episodeSyn.visible = false
    end if
    y = y + 10
    m.desc.translation = [0, y]
    y = y + m.desc.boundingRect().height + 8
    if m.people.text <> ""
        m.people.translation = [0, y]
        y = y + m.people.boundingRect().height + 4
    end if
    y = y + 20
    m.buttons.translation = [0, y]
    y = y + 62
    if m.bestLine.text <> ""
        m.bestLine.translation = [0, y + 4]
        y = y + 32
    end if
    m.headerBottom = 64 + y + 32
    y = m.headerBottom
    m.episodesSection.visible = m.isSeries
    if m.isSeries
        m.episodesSection.translation = [0, y]
        m.episodesY = y
        y = y + 470
    end if
    m.streamsSection.translation = [0, y]
    m.streamsY = y
    h = 134
    if m.streamList.visible and m.streamList.content <> invalid
        n = m.streamList.content.getChildCount()
        if n > 4 then n = 4
        h = h + n * 110
    else
        h = h + 130
    end if
    y = y + h + 30
    m.similar.translation = [0, y]
    m.similarY = y
end sub

function sections() as Object
    out = [{ id: "buttons", node: m.buttons, y: 0 }]
    if m.isSeries
        out.Push({ id: "seasons", node: m.seasons, y: m.episodesY - 40 })
        out.Push({ id: "episodes", node: m.episodes, y: m.episodesY - 40 })
    end if
    if m.filterBar.visible and m.filterBar.callFunc("itemCount") > 0 then out.Push({ id: "filters", node: m.filterBar, y: m.streamsY - 40 })
    if m.hintButton.visible then out.Push({ id: "hint", node: m.hintButton, y: m.streamsY - 40 })
    if m.streamList.visible then out.Push({ id: "streams", node: m.streamList, y: m.streamsY - 40 })
    if m.similar.content <> invalid and m.similar.content.getChildCount() > 0 then out.Push({ id: "similar", node: m.similar, y: m.similarY - 40 })
    return out
end function

sub focusSection(id as String)
    for each s in sections()
        if s.id = id
            s.node.setFocus(true)
            m.lastFocus = s.node
            scrollTo(s.y)
            return
        end if
    end for
end sub

sub scrollTo(y as Float)
    if y < 0 then y = 0
    if y = m.scrollY then return
    m.scrollInterp.keyValue = [[0, -m.scrollY], [0, -y]]
    m.scrollY = y
    m.scrollAnim.control = "start"
end sub

function moveSection(delta as Integer) as Boolean
    list = sections()
    cur = -1
    for i = 0 to list.Count() - 1
        if list[i].node.isInFocusChain() then cur = i
    end for
    j = cur + delta
    if cur < 0 or j < 0 or j >= list.Count() then return false
    list[j].node.setFocus(true)
    m.lastFocus = list[j].node
    scrollTo(list[j].y)
    return true
end function

' ---- seasons & episodes ----

sub buildSeasons()
    seasons = []
    for each v in m.full.videos
        if not arrHas(seasons, v.season) then seasons.Push(v.season)
    end for
    ' specials (0) last
    sorted = []
    for each s in seasons
        k = s
        if s = 0 then k = 99999
        sorted.Push({ s: s, k: k })
    end for
    sorted.SortBy("k")
    m.seasonList = []
    m.seasons.callFunc("clearItems")
    for each x in sorted
        m.seasonList.Push(x.s)
        label = "Season " + tostr(x.s)
        if x.s = 0 then label = "Specials"
        if x.s < 0 then label = "Episodes"
        b = makeButton(label, "", "chip", false)
        b.data = { season: x.s }
        b.observeField("pressed", "onSeasonPressed")
        m.seasons.callFunc("addItem", b)
    end for
end sub

sub onSeasonPressed(e as Object)
    showSeason(e.getRoSGNode().data.season)
end sub

sub showSeason(season as Integer)
    m.season = season
    for i = 0 to m.seasons.callFunc("itemCount") - 1
        b = m.seasons.callFunc("getItem", i)
        b.checked = b.data.season = season
        if b.checked then m.seasons.focusIndex = i
    end for
    eps = []
    for each v in m.full.videos
        if v.season = season then eps.Push(v)
    end for
    eps.SortBy("episode")
    m.seasonEps = eps
    root = CreateObject("roSGNode", "ContentNode")
    row = root.createChild("ContentNode")
    watched = m.global.watched
    focusIdx = 0
    for i = 0 to eps.Count() - 1
        n = row.createChild("EpisodeNode")
        n.video = eps[i]
        n.selected = m.video <> invalid and eps[i].id = m.video.id
        if n.selected then focusIdx = i
        h = historyEntry(m.full.id, eps[i].id)
        n.watched = h <> invalid and toNum(h.d) > 0 and toNum(h.ps) / toNum(h.d) > 0.9
    end for
    m.episodes.content = root
    if eps.Count() > 0 then m.episodes.jumpToRowItem = [0, focusIdx]
    showEpisodeSummary(invalid)
end sub

sub selectEpisode(v as Object, scroll as Boolean)
    m.video = v
    if m.season = invalid or m.season <> v.season then showSeason(v.season) else showSeason(v.season)
    label = ""
    if v.season >= 0 then label = "S" + tostr(v.season) + " E" + tostr(v.episode) + " · "
    m.episodeLabelText = label + v.title
    m.episodeLabel.text = m.episodeLabelText
    m.episodeSyn.text = v.overview
    layoutPage()
    loadStreams(v.id, false)
    if scroll then focusSection("streams")
end sub

sub onEpisodeSelected()
    f = m.episodes.rowItemSelected
    if f = invalid or m.seasonEps = invalid then return
    selectEpisode(m.seasonEps[f[1]], true)
end sub

sub onEpisodeFocused()
    f = m.episodes.rowItemFocused
    if f = invalid or f.Count() < 2 or f[1] < 0 or m.seasonEps = invalid then return
    if m.episodes.hasFocus() then showEpisodeSummary(m.seasonEps[f[1]])
end sub

sub onEpisodesFocus()
    if not m.episodes.isInFocusChain() then showEpisodeSummary(invalid)
end sub

sub showEpisodeSummary(v as Dynamic)
    if v = invalid then v = m.video
    if v = invalid or v.season <> m.season
        m.epSummaryTitle.text = ""
        m.epSummary.text = ""
        return
    end if
    parts = []
    if v.season >= 0 then parts.Push("S" + tostr(v.season) + " E" + tostr(v.episode))
    parts.Push(v.title)
    if v.released <> "" then parts.Push(v.released)
    m.epSummaryTitle.text = joinArr(parts, "  ·  ")
    syn = v.overview
    if syn = "" then syn = "No summary available."
    m.epSummary.text = syn
end sub

' ---- streams ----

function currentVideoId() as String
    if m.isSeries and m.video <> invalid then return m.video.id
    return m.full.id
end function

sub loadStreams(videoId as String, force as Boolean)
    m.reqId = m.reqId + 1
    m.streamsLoading = true
    m.streams = invalid
    m.streamsSummary.text = "searching your addons…"
    m.streamsHint.text = "Asking your addons for debrid-cached streams…"
    m.streamsHint.visible = true
    m.hintButton.visible = false
    m.streamList.visible = false
    m.filterBar.visible = false
    m.extSubs.text = ""
    m.bestLine.text = ""
    refreshButtons()
    m.streamTask.request = {
        action: "load", reqId: m.reqId, type: m.full.type, videoId: videoId, force: force
        addons: m.global.addons, settings: m.global.settings, filter: m.global.streamFilter
    }
end sub

sub sendFilter()
    m.reqId = m.reqId + 1
    m.streamTask.request = { action: "filter", reqId: m.reqId, settings: m.global.settings, filter: m.global.streamFilter, videoId: currentVideoId() }
end sub

sub onStreams()
    r = m.streamTask.result
    if r = invalid or r.reqId <> m.reqId then return
    hadListFocus = m.streamList.hasFocus()
    hadFilterFocus = m.filterBar.isInFocusChain()
    filterIdx = m.filterBar.focusIndex
    m.streams = r
    m.streamsLoading = false
    kind = "episode"
    if not m.isSeries then kind = "title"
    m.hintButton.visible = false
    if r.noStreamAddons
        m.streamsSummary.text = "no stream addons installed"
        m.streamsHint.text = "Install a debrid-enabled stream addon to watch. Only cached results are ever shown."
        m.hintButton.text = "Manage addons"
        m.hintButton.primary = true
        m.hintButton.visible = true
        m.hintAction = "addons"
    else
        s = tostr(r.shown) + " shown · " + tostr(r.cachedCount) + " cached · " + tostr(r.hidden) + " uncached hidden"
        if r.failed.Count() > 0 then s = s + " · failed: " + joinArr(r.failed, ", ")
        m.streamsSummary.text = s
        if r.cachedCount = 0
            if r.total > 0
                m.streamsHint.text = "Found " + tostr(r.total) + " streams, but none are cached on your debrid service yet."
            else
                m.streamsHint.text = "Your addons returned no streams for this " + kind + "."
            end if
        else if r.shown = 0
            m.streamsHint.text = "No cached streams match these filters."
            m.hintButton.text = "Reset filters"
            m.hintButton.primary = false
            m.hintButton.visible = true
            m.hintAction = "reset"
        end if
    end if
    hasList = r.shown > 0
    m.streamsHint.visible = not hasList
    m.hintButton.translation = [64, 190]
    m.streamList.visible = hasList
    if hasList
        m.streamList.content = r.content
        m.streamList.translation = [64, 134]
    end if
    buildFilterBar(r)
    if r.extLangs.Count() > 0
        names = []
        for each l in arrTake(r.extLangs, 8)
            names.Push(langName(l))
        end for
        t = "External subtitles available: " + joinArr(names, ", ")
        if r.extLangs.Count() > 8 then t = t + " +" + tostr(r.extLangs.Count() - 8) + " more"
        m.extSubs.text = t
    else
        m.extSubs.text = ""
    end if
    if r.bestSummary <> "" then m.bestLine.text = "Best for this TV: " + r.bestSummary else m.bestLine.text = ""
    refreshButtons()
    layoutPage()
    if hadListFocus and hasList
        m.streamList.setFocus(true)
    else if hadListFocus or hadFilterFocus
        m.filterBar.focusIndex = filterIdx
        m.filterBar.setFocus(true)
        m.lastFocus = m.filterBar
    end if
end sub

sub buildFilterBar(r as Object)
    m.filterBar.callFunc("clearItems")
    f = m.global.streamFilter
    if r.cachedCount = 0 and not r.noStreamAddons
        b = makeButton("Refresh", "pkg:/images/ic_refresh.png", "chip", false)
        b.data = { act: "refresh" }
        b.observeField("pressed", "onFilterChip")
        m.filterBar.callFunc("addItem", b)
        m.filterBar.visible = true
        return
    end if
    if r.noStreamAddons
        m.filterBar.visible = false
        return
    end if
    m.filterBar.visible = true
    sortLabel = "Best match"
    for each s in SORTS()
        if s.id = f.sort then sortLabel = s.label
    end for
    chips = [
        { label: "Refresh", act: "refresh", icon: "pkg:/images/ic_refresh.png", on: false }
        { label: "Sort: " + sortLabel, act: "sort", on: false }
        { label: "Plays well on this TV", act: "friendly", on: f.deviceFriendlyOnly }
    ]
    for each fc in FACETS()
        options = r.facets.Lookup(fc.kind)
        sel = f.selected.Lookup(fc.kind)
        if sel = invalid then sel = []
        if options <> invalid and (options.Count() > 1 or sel.Count() > 0)
            label = fc.label
            if sel.Count() = 1
                for each o in options
                    if o.value = sel[0] then label = fc.label + ": " + substringBefore(o.label, "  (")
                end for
            else if sel.Count() > 1
                label = fc.label + ": " + tostr(sel.Count())
            end if
            chips.Push({ label: label, act: "facet", kind: fc.kind, on: sel.Count() > 0 })
        end if
    end for
    chips.Push({ label: "Hide CAM", act: "cam", on: f.hideCam })
    if activeFilterCount(f) > 0 then chips.Push({ label: "Reset filters", act: "reset", on: false })
    for each c in chips
        icon = ""
        if c.icon <> invalid then icon = c.icon
        b = makeButton(c.label, icon, "chip", false)
        b.checked = c.on
        b.fontSize = 18
        b.data = c
        b.observeField("pressed", "onFilterChip")
        m.filterBar.callFunc("addItem", b)
    end for
end sub

sub onFilterChip(e as Object)
    d = e.getRoSGNode().data
    f = m.global.streamFilter
    if d.act = "refresh"
        loadStreams(currentVideoId(), true)
    else if d.act = "friendly"
        f.deviceFriendlyOnly = not f.deviceFriendlyOnly
        m.global.streamFilter = f
        sendFilter()
    else if d.act = "cam"
        f.hideCam = not f.hideCam
        m.global.streamFilter = f
        sendFilter()
    else if d.act = "reset"
        m.global.streamFilter = { sort: f.sort, selected: {}, deviceFriendlyOnly: false, hideCam: true }
        sendFilter()
    else if d.act = "sort"
        opts = []
        for each s in SORTS()
            opts.Push({ id: s.id, label: s.label, checked: s.id = f.sort })
        end for
        dlg = CreateObject("roSGNode", "ChoiceDialog")
        dlg.title = "Sort streams"
        dlg.options = opts
        dlg.observeField("chosen", "onSortChosen")
        m.top.getScene().callFunc("pushDialog", dlg)
    else if d.act = "facet"
        openFacet(d.kind)
    end if
end sub

sub onSortChosen(e as Object)
    f = m.global.streamFilter
    f.sort = e.getData()
    m.global.streamFilter = f
    sendFilter()
end sub

sub openFacet(kind as String)
    f = m.global.streamFilter
    sel = f.selected.Lookup(kind)
    if sel = invalid then sel = []
    opts = []
    for each o in m.streams.facets.Lookup(kind)
        opts.Push({ id: o.value, label: o.label, trailing: tostr(o.count), checked: arrHas(sel, o.value) })
    end for
    title = kind
    for each fc in FACETS()
        if fc.kind = kind then title = fc.label
    end for
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = title
    dlg.multiSelect = true
    dlg.showClear = true
    dlg.tag = kind
    dlg.options = opts
    dlg.observeField("chosen", "onFacetToggled")
    dlg.observeField("cleared", "onFacetCleared")
    m.top.getScene().callFunc("pushDialog", dlg)
end sub

sub onFacetToggled(e as Object)
    kind = e.getRoSGNode().tag
    v = e.getData()
    f = m.global.streamFilter
    sel = f.selected.Lookup(kind)
    if sel = invalid then sel = []
    out = []
    found = false
    for each x in sel
        if x = v then found = true else out.Push(x)
    end for
    if not found then out.Push(v)
    f.selected[kind] = out
    m.global.streamFilter = f
    sendFilter()
end sub

sub onFacetCleared(e as Object)
    kind = e.getRoSGNode().tag
    f = m.global.streamFilter
    f.selected.Delete(kind)
    m.global.streamFilter = f
    sendFilter()
end sub

sub onHintPressed()
    if m.hintAction = "addons"
        m.top.navigateTo = { to: "addons" }
    else if m.hintAction = "reset"
        f = m.global.streamFilter
        m.global.streamFilter = { sort: f.sort, selected: {}, deviceFriendlyOnly: false, hideCam: true }
        sendFilter()
    end if
end sub

' ---- playback ----

function resumeSec() as Integer
    if m.full = invalid then return 0
    h = historyEntry(m.full.id, currentVideoId())
    if h = invalid or toNum(h.d) <= 0 then return 0
    p = toNum(h.ps) / toNum(h.d)
    if p >= 0.02 and p <= 0.95 then return toInt(h.ps)
    return 0
end function

sub onPlayPressed()
    if m.streams = invalid
        if not m.streamsLoading then toast("No cached streams for this title")
        return
    end if
    if m.streams.noStreamAddons
        m.top.navigateTo = { to: "addons" }
        return
    end if
    if m.streams.best = invalid
        toast("No cached streams for this title")
        return
    end if
    play(m.streams.best)
end sub

sub onStreamSelected()
    c = m.streamList.content.getChild(m.streamList.itemSelected)
    if c <> invalid then play(c.stream)
end sub

sub play(stream as Object)
    candidates = [stream]
    content = m.streams.content
    for i = 0 to content.getChildCount() - 1
        s = content.getChild(i).stream
        if s.key <> stream.key and candidates.Count() < 5 then candidates.Push(s)
    end for
    label = ""
    if m.isSeries and m.episodeLabelText <> invalid then label = m.episodeLabelText
    videos = []
    if m.isSeries then videos = m.full.videos
    m.top.navigateTo = {
        to: "player", meta: m.full, videoId: currentVideoId(), label: label
        candidates: candidates, subs: m.streams.subs, startSec: resumeSec(), videos: videos
    }
end sub

' ---- buttons ----

sub onChoosePressed()
    if m.streamList.visible then focusSection("streams") else focusSection("filters")
end sub

sub onListPressed()
    toggleMyList(m.full)
end sub

sub onLikePressed()
    if ratingOf(m.full.id) > 0 then rateTitle(m.full, 0) else rateTitle(m.full, 1)
end sub

sub onDislikePressed()
    if ratingOf(m.full.id) < 0 then rateTitle(m.full, 0) else rateTitle(m.full, -1)
end sub

' ---- similar ----

sub onSimilar(e as Object)
    r = e.getData()
    if r = invalid or r.reqId <> m.recReq then return
    root = CreateObject("roSGNode", "ContentNode")
    for each row in r.rows
        row.content.title = row.title
        root.appendChild(row.content)
    end for
    if root.getChildCount() > 0 then setRows(m.similar, root)
    layoutPage()
end sub

sub onSimilarSelected()
    meta = focusedMeta(m.similar)
    if meta <> invalid then m.top.navigateTo = { to: "details", meta: meta }
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "down" then return moveSection(1)
    if key = "up"
        if moveSection(-1)
            if m.buttons.hasFocus() or m.buttons.isInFocusChain() then scrollTo(0)
            return true
        end if
        return false
    end if
    if key = "options" and m.similar.isInFocusChain()
        meta = focusedMeta(m.similar)
        if meta <> invalid then m.top.getScene().callFunc("cardMenu", meta)
        return true
    end if
    if key = "play" and m.full <> invalid
        onPlayPressed()
        return true
    end if
    return false
end function
