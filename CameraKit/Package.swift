// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CameraKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CameraKit", targets: ["CameraKit"]),
    ],
    targets: [
        .target(
            name: "CameraKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .testTarget(name: "CameraKitTests", dependencies: ["CameraKit"]),
    ],
    swiftLanguageModes: [.v5]
)
