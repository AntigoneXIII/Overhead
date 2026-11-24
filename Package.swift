// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HoldingBay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HoldingBay",
            path: "Sources/HoldingBay",
            linkerSettings: [
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
