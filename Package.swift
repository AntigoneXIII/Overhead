// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Overhead",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Overhead",
            path: "Sources/Overhead",
            linkerSettings: [
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
