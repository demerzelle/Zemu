' Port of SearchScreen.kt: searches every catalog that supports "search", one row per catalog.

sub init()
    m.keyboard = m.top.findNode("keyboard")
    m.results = m.top.findNode("results")
    m.status = m.top.findNode("status")
    m.hint = m.top.findNode("hint")
    m.debounce = m.top.findNode("debounce")
    t = m.global.theme
    m.keyboard.keyColor = t.text
    m.keyboard.focusedKeyColor = t.focusText
    m.keyboard.textEditBox.textColor = "0xFFFFFFFF"
    m.keyboard.textEditBox.hintText = "Movies, series, anime…"
    m.keyboard.textEditBox.hintTextColor = t.textMuted
    m.keyboard.observeField("text", "onText")
    m.debounce.observeField("fire", "search")
    setupRowList(m.results, 739)
    m.results.focusXOffset = [24]
    m.results.rowLabelOffset = [[24, 10]]
    m.results.observeField("rowItemSelected", "onSelected")
    m.top.observeField("focusedChild", "onFocusChange")
    m.lastQuery = ""
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
        m.results.content = invalid
        m.results.visible = false
        m.hint.visible = true
        m.status.text = ""
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
