' Port of SearchScreen.kt: searches every catalog that supports "search", one row per catalog.

sub init()
    m.keyboard = m.top.findNode("keyboard")
    m.results = m.top.findNode("results")
    m.status = m.top.findNode("status")
    m.hint = m.top.findNode("hint")
    m.debounce = m.top.findNode("debounce")
    t = m.global.theme
    ' The dynamic keyboard takes voice: hold the remote's mic while it's focused and the words are
    ' typed in (the legacy MiniKeyboard has no voice entry). Whole words, not letter by letter.
    m.keyboard.domain = "generic"
    m.keyboard.textEditBox.voiceEnabled = true
    m.keyboard.textEditBox.voiceEntryType = "generic"
    p = CreateObject("roSGNode", "RSGPalette")
    p.colors = {
        KeyboardColor: t.surfaceHigh
        InputFieldColor: t.bg
        PrimaryTextColor: t.text
        SecondaryTextColor: t.textMuted
        FocusColor: "0xFFFFFFFF"
        FocusItemColor: t.focusText
    }
    m.keyboard.palette = p
    ' Results sit just right of the keyboard, whatever width this Roku OS draws it at.
    kbRight = m.keyboard.translation[0] + m.keyboard.boundingRect().width
    if kbRight > 420
        m.results.translation = [kbRight + 20, 60]
        m.hint.translation = [kbRight + 60, 120]
        m.hint.width = 1240 - kbRight - 60
    end if
    m.keyboard.textEditBox.hintText = "Movies, series, anime…"
    m.keyboard.textEditBox.hintTextColor = t.textMuted
    m.keyboard.observeField("text", "onText")
    m.debounce.observeField("fire", "search")
    setupRowList(m.results, 1179 - m.results.translation[0])
    m.results.focusXOffset = [24]
    m.results.rowLabelOffset = [[24, 10]]
    m.results.observeField("rowItemSelected", "onSelected")
    m.top.observeField("focusedChild", "onFocusChange")
    m.top.observeField("active", "onActive")
    m.lastQuery = ""
    showSaved()
end sub

sub onActive()
    if m.top.active and Len(m.lastQuery) < 2 then showSaved()
end sub

' Nothing typed: titles opened lately and Watch Later, one press away.
sub showSaved()
    root = CreateObject("roSGNode", "ContentNode")
    for each sec in [{ title: "Recently viewed", list: viewedList() }, { title: "Watch Later", list: m.global.watchLater }]
        if sec.list.Count() > 0
            row = root.createChild("ContentNode")
            row.title = sec.title
            for each e in sec.list
                makeMetaNode(row, expandMeta(e)).watched = m.global.watched.DoesExist(e.i)
            end for
        end if
    end for
    has = root.getChildCount() > 0
    if has then setRows(m.results, root) else m.results.content = invalid
    m.results.visible = has
    m.hint.visible = not has
end sub

sub onFocusChange()
    if m.top.hasFocus() then m.keyboard.setFocus(true)
end sub

sub onText()
    m.debounce.control = "stop"
    m.debounce.control = "start"
end sub

sub search()
    q = m.keyboard.text.Trim()
    if q = m.lastQuery then return
    m.lastQuery = q
    if Len(q) < 2
        m.status.text = ""
        showSaved()
        return
    end if
    reqs = []
    multi = 0
    for each a in m.global.addons
        for each c in a.catalogs
            if catalogSupportsExtra(c, "search") then multi = multi + 1
        end for
    end for
    p = 0
    for each a in m.global.addons
        for each c in a.catalogs
            if catalogSupportsExtra(c, "search")
                title = capitalize(c.type)
                if c.type = "movie" then title = "Movies"
                if c.type = "series" then title = "Series"
                if multi > 2 then title = title + " · " + a.name
                reqs.Push({ key: a.id + "/" + c.type + "/" + c.id, title: title, priority: p, base: a.baseUrl, type: c.type, id: c.id, extra: [["search", q]], limit: 40 })
                p = p + 1
            end if
        end for
    end for
    if reqs.Count() = 0
        m.status.text = "None of your addons support search."
        return
    end if
    m.status.text = "Searching…"
    m.task = CreateObject("roSGNode", "CatalogTask")
    m.task.requests = reqs
    m.task.watched = m.global.watched
    m.task.observeField("rows", "onRows")
    m.task.control = "run"
    m.taskQuery = q
end sub

sub onRows(e as Object)
    if m.taskQuery <> m.lastQuery then return
    rows = e.getData()
    root = CreateObject("roSGNode", "ContentNode")
    for each r in rows
        r.content.title = r.title
        root.appendChild(r.content)
    end for
    m.hint.visible = false
    if root.getChildCount() = 0
        m.status.text = "No results."
        m.results.visible = false
        return
    end if
    m.status.text = ""
    setRows(m.results, root)
    m.results.visible = true
end sub

sub onSelected()
    meta = focusedMeta(m.results)
    if meta <> invalid then m.top.navigateTo = { to: "details", meta: meta }
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "right" and m.keyboard.isInFocusChain() and m.results.visible
        m.results.setFocus(true)
        return true
    else if key = "left" and m.results.hasFocus()
        m.keyboard.setFocus(true)
        return true
    else if key = "options" and m.results.hasFocus()
        meta = focusedMeta(m.results)
        if meta <> invalid then m.top.getScene().callFunc("cardMenu", meta)
        return true
    end if
    return false
end function
