sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    reqs = m.top.requests
    watched = m.top.watched
    if watched = invalid then watched = {}
    urls = []
    for each r in reqs
        urls.Push(resourceUrl(r.base, "catalog", r.type, r.id, r.extra))
    end for
    bodies = httpGetMany(urls, 20000)
    rows = []
    ok = 0
    for each b in bodies
        if b <> "" then ok = ok + 1
    end for
    for i = 0 to reqs.Count() - 1
        r = reqs[i]
        metas = []
        if bodies[i] <> ""
            parsed = ParseJson(bodies[i])
            if isAA(parsed) and isArr(parsed.metas) then metas = parsed.metas
        end if
        limit = r.limit
        if limit = invalid or limit = 0 then limit = 40
        content = CreateObject("roSGNode", "ContentNode")
        seen = {}
        style = r.style
        if style = invalid or style = "" then style = "poster"
        for each raw in metas
            if content.getChildCount() >= limit then exit for
            if isAA(raw)
                id = tostr(raw.id)
                if id <> "" and not seen.DoesExist(id)
                    seen[id] = true
                    meta = slimMeta(raw)
                    if r.type = "anime" and meta.type = "" then meta.type = "series"
                    n = content.createChild("MetaNode")
                    n.meta = meta
                    n.style = style
                    n.watched = watched.DoesExist(id)
                end if
            end if
        end for
        if content.getChildCount() > 0
            content.title = r.title
            rows.Push({ key: r.key, title: r.title, priority: r.priority, style: style, content: content })
        end if
    end for
    m.top.rows = rows
end sub
