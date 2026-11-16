import AVFoundation
import XCTest
@testable import smartmarket
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Downloads the real offline speech model and transcribes recorded speech with it.
/// Slow and large (several hundred MB), so it only runs when asked for:
///
///     TEST_RUNNER_NOURLO_PARAKEET_AUDIO=/path/to/folder xcodebuild test …
///
/// The folder holds 16 kHz mono `en.wav` ("Log two eggs and a slice of toast for
/// breakfast"), optionally `de.wav` (the same in German) and `lt.wav` / `lt-word.wav` (any Lithuanian speech).
@MainActor
final class OfflineSpeechLiveTests: XCTestCase {

    private func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let converted = try XCTUnwrap(BufferConverter(to: target).convert(buffer))
        let channel = try XCTUnwrap(converted.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
    }

    func testTheOfflineModelTranscribesSpeechThatTheRuleBookUnderstands() async throws {
        #if canImport(FluidAudio)
        let folder = try XCTUnwrap(ProcessInfo.processInfo.environment["NOURLO_PARAKEET_AUDIO"].map(URL.init(fileURLWithPath:)),
                                   "set TEST_RUNNER_NOURLO_PARAKEET_AUDIO to run this").self
        let directory = folder.appendingPathComponent("model/parakeet-v3", isDirectory: true)
        let started = Date()
        _ = try await AsrModels.download(to: directory, version: .v3)
        XCTAssertTrue(AsrModels.modelsExist(at: directory, version: .v3))
        print("[parakeet] download+compile: \(Int(Date().timeIntervalSince(started))) s")

        let english = try await ParakeetRuntime.shared.transcribe(try samples(folder.appendingPathComponent("en.wav")), language: .english, directory: directory)
        print("[parakeet] en: \(english)")
        guard case .logFood(let items, let slot) = VoiceRuleBook.parse(english, language: .english) else {
            return XCTFail("not understood as food: \(english)")
        }
        XCTAssertEqual(slot, .breakfast)
        XCTAssertEqual(items.first?.name, "eggs")
        XCTAssertEqual(items.first?.quantity, 2)

        let germanFile = folder.appendingPathComponent("de.wav")
        if FileManager.default.fileExists(atPath: germanFile.path) {
            let german = try await ParakeetRuntime.shared.transcribe(try samples(germanFile), language: .german, directory: directory)
            print("[parakeet] de: \(german)")
            guard case .logFood(let items, let slot) = VoiceRuleBook.parse(german, language: .german) else {
                return XCTFail("not understood as food: \(german)")
            }
            XCTAssertEqual(slot, .breakfast)
            XCTAssertEqual(items.first?.name, "egg")
        }
        // Lithuanian has no synthetic voice to record from: any `lt*.wav` put in the folder is
        // transcribed and printed for a person to compare with what was said.
        for name in ["lt.wav", "lt-word.wav"] {
            let file = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let lithuanian = try await ParakeetRuntime.shared.transcribe(try samples(file), language: .lithuanian, directory: directory)
            print("[parakeet] \(name): \(lithuanian)")
            XCTAssertFalse(lithuanian.isEmpty, name)
        }
        await ParakeetRuntime.shared.unload()
        #else
        throw XCTSkip("This build doesn't include the offline speech library.")
        #endif
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOURLO_PARAKEET_AUDIO"] != nil,
                          "Runs only with TEST_RUNNER_NOURLO_PARAKEET_AUDIO set (downloads the model).")
    }
}
