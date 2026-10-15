' App shell: profiles, theme, navigation stack, side menu, dialogs. Port of AppShell.kt / MainActivity.kt.

sub init()
    m.bg = m.top.findNode("bg")
    m.wall = m.top.findNode("wall")
    m.fx = m.top.findNode("fx")
    m.fxAnim = m.top.findNode("fxAnim")
    m.fxMove = m.top.findNode("fxMove")
    m.fxClip = m.top.findNode("fxClip")
    m.views = m.top.findNode("views")
    m.rail = m.top.findNode("rail")
    m.overlay = m.top.findNode("overlay")
    m.toastNode = m.top.findNode("toast")
    m.top.backgroundColor = "0x07090AFF"
    m.top.backgroundUri = ""

    m.global.addFields({
        theme: buildTheme(defaultSettings())
        settings: defaultSettings()
        profileId: "default"
        profiles: []
        addons: []
        addonsReady: false
        myList: []
        history: []
        episodes: {}
        watched: {}
        ratings: {}
        userVersion: 0
        toast: ""
        caps: {}
    })
    m.global.observeField("toast", "onToast")
    m.global.observeField("theme", "onThemeChanged")
    m.rail.observeField("chosen", "onRailChosen")

    m.stack = []      ' pushed views (details, player, person...)
    m.topViews = {}   ' cached top-level views
    m.current = invalid
    m.currentTop = ""
    m.dialogs = []
    m.focusBefore = []

    if regReadStr(APP_SECTION(), "cleaned") <> "1"
        cleanupForeignSections()
        regWriteRaw(APP_SECTION(), "cleaned", "1")
    end if

    m.recTask = CreateObject("roSGNode", "RecommendTask")
    m.recTask.control = "run"

    profiles = loadProfiles()
    m.global.profiles = profiles
    if profiles.Count() > 1 and regReadStr(APP_SECTION(), "skipPicker") <> "true"
        showProfilePicker()
    else
        startProfile(activeProfileId())
    end if
end sub

' ---- profiles ----

sub showProfilePicker()
    applyTheme(defaultSettings())
    picker = CreateObject("roSGNode", "ProfilePicker")
    picker.observeField("picked", "onProfilePicked")
    clearViews()
    m.rail.visible = false
    m.views.translation = [0, 0]
    m.views.appendChild(picker)
    m.current = picker
    picker.setFocus(true)
end sub

sub onProfilePicked(e as Object)
    id = e.getData()
    m.views.removeChild(e.getRoSGNode())
    m.current = invalid
    startProfile(id)
end sub

function switchProfile(params as Object) as Object
    if params.id = invalid or params.id = "" then showProfilePicker() else startProfile(params.id)
    return invalid
end function

sub startProfile(pid as String)
    exists = false
    for each p in m.global.profiles
        if p.id = pid then exists = true
    end for
    if not exists then pid = "default"
    regWriteRaw(APP_SECTION(), "active", pid)
    sec = profileSection(pid)
    m.global.profileId = pid
    settings = loadSettings(pid)
    m.global.settings = settings
    v = regRead(sec, "list")
    if not isArr(v) then v = []
    m.global.myList = v
    v = regRead(sec, "hist")
    if not isArr(v) then v = []
    m.global.history = v
    v = regRead(sec, "eps")
    if not isAA(v) then v = {}
    m.global.episodes = v
    w = {}
    v = regRead(sec, "watched")
    if isArr(v)
        for each id in v
            w[id] = true
        end for
    end if
    m.global.watched = w
    v = regRead(sec, "ratings")
    if not isAA(v) then v = {}
    m.global.ratings = v
    m.global.addonsReady = false
    m.global.addons = []
    applyTheme(settings)

    m.addonTask = CreateObject("roSGNode", "AddonTask")
    m.addonTask.observeField("addons", "onBootAddons")
    m.addonTask.request = { action: "boot", profileId: pid }
    m.addonTask.control = "run"

    clearViews()
    m.stack = []
    m.topViews = {}
    showTop("home")
end sub

sub onBootAddons(e as Object)
    list = e.getData()
    if list = invalid then return
    m.global.addons = list
    m.global.addonsReady = true
end sub

function setAddons(params as Object) as Object
    m.global.addons = params.addons
    return invalid
end function

' ---- theme / settings ----

sub applyTheme(settings as Object)
    t = buildTheme(settings)
    m.global.theme = t
end sub

sub onThemeChanged()
    t = m.global.theme
    m.bg.color = t.bg
    m.top.backgroundColor = t.bg
    m.wall.uri = t.wall
    m.wall.visible = t.wall <> ""
    m.fxAnim.control = "stop"
    m.fx.visible = t.fx <> ""
    if t.fx <> ""
        ' tiles are 640×360 drawn at 2× (1280×720); two tiles stacked (or side by side for "left")
        m.fx.uri = "pkg:/images/fx_" + t.fx + ".png"
        if t.fxDir = "left"
            m.fx.width = 2560
            m.fx.height = 720
            m.fxMove.keyValue = [[0, 0], [-1280, 0]]
        else
            m.fx.width = 1280
            m.fx.height = 1440
            if t.fxDir = "up" then m.fxMove.keyValue = [[0, 0], [0, -720]] else m.fxMove.keyValue = [[0, -720], [0, 0]]
        end if
        m.fxAnim.duration = t.fxSec
    end if
    updateFx()
    m.rail.applyTheme = true
end sub

' The particle layer only moves on browsing screens; it's paused under the player.
sub updateFx()
    moving = m.fx.visible and not (m.current <> invalid and m.current.subtype() = "PlayerView")
    if moving
        if m.fxAnim.state = "paused" then m.fxAnim.control = "resume" else if m.fxAnim.state <> "running" then m.fxAnim.control = "start"
    else if m.fxAnim.state = "running"
        m.fxAnim.control = "pause"
    end if
    m.fxClip.visible = moving
end sub

function applySettings(params as Object) as Object
    old = m.global.settings
    s = params.settings
    m.global.settings = s
    if not saveSettings(m.global.profileId, s) then toast("Couldn't save settings on this TV")
    if old.theme <> s.theme or old.customAccent <> s.customAccent or old.customBackground <> s.customBackground or old.dynamicTheme <> s.dynamicTheme
        applyTheme(s)
        ' rebuild cached screens so they pick up the new colors (keep the settings screen)
        for each k in m.topViews
            if k <> m.currentTop then m.topViews.Delete(k)
        end for
    end if
    return invalid
end function

' ---- navigation ----

sub clearViews()
    m.views.removeChildrenIndex(m.views.getChildCount(), 0)
    m.current = invalid
end sub

function createTop(id as String) as Object
    if id = "home" then return CreateObject("roSGNode", "HomeView")
    if id = "movies" or id = "series" or id = "anime"
        v = CreateObject("roSGNode", "BrowseView")
        v.browseType = id
        if id = "movies" then v.browseType = "movie"
        return v
    end if
    if id = "search" then return CreateObject("roSGNode", "SearchView")
    if id = "mylist" then return CreateObject("roSGNode", "MyListView")
    if id = "addons" then return CreateObject("roSGNode", "AddonsView")
    if id = "settings" then return CreateObject("roSGNode", "SettingsView")
    return CreateObject("roSGNode", "HomeView")
end function

sub showTop(id as String)
    ' leaving pushed screens
    for each v in m.stack
        v.active = false
        if v.hasField("dispose") then v.dispose = true
        m.views.removeChild(v)
    end for
    m.stack = []
    if m.current <> invalid and m.current.hasField("active") then m.current.active = false
    if m.currentTop <> "" and m.topViews.DoesExist(m.currentTop)
        old = m.topViews[m.currentTop]
        old.visible = false
        ' only Home stays alive in the background; other pages are rebuilt (saves memory on the TV)
        if m.currentTop <> "home"
            if old.hasField("dispose") then old.dispose = true
            m.views.removeChild(old)
            m.topViews.Delete(m.currentTop)
        end if
    end if
    v = m.topViews.Lookup(id)
    if v = invalid
        v = createTop(id)
        v.observeField("navigateTo", "onViewNavigate")
        m.topViews[id] = v
        m.views.appendChild(v)
    end if
    v.visible = true
    m.currentTop = id
    m.current = v
    m.rail.current = id
    m.rail.visible = true
    m.views.translation = [101, 0]
    v.active = true
    v.setFocus(true)
end sub

sub pushView(v as Object)
    v.observeField("navigateTo", "onViewNavigate")
    if m.current <> invalid
        if m.current.hasField("active") then m.current.active = false
        m.current.visible = false
    end if
    m.stack.Push(v)
    m.views.appendChild(v)
    m.current = v
    m.rail.visible = false
    m.views.translation = [0, 0]
    v.active = true
    v.setFocus(true)
end sub

sub popView()
    if m.stack.Count() = 0 then return
    v = m.stack.Pop()
    v.active = false
    if v.hasField("dispose") then v.dispose = true
    m.views.removeChild(v)
    if m.stack.Count() > 0
        m.current = m.stack[m.stack.Count() - 1]
        m.rail.visible = false
        m.views.translation = [0, 0]
    else
        m.current = m.topViews.Lookup(m.currentTop)
        m.rail.visible = true
        m.views.translation = [101, 0]
    end if
    if m.current <> invalid
        m.current.visible = true
        m.current.active = true
        m.current.setFocus(true)
    end if
    updateFx()
end sub

sub onViewNavigate(e as Object)
    navigate(e.getData())
end sub

' { to: "details" | "player" | "person" | "back" | "<top id>", ... }
function navigate(p as Object) as Object
    if p = invalid then return invalid
    t = p.to
    if t = "details"
        v = CreateObject("roSGNode", "DetailsView")
        v.section = tostr(p.section)
        v.meta = p.meta
        pushView(v)
    else if t = "player"
        v = CreateObject("roSGNode", "PlayerView")
        v.params = p
        pushView(v)
    else if t = "back"
        popView()
    else if t = "popAndPlay"
        popView()
        navigate({ to: "player", meta: p.meta, videoId: p.videoId, label: p.label, candidates: p.candidates, subs: p.subs, startSec: p.startSec, videos: p.videos })
    else
        showTop(t)
    end if
    updateFx()
    return invalid
end function

sub onRailChosen()
    id = m.rail.chosen
    if id <> m.currentTop or m.stack.Count() > 0
        showTop(id)
    else if m.current <> invalid
        m.current.setFocus(true)
    end if
end sub

sub onDeepLink()
    d = m.top.deepLink
    if d = invalid or d.contentId = invalid then return
    if startsWith(d.contentId, "debug-play")
        url = "https://test-videos.co.uk/vids/bigbuckbunny/mkv/1080/Big_Buck_Bunny_1080_10s_5MB.mkv"
        if Instr(1, d.contentId, "|") > 0 then url = substringAfter(d.contentId, "|")
        meta = { id: "tt1254207", type: "movie", name: "Big Buck Bunny", genres: ["Animation"], imdbRating: "6.4", poster: "", background: "" }
        navigate({ to: "player", meta: meta, videoId: "tt1254207", label: "", candidates: [{ url: url, label: "1080p · test", title: "BigBuckBunny.mkv", key: url, bingeGroup: "", headers: invalid }], subs: [], startSec: 0, videos: [] })
        return
    end if
    typ = "movie"
    if d.mediaType = "series" or d.mediaType = "episode" then typ = "series"
    navigate({ to: "details", meta: { id: d.contentId, type: typ, name: "" } })
end sub

' ---- dialogs ----

function pushDialog(dlg as Object) as Object
    ' remember the whole focus path: the focused chip may be rebuilt while the dialog is open
    chain = []
    n = findFocused(m.top)
    while n <> invalid and not n.isSameNode(m.top)
        chain.Push(n)
        n = n.getParent()
    end while
    m.focusBefore.Push(chain)
    m.dialogs.Push(dlg)
    m.overlay.appendChild(dlg)
    dlg.observeField("closed", "onDialogClosed")
    dlg.setFocus(true)
    return invalid
end function

function isAttached(node as Object) as Boolean
    n = node
    while n <> invalid
        if n.isSameNode(m.top) then return true
        n = n.getParent()
    end while
    return false
end function

function findFocused(node as Object) as Dynamic
    n = node
    while n <> invalid and n.focusedChild <> invalid and not n.focusedChild.isSameNode(n)
        n = n.focusedChild
    end while
    return n
end function

sub onDialogClosed(e as Object)
    closeDialog({ node: e.getRoSGNode() })
end sub

function closeDialog(params as Object) as Object
    dlg = params.node
    idx = -1
    for i = 0 to m.dialogs.Count() - 1
        if m.dialogs[i].isSameNode(dlg) then idx = i
    end for
    if idx < 0 then return invalid
    m.overlay.removeChild(dlg)
    m.dialogs.Delete(idx)
    chain = m.focusBefore[idx]
    m.focusBefore.Delete(idx)
    for each n in chain
        if n.focusable and n.visible and isAttached(n)
            n.setFocus(true)
            return invalid
        end if
    end for
    if m.current <> invalid then m.current.setFocus(true)
    return invalid
end function

sub onToast()
    t = m.global.toast
    if t <> "" then m.toastNode.text = t
end sub

' ---- card menu (port of CardMenuDialog: hold OK → here the ✱ options key) ----

function cardMenu(meta as Object) as Object
    if meta = invalid or meta.id = invalid then return invalid
    m.menuMeta = meta
    opts = [{ id: "details", label: "Details" }]
    if meta.type = "series" then opts.Push({ id: "episodes", label: "Episodes" })
    if inMyList(meta.id) then opts.Push({ id: "mylist", label: "Remove from My List" }) else opts.Push({ id: "mylist", label: "Add to My List" })
    if isWatched(meta.id) then opts.Push({ id: "unwatched", label: "Mark as unwatched" }) else opts.Push({ id: "watched", label: "Mark as watched" })
    if historyEntry(meta.id) <> invalid then opts.Push({ id: "history", label: "Remove from history" })
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = meta.name
    dlg.options = opts
    dlg.observeField("chosen", "onCardMenuChosen")
    pushDialog(dlg)
    return invalid
end function

sub onCardMenuChosen(e as Object)
    id = e.getData()
    meta = m.menuMeta
    if id = "details"
        navigate({ to: "details", meta: meta })
    else if id = "episodes"
        navigate({ to: "details", meta: meta, section: "episodes" })
    else if id = "mylist"
        toggleMyList(meta)
    else if id = "watched"
        setWatched(meta, true)
    else if id = "unwatched"
        setWatched(meta, false)
    else if id = "history"
        removeFromHistory(meta.id)
    end if
end sub

function recommend(req as Object) as Object
    m.recTask.request = req
    return m.recTask
end function

' ---- keys ----

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.dialogs.Count() > 0 then return true
    isTop = m.stack.Count() = 0 and m.current <> invalid and m.rail.visible
    if key = "left" and isTop and not m.rail.hasFocus()
        m.rail.setFocus(true)
        return true
    end if
    if key = "right" and m.rail.hasFocus()
        if m.current <> invalid then m.current.setFocus(true)
        return true
    end if
    if key = "back"
        if m.stack.Count() > 0
            popView()
            return true
        end if
        if m.rail.hasFocus()
            confirmExit()
            return true
        end if
        if m.currentTop <> "home"
            showTop("home")
            return true
        end if
        m.rail.setFocus(true)
        return true
    end if
    return false
end function

sub confirmExit()
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = "Exit Zemu?"
    dlg.options = [{ id: "stay", label: "Keep watching" }, { id: "exit", label: "Exit" }]
    dlg.observeField("chosen", "onExitChosen")
    pushDialog(dlg)
end sub

sub onExitChosen(e as Object)
    if e.getData() = "exit" then m.top.exitApp = true
end sub

