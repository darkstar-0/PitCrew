// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PitCrew",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "PitCrew", path: "Sources/PitCrew")
    ]
)
