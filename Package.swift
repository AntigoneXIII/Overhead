// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notchbox",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Notchbox",
            path: "Sources/Notchbox",
            linkerSettings: [
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
