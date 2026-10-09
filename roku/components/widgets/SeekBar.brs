sub init()
    m.track = m.top.findNode("track")
    m.fill = m.top.findNode("fill")
    m.thumb = m.top.findNode("thumb")
    m.elapsed = m.top.findNode("elapsed")
    m.total = m.top.findNode("total")
    m.fill.color = m.global.theme.accent
    render()
end sub

sub render()
    w = m.top.barWidth
    m.track.width = w
    m.total.width = w
    d = m.top.duration
    p = m.top.position
    frac = 0
    if d > 0 then frac = p / d
    if frac < 0 then frac = 0
    if frac > 1 then frac = 1
    m.fill.width = w * frac
    h = 6
    if m.top.highlight then h = 9
    m.track.height = h
    m.fill.height = h
    m.thumb.visible = m.top.highlight
    m.thumb.translation = [w * frac - 11, h / 2 - 11]
    m.elapsed.translation = [0, h + 12]
    m.total.translation = [0, h + 12]
    m.elapsed.text = formatTime(p)
    if d > 0 then m.total.text = formatTime(d) else m.total.text = ""
end sub
