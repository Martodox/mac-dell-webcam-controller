// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CameraKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CameraKit", targets: ["CameraKit"]),
        // Wrapped into "Dell Camera Agent.app" by the pane's "Embed Camera Agent" build phase,
        // using Support/AgentInfo.plist and Support/Agent.entitlements.
        .executable(name: "DellCameraAgent", targets: ["DellCameraAgent"]),
    ],
    targets: [
        .target(
            name: "CameraKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "DellCameraAgent", dependencies: ["CameraKit"]),
        .testTarget(name: "CameraKitTests", dependencies: ["CameraKit"]),
    ],
    swiftLanguageModes: [.v5]
)
