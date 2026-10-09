sub init()
    m.panel = m.top.findNode("panel")
    m.panelBg = m.top.findNode("panelBg")
    m.list = m.top.findNode("list")
    m.titleLabel = m.top.findNode("titleLabel")
    m.messageLabel = m.top.findNode("messageLabel")
    m.hint = m.top.findNode("hint")
    m.list.observeField("itemSelected", "onSelected")
    m.top.observeField("focusedChild", "onFocus")
end sub

sub build()
    t = m.global.theme
    m.panelBg.blendColor = t.surface
    m.titleLabel.text = m.top.title
    y = 78
    if m.top.message <> ""
        m.messageLabel.text = m.top.message
        m.messageLabel.visible = true
        y = 78 + m.messageLabel.boundingRect().height + 14
    else
        m.messageLabel.visible = false
    end if
    content = CreateObject("roSGNode", "ContentNode")
    focusIdx = 0
    opts = m.top.options
    for i = 0 to opts.Count() - 1
        o = opts[i]
        c = content.createChild("ContentNode")
        c.addFields({ optId: tostr(o.id), label: tostr(o.label), trailing: tostr(o.trailing), checked: bool(o.checked), multi: m.top.multiSelect })
        if tostr(o.id) = m.top.focusId or (m.top.focusId = "" and bool(o.checked) and not m.top.multiSelect) then focusIdx = i
    end for
    if m.top.showClear
        c = content.createChild("ContentNode")
        c.addFields({ optId: "__clear", label: "Clear selection", trailing: "", checked: false, multi: false })
    end if
    rows = content.getChildCount()
    visible = rows
    if visible > 8 then visible = 8
    m.list.numRows = visible
    m.list.translation = [32, y]
    m.list.content = content
    m.list.jumpToItem = focusIdx
    listH = visible * 56
    m.hint.translation = [32, y + listH + 8]
    if m.top.multiSelect then m.hint.text = "OK to toggle · Back when done" else m.hint.text = "OK to choose · Back to cancel"
    h = y + listH + 50
    m.panelBg.width = 624
    m.panelBg.height = h
    m.panel.translation = [(1280 - 624) / 2, (720 - h) / 2]
end sub

sub onFocus()
    if m.top.hasFocus() then m.list.setFocus(true)
end sub

function setChecked(params as Object) as Object
    content = m.list.content
    if content = invalid then return invalid
    for i = 0 to content.getChildCount() - 1
        c = content.getChild(i)
        if params.DoesExist(c.optId) then c.checked = params[c.optId]
    end for
    return invalid
end function

sub onSelected()
    c = m.list.content.getChild(m.list.itemSelected)
    if c.optId = "__clear"
        for i = 0 to m.list.content.getChildCount() - 1
            m.list.content.getChild(i).checked = false
        end for
        m.top.cleared = true
        return
    end if
    if m.top.multiSelect
        c.checked = not c.checked
        m.top.chosen = c.optId
    else
        m.top.chosen = c.optId
        m.top.closed = true
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "back"
        m.top.closed = true
        return true
    end if
    ' swallow everything else so focus can't leave the dialog
    return true
end function
