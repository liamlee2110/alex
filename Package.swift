// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Alex",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Updates (revision 68): the one dependency D3 allows beside maths.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Alex",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Alex",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // Sparkle.framework ships inside the bundle, in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
