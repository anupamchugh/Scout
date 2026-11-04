// swift-tools-version: 6.2
import PackageDescription

/// Feeds, scoring, export and role packs for Scout, with no app or UI dependencies,
/// so other apps (Feedloom) can import the same scouting logic.
let package = Package(
    name: "ScoutKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [.library(name: "ScoutKit", targets: ["ScoutKit"])],
    targets: [
        .target(name: "ScoutKit"),
        .testTarget(name: "ScoutKitTests", dependencies: ["ScoutKit"], resources: [.copy("Fixtures")]),
    ]
)
