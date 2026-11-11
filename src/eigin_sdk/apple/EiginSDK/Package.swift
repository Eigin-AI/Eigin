// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EiginSDK",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "EiginSDK", targets: ["EiginSDK"])],
    targets: [
        .binaryTarget(name: "eigin_sdkFFI", path: "Artifacts/EiginSDKBindings.xcframework"),
        .target(name: "EiginSDKBindings", dependencies: ["eigin_sdkFFI"]),
        .target(
            name: "EiginSDK",
            dependencies: ["EiginSDKBindings"],
            resources: [.copy("Resources/THIRD-PARTY-NOTICES.txt"), .copy("Resources/NOTICES.json")]
        ),
        .testTarget(name: "EiginSDKTests", dependencies: ["EiginSDK"]),
    ]
)
