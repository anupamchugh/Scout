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
    targets: [
        .executableTarget(name: "CompareAll", dependencies: ["ScoutKit"]),
        // LastPosts — a publication's last N posts from its sitemap with topics labelled on device, a full read and tag
        //             check of the posts its feed carries, and its writers' own feeds where a handle can be verified:
        //             swift run LastPosts <host> <medium-slug> <report.md>
        .executableTarget(name: "LastPosts", dependencies: ["ScoutKit"]),
        // MonthReport — every preset publication's last 30 days from its sitemap, topics labelled on device:
        //               swift run MonthReport <report.md>
        .executableTarget(name: "MonthReport", dependencies: ["ScoutKit"]),
        // Originality — title originality over each publication's last 30 days from Natural Language embeddings:
        //               swift run Originality <report.md>
        .executableTarget(name: "Originality", dependencies: ["ScoutKit"]),
    ]
)
