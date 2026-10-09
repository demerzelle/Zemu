sub init()
    m.bg = m.top.findNode("bg")
    m.label = m.top.findNode("label")
    m.timer = m.top.findNode("timer")
    m.timer.observeField("fire", "hide")
    m.top.visible = false
end sub
sub show()
    if m.top.text = "" then return
    m.label.text = m.top.text
    w = m.label.boundingRect().width + 48
    if w > 900 then w = 900
    m.label.width = w - 48
    m.bg.width = w
    m.bg.blendColor = "0x2A2A30F0"
    m.top.translation = [(1280 - w) / 2, 620]
    m.top.visible = true
    m.timer.control = "stop"
    m.timer.control = "start"
end sub
sub hide()
    m.top.visible = false
    m.top.text = ""
end sub
  