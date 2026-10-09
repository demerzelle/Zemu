' Shared helpers. Safe to include from both the render thread and Task threads.

function isStr(v as Dynamic) as Boolean
    t = Type(v)
    return t = "String" or t = "roString"
end function

function isArr(v as Dynamic) as Boolean
    return Type(v) = "roArray"
end function

function isAA(v as Dynamic) as Boolean
    return Type(v) = "roAssociativeArray"
end function

function isNum(v as Dynamic) as Boolean
    t = Type(v)
    return t = "Integer" or t = "roInt" or t = "roInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" or t = "LongInteger" or t = "roLongInteger"
end function

' Lenient string: numbers become text, everything else (invalid, objects) becomes "".
function tostr(v as Dynamic) as String
    if isStr(v) then return v
    if isNum(v)
        t = Type(v)
        if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" then return Str(v).Trim()
        if v = Int(v) and Abs(v) < 2000000000 then return Str(Int(v)).Trim()
        return Str(v).Trim()
    end if
    if Type(v) = "Boolean" or Type(v) = "roBoolean"
        if v then return "true"
        return "false"
    end if
    return ""
end function

' Lenient list of strings from an array, a comma-separated string, or nothing.
function strList(v as Dynamic) as Object
    out = []
    if isArr(v)
        for each x in v
            s = tostr(x)
            if s <> "" then out.Push(s)
        end for
    else if isStr(v) and v <> ""
        for each x in v.Split(",")
            s = x.Trim()
            if s <> "" then out.Push(s)
        end for
    end if
    return out
end function

function toNum(v as Dynamic) as Double
    if isNum(v) then return v
    if isStr(v) and v <> "" then return Val(v)
    return 0
end function

function toInt(v as Dynamic) as Integer
    if isNum(v) then return Int(v)
    if isStr(v) and v <> "" then return Int(Val(v))
    return 0
end function

function bool(v as Dynamic) as Boolean
    if Type(v) = "Boolean" or Type(v) = "roBoolean" then return v
    if isStr(v) then return LCase(v) = "true"
    if isNum(v) then return v <> 0
    return false
end function

function joinArr(arr as Object, sep as String) as String
    out = ""
    first = true
    for each x in arr
        if first
            out = tostr(x)
            first = false
        else
            out = out + sep + tostr(x)
        end if
    end for
    return out
end function

function arrHas(arr as Object, v as Dynamic) as Boolean
    if arr = invalid then return false
    for each x in arr
        if x = v then return true
    end for
    return false
end function

function arrTake(arr as Object, n as Integer) as Object
    out = []
    if arr = invalid then return out
    for each x in arr
        if out.Count() >= n then exit for
        out.Push(x)
    end for
    return out
end function

function aaGet(aa as Dynamic, key as String, default = invalid as Dynamic) as Dynamic
    if not isAA(aa) then return default
    v = aa.Lookup(key)
    if v = invalid then return default
    return v
end function

function startsWith(s as String, prefix as String) as Boolean
    return Left(s, Len(prefix)) = prefix
end function

function endsWith(s as String, suffix as String) as Boolean
    return Right(s, Len(suffix)) = suffix
end function

function substringBefore(s as String, sep as String) as String
    i = Instr(1, s, sep)
    if i = 0 then return s
    return Left(s, i - 1)
end function

function substringAfter(s as String, sep as String, default = "" as String) as String
    i = Instr(1, s, sep)
    if i = 0 then return default
    return Mid(s, i + Len(sep))
end function

function trimEndChar(s as String, c as String) as String
    while Len(s) > 0 and Right(s, 1) = c
        s = Left(s, Len(s) - 1)
    end while
    return s
end function

function replaceAll(s as String, a as String, b as String) as String
    if a = "" then return s
    return s.Replace(a, b)
end function

function capitalize(s as String) as String
    if s = "" then return s
    return UCase(Left(s, 1)) + Mid(s, 2)
end function

function urlEnc(s as String) as String
    if m.__xfer = invalid then m.__xfer = CreateObject("roUrlTransfer")
    return m.__xfer.Escape(s)
end function

function md5(s as String) as String
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(s)
    d = CreateObject("roEVPDigest")
    d.Setup("md5")
    return d.Process(ba)
end function

function nowSec() as Integer
    dt = CreateObject("roDateTime")
    return dt.AsSeconds()
end function

' Local calendar day number; changes at midnight so daily rows rotate.
function daySeed() as Integer
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    return Int(dt.AsSeconds() / 86400)
end function

' "yyyy-MM-dd" for N days ago (UTC is close enough for release-date windows).
function dateString(daysAgo as Integer) as String
    dt = CreateObject("roDateTime")
    dt.FromSeconds(dt.AsSeconds() - daysAgo * 86400)
    return Left(dt.ToISOString(), 10)
end function

function fmt1(v as Double) as String
    tenths = Int(v * 10 + 0.5)
    return tostr(Int(tenths / 10)) + "." + tostr(tenths MOD 10)
end function

function pad2(n as Integer) as String
    if n < 10 then return "0" + tostr(n)
    return tostr(n)
end function

function formatTime(sec as Dynamic) as String
    total = Int(toNum(sec))
    if total < 0 then total = 0
    h = Int(total / 3600)
    mm = Int((total MOD 3600) / 60)
    s = total MOD 60
    if h > 0 then return tostr(h) + ":" + pad2(mm) + ":" + pad2(s)
    return tostr(mm) + ":" + pad2(s)
end function

function formatSize(bytes as Double) as String
    gb = bytes / 1073741824#
    if gb >= 1 then return fmt1(gb) + " GB"
    return tostr(Int(bytes / 1048576# + 0.5)) + " MB"
end function

' Removes emoji and other characters the Roku system font can't draw, and squashes whitespace.
function cleanText(s as String) as String
    if s = "" then return s
    out = ""
    n = Len(s)
    lastSpace = true
    for i = 1 to n
        ch = Mid(s, i, 1)
        c = Asc(ch)
        if c = 10 or c = 13 or c = 9 or c = 32
            if not lastSpace then out = out + " "
            lastSpace = true
        else if c < 32 or (c >= &h2190 and c <= &h2BFF) or (c >= &hD800 and c <= &hF8FF) or c >= &hFE00
            ' arrows, symbols, dingbats, surrogates/private use, variation selectors, emoji
        else
            out = out + ch
            lastSpace = false
        end if
    end for
    return out.Trim()
end function

' Seeded PRNG (LCG) so "daily" choices stay stable for the whole day.
function newRng(seed as Dynamic) as Object
    s& = toInt(seed)
    if s& < 0 then s& = -s&
    s& = (s& MOD 2147483647) + 1
    return {
        state: s&
        nextFloat: function() as Double
            m.state = (m.state * 48271&) MOD 2147483647&
            return m.state / 2147483647#
        end function
        nextInt: function(n as Integer) as Integer
            if n <= 0 then return 0
            return Int(m.nextFloat() * n)
        end function
    }
end function

function shuffled(arr as Object, seed as Dynamic) as Object
    out = []
    for each x in arr
        out.Push(x)
    end for
    rng = newRng(seed)
    i = out.Count() - 1
    while i > 0
        j = rng.nextInt(i + 1)
        t = out[i]
        out[i] = out[j]
        out[j] = t
        i = i - 1
    end while
    return out
end function

function hashStr(s as String) as Integer
    h& = 0
    n = Len(s)
    for i = 1 to n
        h& = (h& * 31 + Asc(Mid(s, i, 1))) MOD 2147483647&
    end for
    return h&
end function

function readJsonFile(path as String) as Dynamic
    fs = CreateObject("roFileSystem")
    if not fs.Exists(path) then return invalid
    raw = ReadAsciiFile(path)
    if raw = "" then return invalid
    return ParseJson(raw)
end function

function writeJsonFile(path as String, v as Dynamic) as Boolean
    return WriteAsciiFile(path, FormatJson(v))
end function

' ---- HTTP (Task threads only: these block) ----

' Percent-encodes characters roUrlTransfer rejects. Configured addons put them in the path,
' e.g. Torrentio "providers=yts,eztv|realdebrid=KEY" or AIOStreams base64 with spaces/quotes.
function safeUrl(url as String) as String
    out = ""
    n = Len(url)
    for i = 1 to n
        ch = Mid(url, i, 1)
        c = Asc(ch)
        if c <= 32 or c >= 127 or ch = "|" or ch = Chr(34) or ch = "<" or ch = ">" or ch = "{" or ch = "}" or ch = "^" or ch = "`" or ch = "\"
            ba = CreateObject("roByteArray")
            ba.FromAsciiString(ch)
            for each b in ba
                out = out + "%" + UCase(Right("0" + StrI(b, 16), 2))
            end for
        else
            out = out + ch
        end if
    end for
    return out
end function

function newXfer(url as String) as Object
    x = CreateObject("roUrlTransfer")
    x.SetUrl(safeUrl(url))
    if startsWith(LCase(url), "https")
        x.SetCertificatesFile("common:/certs/ca-bundle.crt")
        x.InitClientCertificates()
    end if
    x.EnableEncodings(true)
    x.RetainBodyOnError(true)
    x.AddHeader("User-Agent", "Zemu/1.0 (Roku)")
    x.AddHeader("Accept", "application/json")
    return x
end function

' GETs several URLs in parallel (at most maxParallel at once, so low-memory TVs cope).
' Returns one body per URL ("" on failure or timeout). The timeout applies to each request.
' Each transfer gets its own port: roUrlEvent source identities come back as floats on some
' firmware and can't be matched reliably.
function httpGetMany(urls as Object, timeoutMs = 20000 as Integer, maxParallel = 6 as Integer) as Object
    results = []
    for i = 0 to urls.Count() - 1
        results.Push("")
    end for
    active = []
    nextIdx = 0
    while nextIdx < urls.Count() or active.Count() > 0
        while nextIdx < urls.Count() and active.Count() < maxParallel
            x = newXfer(urls[nextIdx])
            port = CreateObject("roMessagePort")
            x.SetMessagePort(port)
            if x.AsyncGetToString() then active.Push({ x: x, port: port, i: nextIdx, t: CreateObject("roTimespan") })
            nextIdx = nextIdx + 1
        end while
        if active.Count() = 0 then exit while
        progressed = false
        still = []
        for each a in active
            msg = a.port.GetMessage()
            if Type(msg) = "roUrlEvent"
                progressed = true
                if msg.GetResponseCode() = 200
                    results[a.i] = msg.GetString()
                else
                    print "[zemu] http "; msg.GetResponseCode(); " "; msg.GetFailureReason(); " "; urls[a.i]
                    m.lastHttpError = httpErrorText(msg.GetResponseCode(), msg.GetFailureReason())
                end if
            else if a.t.TotalMilliseconds() > timeoutMs
                a.x.AsyncCancel()
                print "[zemu] http timeout "; urls[a.i]
                m.lastHttpError = "the server didn't answer in time"
            else
                still.Push(a)
            end if
        end for
        active = still
        if not progressed and active.Count() > 0 then Sleep(20)
    end while
    return results
end function

function httpGet(url as String, timeoutMs = 20000 as Integer) as String
    return httpGetMany([url], timeoutMs)[0]
end function

function httpGetJson(url as String, timeoutMs = 20000 as Integer) as Dynamic
    body = httpGet(url, timeoutMs)
    if body = "" then return invalid
    return ParseJson(body)
end function

function httpGetJsonMany(urls as Object, timeoutMs = 20000 as Integer) as Object
    out = []
    for each body in httpGetMany(urls, timeoutMs)
        if body = "" then out.Push(invalid) else out.Push(ParseJson(body))
    end for
    return out
end function

function httpErrorText(code as Integer, reason as String) as String
    if code > 0 then return "the server answered HTTP " + tostr(code)
    r = reason.Trim()
    if r = "" then r = "network error " + tostr(code)
    return r
end function
