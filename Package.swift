// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DockModeCorePackage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DockModeCore", targets: ["DockModeCore"]),
        .executable(name: "DockModeCoreChecks", targets: ["DockModeCoreChecks"])
    ],
    targets: [
        .target(name: "DockModeCore"),
        .executableTarget(name: "DockModeCoreChecks", dependencies: ["DockModeCore"])
    ],
    swiftLanguageModes: [.v6]
)
