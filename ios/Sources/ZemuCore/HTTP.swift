import Foundation

public struct HTTPError: LocalizedError {
    public let status: Int
    public let url: String
    public var errorDescription: String? { "HTTP \(status) for \(url)" }
}

public struct TimeoutError: LocalizedError {
    public var errorDescription: String? { "timed out" }
}

/** Shared URLSession with an on-disk cache, like the Android app's OkHttp client. */
public enum HTTP {
    public static let userAgent = "Zemu/1.0 (macOS)"

    public static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        let dir = AppPaths.caches.appendingPathComponent("http", isDirectory: true)
        cfg.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 200 << 20, directory: dir)
        cfg.requestCachePolicy = .useProtocolCachePolicy
        cfg.timeoutIntervalForRequest = 25
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent]
        cfg.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: cfg)
    }()

    public static func data(_ url: String, headers: [String: String] = [:], method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.httpBody = body
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw HTTPError(status: h.statusCode, url: url) }
        return data
    }

    public static func string(_ url: String, headers: [String: String] = [:]) async throws -> String {
        String(decoding: try await data(url, headers: headers), as: UTF8.self)
    }

    /** JSON, or nil on any failure (HTTP error, bad JSON). */
    public static func json(_ url: String, headers: [String: String] = [:]) async -> JSONValue? {
        guard let d = try? await data(url, headers: headers.merging(["Accept": "application/json"]) { a, _ in a }) else { return nil }
        return JSONValue.parse(d)
    }

    /** JSON body even for error statuses (debrid APIs report errors in the body). */
    public static func jsonAnyStatus(_ url: String, headers: [String: String] = [:], method: String = "GET", form: [String: String]? = nil) async throws -> JSONValue {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.httpMethod = form == nil ? method : "POST"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(form.map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }.joined(separator: "&").utf8)
        }
        let (data, _) = try await session.data(for: req)
        return JSONValue.parse(data) ?? .object([:])
    }
}

public extension String {
    /** Percent-encodes everything but unreserved characters (spaces become %20). */
    var urlEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
    var formEncoded: String { urlEncoded }
}

/** Runs [op] with a timeout, throwing TimeoutError when it runs out. */
public func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

public enum AppPaths {
    public static let support: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zemu", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    public static let caches: URL = {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Zemu", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
}
