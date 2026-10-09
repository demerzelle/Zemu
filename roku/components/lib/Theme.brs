' Port of Theme.kt: preset themes and the palette derived from accent + background.

function THEME_PRESETS() as Object
    return [
        { id: "CLASSIC", label: "Zemu Neon", accent: "39FF14", bg: "07090A" }
        { id: "CRIMSON", label: "Crimson", accent: "E50914", bg: "0A0A0E" }
        { id: "OLED", label: "OLED Black", accent: "E50914", bg: "000000" }
        { id: "OCEAN", label: "Ocean Blue", accent: "2F80ED", bg: "070B14" }
        { id: "ARCTIC", label: "Arctic", accent: "22D3EE", bg: "0A1218" }
        { id: "EMERALD", label: "Emerald", accent: "10B981", bg: "06100C" }
        { id: "PURPLE", label: "Royal Purple", accent: "8B5CF6", bg: "0C0814" }
        { id: "ROSE", label: "Rose", accent: "EC4899", bg: "12070D" }
        { id: "SUNSET", label: "Sunset", accent: "F97316", bg: "120A06" }
        { id: "GOLD", label: "Gold", accent: "EAB308", bg: "0E0C05" }
        { id: "SLATE", label: "Slate", accent: "94A3B8", bg: "0F1115" }
    ]
end function

function ACCENT_CHOICES() as Object
    return ["39FF14", "E50914", "2F80ED", "22D3EE", "10B981", "8B5CF6", "EC4899", "F97316", "EAB308", "94A3B8", "FFFFFF", "FF4D6D", "00E5A8", "FFB703"]
end function

function BACKGROUND_CHOICES() as Object
    return ["07090A", "000000", "0A0A0E", "070B14", "0A1218", "06100C", "0C0814", "12070D", "120A06", "0E0C05", "0F1115", "1A1A2E"]
end function

function hexByte(h as String) as Integer
    return Val(h, 16)
end function

function rgbHex(r as Integer, g as Integer, b as Integer) as String
    toHex = function(v as Integer) as String
        if v < 0 then v = 0
        if v > 255 then v = 255
        digits = "0123456789ABCDEF"
        return Mid(digits, Int(v / 16) + 1, 1) + Mid(digits, (v MOD 16) + 1, 1)
    end function
    return toHex(r) + toHex(g) + toHex(b)
end function

function lerpHex(a as String, b as String, t as Float) as String
    r = hexByte(Mid(a, 1, 2)) + (hexByte(Mid(b, 1, 2)) - hexByte(Mid(a, 1, 2))) * t
    g = hexByte(Mid(a, 3, 2)) + (hexByte(Mid(b, 3, 2)) - hexByte(Mid(a, 3, 2))) * t
    bl = hexByte(Mid(a, 5, 2)) + (hexByte(Mid(b, 5, 2)) - hexByte(Mid(a, 5, 2))) * t
    return rgbHex(Int(r + 0.5), Int(g + 0.5), Int(bl + 0.5))
end function

function luminance(h as String) as Float
    lin = function(c as Integer) as Float
        v = c / 255.0
        if v <= 0.03928 then return v / 12.92
        return ((v + 0.055) / 1.055) ^ 2.4
    end function
    return 0.2126 * lin(hexByte(Mid(h, 1, 2))) + 0.7152 * lin(hexByte(Mid(h, 3, 2))) + 0.0722 * lin(hexByte(Mid(h, 5, 2)))
end function

' SceneGraph colors are "0xRRGGBBAA".
function sgColor(hex as String, alpha = "FF" as String) as String
    return "0x" + hex + alpha
end function

function buildTheme(settings as Object) as Object
    accent = "39FF14"
    bg = "07090A"
    if settings.theme = "CUSTOM"
        accent = UCase(tostr(settings.customAccent))
        bg = UCase(tostr(settings.customBackground))
    else
        for each p in THEME_PRESETS()
            if p.id = settings.theme
                accent = p.accent
                bg = p.bg
            end if
        end for
    end if
    onAccent = "FFFFFF"
    if luminance(accent) > 0.45 then onAccent = "07130A"
    return {
        accent: sgColor(accent)
        accentHex: accent
        onAccent: sgColor(onAccent)
        bg: sgColor(bg)
        bgHex: bg
        surface: sgColor(lerpHex(bg, "FFFFFF", 0.07))
        surfaceHigh: sgColor(lerpHex(bg, "FFFFFF", 0.14))
        surfaceHighA: sgColor(lerpHex(bg, "FFFFFF", 0.14), "E6")
        text: "0xFFFFFFFF"
        textSecondary: "0xB8B8C2FF"
        textMuted: "0x80808CFF"
        imdb: "0xF5C518FF"
        match: "0x46D369FF"
        cached: "0xFFC94DFF"
        info: "0x5AA9FFFF"
        focusBg: "0xFFFFFFFF"
        focusText: "0x000000FF"
    }
end function
