// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "YToolMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YToolMac",
            path: "YToolMac",
            resources: [
                .copy("Resources/bin"),
                .copy("YToolMac.entitlements")
            ],
            swiftSettings: []
        ),
    ]
)
