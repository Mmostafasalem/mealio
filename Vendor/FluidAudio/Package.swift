// swift-tools-version: 6.0
import PackageDescription

// A trimmed local copy of FluidAudio (see README.md): speech recognition only.
// The upstream package's optional parts are left out, exactly as its own
// `traits: []` configuration does: no text-to-speech, no speaker diarization
// and no prebuilt text-normalization binary. Their source is guarded upstream
// by `#if TTS` / `#if Diarizer` / `canImport(NemoTextProcessing)`, so nothing
// here needs editing to build without them.
let package = Package(
    name: "FluidAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "FluidAudio", targets: ["FluidAudio"]),
    ],
    targets: [
        .target(
            name: "FluidAudio",
            dependencies: ["FastClusterWrapper", "MachTaskSelfWrapper"],
            path: "Sources/FluidAudio",
            exclude: ["ASR/Parakeet/Unified/benchmark.md"]
        ),
        .target(name: "FastClusterWrapper", path: "Sources/FastClusterWrapper", publicHeadersPath: "include"),
        .target(name: "MachTaskSelfWrapper", path: "Sources/MachTaskSelfWrapper", publicHeadersPath: "include"),
    ],
    cxxLanguageStandard: .cxx17
)
