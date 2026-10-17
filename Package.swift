// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.macOS("26.0")],
    targets: [
        // Shared model, storage, icon rendering and the popover UI.
        .target(name: "HarborKit"),
        // The folder editor app.
        .executableTarget(name: "Harbor", dependencies: ["HarborKit"]),
        // The tiny helper copied into every generated folder app in the Dock.
        .executableTarget(name: "HarborStub", dependencies: ["HarborKit"]),

        .testTarget(name: "HarborKitTests", dependencies: ["HarborKit"]),
        .testTarget(name: "HarborTests", dependencies: ["Harbor", "HarborKit"]),
    ]
)
