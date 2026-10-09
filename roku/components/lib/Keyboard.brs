' On-screen keyboard (StandardKeyboardDialog, themed). The Roku mobile app's keyboard and voice
' typing also work in it. Result: observer callback receives the dialog node; read .text/.buttonSelected.
function showKeyboard(title as String, text as String, buttons as Object, callback as String, message = "" as String) as Object
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = title
    dlg.text = text
    dlg.buttons = buttons
    if message <> "" then dlg.message = [message]
    t = m.global.theme
    p = CreateObject("roSGNode", "RSGPalette")
    p.colors = {
        DialogBackgroundColor: t.surface
        DialogItemColor: t.surfaceHigh
        DialogTextColor: "0xFFFFFFFF"
        DialogFocusColor: "0xFFFFFFFF"
        DialogFocusItemColor: "0x000000FF"
        DialogSecondaryTextColor: t.textSecondary
        DialogSecondaryItemColor: t.accent
        DialogInputFieldColor: t.bg
        DialogKeyboardColor: t.surfaceHigh
        DialogFootprintColor: t.accent
    }
    dlg.palette = p
    dlg.observeField("buttonSelected", callback)
    dlg.observeField("wasClosed", callback)
    m.top.getScene().dialog = dlg
    return dlg
end function

sub closeKeyboard(dlg as Object)
    if dlg <> invalid then dlg.close = true
end sub
