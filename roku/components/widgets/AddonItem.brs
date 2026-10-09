sub init()
    m.bg = m.top.findNode("bg")
    m.ring = m.top.findNode("ring")
    m.card = m.top.findNode("card")
    m.logo = m.top.findNode("logo")
    m.name = m.top.findNode("name")
    m.desc = m.top.findNode("desc")
    m.types = m.top.findNode("types")
    m.status = m.top.findNode("status")
    m.theme = m.global.theme
    m.top.findNode("logoBg").blendColor = m.theme.surfaceHigh
    restyle()
end sub

sub render()
    c = m.top.itemContent
    if c = invalid then return
    a = c.addon
    m.logo.uri = a.logo
    name = a.name
    if a.version <> "" then name = name + "  v" + a.version
    m.name.text = name
    m.desc.text = a.description
    types = ""
    for each t in a.types
        if types <> "" then types = types + " · "
        types = types + t
    end for
    m.types.text = types
    if c.installed
        m.status.text = "Installed"
        m.status.color = m.theme.accent
    else if a.configurationRequired
        m.status.text = "Needs setup"
        m.status.color = m.theme.cached
    else
        m.status.text = ""
    end if
end sub

sub restyle()
    f = effFocus()
    if f > 0.5
        m.bg.blendColor = m.theme.surfaceHigh
    else
        m.bg.blendColor = m.theme.surface
    end if
    m.ring.opacity = f
    s = 1 + 0.015 * f
    m.card.scale = [s, s]
end sub

' Focus amount, but 0 when the containing list/grid doesn't have focus.
function effFocus() as Float
    t = m.top
    if t.rowListHasFocus or t.gridHasFocus or t.listHasFocus or t.itemHasFocus then return t.focusPercent
    return 0
end function
