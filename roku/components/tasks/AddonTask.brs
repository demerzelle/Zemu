sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    req = m.top.request
    pid = req.profileId
    if pid = invalid or pid = "" then pid = "default"
    m.section = profileSection(pid)
    CreateDirectory("cachefs:/zemu")
    a = req.action
    if a = "boot"
        boot()
    else if a = "install"
        res = install(req.url, req.current)
        m.top.result = res
    else if a = "remove"
        m.top.result = remove(req.url, req.current)
    else if a = "move"
        m.top.result = move(req.url, req.delta, req.current)
    else if a = "browse"
        m.top.result = browse(req.source)
    else if a = "ensureKitsu"
        cur = req.current
        k = findAddon(cur, KITSU_ID())
        if k <> invalid
            m.top.result = { action: "ensureKitsu", ok: true, addons: cur }
        else
            r = install(KITSU_URL(), cur)
            r.action = "ensureKitsu"
            m.top.result = r
        end if
    end if
end sub

function cachePath(url as String) as String
    return "cachefs:/zemu/m_" + md5(url) + ".json"
end function

function savedUrls() as Dynamic
    v = regRead(m.section, "addons")
    if isArr(v) then return v
    return invalid
end function

function saveUrls(list as Object) as Boolean
    urls = []
    for each a in list
        urls.Push(a.transportUrl)
    end for
    return regWrite(m.section, "addons", urls)
end function

function fetchManifests(urls as Object) as Object
    out = []
    bodies = httpGetMany(urls, 15000)
    for i = 0 to urls.Count() - 1
        man = invalid
        if bodies[i] <> "" then man = compactManifest(ParseJson(bodies[i]), urls[i])
        if man <> invalid then writeJsonFile(cachePath(urls[i]), man)
        out.Push(man)
    end for
    return out
end function

sub boot()
    urls = savedUrls()
    firstRun = urls = invalid
    if firstRun then urls = DEFAULT_ADDONS()
    ' 1) instant start from cached manifests
    list = []
    missing = []
    for each u in urls
        man = readJsonFile(cachePath(u))
        if isAA(man) and man.id <> invalid
            list.Push(man)
        else
            missing.Push(u)
        end if
    end for
    if missing.Count() = 0 and list.Count() > 0
        m.top.addons = list
    end if
    ' 2) refresh everything from the network (keeps cached copies for addons that are down)
    fresh = fetchManifests(urls)
    out = []
    for i = 0 to urls.Count() - 1
        man = fresh[i]
        if man = invalid then man = readJsonFile(cachePath(urls[i]))
        if isAA(man) and man.id <> invalid then out.Push(man)
    end for
    if firstRun and out.Count() > 0 then saveUrls(out)
    m.top.addons = out
end sub

function install(input as String, current as Object) as Object
    url = normalizeTransportUrl(input)
    man = fetchManifests([url])[0]
    if man = invalid
        return { action: "install", ok: false, message: "Couldn't install: the manifest at that address didn't load. Check the URL and that the addon is online." }
    end if
    updated = []
    for each a in current
        if a.id <> man.id and a.transportUrl <> url then updated.Push(a)
    end for
    updated.Push(man)
    if not saveUrls(updated)
        return { action: "install", ok: false, message: "Couldn't save the addon on this TV (storage is full). Remove an addon or clear history and try again." }
    end if
    label = man.name
    if man.version <> "" then label = label + " " + man.version
    return { action: "install", ok: true, addons: updated, addon: man, message: "Installed " + label }
end function

function remove(url as String, current as Object) as Object
    updated = []
    name = ""
    for each a in current
        if a.transportUrl <> url then updated.Push(a) else name = a.name
    end for
    if not saveUrls(updated) then return { action: "remove", ok: false, message: "Couldn't update addons on this TV." }
    DeleteFile(cachePath(url))
    return { action: "remove", ok: true, addons: updated, message: "Uninstalled " + name }
end function

function move(url as String, delta as Integer, current as Object) as Object
    idx = -1
    for i = 0 to current.Count() - 1
        if current[i].transportUrl = url then idx = i
    end for
    j = idx + delta
    if idx < 0 or j < 0 or j >= current.Count() then return { action: "move", ok: false, addons: current }
    t = current[idx]
    current[idx] = current[j]
    current[j] = t
    saveUrls(current)
    return { action: "move", ok: true, addons: current }
end function

' Lists addons from an addon catalog (/addon_catalog/{type}/{id}.json).
function browse(source as Object) as Object
    url = resourceUrl(source.base, "addon_catalog", source.type, source.id)
    root = httpGetJson(url, 25000)
    if not isAA(root) or not isArr(root.addons)
        return { action: "browse", ok: false, key: source.key, message: "Couldn't load " + source.name + "." }
    end if
    items = []
    seen = {}
    for each e in root.addons
        if isAA(e) and isStr(e.transportUrl) and isAA(e.manifest) and not seen.DoesExist(e.transportUrl)
            man = compactManifest(e.manifest, e.transportUrl)
            if man <> invalid
                ' catalogs aren't needed for listing; drop them to keep the payload small
                man.catalogs = []
                seen[e.transportUrl] = true
                items.Push(man)
            end if
        end if
    end for
    return { action: "browse", ok: true, key: source.key, items: items }
end function
