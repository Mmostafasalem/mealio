import AVFoundation
import Foundation
import Observation
#if canImport(FluidAudio)
import FluidAudio
#endif

// MARK: - The optional offline speech model (Parakeet)
//
// Apple's on-device models don't cover every language (Lithuanian, for one).
// The person can download NVIDIA's Parakeet TDT v3 (25 European languages) to
// fill the gap. It is downloaded once from Hugging Face, kept in the app's own
// storage, and runs entirely on the phone through the open-source FluidAudio
// library; nothing spoken is sent anywhere.
//
// Parakeet transcribes a finished recording, so there is no live text while
// you speak: the engine listens for your voice and for the pause that ends it.
//
// Credits (shown in Profile › Voice, and they must stay):
//   Parakeet TDT 0.6B v3 by NVIDIA, CC BY 4.0, converted to Core ML by FluidInference.
//   FluidAudio by FluidInference, Apache 2.0.

@MainActor
@Observable
final class OfflineSpeechModel {
    static let shared = OfflineSpeechModel()

    enum State: Equatable {
        /// This build doesn't include the library that runs it.
        case unsupported
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded
    /// Bytes on disk once downloaded.
    private(set) var sizeOnDisk: Int64 = 0

    /// The languages Parakeet v3 covers that voice commands also know.
    static let languages: Set<VoiceLanguage> = [.english, .german, .lithuanian]

    static let credit = "Parakeet TDT 0.6B v3 by NVIDIA (CC BY 4.0), converted to Core ML by FluidInference. Runs with FluidAudio (Apache 2.0)."
    static let creditURL = URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!

    @ObservationIgnored private var download: Task<Void, Never>?

    /// Kept out of iCloud backups: it can always be downloaded again.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OfflineSpeech/parakeet-v3", isDirectory: true)
    }

    var isReady: Bool { state == .ready }

    init() { refresh() }

    func refresh() {
        #if canImport(FluidAudio)
        if case .downloading = state { return }
        if AsrModels.modelsExist(at: Self.directory, version: .v3) {
            state = .ready
            sizeOnDisk = Self.size(of: Self.directory.deletingLastPathComponent())
        } else {
            state = .notDownloaded
            sizeOnDisk = 0
        }
        #else
        state = .unsupported
        #endif
    }

    func startDownload() {
        #if canImport(FluidAudio)
        guard download == nil else { return }
        state = .downloading(0)
        download = Task { [weak self] in
            do {
                var folder = Self.directory.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? folder.setResourceValues(values)
                // Progress arrives off the main actor; hop back with a fresh weak reference.
                let owner = WeakOfflineModel(self)
                _ = try await AsrModels.download(to: Self.directory, version: .v3) { progress in
                    Task { @MainActor in
                        guard let self = owner.value, case .downloading = self.state else { return }
                        self.state = .downloading(min(max(progress.fractionCompleted, 0), 1))
                    }
                }
                guard !Task.isCancelled else { return }
                self?.download = nil
                self?.refresh()
                if self?.state != .ready { self?.state = .failed("The download didn't finish. Please try again.") }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.download = nil
                self.state = .failed("The download failed. Check your connection and try again.")
                appLog("[Voice] offline model download failed:", error)
            }
        }
        #endif
    }

    func cancelDownload() {
        download?.cancel()
        download = nil
        remove()
    }

    /// Deletes the model from the phone.
    func remove() {
        download?.cancel()
        download = nil
        #if canImport(FluidAudio)
        Task { await ParakeetRuntime.shared.unload() }
        #endif
        try? FileManager.default.removeItem(at: Self.directory.deletingLastPathComponent())
        state = .notDownloaded
        sizeOnDisk = 0
        refresh()
    }

    private static func size(of folder: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

#if canImport(FluidAudio)

/// Holds the loaded model between commands, so only the first one waits for it.
actor ParakeetRuntime {
    static let shared = ParakeetRuntime()
    private var manager: AsrManager?

    func transcribe(_ samples: [Float], language: VoiceLanguage, directory: URL) async throws -> String {
        let manager = try await loaded(from: directory)
        var decoder = TdtDecoderState.make()
        let hint = Language(rawValue: language.rawValue)
        let result = try await manager.transcribe(samples, decoderState: &decoder, language: hint)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loaded(from directory: URL) async throws -> AsrManager {
        if let manager { return manager }
        let models = try await AsrModels.load(from: directory, version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        return manager
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
    }
}

/// Records what is said, then has Parakeet transcribe it when listening stops.
nonisolated final class ParakeetSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let microphone = MicrophoneTap()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var language = VoiceLanguage.english
    private var directory: URL
    private var events: SpeechCaptureEvents?
    private var stopError: Error?

    var lastError: Error? { lock.withLock { stopError } }

    /// 16 kHz mono, as the model expects.
    private static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    /// About 30 seconds: far more than a command, and a bound on memory.
    /// (The voice sheet stops listening at the same point.)
    private static let maximumSamples = 16_000 * 30
    /// Loudness above this counts as someone speaking.
    private static let speechLevel: Float = 0.3

    init(language: VoiceLanguage, directory: URL) {
        self.language = language
        self.directory = directory
    }

    func start(locale: Locale, events: SpeechCaptureEvents) async throws {
        self.events = events
        let converter = BufferConverter(to: Self.format)
        try microphone.start(level: { level in
            events.level(level)
            if level > Self.speechLevel { events.voice() }
        }, onBuffer: { [weak self] buffer in
            guard let self, let converted = converter.convert(buffer), let channel = converted.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
            self.lock.withLock {
                guard self.samples.count < Self.maximumSamples else { return }
                self.samples.append(contentsOf: chunk)
            }
        })
    }

    func stop() async -> String {
        microphone.stop()
        let recorded = lock.withLock {
            defer { samples = [] }
            return samples
        }
        // Under a third of a second can't hold a word.
        guard recorded.count > 16_000 / 3 else { return "" }
        do {
            return try await ParakeetRuntime.shared.transcribe(recorded, language: language, directory: directory)
        } catch {
            // Kept for the caller to read after `stop()`: a `failed` event sent now
            // would arrive after listening has ended and be dropped.
            lock.withLock { stopError = SpeechCaptureError.transcriptionFailed }
            events?.failed(error)
            return ""
        }
    }
}

#endif

/// A weak reference that can cross into the download's progress callback.
private final class WeakOfflineModel: @unchecked Sendable {
    weak var value: OfflineSpeechModel?
    init(_ value: OfflineSpeechModel?) { self.value = value }
}
