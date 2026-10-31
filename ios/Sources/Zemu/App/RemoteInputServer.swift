#if os(tvOS)
import Darwin
import Network
import SwiftUI
import ZemuCore

/**
 * Tiny LAN web page so long text (addon URLs, API keys) can be pasted from a phone instead of typed
 * with the remote, like Android's RemoteInputServer. Only runs while a screen showing its address is open.
 */
@MainActor @Observable
final class RemoteInputServer {
    static let shared = RemoteInputServer()
    static let port: UInt16 = 8765
    private static let maxRequest = 64 * 1024

    private(set) var address: String?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var users = 0

    func retain() {
        users += 1
        if users == 1 { start(NWEndpoint.Port(rawValue: Self.port)!) }
    }

    func release() {
        users -= 1
        guard users == 0 else { return }
        listener?.cancel()
        listener = nil
        address = nil
    }

    private func start(_ port: NWEndpoint.Port) {
        guard let l = try? NWListener(using: .tcp, on: port) else { return }
        listener = l
        // Everything here runs on the main queue (see `start` and `accept`).
        l.newConnectionHandler = { [weak self] c in MainActor.assumeIsolated { self?.accept(c) } }
        l.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.listener === l else { return }
                switch state {
                case .ready: self.address = Self.lanIP().flatMap { ip in l.port.map { "http://\(ip):\($0.rawValue)" } }
                // 8765 is taken: any free port works, since the screen shows the address.
                case .failed: l.cancel(); self.start(.any)
                default: break
                }
            }
        }
        l.start(queue: .main)
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: .main)
        read(c, Data())
        // A client that never finishes its request doesn't get to hold the connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { c.cancel() }
    }

    private func read(_ c: NWConnection, _ data: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] chunk, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { return c.cancel() }
                var data = data
                if let chunk { data.append(chunk) }
                guard error == nil, data.count <= Self.maxRequest else { return c.cancel() }
                if let request = Self.parse(data) {
                    Task { await self.respond(c, request) }
                } else if done {
                    c.cancel()
                } else {
                    self.read(c, data)
                }
            }
        }
    }

    struct Request: Equatable {
        var post: Bool
        var kind: String
        var text: String
    }

    /** nil until the whole request has arrived. */
    nonisolated static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let length = head.dropFirst().first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
        guard data.distance(from: end.upperBound, to: data.endIndex) >= length else { return nil }
        guard head[0].hasPrefix("POST") else {
            // "?kind=..." preselects what's being pasted (the TV's QR codes use it).
            let target = head[0].split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let kind = URLComponents(string: target)?.queryItems?.first { $0.name == "kind" }?.value ?? ""
            return Request(post: false, kind: kind, text: "")
        }
        let body = String(decoding: data[end.upperBound...].prefix(length), as: UTF8.self)
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let value = kv.count > 1 ? kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding : nil
            fields[String(kv[0])] = value ?? ""
        }
        return Request(post: true, kind: fields["kind"] ?? "", text: fields["url"] ?? "")
    }

    private func respond(_ c: NWConnection, _ r: Request) async {
        var message: String?
        if r.post {
            message = r.text.trimmed.isEmpty ? "Please paste something first." : await handle(r)
            if let message { AppModel.shared.toast(message) }
        }
        let page = Data(Self.page(message: message, kind: r.kind).utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.count)\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + page, completion: .contentProcessed { _ in c.cancel() })
    }

    private func handle(_ r: Request) async -> String {
        let session = AppModel.shared.session
        let text = r.text.trimmed
        if r.kind == "tmdb" { return await session.saveTmdbKey(text) }
        if r.kind == "omdb" { session.store.updateSettings { $0.omdbApiKey = text }; return "OMDb key saved." }
        if r.kind == "trakt.id" { session.store.updateSettings { $0.traktClientId = text }; return "Trakt Client ID saved." }
        if r.kind == "trakt.secret" { session.store.updateSettings { $0.traktClientSecret = text }; return "Trakt Client Secret saved." }
        if r.kind.hasPrefix("debrid.") {
            guard let service = DebridService(rawValue: r.kind.removingPrefix("debrid.")) else { return "Unknown debrid service." }
            guard await DebridAuth.verify(service, key: text) else { return "\(service.label) didn't accept that key. Copy it from \(service.keyPage)." }
            return await session.linkDebrid(DebridAccount(service: service, token: text))
        }
        return await session.handlePastedText(text)
    }

    private nonisolated static func lanIP() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var found: String?
        var next = list
        while let i = next {
            next = i.pointee.ifa_next
            guard let sa = i.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  i.pointee.ifa_flags & UInt32(IFF_UP) != 0, i.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard isPrivate(ip) else { continue }
            if String(cString: i.pointee.ifa_name).hasPrefix("en") { return ip }
            found = found ?? ip
        }
        return found
    }

    nonisolated static func isPrivate(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
    }

    private nonisolated static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private nonisolated static func page(message: String?, kind: String) -> String {
        let kinds = [("auto", "Addon URL or TMDB key (detect)"), ("tmdb", "TMDB API key"), ("omdb", "OMDb API key"),
                     ("trakt.id", "Trakt Client ID"), ("trakt.secret", "Trakt Client Secret")]
            + DebridService.allCases.map { ("debrid.\($0.rawValue)", "\($0.label) API key (\($0.keyPage))") }
        let options = kinds.map { "<option value=\"\($0.0)\"\($0.0 == kind ? " selected" : "")>\(esc($0.1))</option>" }.joined()
        let msg = message.map { "<p class=msg>\(esc($0))</p>" } ?? ""
        return """
        <!doctype html><html><head><meta name=viewport content="width=device-width,initial-scale=1">
        <title>Zemu</title><style>
        body{font-family:system-ui,sans-serif;background:#0a0a0e;color:#fff;margin:0;padding:24px;max-width:640px}
        h1{color:#e50914;margin:0 0 8px}p{color:#b8b8c2;line-height:1.5}
        input,select{width:100%;box-sizing:border-box;padding:14px;border-radius:10px;border:1px solid #333;background:#17171e;color:#fff;font-size:16px;margin-top:8px}
        button{margin-top:12px;width:100%;padding:14px;border:0;border-radius:10px;background:#e50914;color:#fff;font-size:16px;font-weight:700}
        .msg{background:#17171e;padding:12px;border-radius:10px;color:#fff}</style></head><body>
        <h1>Zemu</h1>\(msg)<p>Paste a Stremio addon manifest URL (for example your configured debrid addon) to install it on your TV,
        your debrid service API key to link your account,
        or your free TMDB API key (themoviedb.org → Settings → API) to turn on cast photos, studios and filmographies.</p>
        <form method=post action="/"><select name=kind>\(options)</select>
        <input name=url placeholder="Paste here"><button>Send to TV</button></form>
        </body></html>
        """
    }
}

/** The address and QR code of the phone page; the server runs while this is on screen. */
struct RemoteInputBanner: View {
    /** Preselects what the page pastes, e.g. "debrid.TORBOX". */
    var kind: String?
    private var server = RemoteInputServer.shared

    var body: some View {
        HStack(spacing: 14) {
            if let a = server.address {
                QRCode(text: kind.map { "\(a)/?kind=\($0)" } ?? a).frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add from your phone or computer").font(.system(size: 14, weight: .bold))
                    Text(a).font(.system(size: 18, weight: .black, design: .monospaced)).foregroundStyle(P.accent)
                    Text("Open this on the same network, then paste an addon link or API key.").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
            } else {
                Text("Connect the Apple TV to your network to add addons from your phone.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .onAppear { server.retain() }
        .onDisappear { server.release() }
    }
}
#endif
