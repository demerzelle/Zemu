sub init()
    m.grid = m.top.findNode("grid")
    m.empty = m.top.findNode("empty")
    m.grid.observeField("itemSelected", "onSelected")
    m.top.observeField("focusedChild", "onFocusChange")
    m.global.observeField("userVersion", "render")
    render()
end sub

sub render()
    ' Sections: My List, then Watch Later (MarkupGrid draws a divider with each section's title).
    content = CreateObject("roSGNode", "ContentNode")
    watched = m.global.watched
    for each sec in [{ title: "", list: m.global.myList }, { title: "Watch Later", list: m.global.watchLater }]
        if sec.list.Count() > 0
            s = content.createChild("ContentNode")
            s.title = sec.title
            for each e in sec.list
                n = s.createChild("MetaNode")
                n.meta = expandMeta(e)
                n.watched = watched.DoesExist(e.i)
            end for
        end if
    end for
    idx = m.grid.itemFocused
    m.grid.content = content
    total = count()
    m.grid.visible = total > 0
    m.empty.visible = total = 0
    if total > 0 and idx > 0
        if idx >= total then idx = total - 1
        m.grid.jumpToItem = idx
    end if
end sub

function count() as Integer
    n = 0
    for i = 0 to m.grid.content.getChildCount() - 1
        n = n + m.grid.content.getChild(i).getChildCount()
    end for
    return n
end function

' The grid's item index counts across sections.
function itemAt(idx as Integer) as Dynamic
    for i = 0 to m.grid.content.getChildCount() - 1
        s = m.grid.content.getChild(i)
        if idx < s.getChildCount() then return s.getChild(idx)
        idx = idx - s.getChildCount()
    end for
    return invalid
end function

sub onFocusChange()
    if m.top.hasFocus() and m.grid.visible then m.grid.setFocus(true)
end sub

sub onSelected()
    c = itemAt(m.grid.itemSelected)
    if c <> invalid then m.top.navigateTo = { to: "details", meta: c.meta }
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and key = "options" and m.grid.hasFocus()
        c = itemAt(m.grid.itemFocused)
        if c <> invalid then m.top.getScene().callFunc("cardMenu", c.meta)
        return true
    end if
    return false
end function
