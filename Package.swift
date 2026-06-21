// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SparrowWord",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "SparrowWord",
            path: "SparrowWord/SparrowWord",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "SparrowWord.entitlements",
            ]),
    ]
)
