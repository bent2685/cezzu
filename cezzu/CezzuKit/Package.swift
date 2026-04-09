// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CezzuKit",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CezzuKit",
            targets: ["CezzuKit"]
        ),
        // 一个 SwiftPM executable，让你不用建 Xcode workspace 就能直接
        // `swift run CezzuMac` 把整个 App 跑起来。
        // 不带 .app bundle / 不入沙盒；正式上架前再用 README 里的 Xcode 流程。
        .executable(name: "CezzuMac", targets: ["CezzuMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tid-kijyun/Kanna.git", from: "5.3.0")
    ],
    targets: [
        .target(
            name: "CezzuKit",
            dependencies: [
                .product(name: "Kanna", package: "Kanna")
            ],
            resources: [
                .copy("Resources/SeedRules"),
                .copy("Resources/inject_start.js"),
                .copy("Resources/inject_end.js"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "CezzuMac",
            dependencies: ["CezzuKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CezzuKitTests",
            dependencies: ["CezzuKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
