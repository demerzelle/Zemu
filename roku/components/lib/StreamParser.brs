' Port of StreamParser.kt: extracts quality, language and cache info from a Stremio stream object.
' Debrid addons don't share a schema, so this reads the name / description / filename text users see.

function spRx() as Object
    if m.__sp <> invalid then return m.__sp
    B = "(?<![a-z0-9])"
    E = "(?![a-z0-9])"
    EA = "(?![a-z])"
    r = function(p as String, flags = "i" as String) as Object
        return CreateObject("roRegex", p, flags)
    end function
    m.__sp = {
        res2160: r(B + "(?:2160p|4k|uhd)" + E)
        res1440: r(B + "(?:1440p|2k)" + E)
        res1080: r(B + "(?:1080[pi]|fhd)" + E)
        res720: r(B + "(?:720p)" + E)
        resSd: r(B + "(?:576p|480p|360p|sd)" + E)
        cam: r(B + "(?:cam|camrip|hdcam|hd-?ts|telesync|telecine|hd-?tc|dvdscr|screener)" + E)
        remux: r(B + "(?:remux|bdremux)" + E)
        bluray: r(B + "(?:blu-?ray|bdrip|brrip|bd25|bd50|bdmv)" + E)
        webrip: r(B + "(?:web-?rip)" + E)
        webdl: r(B + "(?:web-?dl|web)" + E)
        hdtv: r(B + "(?:hdtv|pdtv|dsr|tvrip)" + E)
        dvd: r(B + "(?:dvd-?rip|dvd|dvd5|dvd9)" + E)
        dv: r(B + "(?:dv|dovi|dolby[ .-]?vision)" + E)
        hdr10p: r(B + "(?:hdr10\+|hdr10plus|hdr10p)(?![a-z0-9])")
        hdr: r(B + "(?:hdr(?:10)?)(?![a-z0-9+])")
        hlg: r(B + "(?:hlg)" + E)
        av1: r(B + "(?:av1)" + E)
        hevc: r(B + "(?:x265|h\.?265|hevc)" + E)
        avc: r(B + "(?:x264|h\.?264|avc)" + E)
        tenBit: r(B + "(?:10-?bit|hi10p)" + E)
        atmos: r(B + "(?:atmos)" + EA)
        truehd: r(B + "(?:true-?hd)" + EA)
        dtsHd: r(B + "(?:dts-?hd(?:[ .-]?ma)?|dts-?x|dts-?ma)" + EA)
        dts: r(B + "(?:dts)" + EA)
        ddp: r(B + "(?:ddp|dd\+|e-?ac-?3|dolby[ .]?digital[ .]?plus)" + EA)
        dd: r(B + "(?:dd|ac-?3|dolby[ .]?digital)" + EA)
        aac: r(B + "(?:aac)" + EA)
        flac: r(B + "(?:flac)" + EA)
        opus: r(B + "(?:opus)" + EA)
        channels: r("(?<![0-9])([2578])[ .]([01])(?![0-9])(?!\s*[gmkt]i?b)")
        size: r("([0-9]+(?:[.,][0-9]+)?)\s*(tb|tib|gb|gib|mb|mib)(?![a-z])")
        seeders: r("👤\s*([0-9]+)|seed(?:er)?s?\s*:?\s*([0-9]+)")
        group: r("-([A-Za-z0-9]{2,15})(?:\.[A-Za-z0-9]{2,4})?\s*$", "")
        ' Case-sensitive on purpose: "[RD+]", "[AD download]", "[TB⚡]".
        serviceTag: r("(?<![A-Za-z])(RD|AD|PM|DL|TB|OC|ED|PKP|EN)(?=\s*(?:\+|⚡|⏳|⬇|download|\]|☁))", "")
        positive: r("\+\]|⚡|✅|(?<![a-z])(?:cached|instant)(?![a-z])")
        negativeName: r("download|⏳|⬇|uncached|not[ _-]?cached")
        negativeDesc: r("⏳|⬇|uncached|not[ _-]?cached")
        anchor: r("^(?:(?:19|20)\d{2}|S\d{1,2}(?:E\d{1,3})?|\d{3,4}P|4K)$", "")
        tokenSplit: r("[^A-Za-z0-9+]+", "")
        multiAudio: r("multi[ ._-]?audio|dual[ ._-]?audio")
        multiSub: r("multi[ ._-]?subs?")
        sub: r("sub")
        lines: r("\r?\n", "")
        services: [
            [r("real-?debrid"), "RD"], [r("alldebrid"), "AD"], [r("premiumize"), "PM"], [r("debrid-?link"), "DL"],
            [r("torbox"), "TB"], [r("offcloud"), "OC"], [r("easydebrid"), "ED"], [r("pikpak"), "PKP"], [r("easynews"), "EN"]
        ]
    }
    return m.__sp
end function

function sourceRank(label as String) as Integer
    ranks = { Remux: 6, BluRay: 5, "WEB-DL": 4, WEBRip: 3, HDTV: 2, DVD: 1, CAM: -10 }
    v = ranks.Lookup(label)
    if v = invalid then return 0
    return v
end function

function audioRank(label as String) as Integer
    ranks = { Atmos: 6, TrueHD: 5, "DTS-HD": 5, DTS: 3, "DD+": 3, DD: 2, FLAC: 3, AAC: 1, Opus: 1 }
    v = ranks.Lookup(label)
    if v = invalid then return 0
    return v
end function

function resolutionLabel(res as Integer) as String
    if res = 2160 then return "4K"
    if res = 1440 then return "1440p"
    if res = 1080 then return "1080p"
    if res = 720 then return "720p"
    if res = 480 then return "SD"
    return "Unknown"
end function

function detectResolution(rx as Object, text as String) as Integer
    if rx.res2160.IsMatch(text) then return 2160
    if rx.res1440.IsMatch(text) then return 1440
    if rx.res1080.IsMatch(text) then return 1080
    if rx.res720.IsMatch(text) then return 720
    if rx.resSd.IsMatch(text) then return 480
    return 0
end function

function parseSizeText(rx as Object, text as String) as Double
    idx = Instr(1, text, "💾")
    mm = []
    if idx > 0 then mm = rx.size.Match(Mid(text, idx))
    if mm.Count() = 0 then mm = rx.size.Match(text)
    if mm.Count() < 3 then return 0
    n# = Val(mm[1].Replace(",", "."))
    unit = LCase(mm[2])
    if unit = "tb" or unit = "tib" then return n# * 1099511627776#
    if unit = "gb" or unit = "gib" then return n# * 1073741824#
    return n# * 1048576#
end function

function splitLines(rx as Object, s as String) as Object
    out = []
    for each l in rx.lines.Split(s)
        t = l.Trim()
        if t <> "" then out.Push(t)
    end for
    return out
end function

function pushUnique(arr as Object, v as String)
    if not arrHas(arr, v) then arr.Push(v)
end function

' raw: a stream object from an addon. Returns a ParsedStream AA.
function parseStream(raw as Object, addonName as String, trustDirect as Boolean) as Object
    rx = spRx()
    name = tostr(raw.name)
    desc = tostr(raw.description)
    if desc = "" then desc = tostr(raw.title)
    hints = raw.behaviorHints
    filename = ""
    videoSize# = 0
    binge = ""
    headers = invalid
    if isAA(hints)
        filename = tostr(hints.filename)
        videoSize# = toNum(hints.videoSize)
        binge = tostr(hints.bingeGroup)
        if isAA(hints.proxyHeaders) and isAA(hints.proxyHeaders.request) then headers = hints.proxyHeaders.request
    end if
    all = name + Chr(10) + desc + Chr(10) + filename
    descLines = splitLines(rx, desc)

    title = filename
    if title = "" and descLines.Count() > 0 then title = descLines[0]
    if title = "" then title = name.Replace(Chr(10), " ")

    res = detectResolution(rx, name)
    if res = 0 then res = detectResolution(rx, all)

    source = "Unknown"
    if rx.cam.IsMatch(all)
        source = "CAM"
    else if rx.remux.IsMatch(all)
        source = "Remux"
    else if rx.bluray.IsMatch(all)
        source = "BluRay"
    else if rx.webrip.IsMatch(all)
        source = "WEBRip"
    else if rx.webdl.IsMatch(all)
        source = "WEB-DL"
    else if rx.hdtv.IsMatch(all)
        source = "HDTV"
    else if rx.dvd.IsMatch(all)
        source = "DVD"
    end if

    hdr = []
    if rx.dv.IsMatch(all) then hdr.Push("Dolby Vision")
    if rx.hdr10p.IsMatch(all) then hdr.Push("HDR10+")
    if rx.hdr.IsMatch(all) then hdr.Push("HDR10")
    if rx.hlg.IsMatch(all) then hdr.Push("HLG")

    codec = "Unknown"
    if rx.av1.IsMatch(all)
        codec = "AV1"
    else if rx.hevc.IsMatch(all)
        codec = "HEVC"
    else if rx.avc.IsMatch(all)
        codec = "H.264"
    end if

    audio = []
    if rx.atmos.IsMatch(all) then audio.Push("Atmos")
    if rx.truehd.IsMatch(all) then audio.Push("TrueHD")
    if rx.dtsHd.IsMatch(all)
        audio.Push("DTS-HD")
    else if rx.dts.IsMatch(all)
        audio.Push("DTS")
    end if
    if rx.ddp.IsMatch(all)
        audio.Push("DD+")
    else if rx.dd.IsMatch(all)
        audio.Push("DD")
    end if
    if rx.aac.IsMatch(all) then audio.Push("AAC")
    if rx.flac.IsMatch(all) then audio.Push("FLAC")
    if rx.opus.IsMatch(all) then audio.Push("Opus")

    channels = ""
    best = -1
    for each mm in rx.channels.MatchAll(desc + Chr(10) + filename)
        v = Val(mm[1] + mm[2])
        if v > best
            best = v
            channels = mm[1] + "." + mm[2]
        end if
    end for

    langs = detectLanguages(rx, name, descLines, filename)
    subs = langs.subs
    if isArr(raw.subtitles)
        for each s in raw.subtitles
            if isAA(s)
                l = langNormalize(tostr(s.lang))
                if l <> "" then pushUnique(subs, l)
            end if
        end for
    end if

    service = ""
    st = rx.serviceTag.Match(name)
    if st.Count() > 1
        service = st[1]
    else
        nd = name + Chr(10) + desc
        for each s in rx.services
            if s[0].IsMatch(nd)
                service = s[1]
                exit for
            end if
        end for
    end if

    size# = videoSize#
    if size# <= 0 then size# = parseSizeText(rx, desc + Chr(10) + name)
    seeders = -1
    sm = rx.seeders.Match(desc)
    if sm.Count() > 1
        if sm[1] <> ""
            seeders = Val(sm[1])
        else if sm.Count() > 2
            seeders = Val(sm[2])
        end if
    end if
    group = ""
    gm = rx.group.Match(title)
    if gm.Count() > 1 then group = gm[1]

    url = tostr(raw.url)
    key = url
    if key = ""
        if tostr(raw.infoHash) <> "" then key = raw.infoHash + ":" + tostr(toInt(raw.fileIdx)) else key = addonName + "|" + name + "|" + desc
    end if
    audioBest = 0
    for each a in audio
        r = audioRank(a)
        if r > audioBest then audioBest = r
    end for

    return {
        key: key
        url: url
        headers: headers
        bingeGroup: binge
        addon: addonName
        title: cleanText(title)
        res: res
        resLabel: resolutionLabel(res)
        source: source
        hdr: hdr
        codec: codec
        tenBit: rx.tenBit.IsMatch(all)
        audio: audio
        audioBest: audioBest
        channels: channels
        aLangs: langs.audio
        multiAudio: langs.multiAudio
        sLangs: subs
        multiSubs: langs.multiSubs
        size: size#
        seeders: seeders
        group: group
        service: service
        cached: isCachedStream(rx, url, name, desc, trustDirect)
    }
end function

' Cached only if it has a direct HTTP(S) URL and the addon marked it cached without a "download"/"⏳" marker.
function isCachedStream(rx as Object, url as String, name as String, desc as String, trustDirect as Boolean) as Boolean
    lu = LCase(url)
    if url = "" or not (startsWith(lu, "https://") or startsWith(lu, "http://")) then return false
    if rx.negativeName.IsMatch(name) or rx.negativeDesc.IsMatch(desc) then return false
    return rx.positive.IsMatch(name) or rx.positive.IsMatch(desc) or trustDirect
end function

function detectLanguages(rx as Object, name as String, descLines as Object, filename as String) as Object
    audio = []
    subs = []
    multiAudio = false
    multiSubs = false

    flagLines = []
    flagLines.Append(descLines)
    flagLines.Append(splitLines(rx, name))
    for each line in flagLines
        flags = langFromFlags(line)
        if flags.Count() > 0
            for each f in flags
                if rx.sub.IsMatch(line) then pushUnique(subs, f) else pushUnique(audio, f)
            end for
        end if
    end for

    aTok = audioTokens()
    sTok = subtitleTokens()
    mTok = multiSubTokens()
    gTok = genericSubTokens()
    lines = []
    lines.Append(descLines)
    if filename.Trim() <> "" then lines.Push(filename)
    for each line in lines
        if rx.multiAudio.IsMatch(line) then multiAudio = true
        if rx.multiSub.IsMatch(line) then multiSubs = true
        tokens = []
        for each t in rx.tokenSplit.Split(line)
            if t <> "" then tokens.Push(UCase(t))
        end for
        anchor = -1
        for i = 0 to tokens.Count() - 1
            if rx.anchor.IsMatch(tokens[i])
                anchor = i
                exit for
            end if
        end for
        ' Language tokens are only trusted after the year/season/resolution, past the title.
        if anchor >= 0
            for i = anchor + 1 to tokens.Count() - 1
                t = tokens[i]
                nxt = ""
                if i + 1 < tokens.Count() then nxt = tokens[i + 1]
                if t = "MULTI" or t = "DUAL"
                    if nxt = "SUB" or nxt = "SUBS" then multiSubs = true else multiAudio = true
                else if mTok.DoesExist(t)
                    multiSubs = true
                else if sTok.DoesExist(t)
                    pushUnique(subs, sTok[t])
                else if aTok.DoesExist(t)
                    if nxt <> "" and gTok.DoesExist(nxt) then pushUnique(subs, aTok[t]) else pushUnique(audio, aTok[t])
                end if
            end for
        end if
    end for
    return { audio: audio, subs: subs, multiAudio: multiAudio or audio.Count() > 1, multiSubs: multiSubs }
end function
