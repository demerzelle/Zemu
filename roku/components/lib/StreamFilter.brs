' Port of StreamFilter.kt and DeviceCapabilities.kt: facets with live counts, filters, and "Best for this TV" ranking.

function FACETS() as Object
    return [
        { kind: "QUALITY", label: "Quality" }, { kind: "AUDIO_LANG", label: "Audio language" }, { kind: "SUB_LANG", label: "Subtitles" },
        { kind: "SIZE", label: "Size" }, { kind: "HDR", label: "HDR" }, { kind: "CODEC", label: "Video codec" },
        { kind: "AUDIO", label: "Audio format" }, { kind: "CHANNELS", label: "Channels" }, { kind: "SOURCE", label: "Source" },
        { kind: "SERVICE", label: "Debrid service" }, { kind: "ADDON", label: "Addon" }
    ]
end function

function SORTS() as Object
    return [
        { id: "BEST", label: "Best match" }, { id: "RESOLUTION", label: "Highest quality" }, { id: "SIZE_DESC", label: "Largest size" },
        { id: "SIZE_ASC", label: "Smallest size" }, { id: "SEEDERS", label: "Most seeded" }
    ]
end function

function SIZE_BUCKETS() as Object
    return [
        { id: "UNDER_2", label: "Under 2 GB", min: 0, max: 2 }, { id: "GB_2_5", label: "2 – 5 GB", min: 2, max: 5 },
        { id: "GB_5_10", label: "5 – 10 GB", min: 5, max: 10 }, { id: "GB_10_20", label: "10 – 20 GB", min: 10, max: 20 },
        { id: "GB_20_40", label: "20 – 40 GB", min: 20, max: 40 }, { id: "OVER_40", label: "40 GB +", min: 40, max: 999999 }
    ]
end function

function defaultFilterState() as Object
    return { sort: "BEST", selected: {}, deviceFriendlyOnly: false, hideCam: true }
end function

function sizeBucket(bytes as Double) as String
    if bytes <= 0 then return "?"
    gb = bytes / 1073741824#
    for each b in SIZE_BUCKETS()
        if gb >= b.min and gb < b.max then return b.id
    end for
    return "?"
end function

' Detects what this Roku can decode and display.
function detectCaps() as Object
    di = CreateObject("roDeviceInfo")
    mode = di.GetVideoMode()
    maxRes = 720
    if Instr(1, mode, "2160") > 0 or Instr(1, mode, "4K") > 0
        maxRes = 2160
    else if Instr(1, mode, "1080") > 0
        maxRes = 1080
    end if
    dp = di.GetDisplayProperties()
    hdr10 = false
    hdr10p = false
    dv = false
    if isAA(dp)
        hdr10 = bool(dp.Hdr10)
        hdr10p = bool(dp.Hdr10Plus)
        dv = bool(dp.DolbyVision)
    end if
    canV = function(di as Object, c as String) as Boolean
        r = di.CanDecodeVideo({ Codec: c })
        return isAA(r) and bool(r.Result)
    end function
    canA = function(di as Object, c as String) as Boolean
        r = di.CanDecodeAudio({ Codec: c })
        return isAA(r) and bool(r.Result)
    end function
    eac3 = canA(di, "eac3")
    audio = {
        AAC: true
        FLAC: canA(di, "flac")
        Opus: canA(di, "opus")
        DD: canA(di, "ac3")
        "DD+": eac3
        Atmos: eac3
        DTS: canA(di, "dts")
        "DTS-HD": false
        TrueHD: false
    }
    return { maxRes: maxRes, hevc: canV(di, "hevc"), av1: canV(di, "av1"), vp9: canV(di, "vp9"), hdr10: hdr10, hdr10Plus: hdr10p, dolbyVision: dv, audio: audio }
end function

function capsCanPlay(caps as Object, a as String) as Boolean
    return bool(caps.audio.Lookup(a))
end function

function facetValues(kind as String, s as Object, ext as Object) as Object
    if kind = "QUALITY" then return [s.resLabel]
    if kind = "AUDIO_LANG"
        out = []
        out.Append(s.aLangs)
        if s.multiAudio then out.Push("multi")
        if out.Count() = 0 then out.Push("und")
        return out
    end if
    if kind = "SUB_LANG"
        out = []
        out.Append(s.sLangs)
        if s.multiSubs then out.Push("multi")
        for each l in ext
            if not arrHas(out, l) then out.Push(l)
        end for
        if out.Count() = 0 then out.Push("none")
        return out
    end if
    if kind = "SIZE" then return [sizeBucket(s.size)]
    if kind = "HDR"
        if s.hdr.Count() = 0 then return ["SDR"]
        return s.hdr
    end if
    if kind = "CODEC" then return [s.codec]
    if kind = "AUDIO"
        if s.audio.Count() = 0 then return ["?"]
        return s.audio
    end if
    if kind = "CHANNELS"
        if s.channels = "" then return ["?"]
        return [s.channels]
    end if
    if kind = "SOURCE" then return [s.source]
    if kind = "SERVICE"
        if s.service = "" then return ["Direct"]
        return [s.service]
    end if
    if kind = "ADDON" then return [s.addon]
    return []
end function

function facetLabel(kind as String, v as String, ext as Object) as String
    if v = "multi" then return "Multi-language"
    if v = "und" then return "Not specified"
    if v = "none" then return "None listed"
    if v = "?" then return "Unknown"
    if kind = "AUDIO_LANG" then return langName(v)
    if kind = "SUB_LANG"
        if arrHas(ext, v) then return langName(v) + "  (incl. external)"
        return langName(v)
    end if
    if kind = "SIZE"
        for each b in SIZE_BUCKETS()
            if b.id = v then return b.label
        end for
    end if
    return v
end function

function streamMatches(s as Object, state as Object, ext as Object, exclude as String) as Boolean
    sel = state.selected
    for each kind in sel
        chosen = sel[kind]
        if kind <> exclude and chosen.Count() > 0
            hit = false
            for each v in facetValues(kind, s, ext)
                if arrHas(chosen, v)
                    hit = true
                    exit for
                end if
            end for
            if not hit then return false
        end if
    end for
    return true
end function

function filterBase(all as Object, state as Object, caps as Object, settings as Object) as Object
    out = []
    maxGb = toInt(settings.maxSizeGb)
    for each s in all
        ok = true
        if state.hideCam and s.source = "CAM" then ok = false
        if ok and state.deviceFriendlyOnly and not isDeviceFriendly(s, caps) then ok = false
        if ok and maxGb > 0 and s.size > maxGb * 1073741824# then ok = false
        if ok then out.Push(s)
    end for
    return out
end function

function isDeviceFriendly(s as Object, caps as Object) as Boolean
    codecOk = true
    if s.codec = "AV1" then codecOk = caps.av1
    if s.codec = "HEVC" then codecOk = caps.hevc
    hdrOk = true
    if s.hdr.Count() > 0
        dvOnly = s.hdr.Count() = 1 and s.hdr[0] = "Dolby Vision"
        if dvOnly then hdrOk = caps.dolbyVision else hdrOk = caps.hdr10 or caps.dolbyVision
    end if
    audioOk = s.audio.Count() = 0
    for each a in s.audio
        if capsCanPlay(caps, a) then audioOk = true
    end for
    return codecOk and hdrOk and audioOk
end function

' Heuristic "how good will this look and sound on this TV, in my languages" score.
function streamScore(s as Object, caps as Object, settings as Object, ext as Object) as Double
    sc# = 0
    effective = s.res
    if caps.maxRes < effective then effective = caps.maxRes
    if effective >= 2160
        sc# = sc# + 40
    else if effective >= 1440
        sc# = sc# + 33
    else if effective >= 1080
        sc# = sc# + 30
    else if effective >= 720
        sc# = sc# + 18
    else if effective > 0
        sc# = sc# + 8
    else
        sc# = sc# + 12
    end if
    if s.res > caps.maxRes then sc# = sc# - 6
    sc# = sc# + sourceRank(s.source) * 4

    if arrHas(s.hdr, "Dolby Vision")
        if caps.dolbyVision and not bool(settings.avoidDolbyVision)
            sc# = sc# + 10
        else if s.hdr.Count() = 1
            sc# = sc# - 18
        end if
        if s.source = "Remux" or s.source = "BluRay" then sc# = sc# - 8
    end if
    if arrHas(s.hdr, "HDR10+") and caps.hdr10Plus then sc# = sc# + 3
    if arrHas(s.hdr, "HDR10") or arrHas(s.hdr, "HDR10+")
        if caps.hdr10 then sc# = sc# + 7 else sc# = sc# - 3
    end if
    if s.codec = "AV1"
        if caps.av1 then sc# = sc# + 3 else sc# = sc# - 35
    else if s.codec = "HEVC"
        if caps.hevc then sc# = sc# + 2 else sc# = sc# - 35
    end if
    if s.audio.Count() > 0
        best = -1
        for each a in s.audio
            if capsCanPlay(caps, a) and audioRank(a) > best then best = audioRank(a)
        end for
        if best < 0 then sc# = sc# - 20 else sc# = sc# + best * 1.5
    end if

    prefAudio = settings.audioLanguages
    hit = false
    for each l in s.aLangs
        if arrHas(prefAudio, l) then hit = true
    end for
    if hit
        sc# = sc# + 25
    else if s.multiAudio
        sc# = sc# + 12
    else if s.aLangs.Count() = 0
        sc# = sc# + 6
    else
        sc# = sc# - 15
    end if
    prefSubs = settings.subtitleLanguages
    if prefSubs.Count() > 0
        subHit = false
        for each l in s.sLangs
            if arrHas(prefSubs, l) then subHit = true
        end for
        for each l in ext
            if arrHas(prefSubs, l) then subHit = true
        end for
        if subHit then sc# = sc# + 4
    end if
    seeds = s.seeders
    if seeds > 100 then seeds = 100
    if seeds > 0 then sc# = sc# + seeds / 25
    gb = s.size / 1073741824#
    if gb > 0 and gb < 0.4 and s.res >= 1080 then sc# = sc# - 10
    return sc#
end function

' Returns ranked entries { s, score, recommended, friendly } in display order.
function applyFilters(all as Object, state as Object, caps as Object, settings as Object, ext as Object) as Object
    ranked = []
    bestScore = -999999
    bestKey = ""
    for each s in filterBase(all, state, caps, settings)
        if streamMatches(s, state, ext, "")
            sc = streamScore(s, caps, settings, ext)
            if sc > bestScore
                bestScore = sc
                bestKey = s.key
            end if
            sizeAsc = s.size
            if sizeAsc <= 0 then sizeAsc = 1e15
            ranked.Push({ s: s, score: sc, recommended: false, friendly: isDeviceFriendly(s, caps), res: s.res * 1000 + sc, size: s.size, sizeAsc: sizeAsc, seeders: s.seeders })
        end if
    end for
    sortKey = state.sort
    if sortKey = "RESOLUTION"
        ranked.SortBy("res", "r")
    else if sortKey = "SIZE_DESC"
        ranked.SortBy("size", "r")
    else if sortKey = "SIZE_ASC"
        ranked.SortBy("sizeAsc")
    else if sortKey = "SEEDERS"
        ranked.SortBy("seeders", "r")
    else
        ranked.SortBy("score", "r")
    end if
    for each r in ranked
        if r.s.key = bestKey then r.recommended = true
    end for
    return ranked
end function

' Options for each facet with counts that respect every *other* active facet.
function computeFacets(all as Object, state as Object, caps as Object, settings as Object, ext as Object) as Object
    base = filterBase(all, state, caps, settings)
    qualityOrder = ["4K", "1440p", "1080p", "720p", "SD", "Unknown"]
    sizeOrder = ["UNDER_2", "GB_2_5", "GB_5_10", "GB_10_20", "GB_20_40", "OVER_40"]
    out = {}
    for each f in FACETS()
        kind = f.kind
        counts = {}
        counts.SetModeCaseSensitive()
        for each s in base
            if streamMatches(s, state, ext, kind)
                for each v in facetValues(kind, s, ext)
                    n = counts.Lookup(v)
                    if n = invalid then n = 0
                    counts[v] = n + 1
                end for
            end if
        end for
        sel = state.selected.Lookup(kind)
        if sel <> invalid
            for each v in sel
                if not counts.DoesExist(v) then counts[v] = 0
            end for
        end if
        options = []
        for each v in counts
            o = { value: v, label: facetLabel(kind, v, ext), count: counts[v] }
            if kind = "QUALITY"
                idx = 99
                for i = 0 to qualityOrder.Count() - 1
                    if qualityOrder[i] = v then idx = i
                end for
                o.order = idx
            else if kind = "SIZE"
                idx = 99
                for i = 0 to sizeOrder.Count() - 1
                    if sizeOrder[i] = v then idx = i
                end for
                o.order = idx
            else
                o.order = LCase(Right("000000" + tostr(999999 - o.count), 6) + o.label)
            end if
            options.Push(o)
        end for
        options.SortBy("order")
        out[kind] = options
    end for
    return out
end function

function activeFilterCount(state as Object) as Integer
    n = 0
    for each k in state.selected
        if state.selected[k].Count() > 0 then n = n + 1
    end for
    if state.deviceFriendlyOnly then n = n + 1
    return n
end function

function hdrLabelOf(s as Object) as String
    dv = arrHas(s.hdr, "Dolby Vision")
    if dv and s.hdr.Count() > 1 then return "DV · HDR"
    if dv then return "Dolby Vision"
    if arrHas(s.hdr, "HDR10+") then return "HDR10+"
    if arrHas(s.hdr, "HDR10") then return "HDR"
    if arrHas(s.hdr, "HLG") then return "HLG"
    return ""
end function

function langListLabel(codes as Object, multi as Boolean) as String
    names = []
    for each c in arrTake(codes, 4)
        names.Push(langName(c))
    end for
    if multi and codes.Count() <= 1 then names.Push("Multi")
    if names.Count() = 0 then return ""
    out = joinArr(names, ", ")
    if codes.Count() > 4 then out = out + " +" + tostr(codes.Count() - 4)
    return out
end function

function bestSummary(s as Dynamic) as String
    if s = invalid then return ""
    parts = [s.resLabel]
    h = hdrLabelOf(s)
    if h <> "" then parts.Push(h)
    bestA = ""
    bestR = -1
    for each a in s.audio
        if audioRank(a) > bestR
            bestR = audioRank(a)
            bestA = a
        end if
    end for
    if bestA <> "" then parts.Push(bestA)
    if s.size > 0 then parts.Push(formatSize(s.size))
    if s.service <> "" then parts.Push(s.service + " cached")
    return joinArr(parts, " · ")
end function
