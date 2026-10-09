// swift-tools-version:6.0
import PackageDescription

let swift: [SwiftSetting] = [.enableUpcomingFeature("BareSlashRegexLiterals")]

let package = Package(
    name: "Zemu",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Zemu", targets: ["Zemu"])],
    targets: [
        // libmpv C API, loaded at runtime (see zemu_mpv.h).
        .target(name: "CMpv"),
        // Stremio protocol, stream parsing/ranking, recommendations and persistence. No UI.
        .target(name: "ZemuCore", swiftSettings: swift),
        .executableTarget(
            name: "Zemu",
            dependencies: ["ZemuCore", "CMpv"],
            swiftSettings: swift,
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // `swift run ZemuCoreTests` — the toolchain here ships neither XCTest nor swift-testing.
        .executableTarget(name: "ZemuCoreTests", dependencies: ["ZemuCore"]),
    ],
    swiftLanguageModes: [.v5]
)
