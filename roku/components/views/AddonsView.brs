' Port of AddonBrowserScreen.kt + AddonBrowserViewModel.kt.

sub init()
    m.tabs = m.top.findNode("tabs")
    m.actions = m.top.findNode("actions")
    m.list = m.top.findNode("list")
    m.message = m.top.findNode("message")
    m.empty = m.top.findNode("empty")
    m.phoneHint = m.top.findNode("phoneHint")
    m.top.findNode("phoneIcon").blendColor = m.global.theme.textSecondary
    m.list.observeField("itemSelected", "onItemSelected")
    m.top.observeField("focusedChild", "onFocusChange")
    m.global.observeField("addons", "onAddonsChanged")
    m.tab = "installed"
    m.typeFilter = "ALL"
    m.query = ""
    m.catalogs = {}
    m.phoneHint.text = "Starting phone input…"
    buildTabs()
    buildActions()
    render()
end sub

sub onActive()
    if m.top.active
        if m.remote = invalid
            m.remote = CreateObject("roSGNode", "RemoteInputTask")
            m.remote.observeField("address", "onRemoteAddress")
            m.remote.observeField("received", "onRemoteReceived")
            m.remote.control = "run"
        end if
    else if m.remote <> invalid
        m.remote.control = "stop"
        m.remote = invalid
    end if
end sub

sub onRemoteAddress()
    m.address = m.remote.address
    m.phoneHint.text = "To avoid typing, open " + m.address + " on your phone (same Wi-Fi) and paste the addon URL there."
end sub

sub onRemoteReceived()
    text = m.remote.received
    if text = "" then return
    m.message.text = "Installing from your phone…"
    install(text, true)
end sub

sub onFocusChange()
    if m.top.hasFocus()
        if m.list.content <> invalid and m.list.content.getChildCount() > 0 then m.list.setFocus(true) else m.actions.setFocus(true)
    end if
end sub

' ---- tabs & filters ----

function sources() as Object
    out = []
    seen = {}
    for each a in m.global.addons
        for each c in a.addonCatalogs
            if c.type = "all"
                key = a.id + "/" + c.id
                name = c.name
                if name = "" then name = c.id
                if not seen.DoesExist(key)
                    seen[key] = true
                    out.Push({ key: key, name: capitalize(name), base: a.baseUrl, type: c.type, id: c.id })
                end if
            end if
        end for
    end for
    out.Push({ key: "stremio-addons.net", name: "stremio-addons.net", base: "https://stremio-addons.net/api", type: "all", id: "stremio-addons.net" })
    return out
end function

sub buildTabs()
    idx = m.tabs.focusIndex
    m.tabs.callFunc("clearItems")
    m.sources = sources()
    tabs = [{ key: "installed", name: "Installed (" + tostr(m.global.addons.Count()) + ")" }]
    tabs.Append(m.sources)
    for each t in tabs
        b = CreateObject("roSGNode", "TvButton")
        b.variant = "chip"
        b.text = t.name
        b.checked = t.key = m.tab
        b.data = { key: t.key }
        b.observeField("pressed", "onTab")
        m.tabs.callFunc("addItem", b)
    end for
    m.tabs.focusIndex = idx
end sub

sub buildActions()
    idx = m.actions.focusIndex
    m.actions.callFunc("clearItems")
    add = CreateObject("roSGNode", "TvButton")
    add.text = "Add by URL"
    add.icon = "pkg:/images/ic_link.png"
    add.primary = true
    add.data = { act: "url" }
    add.observeField("pressed", "onAction")
    m.actions.callFunc("addItem", add)
    search = CreateObject("roSGNode", "TvButton")
    if m.query = "" then search.text = "Search" else search.text = "Search: " + m.query
    search.icon = "pkg:/images/ic_search.png"
    search.data = { act: "search" }
    search.observeField("pressed", "onAction")
    m.actions.callFunc("addItem", search)
    for each t in [["ALL", "All"], ["MOVIE", "Movies"], ["SERIES", "Series"], ["CHANNEL", "Channels"], ["TV", "TV"], ["OTHER", "Other"]]
        b = CreateObject("roSGNode", "TvButton")
        b.variant = "chip"
        b.text = t[1]
        b.checked = m.typeFilter = t[0]
        b.data = { act: "type", type: t[0] }
        b.observeField("pressed", "onAction")
        m.actions.callFunc("addItem", b)
    end for
    m.actions.focusIndex = idx
end sub

sub onTab(e as Object)
    key = e.getRoSGNode().data.key
    m.tab = key
    buildTabs()
    if key <> "installed" and not m.catalogs.DoesExist(key)
        for each s in m.sources
            if s.key = key then loadCatalog(s)
        end for
    end if
    render()
end sub

sub onAction(e as Object)
    d = e.getRoSGNode().data
    if d.act = "type"
        m.typeFilter = d.type
        buildActions()
        render()
    else if d.act = "url"
        m.kb = showKeyboard("Add addon by URL", "", ["Install", "Cancel"], "onUrlKeyboard", "Paste or type a manifest URL. Easier: open " + tostr(m.address) + " on your phone.")
    else if d.act = "search"
        m.kb = showKeyboard("Search addons", m.query, ["Search", "Clear", "Cancel"], "onSearchKeyboard")
    end if
end sub

sub onUrlKeyboard(e as Object)
    dlg = e.getRoSGNode()
    if e.getField() = "wasClosed" then return
    btn = dlg.buttonSelected
    text = dlg.text
    closeKeyboard(dlg)
    m.actions.setFocus(true)
    if btn = 0 and text.Trim() <> "" then install(text, false)
end sub

sub onSearchKeyboard(e as Object)
    dlg = e.getRoSGNode()
    if e.getField() = "wasClosed" then return
    btn = dlg.buttonSelected
    if btn = 0 then m.query = dlg.text.Trim()
    if btn = 1 then m.query = ""
    closeKeyboard(dlg)
    buildActions()
    render()
    m.actions.setFocus(true)
end sub

sub loadCatalog(s as Object)
    m.message.text = "Loading " + s.name + "…"
    t = CreateObject("roSGNode", "AddonTask")
    t.request = { action: "browse", source: s, profileId: m.global.profileId }
    t.observeField("result", "onCatalogLoaded")
    t.control = "run"
    m.browseTask = t
end sub

sub onCatalogLoaded(e as Object)
    r = e.getData()
    if r.ok
        m.catalogs[r.key] = r.items
        m.message.text = ""
    else
        m.message.text = r.message
    end if
    render()
end sub

sub onAddonsChanged()
    buildTabs()
    render()
end sub

function typeOk(a as Object) as Boolean
    if m.typeFilter = "ALL" then return true
    types = []
    for each t in a.types
        types.Push(LCase(t))
    end for
    if m.typeFilter = "MOVIE" then return arrHas(types, "movie")
    if m.typeFilter = "SERIES" then return arrHas(types, "series") or arrHas(types, "anime")
    if m.typeFilter = "CHANNEL" then return arrHas(types, "channel")
    if m.typeFilter = "TV" then return arrHas(types, "tv")
    for each t in types
        if t = "movie" or t = "series" or t = "channel" or t = "tv" then return false
    end for
    return true
end function

sub render()
    installed = m.global.addons
    byId = {}
    for each a in installed
        byId[a.id] = a.transportUrl
    end for
    items = []
    if m.tab = "installed"
        items = installed
    else
        items = m.catalogs.Lookup(m.tab)
        if items = invalid then items = []
    end if
    q = LCase(m.query)
    content = CreateObject("roSGNode", "ContentNode")
    for each a in items
        ok = typeOk(a)
        if ok and q <> "" then ok = Instr(1, LCase(a.name), q) > 0 or Instr(1, LCase(a.description), q) > 0
        if ok
            n = content.createChild("AddonNode")
            n.addon = a
            url = byId.Lookup(a.id)
            n.installed = url <> invalid
            if url <> invalid then n.installedUrl = url
        end if
    end for
    hadFocus = m.list.hasFocus()
    idx = m.list.itemFocused
    m.list.content = content
    n = content.getChildCount()
    m.list.visible = n > 0
    if n = 0
        if m.tab <> "installed" and not m.catalogs.DoesExist(m.tab)
            m.empty.text = "Loading…"
        else
            m.empty.text = "No addons match."
        end if
    else
        m.empty.text = ""
        if idx >= n then idx = n - 1
        if idx > 0 then m.list.jumpToItem = idx
    end if
    if hadFocus and n > 0 then m.list.setFocus(true)
    if hadFocus and n = 0 then m.actions.setFocus(true)
end sub

' ---- actions on one addon ----

sub onItemSelected()
    c = m.list.content.getChild(m.list.itemSelected)
    if c = invalid then return
    m.sel = c
    a = c.addon
    opts = []
    if c.installed
        opts.Push({ id: "uninstall", label: "Uninstall" })
        if a.configurable or a.configurationRequired then opts.Push({ id: "configure", label: "Configure on your phone" })
        if m.tab = "installed"
            opts.Push({ id: "up", label: "Move up" })
            opts.Push({ id: "down", label: "Move down" })
        end if
        opts.Push({ id: "url", label: "Show install URL" })
    else
        if a.configurationRequired
            opts.Push({ id: "configure", label: "Configure on your phone to install" })
        else
            opts.Push({ id: "install", label: "Install" })
            if a.configurable then opts.Push({ id: "configure", label: "Configure on your phone" })
        end if
    end if
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = a.name
    msg = a.description
    if Len(msg) > 220 then msg = Left(msg, 217) + "…"
    dlg.message = msg
    dlg.options = opts
    dlg.observeField("chosen", "onAddonAction")
    m.top.getScene().callFunc("pushDialog", dlg)
end sub

sub onAddonAction(e as Object)
    id = e.getData()
    c = m.sel
    a = c.addon
    if id = "install"
        m.message.text = "Installing " + a.name + "…"
        install(a.transportUrl, false)
    else if id = "uninstall"
        warning = uninstallWarning(a)
        if warning <> ""
            dlg = CreateObject("roSGNode", "ChoiceDialog")
            dlg.title = "Uninstall " + a.name + "?"
            dlg.message = warning
            dlg.options = [{ id: "keep", label: "Keep it" }, { id: "remove", label: "Uninstall anyway" }]
            dlg.observeField("chosen", "onConfirmUninstall")
            m.top.getScene().callFunc("pushDialog", dlg)
        else
            runAction({ action: "remove", url: c.installedUrl })
        end if
    else if id = "up" or id = "down"
        delta = 1
        if id = "up" then delta = -1
        runAction({ action: "move", url: c.installedUrl, delta: delta })
    else if id = "configure"
        q = CreateObject("roSGNode", "QrDialog")
        q.title = "Configure " + a.name
        addr = "the address shown on the Addons screen"
        if m.address <> invalid then addr = m.address
        q.message = "1. Scan the code (or open the address below) on your phone and set the addon up." + Chr(10) + Chr(10) + "2. Copy the install link it gives you." + Chr(10) + Chr(10) + "3. Open " + addr + " on your phone and paste it. It installs on the TV right away."
        q.url = a.baseUrl + "/configure"
        m.top.getScene().callFunc("pushDialog", q)
    else if id = "url"
        q = CreateObject("roSGNode", "QrDialog")
        q.title = a.name
        q.message = "This is the installed manifest URL. Scan it to copy it to your phone."
        q.url = c.installedUrl
        m.top.getScene().callFunc("pushDialog", q)
    end if
end sub

sub onConfirmUninstall(e as Object)
    if e.getData() = "remove" then runAction({ action: "remove", url: m.sel.installedUrl })
end sub

function uninstallWarning(a as Object) as String
    provides = false
    for each c in a.catalogs
        if c.type = "movie" or c.type = "series" then provides = true
    end for
    if not provides then return ""
    for each o in m.global.addons
        if o.id <> a.id
            for each c in o.catalogs
                if (c.type = "movie" or c.type = "series") and not catalogNeedsExtra(c) then return ""
            end for
        end if
    end for
    return a.name + " is your only catalog/metadata provider. Without it, Home, Movies and Series will be empty until you install another one."
end function

sub install(url as String, fromPhone as Boolean)
    m.fromPhone = fromPhone
    runAction({ action: "install", url: url })
end sub

sub runAction(req as Object)
    req.profileId = m.global.profileId
    req.current = m.global.addons
    t = CreateObject("roSGNode", "AddonTask")
    t.request = req
    t.observeField("result", "onActionResult")
    t.control = "run"
    m.actionTask = t
end sub

sub onActionResult(e as Object)
    r = e.getData()
    if r.addons <> invalid and r.ok then m.top.getScene().callFunc("setAddons", { addons: r.addons })
    if r.message <> invalid
        m.message.text = r.message
        toast(r.message)
    end if
    if m.fromPhone = true and m.remote <> invalid and r.action = "install"
        m.remote.reply = r.message
        m.fromPhone = false
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "down"
        if m.tabs.isInFocusChain()
            m.actions.setFocus(true)
            return true
        else if m.actions.isInFocusChain() and m.list.visible
            m.list.setFocus(true)
            return true
        end if
    else if key = "up"
        if m.list.hasFocus()
            m.actions.setFocus(true)
            return true
        else if m.actions.isInFocusChain()
            m.tabs.setFocus(true)
            return true
        end if
    end if
    return false
end function
