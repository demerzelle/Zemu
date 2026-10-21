import Foundation

/**
 * Which addon lists (catalogs) are shown on Home, Movies, Series and Anime. Stored as the lists
 * turned off, as "addonId/type/catalogId", so a new addon's lists are on until turned off.
 */
public enum CatalogToggles {
    public static func key(addonId: String, type: String, catalogId: String) -> String {
        "\(addonId)/\(type)/\(catalogId)"
    }

    /** The disabled list after switching one list on or off. */
    public static func set(_ disabled: [String], addonId: String, type: String, catalogId: String, enabled: Bool) -> [String] {
        let k = key(addonId: addonId, type: type, catalogId: catalogId)
        if enabled { return disabled.filter { $0 != k } }
        return disabled.contains(k) ? disabled : disabled + [k]
    }

    /** The disabled list after turning every one of an addon's lists on or off. */
    public static func setAll(_ disabled: [String], addonId: String, lists: [(type: String, id: String)], enabled: Bool) -> [String] {
        let keys = Set(lists.map { key(addonId: addonId, type: $0.type, catalogId: $0.id) })
        if enabled { return disabled.filter { !keys.contains($0) } }
        return disabled + keys.filter { !disabled.contains($0) }.sorted()
    }
}

public extension AppSettings {
    /** Whether an addon's list is shown. Lists are on unless turned off. */
    func catalogEnabled(addonId: String, type: String, catalogId: String) -> Bool {
        !disabledCatalogs.contains(CatalogToggles.key(addonId: addonId, type: type, catalogId: catalogId))
    }
}
