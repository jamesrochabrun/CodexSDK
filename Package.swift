// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexSDK",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CodexSDK",
            targets: ["CodexSDK"]
        ),
        .executable(
            name: "CodexExample",
            targets: ["CodexExample"]
        ),
        .executable(
            name: "CodexChatApp",
            targets: ["CodexChatApp"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CodexSDK",
            dependencies: []
        ),
        .testTarget(
            name: "CodexSDKTests",
            dependencies: ["CodexSDK"]
        ),
        .executableTarget(
            name: "CodexExample",
            dependencies: ["CodexSDK"],
            path: "Examples/CodexExample"
        ),
        .executableTarget(
            name: "CodexChatApp",
            dependencies: ["CodexSDK"],
            path: "Examples/CodexChatApp"
        )
    ]
)
