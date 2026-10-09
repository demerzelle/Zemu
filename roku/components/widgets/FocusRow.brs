sub init()
    m.items = m.top.findNode("items")
    m.clip = m.top.findNode("clip")
    m.top.focusable = true
    m.top.observeField("focusedChild", "onFocus")
    m.offset = 0
end sub

' Children are added to the inner "items" group via addItem() / clearItems() (callFunc).
function addItem(node as Object) as Object
    m.items.appendChild(node)
    node.observeField("width", "onChildResized")
    doLayout()
    return node
end function

function clearItems(_ = invalid as Dynamic) as Object
    m.items.removeChildrenIndex(m.items.getChildCount(), 0)
    m.top.focusIndex = 0
    m.offset = 0
    m.items.translation = [0, 0]
    return invalid
end function

function itemCount(_ = invalid as Dynamic) as Integer
    return m.items.getChildCount()
end function

function getItem(i as Integer) as Object
    return m.items.getChild(i)
end function

sub onChildResized()
    doLayout()
end sub

sub doLayout()
    x = 0
    h = 0
    for i = 0 to m.items.getChildCount() - 1
        c = m.items.getChild(i)
        if c.visible
            c.translation = [x, 0]
            w = c.width
            if w = invalid or w = 0 then w = c.boundingRect().width
            x = x + w + m.top.spacing
            ch = c.height
            if ch = invalid or ch = 0 then ch = c.boundingRect().height
            if ch > h then h = ch
        end if
    end for
    m.totalWidth = x - m.top.spacing
    m.top.height = h
    if m.top.maxWidth > 0
        m.clip.clippingRect = [-20, -20, m.top.maxWidth + 40, h + 40]
    end if
    scrollToFocus()
end sub

sub onFocus()
    if m.top.hasFocus() and m.items.getChildCount() > 0
        idx = m.top.focusIndex
        if idx >= m.items.getChildCount() then idx = m.items.getChildCount() - 1
        c = m.items.getChild(idx)
        if not c.visible then idx = firstVisible()
        m.top.focusIndex = idx
        m.items.getChild(idx).setFocus(true)
        scrollToFocus()
    end if
end sub

function firstVisible() as Integer
    for i = 0 to m.items.getChildCount() - 1
        if m.items.getChild(i).visible then return i
    end for
    return 0
end function

sub scrollToFocus()
    if m.top.maxWidth <= 0 or m.items.getChildCount() = 0 then return
    idx = m.top.focusIndex
    if idx >= m.items.getChildCount() then return
    c = m.items.getChild(idx)
    cx = c.translation[0]
    w = c.width
    if w = invalid or w = 0 then w = c.boundingRect().width
    if cx - m.offset < 0
        m.offset = cx
    else if cx + w - m.offset > m.top.maxWidth
        m.offset = cx + w - m.top.maxWidth
    end if
    if m.offset < 0 then m.offset = 0
    m.items.translation = [-m.offset, 0]
end sub

function moveFocus(delta as Integer) as Boolean
    i = m.top.focusIndex + delta
    while i >= 0 and i < m.items.getChildCount()
        c = m.items.getChild(i)
        if c.visible and c.focusable
            m.top.focusIndex = i
            c.setFocus(true)
            scrollToFocus()
            return true
        end if
        i = i + delta
    end while
    return false
end function

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "right" then return moveFocus(1)
    if key = "left" then return moveFocus(-1)
    return false
end function
