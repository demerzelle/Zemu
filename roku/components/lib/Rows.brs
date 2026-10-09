' Shared RowList setup for MediaRow-style rows (Cards.kt MediaRow): bold title, 48dp left padding, scaling cards.

function POSTER_SIZE() as Object
    return [176, 264]
end function

function LANDSCAPE_SIZE() as Object
    return [333, 187]
end function

sub setupRowList(rl as Object, width as Integer)
    t = m.global.theme
    rl.itemComponentName = "PosterItem"
    rl.itemSize = [width, 330]
    rl.rowItemSpacing = [[19, 0]]
    rl.itemSpacing = [0, 6]
    rl.showRowLabel = [true]
    rl.rowLabelOffset = [[64, 10]]
    rl.rowLabelColor = t.text
    f = CreateObject("roSGNode", "Font")
    f.uri = "font:BoldSystemFontFile"
    f.size = 24
    rl.rowLabelFont = f
    rl.focusXOffset = [64]
    rl.rowFocusAnimationStyle = "floatingFocus"
    rl.vertFocusAnimationStyle = "fixedFocus"
    rl.drawFocusFeedback = false
    rl.wrapDividerHeight = 0
end sub

' Sets row sizes from each row's style (first child), then the content.
sub setRows(rl as Object, root as Object)
    sizes = []
    heights = []
    for i = 0 to root.getChildCount() - 1
        row = root.getChild(i)
        style = "poster"
        if row.getChildCount() > 0 then style = row.getChild(0).style
        if style = "landscape"
            sizes.Push(LANDSCAPE_SIZE())
            heights.Push(187 + 72)
        else
            sizes.Push(POSTER_SIZE())
            heights.Push(264 + 72)
        end if
    end for
    rl.rowItemSize = sizes
    rl.rowHeights = heights
    rl.content = root
end sub

' Meta of the focused card, or invalid.
function focusedMeta(rl as Object) as Dynamic
    f = rl.rowItemFocused
    if f = invalid or rl.content = invalid or f.Count() < 2 then return invalid
    if f[0] < 0 or f[1] < 0 then return invalid
    row = rl.content.getChild(Int(f[0]))
    if row = invalid then return invalid
    item = row.getChild(Int(f[1]))
    if item = invalid then return invalid
    return item.meta
end function

function makeMetaNode(parent as Object, meta as Object, style = "poster" as String) as Object
    n = parent.createChild("MetaNode")
    n.meta = meta
    n.style = style
    return n
end function

' Left-aligns a scaleToFit logo inside a maxW × maxH box, bottom-aligned (TitleLogo in Hero.kt).
sub fitLogo(p as Object, maxW as Float, maxH as Float, baseY as Float)
    bw = p.bitmapWidth
    bh = p.bitmapHeight
    if bw <= 0 or bh <= 0 then return
    s = maxW / bw
    if bh * s > maxH then s = maxH / bh
    p.width = bw * s
    p.height = bh * s
    p.translation = [0, baseY + maxH - bh * s]
end sub
