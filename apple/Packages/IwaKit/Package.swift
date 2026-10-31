// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IwaKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
    ],
    products: [
        .library(name: "FrigateAPI", targets: ["FrigateAPI"]),
        .library(name: "IwaConnection", targets: ["IwaConnection"]),
    ],
    targets: [
        .target(name: "FrigateAPI"),
        .target(name: "IwaConnection"),
        .testTarget(name: "FrigateAPITests", dependencies: ["FrigateAPI"]),
        .testTarget(name: "IwaConnectionTests", dependencies: ["IwaConnection"]),
    ],
    swiftLanguageModes: [.v6]
)
