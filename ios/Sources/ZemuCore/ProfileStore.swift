import Foundation
import Observation
import ImageIO
import UniformTypeIdentifiers

/** [avatar] is "preset:<index>" or "file:<absolute path>". */
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var avatar: String
    /** A kid profile: Kids Mode is on while it's in use. */
    public var kids: Bool
    public init(id: String, name: String, avatar: String = "preset:0", kids: Bool = false) { self.id = id; self.name = name; self.avatar = avatar; self.kids = kids }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        avatar = (try? c.decode(String.self, forKey: .avatar)) ?? "preset:0"
        kids = (try? c.decodeIfPresent(Bool.self, forKey: .kids)) ?? false
    }
}

private struct ProfilesFile: Codable {
    var profiles: [Profile] = []
    var active: String?
    var skipPicker = false
    var kids = KidsSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = (try? c.decode([Profile].self, forKey: .profiles)) ?? []
        active = try? c.decodeIfPresent(String.self, forKey: .active)
        skipPicker = (try? c.decodeIfPresent(Bool.self, forKey: .skipPicker)) ?? false
        kids = (try? c.decodeIfPresent(KidsSettings.self, forKey: .kids)) ?? KidsSettings()
    }
}

/** The list of profiles and which one is active. Each profile's own data lives in its [UserStore]. */
@MainActor @Observable
public final class ProfileStore {
    public static let defaultId = "default"
    public static let defaultProfile = Profile(id: defaultId, name: "Me", avatar: "preset:0")

    private static var dir: URL {
        let u = AppPaths.support.appendingPathComponent("profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    nonisolated static func dataFile(for id: String) -> URL {
        AppPaths.support.appendingPathComponent("profiles", isDirectory: true).appendingPathComponent("\(id).json")
    }
    private static var file: URL { AppPaths.support.appendingPathComponent("profiles.json") }
    private static var avatarDir: URL {
        let u = AppPaths.support.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private var state: ProfilesFile { didSet { save() } }

    public init() {
        _ = ProfileStore.dir
        if let d = try? Data(contentsOf: ProfileStore.file), let f = try? JSONDecoder().decode(ProfilesFile.self, from: d) {
            state = f
        } else {
            state = ProfilesFile()
        }
        if state.profiles.isEmpty { state.profiles = [ProfileStore.defaultProfile] }
    }

    public var profiles: [Profile] { state.profiles }
    /** Open straight into the last used profile instead of asking who's watching. */
    public var skipPicker: Bool { state.skipPicker }
    public func setSkipPicker(_ v: Bool) { state.skipPicker = v }

    public var activeId: String {
        let id = state.active ?? ProfileStore.defaultId
        return profiles.contains { $0.id == id } ? id : ProfileStore.defaultId
    }
    public func setActive(_ id: String) { state.active = id }

    /** Parental controls cover every profile, so they live here. */
    public var kids: KidsSettings { state.kids }
    public func updateKids(_ change: (inout KidsSettings) -> Void) { change(&state.kids) }
    /** A kid profile is in use. */
    public var kidsOn: Bool { profile(activeId)?.kids == true }
    public func checkParentCode(_ code: String) -> Bool { !state.kids.pinHash.isEmpty && KidsSettings.hash(code) == state.kids.pinHash }

    public func profile(_ id: String) -> Profile? { profiles.first { $0.id == id } }

    @discardableResult
    public func add(name: String, avatar: String, kids: Bool = false) -> Profile {
        let p = Profile(id: String(UUID().uuidString.lowercased().prefix(8)), name: name.trimmed.isEmpty ? "Profile \(profiles.count + 1)" : name, avatar: avatar, kids: kids)
        state.profiles.append(p)
        return p
    }

    public func update(_ profile: Profile) {
        state.profiles = state.profiles.map { $0.id == profile.id ? profile : $0 }
    }

    /** Deletes a profile and all of its data. The default profile can't be deleted. */
    public func delete(_ id: String) {
        guard id != ProfileStore.defaultId else { return }
        state.profiles.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: ProfileStore.dataFile(for: id))
        try? FileManager.default.removeItem(at: ProfileStore.avatarDir.appendingPathComponent("\(id).jpg"))
    }

    /** Crops to a square, downsizes and re-encodes an image file. Returns the avatar value. */
    public func saveAvatarImage(_ id: String, from source: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 640,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let side = min(img.width, img.height)
        guard let square = img.cropping(to: CGRect(x: (img.width - side) / 2, y: (img.height - side) / 2, width: side, height: side)) else { return nil }
        let out = ProfileStore.avatarDir.appendingPathComponent("\(id).jpg")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, square, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        // A changing value makes image caches reload the new picture.
        return "file:\(out.path)?v=\(nowMs())"
    }

    private func save() {
        if let d = try? JSONEncoder().encode(state) { try? d.write(to: ProfileStore.file, options: .atomic) }
    }
}
