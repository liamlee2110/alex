// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Alex",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Alex",
            path: "Sources/Alex",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
