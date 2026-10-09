sub init()
    m.top.functionName = "execute"
end sub

function localIp() as String
    di = CreateObject("roDeviceInfo")
    ips = di.GetIPAddrs()
    for each k in ips
        return ips[k]
    end for
    return ""
end function

sub execute()
    port = CreateObject("roMessagePort")
    m.top.observeField("control", port)
    addr = CreateObject("roSocketAddress")
    addr.setPort(m.top.port)
    server = CreateObject("roStreamSocket")
    server.setMessagePort(port)
    server.setAddress(addr)
    server.notifyReadable(true)
    if not server.listen(4)
        print "[zemu] remote input: listen failed"
        return
    end if
    m.top.address = "http://" + localIp() + ":" + tostr(m.top.port)
    conns = {}
    while true
        msg = Wait(500, port)
        if Type(msg) = "roSGNodeEvent"
            if LCase(tostr(msg.getData())) = "stop" then exit while
        else if Type(msg) = "roSocketEvent"
            id = tostr(Int(msg.getSocketID()))
            if id = tostr(Int(server.getID()))
                if server.isReadable()
                    c = server.accept()
                    if c <> invalid
                        c.setMessagePort(port)
                        c.notifyReadable(true)
                        conns[tostr(Int(c.getID()))] = { sock: c, data: "" }
                    end if
                end if
            else if conns.DoesExist(id)
                entry = conns[id]
                s = entry.sock
                buf = CreateObject("roByteArray")
                buf[16383] = 0
                n = s.receive(buf, 0, 16384)
                if n > 0
                    chunk = CreateObject("roByteArray")
                    for i = 0 to n - 1
                        chunk.Push(buf[i])
                    end for
                    entry.data = entry.data + chunk.ToAsciiString()
                end if
                if requestComplete(entry.data)
                    handle(s, entry.data)
                    s.close()
                    conns.Delete(id)
                else if n <= 0 or not s.eOK()
                    s.close()
                    conns.Delete(id)
                end if
            end if
        end if
    end while
    for each k in conns
        conns[k].sock.close()
    end for
    server.close()
end sub

function requestComplete(data as String) as Boolean
    i = Instr(1, data, Chr(13) + Chr(10) + Chr(13) + Chr(10))
    if i = 0 then return false
    headers = LCase(Left(data, i))
    re = CreateObject("roRegex", "content-length:\s*(\d+)", "i")
    mm = re.Match(headers)
    if mm.Count() < 2 then return true
    return Len(data) - (i + 3) >= Val(mm[1])
end function

function urlDecode(s as String) as String
    x = CreateObject("roUrlTransfer")
    return x.Unescape(s.Replace("+", " "))
end function

sub handle(s as Object, data as String)
    firstLine = substringBefore(data, Chr(13))
    body = substringAfter(data, Chr(13) + Chr(10) + Chr(13) + Chr(10), "")
    msg = ""
    if m.top.reply <> "" then msg = "Last result: " + m.top.reply
    if startsWith(firstLine, "POST")
        text = ""
        for each pair in body.Split("&")
            if startsWith(pair, "url=") then text = urlDecode(Mid(pair, 5))
        end for
        text = text.Trim()
        if text <> ""
            m.top.reply = ""
            m.top.received = text
            msg = "Sent to your TV. Installing… the TV shows the result (reload this page to see it here)."
        else
            msg = "Paste a URL first."
        end if
    end if
    html = page(msg)
    res = "HTTP/1.1 200 OK" + Chr(13) + Chr(10) + "Content-Type: text/html; charset=utf-8" + Chr(13) + Chr(10) + "Connection: close" + Chr(13) + Chr(10) + "Content-Length: " + tostr(Len(html)) + Chr(13) + Chr(10) + Chr(13) + Chr(10) + html
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(res)
    ' Content-Length must be in bytes
    hb = CreateObject("roByteArray")
    hb.FromAsciiString(html)
    res = "HTTP/1.1 200 OK" + Chr(13) + Chr(10) + "Content-Type: text/html; charset=utf-8" + Chr(13) + Chr(10) + "Connection: close" + Chr(13) + Chr(10) + "Content-Length: " + tostr(hb.Count()) + Chr(13) + Chr(10) + Chr(13) + Chr(10) + html
    ba.FromAsciiString(res)
    sent = 0
    t = CreateObject("roTimespan")
    while sent < ba.Count() and t.TotalMilliseconds() < 5000
        n = s.send(ba, sent, ba.Count() - sent)
        if n > 0 then sent = sent + n else Sleep(20)
    end while
end sub

function page(msg as String) as String
    esc = msg.Replace("&", "&amp;").Replace("<", "&lt;")
    note = ""
    if esc <> "" then note = "<p class=msg>" + esc + "</p>"
    h = ""
    h = h + "<!doctype html><html><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>Zemu</title>"
    h = h + "<style>body{background:#07090a;color:#fff;font-family:-apple-system,system-ui,sans-serif;margin:0;padding:24px}h1{color:#39ff14;margin:0 0 8px}"
    h = h + "p{color:#b8b8c2;line-height:1.4}textarea{width:100%;box-sizing:border-box;min-height:120px;background:#1b1d1f;color:#fff;border:2px solid #333;border-radius:10px;padding:12px;font-size:16px}"
    h = h + "button{margin-top:12px;width:100%;padding:14px;border:0;border-radius:10px;background:#39ff14;color:#07130a;font-weight:700;font-size:17px}.msg{color:#fff;background:#1b1d1f;padding:12px;border-radius:10px}</style></head>"
    h = h + "<body><h1>zemu</h1><p>Paste an addon manifest URL (https://.../manifest.json or a stremio:// link). It installs straight onto your TV.</p>"
    h = h + note
    h = h + "<form method=post><textarea name=url placeholder='https://.../manifest.json' autofocus></textarea><button type=submit>Install on TV</button></form>"
    h = h + "<p>Tip: configure an addon on its own website (for example AIOStreams or Torrentio), copy its install link, and paste it here.</p></body></html>"
    return h
end function
