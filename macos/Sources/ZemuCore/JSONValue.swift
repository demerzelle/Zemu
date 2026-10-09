import Foundation

/**
 * Any JSON value. Community addons are loose about types (a rating may be a number or a string, a
 * director a string or an array), so models read fields through this and never fail on one odd field.
 */
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public static func parse(_ data: Data) -> JSONValue? { try? JSONDecoder().decode(JSONValue.self, from: data) }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    /** Primitive content as text (numbers without a trailing ".0"); nil for null, arrays joined. */
    public var text: String? {
        switch self {
        case .null: return nil
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .string(let s): return s
        case .array(let a): return a.compactMap { $0.text }.joined(separator: ", ")
        case .object: return nil
        }
    }

    /** Text that's present and not blank. */
    public var string: String? { text.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
    public var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    public var int: Int? { double.map { Int($0) } }
    public var int64: Int64? { double.map { Int64($0) } }
    public var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s == "true" ? true : s == "false" ? false : nil
        case .number(let n): return n != 0
        default: return nil
        }
    }

    /** A list of strings from an array, or a comma-separated string. */
    public var stringList: [String] {
        switch self {
        case .array(let a): return a.compactMap { $0.text?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case .string(let s): return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        default: return []
        }
    }
}

/** Lenient field readers for hand-written `init(from:)`s. */
extension KeyedDecodingContainer {
    func value(_ key: Key) -> JSONValue? { (try? decodeIfPresent(JSONValue.self, forKey: key)) ?? nil }
    func str(_ key: Key) -> String? { value(key)?.text }
    func strList(_ key: Key) -> [String] { value(key)?.stringList ?? [] }
    func int(_ key: Key) -> Int? { value(key)?.int }
    func int64(_ key: Key) -> Int64? { value(key)?.int64 }
    func list<T: Decodable>(_ key: Key, _ type: T.Type) -> [T] {
        guard let raw = value(key), case .array(let items) = raw else { return [] }
        return items.compactMap { item in
            guard let data = try? JSONEncoder().encode(item) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
    }
    func lenient<T: Decodable>(_ key: Key, _ type: T.Type) -> T? { (try? decodeIfPresent(T.self, forKey: key)) ?? nil }
}
