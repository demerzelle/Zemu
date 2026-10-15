' Port of Theme.kt: preset themes and the palette derived from accent + background.

' The Android palettes (ThemePreset), dark mode.
function THEME_PRESETS() as Object
    return [
        { id: "CLASSIC", label: "Zemu Neon", accent: "39FF14", bg: "07090A" }
        { id: "CRIMSON", label: "Crimson", accent: "E50914", bg: "0A0A0E" }
        { id: "OCEAN", label: "Ocean Blue", accent: "2F80ED", bg: "070B14" }
        { id: "PURPLE", label: "Royal Purple", accent: "8B5CF6", bg: "0C0814" }
        { id: "SUNSET", label: "Sunset", accent: "F97316", bg: "120A06" }
        { id: "OLED", label: "OLED Black", accent: "E6E6E6", bg: "000000" }
        { id: "HIGH_CONTRAST", label: "High Contrast", accent: "FFE600", bg: "000000" }
    ]
end function

' Palettes the Android app removed map to their nearest one (as in ThemePreset.RENAMED).
function themePresetId(id as String) as String
    renamed = { ARCTIC: "OCEAN", EMERALD: "CLASSIC", ROSE: "PURPLE", GOLD: "SUNSET", SLATE: "OCEAN" }
    if renamed.DoesExist(id) then return renamed[id]
    return id
end function

' Animated themes from the Android app (DynamicTheme), drawn as a wallpaper with their own colors.
' fx: a particle layer that slides one tile per loop (dir: "down", "up" or "left"; sec per loop).
function ANIMATED_THEMES() as Object
    return [
        { id: "NONE", label: "Off" }
        { id: "CYBERPUNK", label: "Cyberpunk", accent: "FF2A6D", bg: "0B0518", wall: "cyberpunk", fx: "rain", dir: "down", sec: 2 }
        { id: "FIREFLIES", label: "Fireflies", accent: "FACC15", bg: "070A06", wall: "fireflies", fx: "fireflies", dir: "up", sec: 30 }
        { id: "MATRIX", label: "Matrix", accent: "22C55E", bg: "000500", wall: "matrix", fx: "matrix", dir: "down", sec: 6 }
        { id: "SAKURA", label: "Sakura", accent: "F472B6", bg: "120810", wall: "sakura", fx: "petals", dir: "down", sec: 18 }
        { id: "ETHEREAL", label: "Ethereal · Aurora", accent: "C4B5FD", bg: "0A0918", wall: "ethereal", fx: "sparkles", dir: "up", sec: 40 }
        { id: "Y2K", label: "PS2 · Y2K", accent: "6FB4FF", bg: "00020A", wall: "y2k", fx: "motes", dir: "up", sec: 35 }
        { id: "ACIDWAVE", label: "Acidwave", accent: "C8FF00", bg: "0A0A0B", wall: "acidwave" }
        { id: "RETRO", label: "Cybercore", accent: "000080", bg: "008080", wall: "retro" }
        { id: "LIQUID", label: "Liquid Glass", accent: "0A84FF", bg: "0B1226", wall: "liquid" }
        { id: "SIXTEEN", label: "16-Bit", accent: "B8A9F0", bg: "101848", wall: "sixteen", fx: "clouds", dir: "left", sec: 60 }
        { id: "SPACE", label: "Outer Space", accent: "7CC4FF", bg: "05060F", wall: "space", fx: "stars", dir: "left", sec: 90 }
        { id: "OCEAN_DEEP", label: "Ocean", accent: "38E1FF", bg: "03203A", wall: "ocean", fx: "bubbles", dir: "up", sec: 14 }
    ]
end function

function animatedTheme(id as String) as Object
    for each d in ANIMATED_THEMES()
        if d.id = id then return d
    end for
    return ANIMATED_THEMES()[0]
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
        presetId = themePresetId(tostr(settings.theme))
        for each p in THEME_PRESETS()
            if p.id = presetId
                accent = p.accent
                bg = p.bg
            end if
        end for
    end if
    ' An animated theme brings its own colors and wallpaper (Android: DynamicTheme.applyTo).
    d = animatedTheme(tostr(settings.dynamicTheme))
    wall = ""
    fx = ""
    if d.fx <> invalid then fx = d.fx
    if d.wall <> invalid
        accent = d.accent
        bg = d.bg
        wall = "pkg:/images/wall_" + d.wall + ".jpg"
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
        wall: wall
        fx: fx
        fxDir: d.dir
        fxSec: d.sec
    }
end function
