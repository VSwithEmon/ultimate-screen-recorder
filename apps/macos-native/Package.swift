// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenRec",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenRecCore", targets: ["ScreenRecCore"]),
        .executable(name: "ScreenRecApp", targets: ["ScreenRecApp"]),
    ],
    targets: [
        .target(name: "ScreenRecCore"),
        .executableTarget(name: "ScreenRecApp", dependencies: ["ScreenRecCore"]),
        .testTarget(name: "ScreenRecCoreTests", dependencies: ["ScreenRecCore"]),
    ]
)
