' Port of PlayerActivity.kt + PlayerScreen.kt.
' Menu hidden: OK pauses and opens the menu, Left/Right tap to jump (15 s, more when pressed quickly)
' or hold to scrub smoothly (faster the longer you hold; seeks once on release), Up/Down open the
' menu, Back exits. Menu open: Back (or Up from the seek bar) closes it.

sub init()
    m.video = m.top.findNode("video")
    m.buffering = m.top.findNode("buffering")
    m.scrub = m.top.findNode("scrub")
    m.scrubBar = m.top.findNode("scrubBar")
    m.menu = m.top.findNode("menu")
    m.title = m.top.findNode("title")
    m.label = m.top.findNode("label")
    m.streamLabel = m.top.findNode("streamLabel")
    m.seek = m.top.findNode("seek")
    m.seekBar = m.top.findNode("seekBar")
    m.hint = m.top.findNode("hint")
    m.bar = m.top.findNode("bar")
    m.skipBtn = m.top.findNode("skipBtn")
    m.nextCard = m.top.findNode("nextCard")
    m.nextHeading = m.top.findNode("nextHeading")
    m.nextTitle = m.top.findNode("nextTitle")
    m.nextButtons = m.top.findNode("nextButtons")
    m.tick = m.top.findNode("tick")
    m.hideTimer = m.top.findNode("hideTimer")
    m.seekTimer = m.top.findNode("seekTimer")
    m.holdTimer = m.top.findNode("holdTimer")
    m.okTimer = m.top.findNode("okTimer")
    m.sleepTimer = m.top.findNode("sleepTimer")
    m.labels = m.top.findNode("labels")
    m.top.focusable = true

    m.video.notificationInterval = 1
    m.video.observeField("state", "onState")
    m.video.observeField("position", "onPosition")
    m.video.observeField("duration", "onDuration")
    m.tick.observeField("fire", "onTick")
    m.hideTimer.observeField("fire", "onHideTimer")
    m.seekTimer.observeField("fire", "commitScrub")
    m.holdTimer.observeField("fire", "onHoldTick")
    m.okTimer.observeField("fire", "onOkHeld")
    m.sleepTimer.observeField("fire", "onSleepTimer")
    m.seek.observeField("focusedChild", "onSeekFocus")
    m.skipBtn.observeField("pressed", "onSkip")

    m.segments = []
    m.scrubTarget = -1
    m.holdDir = 0
    m.holdClock = CreateObject("roTimespan")
    m.seekPendingAt = -1
    m.sleepIdx = 0
    m.scrubCount = 0
    m.lastScrubKey = CreateObject("roTimespan")
    m.lastScrubDir = 0
    m.lastFlush = 0
    m.autoplayed = 0
    m.countdown = -1
    m.nextStream = invalid
    m.dismissedCredits = false
    m.settings = m.global.settings
end sub

sub onActive()
    if not m.top.active and m.video <> invalid and m.video.state = "playing" then m.video.control = "pause"
end sub

sub onDispose()
    if not m.finished = true then saveProgress(true)
    m.video.control = "stop"
    m.tick.control = "stop"
    if m.nextTask <> invalid then m.nextTask.control = "stop"
    if m.skipTask <> invalid then m.skipTask.control = "stop"
end sub

' ---- start ----

sub onParams()
    p = m.top.params
    m.meta = p.meta
    m.videoId = p.videoId
    m.labelText = tostr(p.label)
    m.candidates = p.candidates
    m.subs = p.subs
    if m.subs = invalid then m.subs = []
    m.videos = p.videos
    if m.videos = invalid then m.videos = []
    m.candIdx = 0
    m.formatTried = {}
    m.title.text = m.meta.name
    m.label.text = m.labelText
    m.label.visible = m.labelText <> ""
    m.nextVideo = findNextVideo()
    buildBar()
    beginResume(toInt(p.startSec))
    startCandidate(m.resumeAt)
    m.tick.control = "start"
    m.top.setFocus(true)
end sub

function guessFormat(c as Object) as String
    u = LCase(substringBefore(c.url, "?"))
    t = LCase(tostr(c.title))
    if Instr(1, u, ".m3u8") > 0 then return "hls"
    if Instr(1, u, ".mpd") > 0 then return "dash"
    if endsWith(u, ".mp4") or endsWith(u, ".m4v") or endsWith(t, ".mp4") then return "mp4"
    if endsWith(u, ".mkv") or endsWith(t, ".mkv") then return "mkv"
    if endsWith(u, ".webm") then return "mkv"
    ' debrid links rarely carry an extension; most releases are Matroska
    return "mkv"
end function

function iso3For(code as String) as String
    map = { en: "eng", es: "spa", fr: "fre", de: "ger", it: "ita", pt: "por", ru: "rus", ja: "jpn", ko: "kor", zh: "chi", hi: "hin", ar: "ara", tr: "tur", pl: "pol", nl: "dut", sv: "swe", no: "nor", da: "dan", fi: "fin", el: "gre", he: "heb", cs: "cze", hu: "hun", ro: "rum", uk: "ukr", th: "tha", vi: "vie", id: "ind" }
    v = map.Lookup(code)
    if v = invalid then return code
    return v
end function

' Resume: PlayStart asks Roku to start there, but some streams (Matroska without an index, many
' debrid links) start at 0 anyway. Until playback has really begun at the saved spot, nothing is
' saved, so a slow or failed start can't wipe the resume point; once playing, a missed start is fixed
' with a seek.
sub beginResume(startSec as Integer)
    m.resumeAt = startSec
    m.resumed = false
end sub

' Where playback is (or will be): the scrub/seek target, the pending resume point, or the position.
function currentPos() as Float
    if m.scrubTarget >= 0 then return m.scrubTarget
    if m.seekPendingAt >= 0 then return m.seekPendingAt
    if not m.resumed then return m.resumeAt
    return m.video.position
end function

sub checkResume()
    if m.resumed or m.video.state <> "playing" then return
    m.resumed = true
    if m.resumeAt > 5 and Abs(m.video.position - m.resumeAt) > 10
        print "[zemu] start missed the resume point ("; m.video.position; " vs "; m.resumeAt; "), seeking"
        seekTo(m.resumeAt)
    end if
end sub

sub seekTo(t as Float)
    m.seekPendingAt = t
    m.video.seek = t
end sub

sub startCandidate(startSec as Integer, format = "" as String)
    c = m.candidates[m.candIdx]
    if format = "" then format = guessFormat(c)
    m.format = format
    m.formatTried[c.key + "|" + format] = true
    m.streamLabel.text = c.label
    content = CreateObject("roSGNode", "ContentNode")
    content.url = c.url
    content.streamFormat = format
    content.title = m.meta.name
    if startSec > 0 then content.PlayStart = startSec
    if isAA(c.headers)
        hdrs = []
        for each k in c.headers
            hdrs.Push(k + ":" + tostr(c.headers[k]))
        end for
        if hdrs.Count() > 0 then content.HttpHeaders = hdrs
    end if
    tracks = []
    for each s in m.subs
        name = langName(s.lang)
        if s.lang = "" then name = s.raw
        tracks.Push({ Language: iso3For(s.lang), TrackName: s.url, Description: name + " (external)" })
    end for
    if tracks.Count() > 0 then content.SubtitleTracks = tracks
    m.video.content = content
    m.video.globalCaptionMode = "Off"
    if bool(m.settings.autoSubtitles) and tracks.Count() > 0
        m.video.subtitleTrack = tracks[0].TrackName
        m.video.globalCaptionMode = "On"
    end if
    m.video.control = "play"
    m.buffering.visible = true
    m.segmentsLoaded = false
end sub

' ---- state ----

sub onState()
    s = m.video.state
    m.buffering.visible = s = "buffering"
    if s = "playing" or s = "paused" then updatePlayIcon()
    if s = "playing"
        if m.seekPendingAt >= 0 then m.seekPendingAt = -1
        checkResume()
    end if
    if s = "paused" then saveProgress(true)
    if s = "playing"
        if m.menu.visible then m.hideTimer.control = "start"
    else if s = "error"
        handleError()
    else if s = "finished"
        saveProgress(true, true)
        m.finished = true
        onFinished()
    end if
end sub

sub handleError()
    c = m.candidates[m.candIdx]
    curPos = Int(currentPos())
    m.seekPendingAt = -1
    print "[zemu] playback error "; m.video.errorCode; " "; m.video.errorMsg; " "; m.format
    ' 1) same stream with the other container guess
    for each f in ["mkv", "mp4"]
        if not m.formatTried.DoesExist(c.key + "|" + f)
            beginResume(curPos)
            startCandidate(curPos, f)
            return
        end if
    end for
    ' 2) the next-best cached stream
    if m.candIdx + 1 < m.candidates.Count()
        m.candIdx = m.candIdx + 1
        toast("That stream couldn't play on this TV. Trying the next best one…")
        beginResume(curPos)
        startCandidate(curPos)
        return
    end if
    toast("None of the cached streams would play on this TV (" + tostr(m.video.errorMsg) + ").")
    m.top.navigateTo = { to: "back" }
end sub

sub onDuration()
    if m.video.duration > 0 and not m.segmentsLoaded
        m.segmentsLoaded = true
        loadSegments()
    end if
end sub

sub onPosition()
    if m.seekPendingAt >= 0 and Abs(m.video.position - m.seekPendingAt) < 3 then m.seekPendingAt = -1
    checkResume()
    ' the scrub bar stays up until the seek lands
    if m.scrub.visible and m.scrubTarget < 0 and m.seekPendingAt < 0 and m.holdDir = 0 then m.scrub.visible = false
    curPos = currentPos()
    ' while scrubbing or seeking, the bar keeps showing the target instead of jumping back
    if m.menu.visible and m.scrubTarget < 0 then m.seekBar.position = curPos
    m.seekBar.duration = m.video.duration
    updateSkip(curPos)
    checkNextUp(curPos)
end sub

sub onTick()
    if m.video.state = "playing"
        now = nowSec()
        flush = now - m.lastFlush >= 15
        saveProgress(flush)
        if m.countdown > 0
            m.countdown = m.countdown - 1
            renderCountdown()
            if m.countdown = 0 then playNext()
        end if
    else if m.countdown > 0 and m.video.state = "finished"
        m.countdown = m.countdown - 1
        renderCountdown()
        if m.countdown = 0 then playNext()
    end if
end sub

sub saveProgress(flush as Boolean, finished = false as Boolean)
    if m.meta = invalid then return
    ' never overwrite the resume point before playback has reached it
    if not m.resumed and not finished then return
    d = Int(m.video.duration)
    p = Int(currentPos())
    if finished then p = d
    if d <= 0 and p <= 0 then return
    recordProgress(m.meta, m.videoId, m.labelText, p, d, flush)
    if flush then m.lastFlush = nowSec()
end sub

' ---- menu ----
' Port of MenuBar (PlayerScreen.kt): every control in one row, each labeled with its current setting.
' Speed and Picture (aspect) are left out: Roku's video player can't change either.

sub buildBar()
    m.bar.callFunc("clearItems")
    m.labels.removeChildrenIndex(m.labels.getChildCount(), 0)
    m.btns = {}
    m.btnOrder = []
    items = [
        { id: "play", icon: "pause" }
        { id: "back10", icon: "replay10" }
        { id: "fwd10", icon: "forward10" }
    ]
    if m.nextVideo <> invalid then items.Push({ id: "next", icon: "next" })
    items.Append([
        { id: "audio", icon: "audio" }
        { id: "subs", icon: "subtitles" }
        { id: "sleep", icon: "bedtime" }
        { id: "like", icon: "thumbup" }
        { id: "dislike", icon: "thumbdown" }
        { id: "mylist", icon: "heart_outline" }
    ])
    n = items.Count()
    btnW = 54
    slot = 1152 / n
    m.bar.spacing = slot - btnW
    for i = 0 to n - 1
        it = items[i]
        b = CreateObject("roSGNode", "TvButton")
        b.variant = "icon"
        b.iconSize = btnW
        b.icon = "pkg:/images/ic_" + it.icon + ".png"
        b.data = { id: it.id }
        b.observeField("pressed", "onBarPressed")
        b.observeField("focusedChild", "onBarFocus")
        m.bar.callFunc("addItem", b)
        m.btns[it.id] = b
        m.btnOrder.Push(it.id)
        g = m.labels.createChild("Group")
        g.translation = [i * slot + btnW / 2 - slot / 2, 0]
        name = g.createChild("Label")
        name.width = slot
        name.horizAlign = "center"
        name.font = "font:SmallestSystemFont"
        valueLbl = g.createChild("Label")
        valueLbl.width = slot - 6
        valueLbl.translation = [3, 22]
        valueLbl.horizAlign = "center"
        valueLbl.font = "font:SmallestSystemFont"
        it.name = name
        it.value = valueLbl
    end for
    m.barItems = items
    refreshBar()
end sub

' Label, value and "on" state of each button, as in Android's MenuItem.
sub refreshBar()
    if m.btns = invalid then return
    r = ratingOf(m.meta.id)
    listed = inMyList(m.meta.id)
    playing = m.video.state <> "paused"
    if playing then m.btns.play.icon = "pkg:/images/ic_pause.png" else m.btns.play.icon = "pkg:/images/ic_play.png"
    m.btns.like.checked = r > 0
    m.btns.dislike.checked = r < 0
    if listed then m.btns.mylist.icon = "pkg:/images/ic_favorite.png" else m.btns.mylist.icon = "pkg:/images/ic_heart_outline.png"
    m.btns.mylist.checked = listed
    subText = subtitleLabel()
    m.btns.subs.checked = subText <> "Off"
    m.btns.sleep.checked = m.sleepIdx > 0
    accent = m.global.theme.accent
    for each it in m.barItems
        id = it.id
        label = ""
        value = ""
        if id = "play"
            if playing then label = "Pause" else label = "Play"
        else if id = "back10"
            label = "−10s"
        else if id = "fwd10"
            label = "+10s"
        else if id = "next"
            label = "Next"
            value = "episode"
        else if id = "audio"
            label = "Audio"
            value = audioLabel()
        else if id = "subs"
            label = "Subtitles"
            value = subText
        else if id = "sleep"
            label = "Sleep"
            value = sleepShort()
        else if id = "like"
            if r > 0 then label = "Liked" else label = "Like"
        else if id = "dislike"
            if r < 0 then label = "Disliked" else label = "Dislike"
        else if id = "mylist"
            label = "My List"
            if listed then value = "Added"
        end if
        focused = m.btns[id].hasFocus()
        it.name.text = label
        if focused then it.name.color = "0xFFFFFFFF" else it.name.color = "0xFFFFFFBF"
        if focused then it.name.font = "font:SmallestBoldSystemFont" else it.name.font = "font:SmallestSystemFont"
        it.value.text = value
        if m.btns[id].checked and id <> "like" and id <> "dislike" then it.value.color = accent else it.value.color = "0xFFFFFF8C"
    end for
end sub

sub updatePlayIcon()
    refreshBar()
end sub

sub onBarFocus(e as Object)
    b = e.getRoSGNode()
    if b.hasFocus()
        refreshBar()
        bumpMenu()
    end if
end sub

function audioLabel() as String
    tracks = m.video.availableAudioTracks
    if tracks = invalid or tracks.Count() = 0 then return "Default"
    for each t in tracks
        if tostr(t.Track) = tostr(m.video.currentAudioTrack) then return langName(langNormalize(tostr(t.Language)))
    end for
    return langName(langNormalize(tostr(tracks[0].Language)))
end function

function subtitleLabel() as String
    if m.video.globalCaptionMode <> "On" then return "Off"
    tracks = m.video.availableSubtitleTracks
    if tracks <> invalid
        for each t in tracks
            if tostr(t.TrackName) = tostr(m.video.currentSubtitleTrack)
                l = tostr(t.Language)
                if l <> "" then return langName(langNormalize(l))
                return tostr(t.Description)
            end if
        end for
    end if
    return "On"
end function

' OK on Audio or Subtitles switches to the next track; holding OK lists every track.
sub cycleAudio()
    tracks = m.video.availableAudioTracks
    if tracks = invalid or tracks.Count() < 2
        toast("This stream has a single audio track")
        return
    end if
    i = 0
    for j = 0 to tracks.Count() - 1
        if tostr(tracks[j].Track) = tostr(m.video.currentAudioTrack) then i = j
    end for
    t = tracks[(i + 1) MOD tracks.Count()]
    m.video.audioTrack = t.Track
    toast("Audio: " + langName(langNormalize(tostr(t.Language))))
end sub

sub cycleSubs()
    tracks = m.video.availableSubtitleTracks
    if tracks = invalid or tracks.Count() = 0
        toast("No subtitles for this stream")
        return
    end if
    if m.video.globalCaptionMode <> "On"
        m.video.subtitleTrack = tracks[0].TrackName
        m.video.globalCaptionMode = "On"
    else
        i = -1
        for j = 0 to tracks.Count() - 1
            if tostr(tracks[j].TrackName) = tostr(m.video.currentSubtitleTrack) then i = j
        end for
        if i + 1 >= tracks.Count()
            m.video.globalCaptionMode = "Off"
        else
            m.video.subtitleTrack = tracks[i + 1].TrackName
        end if
    end if
    refreshBar()
end sub

' ---- sleep timer (port of SleepTimer) ----

function SLEEP_OPTIONS() as Object
    return [
        { label: "Off", min: 0 }, { label: "15 min", min: 15 }, { label: "30 min", min: 30 }
        { label: "1 hour", min: 60 }, { label: "90 min", min: 90 }, { label: "End of episode", min: -1 }
    ]
end function

sub cycleSleepTimer()
    opts = SLEEP_OPTIONS()
    m.sleepIdx = (m.sleepIdx + 1) MOD opts.Count()
    o = opts[m.sleepIdx]
    m.sleepTimer.control = "stop"
    if o.min > 0
        m.sleepTimer.duration = o.min * 60
        m.sleepTimer.control = "start"
        m.sleepClock = CreateObject("roTimespan")
    end if
    if o.min = 0 then toast("Sleep timer off") else toast("Sleep: " + o.label)
    refreshBar()
end sub

function sleepShort() as String
    o = SLEEP_OPTIONS()[m.sleepIdx]
    if o.min = 0 then return "Off"
    if o.min < 0 then return "End of ep."
    remain = o.min - Int(m.sleepClock.TotalSeconds() / 60)
    if remain < 1 then remain = 1
    return tostr(remain) + " min"
end function

sub onSleepTimer()
    goToSleep()
end sub

sub goToSleep()
    m.sleepIdx = 0
    saveProgress(true)
    m.video.control = "pause"
    m.finished = true
    toast("Sleep timer: stopped playback")
    m.top.navigateTo = { to: "back" }
end sub

sub openMenu(target as String)
    m.menu.visible = true
    m.scrub.visible = false
    m.seekBar.position = currentPos()
    m.seekBar.duration = m.video.duration
    refreshBar()
    if target = "seek"
        m.seek.setFocus(true)
    else
        m.bar.focusIndex = 0
        m.bar.setFocus(true)
    end if
    bumpMenu()
end sub

sub closeMenu()
    m.menu.visible = false
    m.hideTimer.control = "stop"
    m.top.setFocus(true)
end sub

sub bumpMenu()
    m.hideTimer.control = "stop"
    if m.video.state = "playing" then m.hideTimer.control = "start"
end sub

sub onHideTimer()
    if m.menu.visible and m.video.state = "playing" and m.holdDir = 0 then closeMenu()
end sub

sub onSeekFocus()
    m.seekBar.highlight = m.seek.hasFocus()
    m.hint.visible = m.seek.hasFocus()
end sub

sub togglePlay()
    if m.video.state = "paused" then m.video.control = "resume" else m.video.control = "pause"
end sub

sub seekBy(sec as Float)
    t = currentPos() + sec
    if t < 0 then t = 0
    if m.video.duration > 0 and t > m.video.duration - 2 then t = m.video.duration - 2
    seekTo(t)
    if m.menu.visible then m.seekBar.position = t
end sub

sub onBarPressed(e as Object)
    id = e.getRoSGNode().data.id
    m.autoplayed = 0
    bumpMenu()
    if id = "audio" or id = "subs"
        ' decided on release: a tap cycles, a hold opens the full list
        m.okTarget = id
        m.okTimer.control = "start"
        return
    end if
    if id = "play"
        togglePlay()
    else if id = "back10"
        seekBy(-10)
    else if id = "fwd10"
        seekBy(10)
    else if id = "sleep"
        cycleSleepTimer()
    else if id = "like"
        if ratingOf(m.meta.id) > 0 then rateTitle(m.meta, 0) else rateTitle(m.meta, 1)
    else if id = "dislike"
        if ratingOf(m.meta.id) < 0 then rateTitle(m.meta, 0) else rateTitle(m.meta, -1)
    else if id = "mylist"
        toggleMyList(m.meta)
    else if id = "next"
        loadNextStreams(true)
    end if
    refreshBar()
end sub

sub onOkHeld()
    id = m.okTarget
    m.okTarget = invalid
    if id = "audio" then chooseAudio()
    if id = "subs" then chooseSubs()
end sub

sub onOkReleased()
    if m.okTarget = invalid then return
    m.okTimer.control = "stop"
    id = m.okTarget
    m.okTarget = invalid
    if id = "audio" then cycleAudio()
    if id = "subs" then cycleSubs()
    refreshBar()
end sub

sub chooseAudio()
    tracks = m.video.availableAudioTracks
    if tracks = invalid or tracks.Count() = 0
        toast("This stream has a single audio track")
        return
    end if
    opts = []
    for each t in tracks
        name = tostr(t.Name)
        lang = langName(langNormalize(tostr(t.Language)))
        label = lang
        if name <> "" and name <> lang then label = lang + " · " + name
        if tostr(t.Format) <> "" then label = label + " (" + t.Format + ")"
        opts.Push({ id: tostr(t.Track), label: label, checked: tostr(t.Track) = tostr(m.video.currentAudioTrack) })
    end for
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = "Audio"
    dlg.options = opts
    dlg.observeField("chosen", "onAudioChosen")
    m.top.getScene().callFunc("pushDialog", dlg)
end sub

sub onAudioChosen(e as Object)
    m.video.audioTrack = e.getData()
end sub

sub chooseSubs()
    tracks = m.video.availableSubtitleTracks
    opts = [{ id: "__off", label: "Off", checked: m.video.globalCaptionMode <> "On" }]
    if tracks <> invalid
        for each t in tracks
            desc = tostr(t.Description)
            if desc = "" then desc = langName(langNormalize(tostr(t.Language)))
            opts.Push({ id: tostr(t.TrackName), label: desc, checked: m.video.globalCaptionMode = "On" and tostr(m.video.currentSubtitleTrack) = tostr(t.TrackName) })
        end for
    end if
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = "Subtitles"
    dlg.message = "Subtitle size and style follow your Roku's caption settings (Settings → Accessibility → Captions style)."
    dlg.options = opts
    dlg.observeField("chosen", "onSubChosen")
    m.top.getScene().callFunc("pushDialog", dlg)
end sub

sub onSubChosen(e as Object)
    id = e.getData()
    if id = "__off"
        m.video.globalCaptionMode = "Off"
    else
        m.video.subtitleTrack = id
        m.video.globalCaptionMode = "On"
    end if
end sub

' ---- scrubbing ----
' Port of PlayerActivity.scrub / startHoldScrub. Roku sends one press and one release per key, so
' holding is timed here: a tap jumps a step (15 s → 60 s when pressed quickly), holding moves the
' preview smoothly (10 s → 5 min of video per second held) and seeks once on release.

sub scrub(dir as Integer)
    if m.lastScrubKey.TotalMilliseconds() < 700 and dir = m.lastScrubDir then m.scrubCount = m.scrubCount + 1 else m.scrubCount = 0
    m.lastScrubKey.Mark()
    m.lastScrubDir = dir
    steps = [15, 30, 60]
    level = Int(m.scrubCount / 2)
    if level > 2 then level = 2
    moveScrub(dir * steps[level])
    m.seekTimer.control = "stop"
    m.seekTimer.control = "start"
end sub

sub moveScrub(delta as Float)
    if m.scrubTarget < 0 then m.scrubTarget = currentPos()
    m.scrubTarget = m.scrubTarget + delta
    if m.scrubTarget < 0 then m.scrubTarget = 0
    d = m.video.duration
    if d > 0 and m.scrubTarget > d - 2 then m.scrubTarget = d - 2
    if m.menu.visible
        m.seekBar.position = m.scrubTarget
        bumpMenu()
    else
        m.scrub.visible = true
        m.scrubBar.highlight = true
        m.scrubBar.duration = d
        m.scrubBar.position = m.scrubTarget
    end if
end sub

' Key down on Left/Right/FF/Rewind: one step now; if still held after 0.4 s, smooth scrubbing.
sub startHold(dir as Integer)
    if m.holdDir = dir then return
    m.holdDir = dir
    m.holdStarted = false
    m.holdClock.Mark()
    m.seekTimer.control = "stop"
    scrub(dir)
    m.holdTimer.control = "start"
end sub

sub onHoldTick()
    if m.holdDir = 0 then return
    ms = m.holdClock.TotalMilliseconds()
    if ms < 400 then return
    if not m.holdStarted
        m.holdStarted = true
        m.lastHoldMs = ms
    end if
    held = (ms - 400) / 1000.0
    rate = 10.0 * (1.75 ^ held)
    if rate > 300 then rate = 300
    moveScrub(m.holdDir * rate * (ms - m.lastHoldMs) / 1000.0)
    m.lastHoldMs = ms
end sub

sub stopHold()
    if m.holdDir = 0 then return
    m.holdDir = 0
    m.holdTimer.control = "stop"
    if m.holdStarted
        commitScrub()
    else
        m.seekTimer.control = "stop"
        m.seekTimer.control = "start"
    end if
end sub

sub commitScrub()
    m.seekTimer.control = "stop"
    if m.holdDir <> 0 then return
    if m.scrubTarget >= 0
        t = m.scrubTarget
        m.scrubTarget = -1
        seekTo(t)
        if m.menu.visible then m.seekBar.position = t
    else
        m.scrub.visible = false
    end if
end sub

' ---- skip intro / recap ----

sub loadSegments()
    if not bool(m.settings.skipIntroButton) and m.nextVideo = invalid then return
    season = invalid
    episode = invalid
    for each v in m.videos
        if v.id = m.videoId
            season = v.season
            episode = v.episode
        end if
    end for
    m.skipTask = CreateObject("roSGNode", "SkipTask")
    m.skipTask.params = { meta: m.meta, videoId: m.videoId, season: season, episode: episode, durationSec: Int(m.video.duration) }
    m.skipTask.observeField("segments", "onSegments")
    m.skipTask.control = "run"
end sub

sub onSegments()
    m.segments = m.skipTask.segments
end sub

function activeSegment(curPos as Float) as Dynamic
    for each s in m.segments
        en = s.end
        if en < 0 then en = m.video.duration
        if curPos >= s.start and curPos < en - 1 then return s
    end for
    return invalid
end function

sub updateSkip(curPos as Float)
    if not bool(m.settings.skipIntroButton)
        m.skipBtn.visible = false
        return
    end if
    s = activeSegment(curPos)
    show = s <> invalid and s.type <> "credits" and not m.menu.visible and not m.nextCard.visible
    if show
        labels = { intro: "Skip intro", recap: "Skip recap", preview: "Skip preview" }
        m.skipBtn.text = labels[s.type]
        m.skipBtn.translation = [1216 - m.skipBtn.width, 600]
        m.skipSeg = s
    end if
    if m.skipBtn.visible <> show
        m.skipBtn.visible = show
        if show then m.skipBtn.setFocus(true) else if m.skipBtn.hasFocus() then m.top.setFocus(true)
    end if
end sub

sub onSkip()
    s = m.skipSeg
    if s = invalid then return
    en = s.end
    if en < 0 then en = m.video.duration - 1
    seekTo(en)
    m.skipBtn.visible = false
    m.top.setFocus(true)
end sub

' ---- next episode ----

function findNextVideo() as Dynamic
    if m.videos.Count() = 0 then return invalid
    list = []
    for each v in m.videos
        k = v.season
        if k = 0 then k = 100000
        list.Push({ v: v, k: k * 10000 + v.episode })
    end for
    list.SortBy("k")
    for i = 0 to list.Count() - 2
        if list[i].v.id = m.videoId
            nxt = list[i + 1].v
            cur = list[i].v
            if cur.season > 0 and nxt.season = 0 then return invalid
            return nxt
        end if
    end for
    return invalid
end function

function episodeTitle(v as Object) as String
    if v.season >= 0 then return "S" + tostr(v.season) + " E" + tostr(v.episode) + " · " + v.title
    return v.title
end function

sub checkNextUp(curPos as Float)
    if m.nextVideo = invalid or not bool(m.settings.autoplayNext) then return
    if SLEEP_OPTIONS()[m.sleepIdx].min < 0 then return
    d = m.video.duration
    if d <= 0 then return
    if curPos / d > 0.8 and m.nextTask = invalid then loadNextStreams(false)
    if m.nextCard.visible or m.dismissedCredits then return
    creditsAt = d - 12
    for each s in m.segments
        if s.type = "credits" and s.start > d * 0.5 then creditsAt = s.start
    end for
    if curPos >= creditsAt then showNextCard()
end sub

sub loadNextStreams(playWhenReady as Boolean)
    m.playNextWhenReady = playWhenReady
    if m.nextStream <> invalid
        if playWhenReady then playNext()
        return
    end if
    if m.nextTask = invalid
        m.nextTask = CreateObject("roSGNode", "StreamTask")
        m.nextTask.observeField("result", "onNextStreams")
        m.nextTask.control = "run"
        m.nextTask.request = { action: "load", reqId: 1, type: m.meta.type, videoId: m.nextVideo.id, addons: m.global.addons, settings: m.global.settings, filter: m.global.streamFilter }
    end if
    if playWhenReady then toast("Finding a cached stream for the next episode…")
end sub

sub onNextStreams()
    r = m.nextTask.result
    if r = invalid then return
    cands = []
    ' prefer the same release group (addon bingeGroup) as the current stream
    cur = m.candidates[m.candIdx]
    content = r.content
    if cur.bingeGroup <> "" and content <> invalid
        for i = 0 to content.getChildCount() - 1
            s = content.getChild(i).stream
            if s.bingeGroup = cur.bingeGroup and cands.Count() = 0 then cands.Push(s)
        end for
    end if
    if content <> invalid
        for i = 0 to content.getChildCount() - 1
            s = content.getChild(i).stream
            if cands.Count() < 5 and (cands.Count() = 0 or cands[0].key <> s.key) then cands.Push(s)
        end for
    end if
    if cands.Count() = 0
        m.nextStream = invalid
        if m.playNextWhenReady then toast("No cached streams for the next episode")
        return
    end if
    m.nextStream = { candidates: cands, subs: r.subs }
    if m.playNextWhenReady then playNext()
end sub

sub showNextCard()
    if m.nextVideo = invalid then return
    stillN = toInt(m.settings.stillWatchingEpisodes)
    if bool(m.settings.stillWatchingPrompt) and stillN > 0 and m.autoplayed >= stillN
        askStillWatching()
        return
    end if
    m.nextHeading.text = "Next episode"
    m.nextTitle.text = episodeTitle(m.nextVideo)
    m.countdown = toInt(m.settings.autoplayCountdownSec)
    if m.countdown <= 0 then m.countdown = 10
    m.nextButtons.callFunc("clearItems")
    play = CreateObject("roSGNode", "TvButton")
    play.text = "Play now"
    play.primary = true
    play.icon = "pkg:/images/ic_play.png"
    play.observeField("pressed", "onPlayNow")
    cancel = CreateObject("roSGNode", "TvButton")
    cancel.text = "Cancel"
    cancel.observeField("pressed", "cancelCountdown")
    m.nextButtons.callFunc("addItem", play)
    m.nextButtons.callFunc("addItem", cancel)
    m.nextCard.translation = [1280 - 460 - 53, 720 - 168 - 53]
    m.nextCard.visible = true
    m.skipBtn.visible = false
    if m.menu.visible then closeMenu()
    m.nextButtons.setFocus(true)
    renderCountdown()
end sub

sub renderCountdown()
    if m.countdown > 0 then m.nextHeading.text = "Next episode in " + tostr(m.countdown) + "s"
end sub

sub onPlayNow()
    m.autoplayed = 0
    playNext()
end sub

sub cancelCountdown()
    m.countdown = -1
    m.nextCard.visible = false
    m.dismissedCredits = true
    m.top.setFocus(true)
    if m.video.state = "finished" then m.top.navigateTo = { to: "back" }
end sub

sub playNext()
    if m.nextVideo = invalid then return
    if m.nextStream = invalid
        loadNextStreams(true)
        return
    end if
    if m.countdown = 0 then m.autoplayed = m.autoplayed + 1
    saveProgress(true)
    m.countdown = -1
    m.nextCard.visible = false
    v = m.nextVideo
    m.videoId = v.id
    m.labelText = episodeTitle(v)
    m.label.text = m.labelText
    m.finished = false
    m.candidates = m.nextStream.candidates
    m.subs = m.nextStream.subs
    m.candIdx = 0
    m.formatTried = {}
    m.segments = []
    m.dismissedCredits = false
    m.nextStream = invalid
    if m.nextTask <> invalid then m.nextTask.control = "stop"
    m.nextTask = invalid
    m.nextVideo = findNextVideo()
    buildBar()
    m.video.control = "stop"
    beginResume(0)
    startCandidate(0)
    m.top.setFocus(true)
end sub

sub askStillWatching()
    if m.stillDlg <> invalid then return
    m.video.control = "pause"
    dlg = CreateObject("roSGNode", "ChoiceDialog")
    dlg.title = "Are you still watching?"
    dlg.options = [{ id: "yes", label: "Continue watching" }, { id: "never", label: "Continue, and don't ask again" }, { id: "stop", label: "Stop" }]
    dlg.observeField("chosen", "onStillChosen")
    dlg.observeField("closed", "onStillClosed")
    m.stillDlg = dlg
    m.top.getScene().callFunc("pushDialog", dlg)
    ' Nobody answered in 5 minutes: leave the player (the Roku screensaver takes it from there).
    m.stillTimer = CreateObject("roSGNode", "Timer")
    m.stillTimer.duration = 300
    m.stillTimer.observeField("fire", "onStillTimeout")
    m.stillTimer.control = "start"
end sub

sub onStillClosed()
    m.stillDlg = invalid
    if m.stillTimer <> invalid then m.stillTimer.control = "stop"
end sub

sub onStillTimeout()
    if m.stillDlg = invalid then return
    m.top.getScene().callFunc("closeDialog", { node: m.stillDlg })
    onStillClosed()
    m.autoplayed = 0
    m.top.navigateTo = { to: "back" }
end sub

sub onStillChosen(e as Object)
    id = e.getData()
    onStillClosed()
    m.autoplayed = 0
    if id = "stop"
        m.top.navigateTo = { to: "back" }
        return
    end if
    if id = "never"
        s = m.global.settings
        s.stillWatchingPrompt = false
        m.top.getScene().callFunc("applySettings", { settings: s })
        m.settings = s
    end if
    ' The episode this starts is the first of the next run, so the question comes back after the set number.
    m.autoplayed = 1
    if m.video.state = "finished" then playNext() else m.video.control = "resume"
end sub

sub onFinished()
    if SLEEP_OPTIONS()[m.sleepIdx].min < 0
        goToSleep()
        return
    end if
    if m.nextVideo <> invalid and bool(m.settings.autoplayNext)
        if not m.nextCard.visible then showNextCard()
        return
    end if
    m.top.navigateTo = { to: "back" }
end sub

' ---- keys ----

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press
        if key = "left" or key = "right" or key = "rewind" or key = "fastforward"
            if m.holdDir <> 0
                stopHold()
                return true
            end if
        else if key = "OK"
            onOkReleased()
        end if
        return false
    end if
    m.autoplayed = 0
    ' media keys work everywhere
    if key = "play"
        togglePlay()
        return true
    else if key = "rewind"
        startHold(-1)
        return true
    else if key = "fastforward"
        startHold(1)
        return true
    else if key = "replay"
        seekBy(-10)
        return true
    end if

    if m.nextCard.visible
        if key = "back"
            cancelCountdown()
            return true
        end if
        return false
    end if

    if m.menu.visible
        bumpMenu()
        if key = "back"
            closeMenu()
            return true
        end if
        if m.seek.hasFocus()
            if key = "left" then startHold(-1)
            if key = "right" then startHold(1)
            if key = "OK" then togglePlay()
            if key = "up" then closeMenu()
            if key = "down" then m.bar.setFocus(true)
            return true
        end if
        if key = "up"
            m.seek.setFocus(true)
            return true
        end if
        return true
    end if

    if m.skipBtn.visible and m.skipBtn.hasFocus() and key = "OK" then return false
    if key = "OK"
        if m.video.state = "playing" then m.video.control = "pause"
        openMenu("play")
        return true
    else if key = "left"
        startHold(-1)
        return true
    else if key = "right"
        startHold(1)
        return true
    else if key = "up" or key = "down" or key = "options"
        openMenu("play")
        return true
    else if key = "back"
        if not m.finished = true then saveProgress(true)
        m.finished = true
        m.top.navigateTo = { to: "back" }
        return true
    end if
    return false
end function
