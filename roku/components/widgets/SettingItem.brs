sub init()
    m.bg = m.top.findNode("bg")
    m.header = m.top.findNode("header")
    m.label = m.top.findNode("label")
    m.desc = m.top.findNode("desc")
    m.value = m.top.findNode("value")
    m.toggle = m.top.findNode("toggle")
    m.track = m.top.findNode("track")
    m.knob = m.top.findNode("knob")
    m.theme = m.global.theme
end sub

sub render()
    c = m.top.itemContent
    if c = invalid then return
    isHeader = c.kind = "header"
    m.header.visible = isHeader
    m.header.text = c.label
    m.label.visible = not isHeader
    m.desc.visible = not isHeader
    m.label.text = c.label
    m.desc.text = c.desc
    if c.desc = "" then m.label.translation = [22, 22] else m.label.translation = [22, 10]
    m.value.visible = c.kind = "value" or c.kind = "info"
    m.value.text = c.value
    m.toggle.visible = c.kind = "toggle"
    if c.kind = "toggle"
        if c.on
            m.track.blendColor = m.theme.accent
            m.knob.translation = [41, 3]
            m.knob.blendColor = m.theme.onAccent
        else
            m.track.blendColor = "0x55555CFF"
            m.knob.translation = [3, 3]
            m.knob.blendColor = "0xFFFFFFFF"
        end if
    end if
    restyle()
end sub

sub restyle()
    c = m.top.itemContent
    if c = invalid then return
    if c.kind = "header"
        m.bg.visible = false
        return
    end if
    m.bg.visible = true
    f = effFocus()
    if f > 0.5
        m.bg.blendColor = m.theme.focusBg
        m.label.color = m.theme.focusText
        m.desc.color = "0x333333FF"
        m.value.color = "0x333333FF"
    else
        m.bg.blendColor = m.theme.surface
        m.label.color = m.theme.text
        m.desc.color = m.theme.textSecondary
        m.value.color = m.theme.textSecondary
    end if
    if c.kind = "info" then m.bg.blendColor = m.theme.surface
    if c.kind = "info" then m.label.color = m.theme.text
end sub

' Focus amount, but 0 when the containing list/grid doesn't have focus.
function effFocus() as Float
    t = m.top
    if t.rowListHasFocus or t.gridHasFocus or t.listHasFocus then return t.focusPercent
    return 0
end function
