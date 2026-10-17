// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Shared model, storage, icon rendering and the popover UI.
        .target(name: "HarborKit"),
        // The folder editor app.
        .executableTarget(
            name: "Harbor",
            dependencies: ["HarborKit", .product(name: "Sparkle", package: "Sparkle")],
            // scripts/build.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // The tiny helper copied into every generated folder app in the Dock.
        .executableTarget(name: "HarborStub", dependencies: ["HarborKit"]),

        .testTarget(name: "HarborKitTests", dependencies: ["HarborKit"]),
        .testTarget(name: "HarborTests", dependencies: ["Harbor", "HarborKit"]),
    ]
)
