sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    current = manifestVersion()
    r = httpGetJson("https://api.github.com/repos/demerzelle/Zemu/releases/latest")
    if not isAA(r) or not isArr(r.assets) then return
    latest = tostr(r.tag_name)
    if startsWith(latest, "v") then latest = Mid(latest, 2)
    hasZip = false
    for each a in r.assets
        if startsWith(tostr(a.name), "Zemu-Roku-") then hasZip = true
    end for
    if hasZip and isNewerVersion(latest, current) then m.top.update = { version: latest, current: current }
end sub

' "major.minor.build" from the manifest.
function manifestVersion() as String
    v = { major_version: "0", minor_version: "0", build_version: "0" }
    for each line in ReadAsciiFile("pkg:/manifest").Split(Chr(10))
        kv = line.Trim().Split("=")
        if kv.Count() = 2 and v.DoesExist(kv[0]) then v[kv[0]] = kv[1]
    end for
    return toInt(v.major_version).ToStr() + "." + toInt(v.minor_version).ToStr() + "." + toInt(v.build_version).ToStr()
end function

' "1.0.10" > "1.0.9"; a missing part counts as 0.
function isNewerVersion(a as String, b as String) as Boolean
    x = a.Split(".")
    y = b.Split(".")
    n = x.Count()
    if y.Count() > n then n = y.Count()
    for i = 0 to n - 1
        p = 0
        q = 0
        if i < x.Count() then p = toInt(x[i])
        if i < y.Count() then q = toInt(y[i])
        if p <> q then return p > q
    end for
    return false
end function
