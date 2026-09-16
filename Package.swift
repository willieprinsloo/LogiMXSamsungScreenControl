// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "G9KeyboardSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "G9Core"),
        .executableTarget(
            name: "G9KeyboardSwitch",
            dependencies: ["G9Core"],
            resources: [
                .copy("Resources/m1ddc"),
                .copy("Resources/m1ddc-LICENSE"),
            ]
        ),
        .testTarget(name: "G9CoreTests", dependencies: ["G9Core"]),
    ]
)
