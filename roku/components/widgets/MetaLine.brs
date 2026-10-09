sub init()
    m.matchL = m.top.findNode("matchL")
    m.year = m.top.findNode("year")
    m.runtime = m.top.findNode("runtime")
    m.tag = m.top.findNode("tag")
    m.tagBox = m.top.findNode("tagBox")
    m.tagText = m.top.findNode("tagText")
    m.imdb = m.top.findNode("imdb")
    m.imdbBox = m.top.findNode("imdbBox")
    m.imdbText = m.top.findNode("imdbText")
end sub
sub render()
    meta = m.top.meta
    if meta = invalid or meta.id = invalid then return
    x = 0
    gap = 19
    place = function(node as Object, x as Float, gap as Integer, w as Float) as Float
        node.translation = [x, 0]
        return x + w + gap
    end function
    m.matchL.visible = m.top.match > 0
    if m.matchL.visible
        m.matchL.text = tostr(m.top.match) + "% Match"
        x = place(m.matchL, x, gap, m.matchL.boundingRect().width)
    end if
    m.year.text = tostr(meta.releaseInfo)
    m.year.visible = m.year.text <> ""
    if m.year.visible then x = place(m.year, x, gap, m.year.boundingRect().width)
    m.runtime.text = runtimeLabel(tostr(meta.runtime))
    m.runtime.visible = m.runtime.text <> ""
    if m.runtime.visible then x = place(m.runtime, x, gap, m.runtime.boundingRect().width)
    if meta.type = "series" then m.tagText.text = "SERIES" else m.tagText.text = "MOVIE"
    tw = m.tagText.boundingRect().width + 16
    m.tagBox.width = tw
    x = place(m.tag, x, gap, tw)
    r = tostr(meta.imdbRating)
    m.imdb.visible = r <> ""
    if m.imdb.visible
        m.imdbText.text = r
        m.imdb.translation = [x, 0]
    end if
end sub
  