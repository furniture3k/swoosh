// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Swoosh",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: layouts, swipe grammar, geometry, hit-test policy. No AppKit.
        .target(name: "SwooshCore", path: "Sources/SwooshCore"),
        .executableTarget(
            name: "Swoosh",
            dependencies: ["SwooshCore"],
            path: "Sources/Swoosh",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(name: "SwooshCoreTests", dependencies: ["SwooshCore"], path: "Tests/SwooshCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
