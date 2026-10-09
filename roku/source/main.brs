sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.Show()
    if args <> invalid and args.contentId <> invalid then scene.deepLink = { contentId: args.contentId, mediaType: args.mediaType }

    scene.observeField("exitApp", port)
    input = CreateObject("roInput")
    input.SetMessagePort(port)
    while true
        msg = Wait(0, port)
        t = Type(msg)
        if t = "roSGScreenEvent"
            if msg.IsScreenClosed() then return
        else if t = "roSGNodeEvent"
            if msg.getField() = "exitApp" and msg.getData() = true then return
        else if t = "roInputEvent"
            info = msg.GetInfo()
            if info <> invalid and info.contentId <> invalid then scene.deepLink = { contentId: info.contentId, mediaType: info.mediaType }
        end if
    end while
end sub
