sub init()
    m.bg = m.top.findNode("bg")
    m.box = m.top.findNode("box")
    m.check = m.top.findNode("check")
    m.label = m.top.findNode("label")
    m.trailing = m.top.findNode("trailing")
end sub
sub render()
    c = m.top.itemContent
    if c = invalid then return
    m.label.text = c.label
    m.trailing.text = c.trailing
    if c.checked <> invalid then m.check.visible = c.checked
    m.box.visible = c.multi = true
    if c.multi <> true
        m.label.translation = [18, 0]
        m.check.translation = [516, 13]
        m.trailing.translation = [330, 0]
    end if
    if not m.observing = true
        c.observeField("checked", "render")
        m.observing = true
    end if
    restyle()
end sub
sub restyle()
    t = m.global.theme
    f = effFocus()
    on = f > 0.5
    if on
        m.bg.blendColor = t.focusBg
        m.bg.opacity = 1
        m.label.color = t.focusText
        m.trailing.color = "0x333333FF"
        m.check.blendColor = t.focusText
        m.box.blendColor = t.focusText
    else
        m.bg.blendColor = t.surfaceHigh
        m.bg.opacity = 0.0
        m.label.color = t.text
        m.trailing.color = t.textMuted
        m.check.blendColor = t.accent
        m.box.blendColor = t.textMuted
    end if
end sub
  
' Focus amount, but 0 when the containing list/grid doesn't have focus.
function effFocus() as Float
    t = m.top
    if t.rowListHasFocus or t.gridHasFocus or t.listHasFocus or t.itemHasFocus then return t.focusPercent
    return 0
end function
