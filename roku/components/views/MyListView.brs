sub init()
    m.grid = m.top.findNode("grid")
    m.empty = m.top.findNode("empty")
    m.grid.observeField("itemSelected", "onSelected")
    m.top.observeField("focusedChild", "onFocusChange")
    m.global.observeField("userVersion", "render")
    render()
end sub

sub render()
    content = CreateObject("roSGNode", "ContentNode")
    watched = m.global.watched
    for each e in m.global.myList
        n = content.createChild("MetaNode")
        n.meta = expandMeta(e)
        n.watched = watched.DoesExist(e.i)
    end for
    idx = m.grid.itemFocused
    m.grid.content = content
    has = content.getChildCount() > 0
    m.grid.visible = has
    m.empty.visible = not has
    if has and idx > 0
        if idx >= content.getChildCount() then idx = content.getChildCount() - 1
        m.grid.jumpToItem = idx
    end if
end sub

sub onFocusChange()
    if m.top.hasFocus() and m.grid.visible then m.grid.setFocus(true)
end sub

sub onSelected()
    c = m.grid.content.getChild(m.grid.itemSelected)
    if c <> invalid then m.top.navigateTo = { to: "details", meta: c.meta }
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and key = "options" and m.grid.hasFocus()
        c = m.grid.content.getChild(m.grid.itemFocused)
        if c <> invalid then m.top.getScene().callFunc("cardMenu", c.meta)
        return true
    end if
    return false
end function
