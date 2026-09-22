// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UTHSEBMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UTHSEBMac", targets: ["UTHSEBMac"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "UTHSEBMac",
            dependencies: [],
            path: ".",
            sources: [
                "Sources"
            ],
            resources: [
                .copy("Resources/bgcourses.jpg"),
                .copy("Resources/launcher.html"),
                .copy("Resources/AiMoodle.js")
            ]
        )
    ]
)
