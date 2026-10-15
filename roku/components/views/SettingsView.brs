' Port of SettingsScreen.kt (Roku-relevant sections).

sub init()
    m.list = m.top.findNode("list")
    m.list.observeField("itemSelected", "onSelected")
    m.top.observeField("focusedChild", "onFocusChange")
    m.caps = detectCaps()
    build()
end sub

sub onFocusChange()
    if m.top.hasFocus() then m.list.setFocus(true)
end sub

function onOff(b as Boolean) as String
    if b then return "On"
    return "Off"
end function

function langsLabel(list as Object) as String
    if list.Count() = 0 then return "None"
    names = []
    for each l in list
        names.Push(langName(l))
    end for
    return joinArr(names, ", ")
end function

sub build()
    s = m.global.settings
    items = []
    add = function(items as Object, key as String, kind as String, label as String, desc = "" as String, value = "" as String, on = false as Boolean)
        items.Push({ key: key, kind: kind, label: label, desc: desc, value: value, on: on })
    end function

    profiles = m.global.profiles
    current = ""
    for each p in profiles
        if p.id = m.global.profileId then current = p.name
    end for

    add(items, "", "header", "Addons")
    add(items, "addons", "action", "Manage addons", "Install, remove and configure stream, catalog and subtitle addons")
    provider = "Automatic"
    for each a in m.global.addons
        if a.id = s.metaProvider then provider = a.name
    end for
    add(items, "metaProvider", "value", "Metadata provider", "Addon used for title details and the Movies / Series pages", provider)

    add(items, "", "header", "Profiles")
    add(items, "switchProfile", "value", "Switch profile", "Each profile has its own addons, history, My List and settings", current)
    add(items, "addProfile", "action", "Add profile")
    add(items, "renameProfile", "action", "Rename this profile")
    if m.global.profileId <> "default" then add(items, "deleteProfile", "action", "Delete this profile", "Removes its addons, history, My List and settings")
    add(items, "askProfile", "toggle", "Ask who's watching at launch", "Only when there's more than one profile", "", regReadStr(APP_SECTION(), "skipPicker") <> "true")

    add(items, "", "header", "Theme")
    themeLabel = "Custom"
    for each p in THEME_PRESETS()
        if p.id = themePresetId(tostr(s.theme)) then themeLabel = p.label
    end for
    add(items, "theme", "value", "Color theme", "", themeLabel)
    add(items, "dynamicTheme", "value", "Animated theme", "Wallpapers from the Android app, with drifting rain, petals, stars and more. Brings its own colors.", animatedTheme(tostr(s.dynamicTheme)).label)
    if s.theme = "CUSTOM"
        add(items, "customAccent", "value", "Custom accent color", "", "#" + s.customAccent)
        add(items, "customBackground", "value", "Custom background", "", "#" + s.customBackground)
    end if

    add(items, "", "header", "Cached streams")
    add(items, "trustDirectLinks", "toggle", "Treat direct links as cached", "Count plain HTTP streams without debrid markers as cached", "", bool(s.trustDirectLinks))
    sizeLabel = "No limit"
    if toInt(s.maxSizeGb) > 0 then sizeLabel = tostr(s.maxSizeGb) + " GB"
    add(items, "maxSizeGb", "value", "Maximum file size", "Hide streams bigger than this (helps on slower Wi-Fi)", sizeLabel)

    add(items, "", "header", "Languages")
    add(items, "audioLanguages", "value", "Preferred audio", "", langsLabel(s.audioLanguages))
    add(items, "subtitleLanguages", "value", "Preferred subtitles", "", langsLabel(s.subtitleLanguages))
    add(items, "autoSubtitles", "toggle", "Turn on subtitles automatically", "Select a subtitle track in your preferred language when playback starts.", "", bool(s.autoSubtitles))

    add(items, "", "header", "Playback")
    add(items, "autoplayNext", "toggle", "Autoplay next episode", "Near the end of an episode, count down and start the next one.", "", bool(s.autoplayNext))
    add(items, "autoplayCountdownSec", "value", "Next episode countdown", "", tostr(s.autoplayCountdownSec) + " s")
    add(items, "stillWatchingPrompt", "toggle", "Ask " + Chr(34) + "Are you still watching?" + Chr(34), "Pause and check in after several episodes play without touching the remote.", "", bool(s.stillWatchingPrompt))
    add(items, "stillWatchingEpisodes", "value", "Ask after", "", tostr(s.stillWatchingEpisodes) + " episodes")
    add(items, "skipIntroButton", "toggle", "Skip intro button", "Show " + Chr(34) + "Skip intro" + Chr(34) + " / " + Chr(34) + "Skip recap" + Chr(34) + " from TheIntroDB and AniSkip", "", bool(s.skipIntroButton))
    add(items, "avoidDolbyVision", "toggle", "Play Dolby Vision as HDR10", "Prefer non-Dolby Vision releases when ranking streams", "", bool(s.avoidDolbyVision))
    add(items, "clearHistory", "action", "Clear watch history", "Resets Continue Watching and recommendations")

    add(items, "", "header", "This TV")
    c = m.caps
    res = tostr(c.maxRes) + "p"
    if c.maxRes >= 2160 then res = "4K"
    add(items, "", "info", "Max output", "Used to pick the " + Chr(34) + "Best for this TV" + Chr(34) + " stream", res)
    add(items, "", "info", "HEVC / H.265", "", yesNo(c.hevc))
    add(items, "", "info", "AV1", "", yesNo(c.av1))
    add(items, "", "info", "HDR10 / Dolby Vision", "", yesNo(c.hdr10) + " / " + yesNo(c.dolbyVision))
    add(items, "", "info", "Dolby Digital+ / DTS", "", yesNo(c.audio["DD+"]) + " / " + yesNo(c.audio.DTS))
    add(items, "", "info", "Storage free", "Roku keeps about 16 KB for app settings, history and My List", tostr(registrySpaceKb()) + " KB")

    content = CreateObject("roSGNode", "ContentNode")
    for each it in items
        n = content.createChild("SettingNode")
        n.key = it.key
        n.kind = it.kind
        n.label = it.label
        n.desc = it.desc
        n.value = it.value
        n.on = it.on
    end for
    idx = m.list.itemFocused
    if m.global.hasField("settingsFocus") and m.global.settingsFocus > 0
        idx = m.global.settingsFocus
        m.global.settingsFocus = 0
    end if
    m.list.content = content
    if idx > 0 then m.list.jumpToItem = idx else m.list.jumpToItem = 1
end sub

function yesNo(b as Boolean) as String
    if b then return "Yes"
    return "No"
end function

sub setSetting(key as String, value as Dynamic)
    s = m.global.settings
    s[key] = value
    m.top.getScene().callFunc("applySettings", { settings: s })
    if key = "theme" or key = "customAccent" or key = "customBackground" or key = "dynamicTheme"
        ' list items cache colors: rebuild this page in the new theme, keeping the position
        if not m.global.hasField("settingsFocus") then m.global.addFields({ settingsFocus: 0 })
        m.global.settingsFocus = m.list.itemFocused
        m.top.navigateTo = { to: "settings" }
        return
    end if
    build()
end sub

sub choose(key as String, title as String, opts as Object, multi = false as Boolean)
    m.pending = key
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = title
    dlg.options = opts
    dlg.multiSelect = multi
    dlg.observeField("chosen", "onChosen")
    m.top.getScene().callFunc("pushDialog", dlg)
end sub

sub onSelected()
    c = m.list.content.getChild(m.list.itemSelected)
    if c = invalid then return
    k = c.key
    s = m.global.settings
    if c.kind = "toggle" and k <> "askProfile"
        setSetting(k, not bool(s[k]))
        return
    end if
    if k = "addons"
        m.top.navigateTo = { to: "addons" }
    else if k = "metaProvider"
        opts = [{ id: "", label: "Automatic", checked: s.metaProvider = "" }]
        for each a in m.global.addons
            if addonHasResource(a, "meta") or a.catalogs.Count() > 0 then opts.Push({ id: a.id, label: a.name, checked: a.id = s.metaProvider })
        end for
        choose(k, "Metadata provider", opts)
    else if k = "theme"
        opts = []
        for each p in THEME_PRESETS()
            opts.Push({ id: p.id, label: p.label, checked: p.id = themePresetId(tostr(s.theme)) })
        end for
        opts.Push({ id: "CUSTOM", label: "Custom colors", checked: s.theme = "CUSTOM" })
        choose(k, "Color theme", opts)
    else if k = "dynamicTheme"
        opts = []
        for each d in ANIMATED_THEMES()
            opts.Push({ id: d.id, label: d.label, checked: d.id = tostr(s.dynamicTheme) })
        end for
        choose(k, "Animated theme", opts)
    else if k = "customAccent" or k = "customBackground"
        opts = []
        list = ACCENT_CHOICES()
        if k = "customBackground" then list = BACKGROUND_CHOICES()
        for each h in list
            opts.Push({ id: h, label: "#" + h, checked: h = s[k] })
        end for
        choose(k, c.label, opts)
    else if k = "maxSizeGb"
        opts = []
        for each g in [0, 2, 5, 10, 20, 40, 60]
            label = "No limit"
            if g > 0 then label = tostr(g) + " GB"
            opts.Push({ id: tostr(g), label: label, checked: g = toInt(s.maxSizeGb) })
        end for
        choose(k, "Maximum file size", opts)
    else if k = "audioLanguages" or k = "subtitleLanguages"
        opts = []
        for each l in LANG_COMMON()
            opts.Push({ id: l, label: langName(l), checked: arrHas(s[k], l) })
        end for
        title = "Preferred audio languages"
        if k = "subtitleLanguages" then title = "Preferred subtitle languages"
        choose(k, title, opts, true)
    else if k = "autoplayCountdownSec"
        opts = []
        for each n in [5, 10, 15, 20, 30]
            opts.Push({ id: tostr(n), label: tostr(n) + " seconds", checked: n = toInt(s[k]) })
        end for
        choose(k, "Next episode countdown", opts)
    else if k = "stillWatchingEpisodes"
        opts = []
        for each n in [2, 3, 4, 5, 6, 8]
            opts.Push({ id: tostr(n), label: tostr(n) + " episodes", checked: n = toInt(s[k]) })
        end for
        choose(k, "Ask after", opts)
    else if k = "clearHistory"
        clearHistory()
        toast("Watch history cleared")
        build()
    else if k = "switchProfile"
        m.top.getScene().callFunc("switchProfile", { id: "" })
    else if k = "addProfile"
        m.kbMode = "add"
        m.kb = showKeyboard("New profile name", "", ["Create", "Cancel"], "onNameKeyboard")
    else if k = "renameProfile"
        m.kbMode = "rename"
        name = ""
        for each p in m.global.profiles
            if p.id = m.global.profileId then name = p.name
        end for
        m.kb = showKeyboard("Rename profile", name, ["Save", "Cancel"], "onNameKeyboard")
    else if k = "deleteProfile"
        choose(k, "Delete this profile?", [{ id: "no", label: "Keep it" }, { id: "yes", label: "Delete profile and its data" }])
    else if k = "askProfile"
        cur = regReadStr(APP_SECTION(), "skipPicker") = "true"
        if cur then regWriteRaw(APP_SECTION(), "skipPicker", "false") else regWriteRaw(APP_SECTION(), "skipPicker", "true")
        build()
    end if
end sub

sub onChosen(e as Object)
    v = e.getData()
    k = m.pending
    s = m.global.settings
    if k = "audioLanguages" or k = "subtitleLanguages"
        cur = s[k]
        out = []
        found = false
        for each l in cur
            if l = v then found = true else out.Push(l)
        end for
        if not found then out.Push(v)
        setSetting(k, out)
    else if k = "maxSizeGb" or k = "autoplayCountdownSec" or k = "stillWatchingEpisodes"
        setSetting(k, toInt(v))
    else if k = "deleteProfile"
        if v = "yes" then deleteProfile()
    else
        setSetting(k, v)
    end if
end sub

sub onNameKeyboard(e as Object)
    dlg = e.getRoSGNode()
    if e.getField() = "wasClosed" then return
    btn = dlg.buttonSelected
    name = dlg.text.Trim()
    closeKeyboard(dlg)
    m.list.setFocus(true)
    if btn <> 0 then return
    profiles = m.global.profiles
    if m.kbMode = "add"
        if name = "" then name = "Profile " + tostr(profiles.Count() + 1)
        id = Left(md5(name + tostr(nowSec())), 8)
        profiles.Push({ id: id, name: name, avatar: profiles.Count() MOD 8 })
        if saveProfiles(profiles)
            m.global.profiles = profiles
            toast("Added " + name)
        else
            toast("Couldn't save the profile (storage full)")
        end if
    else if name <> ""
        for each p in profiles
            if p.id = m.global.profileId then p.name = name
        end for
        saveProfiles(profiles)
        m.global.profiles = profiles
    end if
    build()
end sub

sub deleteProfile()
    id = m.global.profileId
    if id = "default" then return
    out = []
    for each p in m.global.profiles
        if p.id <> id then out.Push(p)
    end for
    saveProfiles(out)
    m.global.profiles = out
    reg = CreateObject("roRegistry")
    reg.Delete(profileSection(id))
    reg.Flush()
    m.top.getScene().callFunc("switchProfile", { id: "default" })
end sub
