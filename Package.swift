// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PPTTimerMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PPTTimer", targets: ["PPTTimer"])
    ],
    targets: [
        .executableTarget(
            name: "PPTTimer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PPTTimerTests",
            dependencies: ["PPTTimer"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
