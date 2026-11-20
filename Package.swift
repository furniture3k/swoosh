// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Swoosh",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Swoosh",
            path: "Sources/Swoosh",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
