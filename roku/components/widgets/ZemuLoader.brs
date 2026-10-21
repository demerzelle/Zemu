' 60 frames at 30 fps (a 2 s loop). Sized for the 1280x720 UI, which Roku scales to the TV.
sub init()
    m.frame = m.top.findNode("frame")
    m.tick = m.top.findNode("tick")
    m.i = 0
    m.tick.observeField("fire", "onTick")
    m.top.observeField("visible", "onVisible")
    onVisible()
end sub

sub onVisible()
    if m.top.visible then m.tick.control = "start" else m.tick.control = "stop"
end sub

sub onTick()
    m.i = (m.i + 1) mod 60
    n = m.i.ToStr()
    if m.i < 10 then n = "0" + n
    m.frame.uri = "pkg:/images/loader/" + n + ".png"
end sub
