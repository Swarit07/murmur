// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

/// MLX compiles Metal shaders, which needs full Xcode. `MURMUR_NO_MLX=1 swift test` builds and tests
/// everything else with only the command line tools.
let withMLX = Context.environment["MURMUR_NO_MLX"] == nil
let mlxTargets: [Target.Dependency] = withMLX ? ["CleanupMLX"] : []

let package = Package(
    name: "murmur",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MurmurKit", targets: ["MurmurKit"]),
        .executable(name: "murmur-cli", targets: ["MurmurCLI"]),
        .executable(name: "murmur-bench", targets: ["MurmurBench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "3.32.3")),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMinor(from: "0.32.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.12.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.4"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Pure Swift: state machine, shared models, timings, text metrics. No UI, no system services.
        .target(name: "Core", swiftSettings: strict),

        .target(name: "Hotkey", dependencies: ["Core"], swiftSettings: strict),
        .target(name: "Audio", dependencies: ["Core"], swiftSettings: strict),
        .target(
            name: "SpeechEngines",
            dependencies: [
                "Core", "Audio",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            swiftSettings: strict
        ),
        // Rules stage, guard checker, time limit, CleanupProvider protocol, hosted and Apple providers.
        .target(name: "Cleanup", dependencies: ["Core"], swiftSettings: strict),
        .target(name: "Context", dependencies: ["Core"], swiftSettings: strict),
        .target(name: "Insertion", dependencies: ["Core", "Context"], swiftSettings: strict),
        .target(name: "Store", dependencies: ["Core", .product(name: "GRDB", package: "GRDB.swift")], swiftSettings: strict),
        // Wires engines, cleanup and insertion together; shared by the CLI, the bench and later the app.
        .target(
            name: "Pipeline",
            dependencies: ["Core", "Audio", "SpeechEngines", "Cleanup", "Context", "Insertion"] + mlxTargets,
            swiftSettings: strict
        ),
        .target(name: "UI", dependencies: ["Core"], swiftSettings: strict),

        // App-level orchestration the menu-bar app links: the dictation controller and its wiring.
        .target(
            name: "MurmurKit",
            dependencies: ["Core", "Hotkey", "Audio", "SpeechEngines", "Cleanup", "Context", "Insertion", "Store", "Pipeline"],
            swiftSettings: strict
        ),
        .executableTarget(
            name: "MurmurCLI",
            dependencies: [
                "Core", "Hotkey", "Audio", "SpeechEngines", "Cleanup", "Context", "Insertion", "Pipeline",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strict
        ),
        .executableTarget(
            name: "MurmurBench",
            dependencies: [
                "Core", "Audio", "SpeechEngines", "Cleanup", "Pipeline",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strict
        ),

        .testTarget(name: "CoreTests", dependencies: ["Core"], swiftSettings: strict),
        .testTarget(name: "HotkeyTests", dependencies: ["Hotkey"], swiftSettings: strict),
        .testTarget(name: "StoreTests", dependencies: ["Core", "Store"], swiftSettings: strict),
        .testTarget(name: "CleanupTests", dependencies: ["Core", "Cleanup"], swiftSettings: strict),
        .testTarget(name: "InsertionTests", dependencies: ["Core", "Context", "Insertion"], swiftSettings: strict),
    ]
)

if withMLX {
    package.targets.append(
        // The MLX provider lives apart so the rest of Cleanup builds and tests without MLX.
        .target(
            name: "CleanupMLX",
            dependencies: [
                "Core", "Cleanup",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: strict
        )
    )
}
