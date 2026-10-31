import Foundation

/**
 * tvOS may clear Caches, where the app's files live, and only UserDefaults survives that (about 500 KB
 * in all). So what can't be rebuilt is mirrored there, compressed: profiles, addons, debrid, settings
 * and lists. No-ops elsewhere.
 */
enum TVBackup {
    /** Per file; leaves room for several profiles under the system limit. */
    static let maxBytes = 90 * 1024

    private static func key(_ file: URL) -> String { "backup." + file.lastPathComponent }

    /** Returns false when it's too big to keep. */
    @discardableResult
    static func save(_ data: Data, for file: URL) -> Bool {
        #if os(tvOS)
        guard let small = try? (data as NSData).compressed(using: .lzfse) as Data, small.count <= maxBytes else { return false }
        UserDefaults.standard.set(small, forKey: key(file))
        #endif
        return true
    }

    static func remove(for file: URL) {
        #if os(tvOS)
        UserDefaults.standard.removeObject(forKey: key(file))
        #endif
    }

    /** The file, or its backup if the system cleared it. */
    static func read(_ file: URL) -> Data? {
        if let d = try? Data(contentsOf: file) { return d }
        #if os(tvOS)
        if let small = UserDefaults.standard.data(forKey: key(file)) { return try? (small as NSData).decompressed(using: .lzfse) as Data }
        #endif
        return nil
    }
}
