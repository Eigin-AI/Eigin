// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SDKBindingContracts",
    platforms: [.macOS(.v15)],
    targets: [
        .systemLibrary(name: "eigin_sdkFFI", path: "Generated/FFI"),
        .target(
            name: "FixtureBindings",
            dependencies: ["eigin_sdkFFI"],
            path: "Generated/Swift",
            linkerSettings: [.linkedLibrary("eigin_sdk")]
        ),
        .testTarget(name: "BindingContractTests", dependencies: ["FixtureBindings"]),
    ]
)
