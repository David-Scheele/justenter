// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JustEnter",
    platforms: [
        .macOS("26.0"),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.2"),
    ],
    targets: [
        .executableTarget(
            name: "JustEnter",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        // Diagnostic CLI: `swift run ModelTest <variant>` downloads and loads a
        // speech model exactly like the app does.
        .executableTarget(
            name: "ModelTest",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
