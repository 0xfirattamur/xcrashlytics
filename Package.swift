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
        .target(
            name: "XCrashlyticsCore",
            path: "Sources/XCrashlyticsCore"
        ),
        .executableTarget(
            name: "xcrashlytics",
            dependencies: [
                "XCrashlyticsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/xcrashlytics"
        ),
        .target(
            name: "XCrashlyticsTestSupport",
            dependencies: ["XCrashlyticsCore"],
            path: "Tests/XCrashlyticsTestSupport"
        ),
        .testTarget(
            name: "XCrashlyticsCoreTests",
            dependencies: ["XCrashlyticsCore", "XCrashlyticsTestSupport"],
            path: "Tests/XCrashlyticsCoreTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "xcrashlyticsTests",
            dependencies: ["XCrashlyticsCore", "XCrashlyticsTestSupport", "xcrashlytics"],
            path: "Tests/xcrashlyticsTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
