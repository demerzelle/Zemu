sub init()
    m.backdrop = m.top.findNode("backdrop")
    m.imgA = m.top.findNode("imgA")
    m.imgB = m.top.findNode("imgB")
    m.gradLeft = m.top.findNode("gradLeft")
    m.gradBottom = m.top.findNode("gradBottom")
    m.info = m.top.findNode("info")
    m.logo = m.top.findNode("logo")
    m.titleText = m.top.findNode("titleText")
    m.metaLine = m.top.findNode("metaLine")
    m.genres = m.top.findNode("genres")
    m.hintLabel = m.top.findNode("hintLabel")
    m.desc = m.top.findNode("desc")
    m.fade = m.top.findNode("fade")
    m.fadeIn = m.top.findNode("fadeIn")
    m.front = m.imgA
    m.back = m.imgB
    m.imgA.observeField("loadStatus", "onLoaded")
    m.imgB.observeField("loadStatus", "onLoaded")
    m.logo.observeField("loadStatus", "onLogo")
    m.currentId = ""
    layout()
end sub

sub layout()
    t = m.global.theme
    h = m.top.backdropHeight
    aw = m.top.areaWidth
    x = Int(aw * 0.22)
    for each p in [m.imgA, m.imgB]
        p.translation = [x, 0]
        p.width = aw - x
        p.height = h
        p.loadWidth = 960
        p.loadHeight = Int(960 * h / (aw - x))
    end for
    m.gradLeft.width = aw
    m.gradLeft.height = h
    m.gradLeft.blendColor = t.bg
    m.gradBottom.width = aw
    m.gradBottom.height = h + 2
    m.gradBottom.blendColor = t.bg
    m.info.visible = m.top.mode = "home" and m.top.showInfo and m.top.meta <> invalid and m.top.meta.id <> invalid
end sub

sub onMeta()
    meta = m.top.meta
    if meta = invalid or meta.id = invalid then return
    m.info.visible = m.top.mode = "home" and m.top.showInfo
    if meta.id <> m.currentId
        m.currentId = meta.id
        uri = meta.background
        if uri = invalid or uri = "" then uri = meta.poster
        if uri <> m.front.uri
            ' load into the hidden poster, then cross-fade
            m.back.opacity = 0
            m.back.uri = uri
        end if
    end if
    renderInfo()
end sub

sub onLoaded(e as Object)
    p = e.getRoSGNode()
    if p.isSameNode(m.back) and p.loadStatus = "ready"
        m.fadeIn.fieldToInterp = p.id + ".opacity"
        m.fade.control = "start"
        old = m.front
        m.front = m.back
        m.back = old
        ' keep the old image underneath until the new one is opaque
        m.backdrop.removeChild(m.front)
        m.backdrop.insertChild(m.front, 1)
    end if
end sub

sub onLogo()
    if m.logo.loadStatus = "failed"
        m.logo.visible = false
        m.titleText.visible = true
        positionInfo()
    else if m.logo.loadStatus = "ready"
        positionInfo()
    end if
end sub

sub renderInfo()
    meta = m.top.meta
    if meta = invalid or meta.id = invalid or not m.info.visible then return
    m.titleText.text = meta.name
    logo = meta.logo
    if logo <> invalid and logo <> ""
        m.logo.visible = true
        m.titleText.visible = false
        if m.logo.uri <> logo then m.logo.uri = logo
    else
        m.logo.visible = false
        m.logo.uri = ""
        m.titleText.visible = true
    end if
    m.metaLine.meta = meta
    m.metaLine.match = m.top.match
    g = meta.genres
    if g <> invalid and g.Count() > 0 then m.genres.text = joinArr(arrTake(g, 4), "  •  ") else m.genres.text = ""
    m.hintLabel.text = m.top.hint
    m.desc.text = meta.description
    positionInfo()
end sub

sub positionInfo()
    ' logo box is 107px tall (80dp), bottom-aligned
    logoH = 107
    if m.logo.loadStatus = "ready"
        fitLogo(m.logo, 560, logoH, 0)
    else
        m.logo.width = 560
        m.logo.height = logoH
    end if
    if m.titleText.visible
        th = m.titleText.boundingRect().height
        m.titleText.translation = [0, logoH - th]
    end if
    y = logoH + 13
    m.metaLine.translation = [0, y]
    y = y + 32
    gw = 0
    if m.genres.text <> ""
        m.genres.translation = [0, y]
        gw = m.genres.boundingRect().width + 40
    end if
    m.hintLabel.translation = [gw, y + 2]
    y = y + 34
    m.desc.translation = [0, y]
end sub
