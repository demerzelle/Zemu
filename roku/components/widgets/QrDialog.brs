sub init()
    m.top.findNode("bg").blendColor = m.global.theme.surface
    m.top.focusable = true
end sub

sub render()
    m.top.findNode("titleLabel").text = m.top.title
    m.top.findNode("msg").text = m.top.message
    m.top.findNode("urlLabel").text = m.top.url
    m.top.findNode("qr").uri = "https://api.qrserver.com/v1/create-qr-code/?size=280x280&margin=0&data=" + urlEnc(m.top.url)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and (key = "OK" or key = "back")
        m.top.closed = true
    end if
    return true
end function
