sub init()
    m.items = [
        { id: "search", label: "Search", icon: "search" }
        { id: "home", label: "Home", icon: "home" }
        { id: "movies", label: "Movies", icon: "movie" }
        { id: "series", label: "Series", icon: "tv" }
        { id: "anime", label: "Anime", icon: "anime" }
        { id: "mylist", label: "My List", icon: "favorite" }
        { id: "addons", label: "Addons", icon: "puzzle" }
        { id: "settings", label: "Settings", icon: "settings" }
    ]
    m.bg = m.top.findNode("bg")
    m.logo = m.top.findNode("logo")
    m.wordmark = m.top.findNode("wordmark")
    m.list = m.top.findNode("list")
    m.rows = []
    itemH = 53
    top = (720 - m.items.Count() * (itemH + 3)) / 2 + 20
    for i = 0 to m.items.Count() - 1
        it = m.items[i]
        g = CreateObject("roSGNode", "Group")
        g.translation = [0, top + i * (itemH + 3)]
        g.scaleRotateCenter = [0, itemH / 2]
        hl = g.createChild("Poster")
        hl.uri = "pkg:/images/rr12.9.png"
        hl.width = 69
        hl.height = itemH
        hl.visible = false
        ic = g.createChild("Poster")
        ic.uri = "pkg:/images/ic_" + it.icon + ".png"
        ic.width = 29
        ic.height = 29
        ic.translation = [19, 12]
        lb = g.createChild("Label")
        lb.text = it.label
        lb.translation = [69, 0]
        lb.height = itemH
        lb.vertAlign = "center"
        lb.visible = false
        f = CreateObject("roSGNode", "Font")
        f.uri = "font:SystemFontFile"
        f.size = 21
        lb.font = f
        m.list.appendChild(g)
        m.rows.Push({ g: g, hl: hl, ic: ic, lb: lb })
    end for
    m.index = 1
    m.top.focusable = true
    m.top.observeField("focusedChild", "onFocus")
    onTheme()
end sub

sub onTheme()
    if m.global.theme = invalid then return
    m.bg.color = m.global.theme.bg
    restyle()
end sub

sub onFocus()
    focused = m.top.hasFocus()
    if focused <> m.top.expanded
        m.top.expanded = focused
        if focused
            ' entering the menu always lands on the current page
            for i = 0 to m.items.Count() - 1
                if m.items[i].id = m.top.current then m.index = i
            end for
        end if
    end if
    restyle()
end sub

sub restyle()
    t = m.global.theme
    if t = invalid or m.rows = invalid then return
    ex = m.top.expanded
    if ex then m.bg.width = 280 else m.bg.width = 101
    m.logo.visible = not ex
    m.wordmark.visible = ex
    for i = 0 to m.rows.Count() - 1
        r = m.rows[i]
        isCurrent = m.items[i].id = m.top.current
        focused = ex and i = m.index
        r.lb.visible = ex
        r.hl.visible = focused
        r.hl.width = 248
        if ex then r.hl.width = 248 else r.hl.width = 69
        r.hl.blendColor = t.focusBg
        if focused
            r.ic.blendColor = t.focusText
            r.lb.color = t.focusText
            r.g.scale = [1.03, 1.03]
        else
            r.g.scale = [1, 1]
            r.lb.color = t.text
            if isCurrent and not ex then r.ic.blendColor = t.accent else r.ic.blendColor = t.text
        end if
        if isCurrent then r.lb.font.uri = "font:BoldSystemFontFile" else r.lb.font.uri = "font:SystemFontFile"
    end for
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "up"
        if m.index > 0 then m.index = m.index - 1
        restyle()
        return true
    else if key = "down"
        if m.index < m.items.Count() - 1 then m.index = m.index + 1
        restyle()
        return true
    else if key = "OK"
        m.top.chosen = m.items[m.index].id
        return true
    end if
    return false
end function
