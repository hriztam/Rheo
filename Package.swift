// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rheo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Rheo",
            targets: ["RheoApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "RheoApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources"
        )
    ]
)
