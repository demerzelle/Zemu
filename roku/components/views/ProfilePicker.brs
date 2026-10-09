sub init()
    m.row = m.top.findNode("row")
    m.colors = ["0xE50914FF", "0x2F80EDFF", "0x10B981FF", "0x8B5CF6FF", "0xF97316FF", "0xEC4899FF", "0xEAB308FF", "0x22D3EEFF"]
    m.items = []
    profiles = m.global.profiles
    n = profiles.Count()
    w = 170
    gap = 40
    total = n * w + (n - 1) * gap
    x = (1280 - total) / 2
    for i = 0 to n - 1
        p = profiles[i]
        g = m.row.createChild("Group")
        g.translation = [x + i * (w + gap), 0]
        g.scaleRotateCenter = [85, 85]
        ring = g.createChild("Poster")
        ring.uri = "pkg:/images/circle_ring.png"
        ring.width = 182
        ring.height = 182
        ring.translation = [-6, -6]
        ring.visible = false
        av = g.createChild("Poster")
        av.uri = "pkg:/images/circle.png"
        av.width = 170
        av.height = 170
        av.blendColor = m.colors[toInt(p.avatar) MOD m.colors.Count()]
        initial = g.createChild("Label")
        initial.text = UCase(Left(p.name, 1))
        initial.width = 170
        initial.height = 170
        initial.horizAlign = "center"
        initial.vertAlign = "center"
        f = CreateObject("roSGNode", "Font")
        f.uri = "font:BoldSystemFontFile"
        f.size = 72
        initial.font = f
        initial.color = "0xFFFFFFFF"
        name = g.createChild("Label")
        name.text = p.name
        name.width = 170
        name.horizAlign = "center"
        name.translation = [0, 190]
        nf = CreateObject("roSGNode", "Font")
        nf.uri = "font:SystemFontFile"
        nf.size = 22
        name.font = nf
        m.items.Push({ g: g, ring: ring, name: name, id: p.id })
    end for
    m.index = 0
    active = m.global.profileId
    for i = 0 to m.items.Count() - 1
        if m.items[i].id = active then m.index = i
    end for
    m.top.focusable = true
    restyle()
end sub

sub restyle()
    for i = 0 to m.items.Count() - 1
        it = m.items[i]
        on = i = m.index
        it.ring.visible = on
        if on then it.g.scale = [1.08, 1.08] else it.g.scale = [1, 1]
        if on then it.name.color = "0xFFFFFFFF" else it.name.color = "0x80808CFF"
    end for
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "left" and m.index > 0
        m.index = m.index - 1
        restyle()
    else if key = "right" and m.index < m.items.Count() - 1
        m.index = m.index + 1
        restyle()
    else if key = "OK"
        m.top.picked = m.items[m.index].id
    end if
    return true
end function
