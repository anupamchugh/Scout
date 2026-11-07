// swift-tools-version: 6.2
// CompareAll — every preset publication through ScoutKit's PublicationComparison (the Compare tab's engine),
// read on this Mac's on-device model, written as a Markdown report and an optional digest. Not shipped in the app.
//
//   swift run CompareAll <report.md> [digest.md]
import PackageDescription

let package = Package(
    name: "PulsePrototype",
    platforms: [.macOS("27.0")],
    dependencies: [.package(path: "../../Packages/ScoutKit")],
    targets: [.executableTarget(name: "CompareAll", dependencies: ["ScoutKit"])]
)
