sub init()
    m.card = m.top.findNode("card")
    m.bg = m.top.findNode("bg")
    m.ring = m.top.findNode("ring")
    m.res = m.top.findNode("res")
    m.hdr = m.top.findNode("hdr")
    m.tag = m.top.findNode("tag")
    m.tagBg = m.top.findNode("tagBg")
    m.tagText = m.top.findNode("tagText")
    m.name = m.top.findNode("name")
    m.specs = m.top.findNode("specs")
    m.audio = m.top.findNode("audio")
    m.subs = m.top.findNode("subs")
    m.subIcon = m.top.findNode("subIcon")
    m.size = m.top.findNode("size")
    m.svc = m.top.findNode("svc")
    m.service = m.top.findNode("service")
    m.addon = m.top.findNode("addon")
    m.theme = m.global.theme
    restyle()
end sub

sub render()
    c = m.top.itemContent
    if c = invalid then return
    m.res.text = c.res
    m.hdr.text = c.hdr
    x = 152
    if c.badge = "best"
        m.tag.visible = true
        m.tagText.text = "BEST FOR THIS TV"
        m.tagText.color = "0x000000FF"
        m.tagBg.uri = "pkg:/images/rr4.9.png"
        m.tagBg.blendColor = m.theme.match
    else if c.badge = "warn"
        m.tag.visible = true
        m.tagText.text = "May not play well"
        m.tagText.color = m.theme.cached
        m.tagBg.uri = "pkg:/images/ring4.9.png"
        m.tagBg.blendColor = "0xFFC94DB3"
    else
        m.tag.visible = false
    end if
    if m.tag.visible
        tw = m.tagText.boundingRect().width + 16
        m.tagBg.width = tw
        x = 152 + tw + 11
    end if
    m.name.translation = [x, 12]
    m.name.width = 900 - x
    m.name.text = c.name
    m.specs.text = c.specs
    m.audio.text = c.audioLangs
    m.subs.text = c.subLangs
    m.subs.visible = c.subLangs <> ""
    m.subIcon.visible = m.subs.visible
    m.size.text = c.size
    m.service.text = c.service + " cached"
    sw = m.service.boundingRect().width + 19
    m.svc.translation = [1128 - sw, 44]
    m.addon.text = c.addon
end sub

sub restyle()
    f = effFocus()
    if f > 0.5
        m.bg.blendColor = m.theme.surfaceHigh
        m.bg.opacity = 1
    else
        m.bg.blendColor = m.theme.surface
        m.bg.opacity = 0.92
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
