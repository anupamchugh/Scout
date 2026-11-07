// swift-tools-version: 6.2
// Prototypes for docs/specs/2026-11-07-publication-pulse.md. Not shipped in the app.
//   PulsePrototype — writers' own feeds compared with a publication's average post.
//   EditorDesk — the editor team: ScoutKit's StoryCritic rates each article on a neutral rubric, code computes
//                trajectories and averages, and a Markdown report is written.
import PackageDescription

let package = Package(
    name: "PulsePrototype",
    platforms: [.macOS("27.0")],
    dependencies: [.package(path: "../../Packages/ScoutKit")],
    targets: [
        .executableTarget(name: "PulsePrototype", dependencies: ["ScoutKit"]),
        .executableTarget(name: "EditorDesk", dependencies: ["ScoutKit"]),
        // CompareAll — every preset publication through ScoutKit's PublicationComparison (the Compare tab's
        //              engine), with good/bad slop buckets and readability, as one Markdown report.
        .executableTarget(name: "CompareAll", dependencies: ["ScoutKit"]),
    ]
)
