sub init()
    m.card = m.top.findNode("card")
    m.bg = m.top.findNode("bg")
    m.fallback = m.top.findNode("fallback")
    m.image = m.top.findNode("image")
    m.shade = m.top.findNode("shade")
    m.landInfo = m.top.findNode("landInfo")
    m.landTitle = m.top.findNode("landTitle")
    m.landSub = m.top.findNode("landSub")
    m.progressTrack = m.top.findNode("progressTrack")
    m.progressBar = m.top.findNode("progressBar")
    m.rating = m.top.findNode("rating")
    m.ratingBg = m.top.findNode("ratingBg")
    m.ratingText = m.top.findNode("ratingText")
    m.watchedBadge = m.top.findNode("watchedBadge")
    m.watchedBg = m.top.findNode("watchedBg")
    m.watchedText = m.top.findNode("watchedText")
    m.matchBadge = m.top.findNode("matchBadge")
    m.matchBg = m.top.findNode("matchBg")
    m.matchText = m.top.findNode("matchText")
    m.ring = m.top.findNode("ring")
    t = m.global.theme
    m.bg.blendColor = t.surface
    m.watchedBg.blendColor = t.accent
    m.watchedText.color = t.onAccent
    m.progressBar.color = t.accent
    m.ring.blendColor = "0xFFFFFFFF"
    m.w = 0
    m.h = 0
end sub

sub sizeChanged()
    w = m.top.width
    h = m.top.height
    if w = 0 or h = 0 or (w = m.w and h = m.h) then return
    m.w = w
    m.h = h
    m.bg.width = w
    m.bg.height = h
    m.image.width = w
    m.image.height = h
    m.image.loadWidth = w
    m.image.loadHeight = h
    m.fallback.width = w - 16
    m.fallback.height = h - 16
    m.fallback.translation = [8, 8]
    m.shade.width = w
    m.shade.height = h
    m.ring.width = w + 8
    m.ring.height = h + 8
    m.ring.translation = [-4, -4]
    m.card.scaleRotateCenter = [w / 2, h / 2]
    m.landTitle.width = w - 26
    m.landSub.width = w - 26
    m.progressTrack.width = w - 26
    layoutBadges()
    render()
end sub

sub render()
    c = m.top.itemContent
    if c = invalid or m.w = 0 then return
    meta = c.meta
    if meta = invalid then return
    landscape = c.style = "landscape"
    m.fallback.text = meta.name
    if landscape
        uri = meta.background
        if uri = "" then uri = meta.poster
        m.image.uri = uri
        m.shade.visible = true
        m.landInfo.visible = true
        m.landTitle.text = meta.name
        m.landSub.text = c.subtitle
        p = c.progress
        hasP = p > 0
        m.progressTrack.visible = hasP
        m.progressBar.visible = hasP
        if p > 1 then p = 1
        m.progressBar.width = (m.w - 26) * p
        y = m.h - 13
        if hasP
            y = y - 10
            m.progressTrack.translation = [13, m.h - 15]
            m.progressBar.translation = [13, m.h - 15]
        end if
        if c.subtitle <> ""
            m.landSub.translation = [13, y - 21]
            y = y - 21
        end if
        m.landTitle.translation = [13, y - 24]
        m.landSub.visible = c.subtitle <> ""
    else
        m.image.uri = meta.poster
        m.shade.visible = false
        m.landInfo.visible = false
    end if
    r = meta.imdbRating
    if r <> invalid and r <> "" and not landscape
        m.ratingText.text = r
        m.rating.visible = true
    else
        m.rating.visible = false
    end if
    m.watchedBadge.visible = c.watched
    if c.badge <> ""
        m.matchText.text = c.badge
        m.matchBadge.visible = true
    else
        m.matchBadge.visible = false
    end if
    layoutBadges()
end sub

sub layoutBadges()
    if m.w = 0 then return
    rw = m.ratingText.boundingRect().width + 30
    m.ratingBg.width = rw
    m.rating.translation = [8, m.h - 30]
    ww = m.watchedText.boundingRect().width + 14
    m.watchedBg.width = ww
    m.watchedBadge.translation = [8, 8]
    mw = m.matchText.boundingRect().width + 14
    m.matchBg.width = mw
    m.matchBadge.translation = [m.w - mw - 8, 8]
end sub

sub onFocusPercent()
    f = effFocus()
    s = 1 + 0.1 * f
    if m.top.itemContent <> invalid and m.top.itemContent.style = "landscape" then s = 1 + 0.08 * f
    m.card.scale = [s, s]
    m.ring.opacity = f
end sub

' Focus amount, but 0 when the containing list/grid doesn't have focus.
function effFocus() as Float
    t = m.top
    if t.rowListHasFocus or t.gridHasFocus or t.listHasFocus or t.itemHasFocus then return t.focusPercent
    return 0
end function
