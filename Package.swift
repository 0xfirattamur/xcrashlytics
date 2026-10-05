// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xcrashlytics",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "xcrashlytics", targets: ["xcrashlytics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "xcrashlytics",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/xcrashlytics"
        ),
        .testTarget(
            name: "xcrashlyticsTests",
            dependencies: ["xcrashlytics"],
            path: "Tests/xcrashlyticsTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
