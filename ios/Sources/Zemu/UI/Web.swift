import SwiftUI
import WebKit
import ZemuCore

/** Which hero trailer is playing and how far in, so it can continue full screen. */
@MainActor @Observable
final class HeroTrailerState {
    static let shared = HeroTrailerState()
    var playingId: String?
    @ObservationIgnored var seconds: Double = 0
}

/**
 * YouTube IFrame player in a WKWebView. YouTube wants embeds to identify the app via the page
 * origin, so the HTML is loaded with a fixed base URL.
 */
struct YouTubeView: UIViewRepresentable {
    let videoId: String
    var muted = true
    var controls = false
    /** Crop to fill (hero) instead of letterboxing (full screen). */
    var cover = true
    var start = 0
    var onPlaying: () -> Void = {}
    var onEnded: () -> Void = {}
    var onError: (Int) -> Void = { _ in }
    var onTime: (Double) -> Void = { _ in }

    static let origin = "https://zemu.app"

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: YouTubeView
        init(_ p: YouTubeView) { parent = p }
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["e"] as? String else { return }
            switch kind {
            case "playing": parent.onPlaying()
            case "ended": parent.onEnded()
            case "error": parent.onError(body["v"] as? Int ?? 0)
            case "time": parent.onTime(body["v"] as? Double ?? 0)
            default: break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsInlineMediaPlayback = true
        cfg.userContentController.add(context.coordinator, name: "zemu")
        let web = PassiveWebView(frame: .zero, configuration: cfg)
        web.passive = !controls
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.loadHTMLString(html, baseURL: URL(string: Self.origin))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.parent = self }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "zemu")
        web.loadHTMLString("", baseURL: nil)
    }

    private var html: String {
        let id = videoId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let fit = cover
            ? "position:absolute;top:50%;left:50%;width:100vw;height:56.25vw;min-height:100vh;min-width:177.78vh;transform:translate(-50%,-50%);pointer-events:none"
            : "position:absolute;top:0;left:0;width:100%;height:100%"
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;overflow:hidden;background:transparent}#p{\(fit)}</style></head>
        <body><div id="p"></div><script src="https://www.youtube.com/iframe_api"></script><script>
        var player;function post(e,v){try{webkit.messageHandlers.zemu.postMessage({e:e,v:v})}catch(x){}}
        function onYouTubeIframeAPIReady(){player=new YT.Player('p',{videoId:'\(id)',
         playerVars:{autoplay:1,start:\(start),mute:\(muted ? 1 : 0),controls:\(controls ? 1 : 0),rel:0,modestbranding:1,playsinline:1,iv_load_policy:3,fs:0,disablekb:\(controls ? 0 : 1),origin:'\(Self.origin)'},
         events:{onReady:function(e){e.target.playVideo()},
          onStateChange:function(e){if(e.data===1)post('playing',0);if(e.data===0)post('ended',0)},
          onError:function(e){post('error',e.data)}}});}
        setInterval(function(){try{if(player&&player.getCurrentTime)post('time',player.getCurrentTime())}catch(e){}},1000);
        function toggle(){if(!player)return;if(player.getPlayerState()===1)player.pauseVideo();else player.playVideo()}
        function seek(d){if(player)player.seekTo(Math.max(0,player.getCurrentTime()+d),true)}
        </script></body></html>
        """
    }
}

/** A web view that doesn't take clicks when [passive] (hero trailers sit under the UI). */
final class PassiveWebView: WKWebView {
    var passive = false
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { passive ? nil : super.hitTest(point, with: event) }
}

/** Muted, cropped trailer that fades in once it actually starts playing. */
struct HeroTrailer: View {
    let videoId: String
    var sound = false
    var onFinished: () -> Void = {}
    @State private var playing = false

    var body: some View {
        YouTubeView(videoId: videoId, muted: !sound, controls: false, cover: true,
                    onPlaying: {
                        playing = true
                        HeroTrailerState.shared.playingId = videoId
                    },
                    onEnded: { stop() },
                    onError: { _ in stop() },
                    onTime: { HeroTrailerState.shared.seconds = $0 })
            .opacity(playing ? 1 : 0)
            .animation(.easeInOut(duration: 0.9), value: playing)
            .onDisappear { if HeroTrailerState.shared.playingId == videoId { HeroTrailerState.shared.playingId = nil } }
    }

    private func stop() {
        playing = false
        if HeroTrailerState.shared.playingId == videoId { HeroTrailerState.shared.playingId = nil }
        onFinished()
    }
}

/** Full-window trailer with sound and YouTube's own controls. Esc closes it. */
struct TrailerOverlay: View {
    let request: TrailerRequest
    var app = AppModel.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            YouTubeView(videoId: request.youtubeId, muted: false, controls: true, cover: false, start: request.start,
                        onEnded: { app.trailer = nil },
                        onError: { _ in
                            // Embedding disabled by the uploader (101/150) or blocked: hand off to the browser.
                            NSWorkspace.shared.open(URL(string: "https://www.youtube.com/watch?v=\(request.youtubeId)")!)
                            app.trailer = nil
                        })
            ZButton(title: "Close", icon: "xmark", small: true) { app.trailer = nil }
                .keyboardShortcut(.cancelAction)
                .padding(20)
                .padding(.top, 16)
        }
    }
}

// MARK: - Addon configure pages

/**
 * An addon's `/configure` page. When the page opens a `stremio://` install link or a manifest
 * URL, or copies one to the clipboard, the addon is installed into Zemu instead.
 */
struct ConfigureSheet: View {
    let request: ConfigureRequest
    var app = AppModel.shared
    @State private var copied: String?
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configure \(request.name)").font(.system(size: 15, weight: .bold))
                    Text(status ?? "The page's Install button installs the addon straight into Zemu.")
                        .font(.system(size: 12)).foregroundStyle(status == nil ? Palette.textSecondary : Palette.cached)
                }
                Spacer()
                ZButton(title: "Open in Browser", icon: "safari", small: true) { NSWorkspace.shared.open(URL(string: request.url)!) }
                ZButton(title: "Done", primary: true, small: true) { app.configure = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(P.surface)
            ConfigureWebView(url: request.url, onInstallLink: install, onCopied: { copied = $0 })
        }
        .alert("Install this addon?", isPresented: Binding(get: { copied != nil }, set: { if !$0 { copied = nil } })) {
            Button("Install") { if let c = copied { install(c) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String((copied ?? "").prefix(300)))
        }
    }

    private func install(_ url: String) {
        status = "Installing…"
        Task {
            do {
                let a = try await app.session.addons.install(url)
                app.session.streams.invalidate()
                app.toast("Installed \(a.manifest.name)")
                app.configure = nil
            } catch {
                status = "Couldn't install: \(error.localizedDescription)"
            }
        }
    }
}

struct ConfigureWebView: UIViewRepresentable {
    let url: String
    let onInstallLink: (String) -> Void
    let onCopied: (String) -> Void

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: ConfigureWebView
        init(_ p: ConfigureWebView) { parent = p }

        static func installTarget(_ url: String) -> String? {
            if url.hasPrefix("stremio://") { return "https://" + url.removingPrefix("stremio://") }
            if (url.hasPrefix("http://") || url.hasPrefix("https://")) && url.before("?").hasSuffix("/manifest.json") { return url }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let u = action.request.url?.absoluteString, let target = Self.installTarget(u) {
                await MainActor.run { parent.onInstallLink(target) }
                return .cancel
            }
            return .allow
        }

        /** target=_blank links: install links install, others open in the same view. */
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = action.request.url {
                if let t = Self.installTarget(u.absoluteString) { parent.onInstallLink(t) } else { webView.load(URLRequest(url: u)) }
            }
            return nil
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let t = (message.body as? String)?.trimmed, t.hasPrefix("stremio://") || t.contains("manifest.json") else { return }
            parent.onCopied(t)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // Many configure pages offer "Copy URL" instead of an install link; catch that too.
        let hook = """
        (function(){if(window.__zHook)return;window.__zHook=1;
        var report=function(t){try{webkit.messageHandlers.copied.postMessage(String(t||''))}catch(e){}};
        try{if(navigator.clipboard){var w=navigator.clipboard.writeText.bind(navigator.clipboard);navigator.clipboard.writeText=function(t){report(t);return w(t).catch(function(){})}}}catch(e){}
        var ec=document.execCommand;document.execCommand=function(c){if(c==='copy'){var a=document.activeElement;report(a&&a.value?a.value:String(window.getSelection()))}return ec.apply(document,arguments)};
        })()
        """
        cfg.userContentController.addUserScript(WKUserScript(source: hook, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        cfg.userContentController.add(context.coordinator, name: "copied")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        if let u = URL(string: url) { web.load(URLRequest(url: u)) }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.parent = self }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "copied")
    }
}
