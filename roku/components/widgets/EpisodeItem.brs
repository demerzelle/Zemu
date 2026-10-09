sub init()
    m.card = m.top.findNode("card")
    m.bg = m.top.findNode("bg")
    m.thumb = m.top.findNode("thumb")
    m.num = m.top.findNode("num")
    m.title = m.top.findNode("title")
    m.date = m.top.findNode("date")
    m.ring = m.top.findNode("ring")
    m.selRing = m.top.findNode("selRing")
    m.watchedBadge = m.top.findNode("watchedBadge")
    t = m.global.theme
    m.bg.blendColor = t.surface
    m.selRing.blendColor = t.accent
    m.top.findNode("watchedBg").blendColor = t.accent
    m.top.findNode("watchedText").color = t.onAccent
end sub

sub render()
    c = m.top.itemContent
    if c = invalid then return
    v = c.video
    m.thumb.uri = v.thumbnail
    label = "E" + v.episode.ToStr()
    if c.selected then label = label + "  ·  Selected"
    m.num.text = label
    m.title.text = v.title
    m.date.text = v.released
    m.selRing.visible = c.selected
    m.watchedBadge.visible = c.watched
end sub

sub onFocusPercent()
    f = effFocus()
    s = 1 + 0.07 * f
    m.card.scale = [s, s]
    m.ring.opacity = f
end sub

' Focus amount, but 0 when the containing list/grid doesn't have focus.
function effFocus() as Float
    t = m.top
    if t.rowListHasFocus or t.gridHasFocus or t.listHasFocus or t.itemHasFocus then return t.focusPercent
    return 0
end function
