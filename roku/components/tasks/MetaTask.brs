sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    typ = m.top.type
    id = m.top.metaId
    providers = addonsFor(m.top.addons, "meta", typ, id)
    ordered = []
    for each a in providers
        if a.id = m.top.preferred then ordered.Unshift(a) else ordered.Push(a)
    end for
    for each a in ordered
        o = httpGetJson(resourceUrl(a.baseUrl, "meta", typ, id), 15000)
        if isAA(o) and isAA(o.meta) and tostr(o.meta.id) <> ""
            meta = slimMeta(o.meta, true)
            if meta.type = "" or (typ <> "anime" and meta.type <> typ) then meta.type = typ
            m.top.meta = meta
            return
        end if
    end for
    m.top.failed = true
end sub
