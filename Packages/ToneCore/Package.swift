// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToneCore",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "ToneCore", targets: ["ToneCore"]),
        .library(name: "ToneAudio", targets: ["ToneAudio"]),
        .executable(name: "eqcli", targets: ["eqcli"]),
    ],
    targets: [
        // Pure DSP. No Core Audio, no Bluetooth — the part that must be correct is the
        // part that is easiest to test.
        .target(name: "ToneCore"),
        // Core Audio plumbing: process tap, aggregate device, IO callback.
        .target(name: "ToneAudio", dependencies: ["ToneCore"]),
        // Headless driver, so the pipeline can be measured without a UI.
        .executableTarget(name: "eqcli", dependencies: ["ToneAudio", "ToneCore"]),
        .testTarget(name: "ToneCoreTests", dependencies: ["ToneCore"]),
    ]
)
