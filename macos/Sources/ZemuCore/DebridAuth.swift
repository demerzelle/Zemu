import Foundation

/**
 * Debrid services Zemu can link. [torrentio] is the service's name in a Torrentio config URL;
 * [codeLogin] means the Mac can be approved with a code on the service's website.
 */
public enum DebridService: String, Codable, CaseIterable, Sendable {
    case REAL_DEBRID, ALL_DEBRID, PREMIUMIZE, TORBOX, DEBRID_LINK

    public var label: String {
        switch self {
        case .REAL_DEBRID: "Real-Debrid"; case .ALL_DEBRID: "AllDebrid"; case .PREMIUMIZE: "Premiumize"
        case .TORBOX: "TorBox"; case .DEBRID_LINK: "Debrid-Link"
        }
    }
    public var keyPage: String {
        switch self {
        case .REAL_DEBRID: "real-debrid.com/apitoken"; case .ALL_DEBRID: "alldebrid.com/apikeys"
        case .PREMIUMIZE: "premiumize.me/account"; case .TORBOX: "torbox.app/settings"; case .DEBRID_LINK: "debrid-link.com/webapp/apikey"
        }
    }
    public var torrentio: String {
        switch self {
        case .REAL_DEBRID: "realdebrid"; case .ALL_DEBRID: "alldebrid"; case .PREMIUMIZE: "premiumize"
        case .TORBOX: "torbox"; case .DEBRID_LINK: "debridlink"
        }
    }
    public var codeLogin: Bool { self == .REAL_DEBRID || self == .ALL_DEBRID }
}

/** A linked account. Code-approved Real-Debrid logins expire and carry what's needed to renew them. */
public struct DebridAccount: Codable, Hashable, Sendable {
    public var service: DebridService
    public var token: String
    public var refreshToken: String?
    public var clientId: String?
    public var clientSecret: String?
    public var expiresAt: Int64 = 0

    public init(service: DebridService, token: String, refreshToken: String? = nil, clientId: String? = nil, clientSecret: String? = nil, expiresAt: Int64 = 0) {
        self.service = service; self.token = token; self.refreshToken = refreshToken
        self.clientId = clientId; self.clientSecret = clientSecret; self.expiresAt = expiresAt
    }

    public var renewable: Bool { refreshToken != nil && clientId != nil && clientSecret != nil }

    /** Torrentio set up for this account. Its own debrid catalog is left off so Home stays tidy. */
    public var torrentioUrl: String { "https://torrentio.strem.fun/debridoptions=nocatalog|\(service.torrentio)=\(token)/manifest.json" }
}

/** A pending code login: the user opens [url] and enters [userCode], or scans [directUrl]. */
public struct DeviceLogin: Sendable {
    public let service: DebridService
    public let userCode: String
    public let url: String
    public let directUrl: String
    public let expiresAt: Date
    public let interval: TimeInterval
    let poll: @Sendable () async throws -> DebridAccount?

    /** The account once the user has approved, nil while still waiting. */
    public func check() async throws -> DebridAccount? { try await poll() }
}

public struct DebridAuthError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/** Code logins (Real-Debrid device code, AllDebrid PIN) and API key checks. */
public enum DebridAuth {
    private static let agent = "zemu"
    private static let adApi = "https://api.alldebrid.com/v4"
    private static let rdOauth = "https://api.real-debrid.com/oauth/v2"
    /** Real-Debrid's public client id for open-source apps. */
    private static let rdClientId = "X35EXNSAZVT6O"
    private static let ua = ["User-Agent": "Zemu"]

    public static func start(_ service: DebridService) async throws -> DeviceLogin {
        switch service {
        case .REAL_DEBRID: return try await startRealDebrid()
        case .ALL_DEBRID: return try await startAllDebrid()
        default: throw DebridAuthError(message: "\(service.label) doesn't support code login. Paste your API key instead.")
        }
    }

    private static func rdError(_ o: JSONValue) -> String? {
        guard let e = o["error"]?.string else { return nil }
        if e == "permission_denied" {
            return "Real-Debrid refused the request from this network. It blocks most VPNs and some providers. Turn the VPN off and try again, or paste your API key instead."
        }
        return "Real-Debrid: \(e)"
    }

    private static func startRealDebrid() async throws -> DeviceLogin {
        let o = try await HTTP.jsonAnyStatus("\(rdOauth)/device/code?client_id=\(rdClientId)&new_credentials=yes", headers: ua)
        if let e = rdError(o) { throw DebridAuthError(message: e) }
        guard let deviceCode = o["device_code"]?.string else { throw DebridAuthError(message: "Real-Debrid didn't return a code.") }
        let verification = o["verification_url"]?.string ?? "https://real-debrid.com/device"
        return DeviceLogin(
            service: .REAL_DEBRID,
            userCode: o["user_code"]?.string ?? "",
            url: verification,
            directUrl: o["direct_verification_url"]?.string ?? verification,
            expiresAt: Date().addingTimeInterval(Double(o["expires_in"]?.int ?? 600)),
            interval: max(3, Double(o["interval"]?.int ?? 5))
        ) {
            let creds = try await HTTP.jsonAnyStatus("\(rdOauth)/device/credentials?client_id=\(rdClientId)&code=\(deviceCode)", headers: ua)
            guard let id = creds["client_id"]?.string, let secret = creds["client_secret"]?.string else { return nil }
            return try await rdToken(clientId: id, secret: secret, code: deviceCode)
        }
    }

    private static func rdToken(clientId: String, secret: String, code: String) async throws -> DebridAccount {
        let o = try await HTTP.jsonAnyStatus("\(rdOauth)/token", headers: ua, form: [
            "client_id": clientId, "client_secret": secret, "code": code,
            "grant_type": "http://oauth.net/grant_type/device/1.0",
        ])
        if let e = rdError(o) { throw DebridAuthError(message: e) }
        guard let token = o["access_token"]?.string else { throw DebridAuthError(message: "Real-Debrid didn't return a token.") }
        return DebridAccount(service: .REAL_DEBRID, token: token, refreshToken: o["refresh_token"]?.string,
                             clientId: clientId, clientSecret: secret,
                             expiresAt: nowMs() + Int64(o["expires_in"]?.int ?? 3600) * 1000)
    }

    /** New token for a code-approved Real-Debrid login, or nil if it can't be renewed. */
    public static func refresh(_ a: DebridAccount) async -> DebridAccount? {
        guard a.renewable else { return nil }
        return try? await rdToken(clientId: a.clientId!, secret: a.clientSecret!, code: a.refreshToken!)
    }

    private static func startAllDebrid() async throws -> DeviceLogin {
        let o = try await HTTP.jsonAnyStatus("\(adApi)/pin/get?agent=\(agent)", headers: ua)
        guard let data = o["data"]?.object else {
            throw DebridAuthError(message: o["error"]?["message"]?.string.map { "AllDebrid: \($0)" } ?? "AllDebrid didn't return a PIN.")
        }
        let pin = data["pin"]?.string ?? ""
        let check = data["check"]?.string ?? ""
        let checkUrl = data["check_url"]?.string ?? "\(adApi)/pin/check?check=\(check)&pin=\(pin)&agent=\(agent)"
        return DeviceLogin(
            service: .ALL_DEBRID,
            userCode: pin,
            url: data["base_url"]?.string ?? "https://alldebrid.com/pin/",
            directUrl: data["user_url"]?.string ?? "https://alldebrid.com/pin/?pin=\(pin)",
            expiresAt: Date().addingTimeInterval(Double(data["expires_in"]?.int ?? 600)),
            interval: 5
        ) {
            let d = try await HTTP.jsonAnyStatus(checkUrl, headers: ua)["data"]
            if d?["activated"]?.bool == true, let key = d?["apikey"]?.string { return DebridAccount(service: .ALL_DEBRID, token: key) }
            return nil
        }
    }

    /** True if the service accepts [key] as an API key. */
    public static func verify(_ service: DebridService, key: String) async -> Bool {
        let k = key.trimmed
        let bearer = ua.merging(["Authorization": "Bearer \(k)"]) { a, _ in a }
        do {
            switch service {
            case .REAL_DEBRID:
                // From a VPN Real-Debrid refuses every call, so the key can't be checked here; Torrentio checks it from its servers.
                let o = try await HTTP.jsonAnyStatus("https://api.real-debrid.com/rest/1.0/user", headers: bearer)
                return o["username"]?.string != nil || o["error"]?.string == "permission_denied"
            case .ALL_DEBRID:
                return try await HTTP.jsonAnyStatus("\(adApi)/user?agent=\(agent)", headers: bearer)["status"]?.string == "success"
            case .PREMIUMIZE:
                return try await HTTP.jsonAnyStatus("https://www.premiumize.me/api/account/info?apikey=\(k.urlEncoded)", headers: ua)["status"]?.string == "success"
            case .TORBOX:
                return try await HTTP.jsonAnyStatus("https://api.torbox.app/v1/api/user/me", headers: bearer)["success"]?.bool == true
            case .DEBRID_LINK:
                return try await HTTP.jsonAnyStatus("https://debrid-link.com/api/v2/account/infos", headers: bearer)["success"]?.bool == true
            }
        } catch { return false }
    }
}
