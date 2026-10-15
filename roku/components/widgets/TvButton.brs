sub init()
    m.body = m.top.findNode("body")
    m.bg = m.top.findNode("bg")
    m.iconPoster = m.top.findNode("iconPoster")
    m.label = m.top.findNode("label")
    m.top.focusable = true
    m.top.observeField("focusedChild", "restyle")
    m.focused = false
    layout()
end sub

sub layout()
    v = m.top.variant
    size = m.top.fontSize
    m.label.font.size = size
    m.label.text = m.top.text
    iconUri = m.top.icon
    if v = "chip" and m.top.checked then iconUri = "pkg:/images/ic_check.png"
    hasIcon = iconUri <> ""
    if v = "icon"
        h = m.top.iconSize
        w = h
        m.bg.uri = "pkg:/images/circle.png"
        m.iconPoster.uri = m.top.icon
        isz = Int(h * 0.48)
        m.iconPoster.width = isz
        m.iconPoster.height = isz
        m.iconPoster.translation = [(w - isz) / 2, (h - isz) / 2]
        m.label.visible = false
    else
        m.label.visible = true
        padX = 29
        padY = 13
        if v = "chip"
            padX = 21
            padY = 9
            m.bg.uri = "pkg:/images/pill.9.png"
        else
            m.bg.uri = "pkg:/images/rr8.9.png"
        end if
        textW = m.label.boundingRect().width
        h = size + padY * 2 + 6
        x = padX
        if hasIcon
            m.iconPoster.uri = iconUri
            m.iconPoster.width = size + 6
            m.iconPoster.height = size + 6
            m.iconPoster.translation = [padX, (h - size - 6) / 2]
            x = padX + size + 6 + 11
        else
            m.iconPoster.uri = ""
        end if
        w = x + textW + padX
        if w < m.top.minWidth then w = m.top.minWidth
        m.label.translation = [x, 0]
        m.label.height = h
    end if
    m.bg.width = w
    m.bg.height = h
    m.top.width = w
    m.top.height = h
    m.body.scaleRotateCenter = [w / 2, h / 2]
    restyle()
end sub

sub restyle()
    t = m.global.theme
    if t = invalid then return
    focused = m.top.hasFocus()
    v = m.top.variant
    on = m.top.primary or ((v = "chip" or v = "icon") and m.top.checked)
    if focused
        m.bg.blendColor = t.focusBg
        fg = t.focusText
        m.bg.opacity = 1
    else if on
        m.bg.blendColor = t.accent
        fg = t.onAccent
        m.bg.opacity = 1
    else
        m.bg.blendColor = t.surfaceHigh
        fg = t.text
        m.bg.opacity = 0.92
    end if
    m.label.color = fg
    m.iconPoster.blendColor = fg
    s = 1.0
    if focused
        s = 1.05
        if v = "icon" then s = 1.1
    end if
    m.body.scale = [s, s]
    m.top.opacity = 1
    if m.top.dim and not focused then m.top.opacity = 0.6
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and key = "OK"
        ' Report the press after this key event finishes: handlers often rebuild the row this
        ' button lives in, and removing the focused node inside its own key handler loses focus.
        if m.pressTimer = invalid
            m.pressTimer = CreateObject("roSGNode", "Timer")
            m.pressTimer.duration = 0.01
            m.pressTimer.observeField("fire", "firePressed")
        end if
        m.pressTimer.control = "start"
        return true
    end if
    return false
end function

sub firePressed()
    m.top.pressed = true
end sub
