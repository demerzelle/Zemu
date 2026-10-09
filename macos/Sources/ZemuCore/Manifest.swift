import Foundation

public struct ResourceDef: Hashable, Sendable {
    public var name: String
    public var types: [String]?
    public var idPrefixes: [String]?
}

public struct ExtraDef: Hashable, Sendable {
    public var name: String
    public var isRequired: Bool
    public var options: [String]
}

public struct CatalogDef: Hashable, Sendable {
    public var type: String
    public var id: String
    public var name: String?
    public var extra: [ExtraDef]
    public var extraRequired: [String]
    public var extraSupported: [String]

    public var requiredExtras: Set<String> { Set(extra.filter(\.isRequired).map(\.name) + extraRequired) }
    public func supportsExtra(_ name: String) -> Bool { extra.contains { $0.name == name } || extraSupported.contains(name) }
    public func optionsFor(_ name: String) -> [String] { extra.first { $0.name == name }?.options ?? [] }

    init?(_ v: JSONValue) {
        guard let o = v.object else { return nil }
        type = o["type"]?.text ?? ""
        id = o["id"]?.text ?? ""
        name = o["name"]?.string
        extra = (o["extra"]?.array ?? []).compactMap { e in
            guard let eo = e.object else { return nil }
            return ExtraDef(name: eo["name"]?.text ?? "", isRequired: eo["isRequired"]?.bool ?? false, options: eo["options"]?.stringList ?? [])
        }
        extraRequired = o["extraRequired"]?.stringList ?? []
        extraSupported = o["extraSupported"]?.stringList ?? []
    }
}

public struct AddonCatalogDef: Hashable, Sendable {
    public var type: String
    public var id: String
    public var name: String?
}

public struct AddonManifest: Hashable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var logo: String?
    public var types: [String]
    public var idPrefixes: [String]?
    public var resources: [ResourceDef]
    public var catalogs: [CatalogDef]
    public var addonCatalogs: [AddonCatalogDef]
    /** Has a `/configure` page. */
    public var configurable: Bool
    /** Can't be installed without configuring first. */
    public var configurationRequired: Bool

    public func hasResource(_ resource: String) -> Bool { resources.contains { $0.name == resource } }

    public func supports(_ resource: String, type: String, id: String?) -> Bool {
        guard let res = resources.first(where: { $0.name == resource }) else { return false }
        let types = res.types ?? self.types
        if !types.isEmpty && !types.contains(type) { return false }
        let prefixes = res.idPrefixes ?? idPrefixes
        if let id, let prefixes, !prefixes.isEmpty, !prefixes.contains(where: { id.hasPrefix($0) }) { return false }
        return true
    }

    public enum ParseError: LocalizedError {
        case invalid, noId
        public var errorDescription: String? { self == .noId ? "Manifest has no id" : "Not a valid addon manifest" }
    }

    public static func parse(_ raw: String) throws -> AddonManifest {
        guard let v = JSONValue.parse(Data(raw.utf8)) else { throw ParseError.invalid }
        return try from(v)
    }

    public static func from(_ v: JSONValue) throws -> AddonManifest {
        guard let o = v.object else { throw ParseError.invalid }
        guard let id = o["id"]?.string else { throw ParseError.noId }
        let resources: [ResourceDef] = (o["resources"]?.array ?? []).compactMap { r in
            switch r {
            case .string(let s): return ResourceDef(name: s, types: nil, idPrefixes: nil)
            case .object(let ro):
                guard let n = ro["name"]?.string else { return nil }
                return ResourceDef(name: n, types: ro["types"]?.array.map { $0.compactMap(\.text) }, idPrefixes: ro["idPrefixes"]?.array.map { $0.compactMap(\.text) })
            default: return nil
            }
        }
        let hints = o["behaviorHints"]?.object
        let description = o["description"]?.string.map {
            $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
        }
        return AddonManifest(
            id: id,
            name: o["name"]?.string ?? id,
            version: o["version"]?.text ?? "",
            description: description,
            logo: o["logo"]?.string,
            types: o["types"]?.array?.compactMap(\.text) ?? [],
            idPrefixes: o["idPrefixes"]?.array?.compactMap(\.text),
            resources: resources,
            catalogs: (o["catalogs"]?.array ?? []).compactMap(CatalogDef.init),
            addonCatalogs: (o["addonCatalogs"]?.array ?? []).compactMap { c in
                c.object.map { AddonCatalogDef(type: $0["type"]?.text ?? "", id: $0["id"]?.text ?? "", name: $0["name"]?.string) }
            },
            configurable: hints?["configurable"]?.bool ?? false,
            configurationRequired: hints?["configurationRequired"]?.bool ?? false
        )
    }
}

public struct Addon: Hashable, Identifiable, Sendable {
    public let transportUrl: String
    public let manifest: AddonManifest
    public var id: String { transportUrl }
    public var baseUrl: String { Addon.base(of: transportUrl) }
    public var configureUrl: String { "\(baseUrl)/configure" }

    public init(transportUrl: String, manifest: AddonManifest) { self.transportUrl = transportUrl; self.manifest = manifest }

    public static func base(of transportUrl: String) -> String {
        var s = transportUrl.before("?").removingSuffix("/manifest.json")
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

/** An entry from an addon catalog (Stremio's "addon_catalog" resource). */
public typealias CatalogAddon = Addon

public struct AddonCatalogSource: Hashable, Sendable {
    public var key: String
    public var name: String
    public var base: String
    public var type: String
    public var id: String
}
