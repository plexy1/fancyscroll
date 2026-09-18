// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FancyScroll",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FancyScroll",
            path: "Sources/FancyScroll",
            swiftSettings: [
                .unsafeFlags(["-Onone"], .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
