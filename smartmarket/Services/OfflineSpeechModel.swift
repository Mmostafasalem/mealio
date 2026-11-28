import AVFoundation
import Foundation
import Observation
import UIKit
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
// The download (about 470 MB, almost all of it one 445 MB file) is the fragile
// part. FluidAudio streams each file into a `.partial` file and resumes it with
// an HTTP range request, retrying a dropped connection itself; on top of that:
//
//  • the result is judged by the files on disk, never by the state the screen
//    is in (a finished download used to be reported as "didn't finish");
//  • Try again always starts a fresh attempt: the attempt before it is
//    cancelled and ignored, a half-finished download resumes from its bytes,
//    and anything that was corrupt or incomplete is deleted first;
//  • the app asks iOS for time to keep going when it is sent to the
//    background, keeps the screen awake while downloading, and picks an
//    interrupted download up again when it comes back;
//  • free space is checked first, and a failure says what went wrong (no
//    connection, not enough space, the server).
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
        /// Files are arriving: 0…1.
        case downloading(Double)
        /// Everything is downloaded; Core ML is preparing the model for this iPhone.
        case preparing
        case ready
        case failed(String)
    }

    /// Why a download stopped.
    enum Failure: Equatable {
        case noConnection
        /// The connection dropped or the app was in the background too long; what arrived is kept.
        case interrupted
        case tooSlow
        case notEnoughSpace
        case server(Int?)
        /// A file arrived damaged or the set was incomplete; it is downloaded again from the start.
        case corrupt
        case other

        var message: String {
            switch self {
            case .noConnection: return "There's no internet connection. Connect to Wi-Fi or mobile data and try again."
            case .interrupted: return "The download was interrupted. Try again to continue where it stopped."
            case .tooSlow: return "The connection is too slow right now. Try again on Wi-Fi."
            case .notEnoughSpace:
                let needed = ByteCountFormatter.string(fromByteCount: OfflineSpeechModel.requiredSpace, countStyle: .file)
                return "There isn't enough free space on this iPhone. The model needs about \(needed)."
            case .server(let code?): return "Hugging Face, where the model is kept, didn't answer properly (error \(code)). Please try again later."
            case .server(nil): return "Hugging Face, where the model is kept, didn't answer properly. Please try again later."
            case .corrupt: return "A downloaded file was damaged, so it was removed. Try again to download it afresh."
            case .other: return "The download didn't finish. Please try again."
            }
        }

        /// The bytes already on the phone are worth keeping for the next attempt.
        var keepsPartialFiles: Bool {
            switch self {
            case .noConnection, .interrupted, .tooSlow, .server: return true
            case .notEnoughSpace, .corrupt, .other: return false
            }
        }
    }

    /// What does the downloading, so tests can stand in for Hugging Face.
    struct Installer {
        enum Step: Sendable { case downloading(Double), preparing }
        var isSupported: Bool
        /// True when the model in `folder` is complete and ready to load.
        var isInstalled: @MainActor (_ folder: URL) -> Bool
        var download: @MainActor (_ folder: URL, _ step: @escaping @Sendable (Step) -> Void) async throws -> Void
        /// Free bytes on the volume holding `folder`, when known.
        var freeSpace: @MainActor (_ folder: URL) -> Int64?
    }

    private(set) var state: State = .notDownloaded
    /// Bytes on disk once downloaded.
    private(set) var sizeOnDisk: Int64 = 0
    /// Why the last attempt stopped (nil while none has failed).
    private(set) var lastFailure: Failure?

    /// The languages Parakeet v3 covers that voice commands also know.
    static let languages: Set<VoiceLanguage> = [.english, .german, .spanish, .french, .russian, .lithuanian]

    static let credit = "Parakeet TDT 0.6B v3 by NVIDIA (CC BY 4.0), converted to Core ML by FluidInference. Runs with FluidAudio (Apache 2.0)."
    static let creditURL = URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!
    /// The download plus room for Core ML's compiled copy.
    static let requiredSpace: Int64 = 1_200_000_000

    /// Kept out of iCloud backups: it can always be downloaded again.
    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OfflineSpeech/parakeet-v3", isDirectory: true)
    }

    /// Where this instance keeps the model (`directory`, or a test folder).
    let folder: URL
    /// The folder holding everything the download writes (FluidAudio puts the files beside `folder`).
    var root: URL { folder.deletingLastPathComponent() }

    @ObservationIgnored private let installer: Installer
    @ObservationIgnored private var download: Task<Void, Never>?
    /// Bumped by every attempt, so a late answer from an older one is ignored.
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// An interrupted download goes on by itself when the app comes back, once per interruption.
    @ObservationIgnored private var resumeWhenActive = false

    var isReady: Bool { state == .ready }
    var isBusy: Bool {
        switch state {
        case .downloading, .preparing: return true
        default: return false
        }
    }

    init(installer: Installer = .parakeet, folder: URL = OfflineSpeechModel.directory, watchesApp: Bool = true) {
        self.installer = installer
        self.folder = folder
        refresh()
        if watchesApp { watchApp() }
    }

    /// Reads the state from the files on disk. While a download runs it is left alone.
    func refresh() {
        guard installer.isSupported else {
            state = .unsupported
            return
        }
        guard !isBusy else { return }
        if installer.isInstalled(folder) {
            state = .ready
            lastFailure = nil
            sizeOnDisk = Self.size(of: root)
        } else if case .failed = state {
            // Keep the message until the person tries again.
        } else {
            state = .notDownloaded
            sizeOnDisk = 0
        }
    }

    /// Starts the download, or starts it again. Always a fresh attempt: one
    /// still running is dropped, and files from a failed attempt that can't be
    /// resumed are deleted first.
    func startDownload() {
        guard installer.isSupported else {
            state = .unsupported
            return
        }
        if installer.isInstalled(folder) {
            finishAttempt()
            state = .ready
            sizeOnDisk = Self.size(of: root)
            return
        }
        download?.cancel()
        download = nil
        attempt += 1
        let attempt = attempt
        resumeWhenActive = false
        if let lastFailure, !lastFailure.keepsPartialFiles { clearFiles() }
        if let free = installer.freeSpace(root), free < Self.requiredSpace - Self.size(of: root) {
            fail(.notEnoughSpace, attempt: attempt)
            return
        }
        lastFailure = nil
        state = .downloading(0)
        keepGoingInBackground(true)
        // Progress arrives off the main actor; hop back with a fresh weak reference.
        let owner = WeakOfflineModel(self)
        let progress: @Sendable (Installer.Step) -> Void = { step in
            Task { @MainActor in owner.value?.advance(step, attempt: attempt) }
        }
        let folder = folder
        let installer = installer
        download = Task { [weak self] in
            do {
                try Self.prepare(folder.deletingLastPathComponent())
                try await installer.download(folder, progress)
                self?.completed(attempt: attempt)
            } catch {
                guard let self, attempt == self.attempt else { return }
                // Cancelled by the person (or by a newer attempt): nothing to report.
                if Task.isCancelled { return }
                appLog("[Voice] offline model download failed:", error)
                self.fail(Self.failure(for: error, inBackground: UIApplication.shared.applicationState == .background), attempt: attempt)
            }
        }
    }

    func cancelDownload() {
        attempt += 1
        download?.cancel()
        download = nil
        finishAttempt()
        remove()
    }

    /// Deletes the model from the phone.
    func remove() {
        attempt += 1
        download?.cancel()
        download = nil
        finishAttempt()
        #if canImport(FluidAudio)
        Task { await ParakeetRuntime.shared.unload() }
        #endif
        clearFiles()
        lastFailure = nil
        state = .notDownloaded
        sizeOnDisk = 0
        refresh()
    }

    // MARK: Attempts

    private func advance(_ step: Installer.Step, attempt: Int) {
        guard attempt == self.attempt else { return }
        switch (step, state) {
        case (.downloading(let fraction), .downloading(let shown)):
            // Never backwards: each model file reports its own progress from zero.
            state = .downloading(max(shown, min(max(fraction, 0), 1)))
        case (.preparing, .downloading), (.preparing, .preparing):
            state = .preparing
        default:
            break
        }
    }

    private func completed(attempt: Int) {
        guard attempt == self.attempt else { return }
        download = nil
        finishAttempt()
        // Judged by the files, not by what the screen showed.
        if installer.isInstalled(folder) {
            lastFailure = nil
            state = .ready
            sizeOnDisk = Self.size(of: root)
        } else {
            fail(.corrupt, attempt: attempt)
        }
    }

    private func fail(_ failure: Failure, attempt: Int) {
        guard attempt == self.attempt else { return }
        download = nil
        finishAttempt()
        lastFailure = failure
        if !failure.keepsPartialFiles { clearFiles() }
        state = .failed(failure.message)
        resumeWhenActive = failure == .interrupted
    }

    /// Deletes everything the download wrote, finished or not.
    private func clearFiles() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func prepare(_ root: URL) throws {
        var root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    /// What a download error means for the person.
    nonisolated static func failure(for error: Error, inBackground: Bool = false) -> Failure {
        #if canImport(FluidAudio)
        if let download = error as? DownloadError {
            switch download {
            case .rateLimited(let code, _): return .server(code)
            case .invalidResponse, .htmlErrorResponse: return .server(nil)
            case .invalidArtifact, .modelNotFound, .modelMissing: return .corrupt
            case .stalled: return .interrupted
            case .networkDisabled: return .noConnection
            case .downloadFailed(_, let underlying): return failure(for: underlying, inBackground: inBackground)
            }
        }
        #endif
        var current: NSError? = error as NSError
        var seen = 0
        while let nsError = current, seen < 8 {
            seen += 1
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
                     NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorCannotConnectToHost:
                    return inBackground ? .interrupted : .noConnection
                case NSURLErrorTimedOut: return inBackground ? .interrupted : .tooSlow
                case NSURLErrorNetworkConnectionLost, NSURLErrorCancelled, NSURLErrorBackgroundSessionWasDisconnected,
                     NSURLErrorCallIsActive:
                    return .interrupted
                case NSURLErrorBadServerResponse, NSURLErrorResourceUnavailable, NSURLErrorZeroByteResource,
                     NSURLErrorCannotDecodeContentData, NSURLErrorCannotParseResponse:
                    return .server(nil)
                default: break
                }
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError { return .notEnoughSpace }
            if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return .notEnoughSpace }
            if nsError.domain == "HTTP" { return .server(nsError.code) }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return inBackground ? .interrupted : .other
    }

    // MARK: Background and foreground

    /// While downloading: more time from iOS if the app is sent away, and no screen lock.
    private func keepGoingInBackground(_ on: Bool) {
        guard Self.isRunningAsApp else { return }
        UIApplication.shared.isIdleTimerDisabled = on
        if on, backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Offline speech model") { [weak self] in
                // Out of time: the transfer stops here and resumes when the app is back.
                MainActor.assumeIsolated { self?.endBackgroundTask() }
            }
        } else if !on {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func finishAttempt() {
        keepGoingInBackground(false)
    }

    private func watchApp() {
        guard Self.isRunningAsApp else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
    }

    /// Back in the app after an interruption: carry on from the bytes already here.
    func becameActive() {
        guard resumeWhenActive, case .failed = state else { return }
        resumeWhenActive = false
        startDownload()
    }

    /// Unit tests host the app too; they drive the model by hand.
    private static var isRunningAsApp: Bool { NSClassFromString("XCTestCase") == nil }

    static func size(of folder: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// A weak reference that can cross into the download's progress callback.
private final class WeakOfflineModel: @unchecked Sendable {
    weak var value: OfflineSpeechModel?
    init(_ value: OfflineSpeechModel?) { self.value = value }
}

extension OfflineSpeechModel.Installer {
    /// The real one: Parakeet TDT v3 from Hugging Face, through FluidAudio.
    nonisolated static var parakeet: Self {
        #if canImport(FluidAudio)
        Self(
            isSupported: true,
            isInstalled: { AsrModels.modelsExist(at: $0, version: .v3) },
            download: { folder, step in
                _ = try await AsrModels.download(to: folder, version: .v3) { progress in
                    switch progress.phase {
                    case .listing: step(.downloading(0))
                    // Each call reports downloading as the first half and compiling as the second.
                    case .downloading: step(.downloading(min(progress.fractionCompleted * 2, 1)))
                    case .compiling: step(.preparing)
                    }
                }
            },
            freeSpace: { folder in
                let probe = FileManager.default.fileExists(atPath: folder.path) ? folder : folder.deletingLastPathComponent()
                let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                return values?.volumeAvailableCapacityForImportantUsage
            }
        )
        #else
        Self(isSupported: false, isInstalled: { _ in false }, download: { _, _ in }, freeSpace: { _ in nil })
        #endif
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

