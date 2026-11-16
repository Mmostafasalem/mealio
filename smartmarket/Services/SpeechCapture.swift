import AVFoundation
import Speech

// MARK: - Speech to text, on the device
//
// One tap starts listening; the text arrives as it is spoken. Two engines sit
// behind the same small interface:
//
//  • `AnalyzerSpeechEngine` — Apple's speech analyser (iOS 26 and later).
//  • `RecognizerSpeechEngine` — the older on-device recogniser, for iOS 17–25
//    and for languages the new model doesn't cover yet.
//
// Audio never leaves the phone: the older recogniser is only used when it can
// work on the device. Both classes run off the main actor (the microphone tap
// fires on an audio thread) and report back through `@Sendable` callbacks.

nonisolated enum SpeechCaptureError: LocalizedError {
    case microphoneDenied, speechDenied, unsupportedLanguage, unavailable, audio(String)
    /// The language needs the offline model, which isn't downloaded.
    case needsOfflineModel

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Nourlo can't use the microphone. Turn it on in Settings › Nourlo."
        case .speechDenied: return "Speech recognition is off for Nourlo. Turn it on in Settings › Nourlo."
        case .unsupportedLanguage: return "On-device dictation isn't available for this language on this iPhone."
        case .needsOfflineModel: return "This language needs the offline speech model. Download it in Profile › Voice."
        case .unavailable: return "On-device dictation isn't available right now."
        case .audio(let detail): return "The microphone couldn't start. \(detail)"
        }
    }
}

/// What an engine reports while it listens.
nonisolated struct SpeechCaptureEvents: Sendable {
    /// Everything heard so far (finished text plus the part still changing).
    var transcript: @Sendable (String) -> Void
    /// Loudness from 0 to 1, a few times a second, for the listening animation.
    var level: @Sendable (Float) -> Void
    /// The language model is being downloaded before the first use.
    var preparing: @Sendable (Bool) -> Void
    /// Listening stopped because of an error.
    var failed: @Sendable (Error) -> Void
    /// Someone is speaking right now. Sent by engines that give no text until
    /// the end (the offline model), so the end of speech can still be heard.
    var voice: @Sendable () -> Void = {}
}

nonisolated protocol SpeechEngine: AnyObject, Sendable {
    func start(locale: Locale, events: SpeechCaptureEvents) async throws
    /// Stops the microphone and returns the final text.
    func stop() async -> String
}

nonisolated enum SpeechCapture {

    /// Asks for the microphone, and for speech recognition when the older engine will be used.
    static func requestPermissions(needsSpeechAuthorization: Bool) async throws {
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard microphone else { throw SpeechCaptureError.microphoneDenied }
        guard needsSpeechAuthorization else { return }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw SpeechCaptureError.speechDenied }
    }

    /// How a language would be listened to on this phone.
    enum Route: Equatable {
        /// Apple's speech model (iOS 26).
        case appleSpeech
        /// Apple's dictation model through the analyser (iOS 26).
        case appleDictation
        /// The older on-device recogniser (iOS 17–25).
        case appleRecognizer
        /// The downloaded offline model.
        case offlineModel
        /// Nothing on this phone can listen in this language yet; `offlineModelWouldHelp`
        /// says whether downloading the offline model would change that.
        case none(offlineModelWouldHelp: Bool)

        var name: String {
            switch self {
            case .appleSpeech: return "Apple's speech model, on this iPhone"
            case .appleDictation, .appleRecognizer: return "Apple dictation, on this iPhone"
            case .offlineModel: return "The offline model, on this iPhone"
            case .none(true): return "Needs the offline model"
            case .none(false): return "Not available on this iPhone"
            }
        }
    }

    /// Apple's models first (they show text as you speak), then the offline model.
    @MainActor
    static func route(for language: VoiceLanguage) async -> Route {
        let locale = language.locale
        if #available(iOS 26.0, *) {
            if await AnalyzerSpeechEngine.supportedLocale(for: locale, model: .speech) != nil { return .appleSpeech }
            if await AnalyzerSpeechEngine.supportedLocale(for: locale, model: .dictation) != nil { return .appleDictation }
        }
        if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition {
            return .appleRecognizer
        }
        let covered = OfflineSpeechModel.languages.contains(language)
        if covered, OfflineSpeechModel.shared.isReady { return .offlineModel }
        return .none(offlineModelWouldHelp: covered && OfflineSpeechModel.shared.state != .unsupported)
    }

    /// The engine for a route, and whether it needs the speech-recognition permission.
    @MainActor
    static func engine(for route: Route, language: VoiceLanguage) -> (engine: any SpeechEngine, needsSpeechAuthorization: Bool)? {
        switch route {
        case .appleSpeech:
            if #available(iOS 26.0, *) { return (AnalyzerSpeechEngine(model: .speech), false) }
            return nil
        case .appleDictation:
            if #available(iOS 26.0, *) { return (AnalyzerSpeechEngine(model: .dictation), true) }
            return nil
        case .appleRecognizer:
            return (RecognizerSpeechEngine(), true)
        case .offlineModel:
            #if canImport(FluidAudio)
            return (ParakeetSpeechEngine(language: language, directory: OfflineSpeechModel.directory), false)
            #else
            return nil
            #endif
        case .none:
            return nil
        }
    }
}

// MARK: - Microphone

/// The microphone tap shared by both engines: starts the audio session, hands
/// every buffer to `onBuffer` and reports loudness.
nonisolated final class MicrophoneTap: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var running = false

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func start(level: @escaping @Sendable (Float) -> Void, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechCaptureError.audio(error.localizedDescription)
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechCaptureError.audio("No microphone input.") }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            level(Self.loudness(of: buffer))
            onBuffer(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechCaptureError.audio(error.localizedDescription)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Root-mean-square loudness mapped to 0…1 (quiet room ≈ 0, normal speech ≈ 0.5).
    static func loudness(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for index in 0..<count { sum += data[index] * data[index] }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 50) / 40, 0), 1)
    }
}

// MARK: - Apple's speech analyser (iOS 26+)

/// Runs either of the analyser's transcribers: the new speech model
/// (`SpeechTranscriber`: English, German and a few more) or the dictation
/// model (`DictationTranscriber`: the same on-device models as keyboard
/// dictation, which cover more languages, Arabic among them).
@available(iOS 26.0, *)
nonisolated final class AnalyzerSpeechEngine: SpeechEngine, @unchecked Sendable {
    enum Model: Sendable { case speech, dictation }

    private let model: Model
    private let microphone = MicrophoneTap()
    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var finished = ""
    private var changing = ""

    init(model: Model = .speech) { self.model = model }

    /// The locale this model would listen in, or nil when it doesn't cover the language.
    static func supportedLocale(for locale: Locale, model: Model) async -> Locale? {
        switch model {
        case .speech: return await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        case .dictation: return await DictationTranscriber.supportedLocale(equivalentTo: locale)
        }
    }

    private var text: String {
        lock.withLock { (finished + changing).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func take(_ piece: String, isFinal: Bool) {
        lock.withLock {
            if isFinal {
                finished += piece
                changing = ""
            } else {
                changing = piece
            }
        }
    }

    func start(locale: Locale, events: SpeechCaptureEvents) async throws {
        guard let supported = await Self.supportedLocale(for: locale, model: model) else {
            throw SpeechCaptureError.unsupportedLanguage
        }
        let module: any SpeechModule
        let listen: @Sendable () async throws -> Void
        switch model {
        case .speech:
            let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
            module = transcriber
            listen = { [weak self] in
                for try await result in transcriber.results {
                    guard let self else { return }
                    self.take(String(result.text.characters), isFinal: result.isFinal)
                    events.transcript(self.text)
                }
            }
        case .dictation:
            let transcriber = DictationTranscriber(locale: supported, preset: .progressiveShortDictation)
            module = transcriber
            listen = { [weak self] in
                for try await result in transcriber.results {
                    guard let self else { return }
                    self.take(String(result.text.characters), isFinal: result.isFinal)
                    events.transcript(self.text)
                }
            }
        }
        // The language model is downloaded by the system once, then kept.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            events.preparing(true)
            defer { events.preparing(false) }
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw SpeechCaptureError.unavailable
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)
        lock.withLock {
            self.analyzer = analyzer
            self.input = continuation
        }
        results = Task {
            do { try await listen() } catch { events.failed(error) }
        }

        let converter = BufferConverter(to: format)
        try microphone.start(level: events.level) { buffer in
            guard let converted = converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func stop() async -> String {
        microphone.stop()
        let (analyzer, input) = lock.withLock { (self.analyzer, self.input) }
        input?.finish()
        // Lets the model finish the last words before the text is read.
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
        lock.withLock {
            self.analyzer = nil
            self.input = nil
        }
        return text
    }
}

/// Converts microphone buffers to the format the speech model asks for.
nonisolated final class BufferConverter: @unchecked Sendable {
    private let format: AVAudioFormat
    private var converter: AVAudioConverter?

    init(to format: AVAudioFormat) { self.format = format }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            // One buffer at a time, with no resampler state carried over to pad.
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        let source = Once(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if let next = source.take() {
                inputStatus.pointee = .haveData
                return next
            }
            inputStatus.pointee = .noDataNow
            return nil
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    /// Hands its buffer out exactly once.
    private final class Once: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        func take() -> AVAudioPCMBuffer? {
            defer { buffer = nil }
            return buffer
        }
    }
}

// MARK: - The older on-device recogniser (iOS 17+)

nonisolated final class RecognizerSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let microphone = MicrophoneTap()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var heard = ""
    private var done: CheckedContinuation<Void, Never>?
    private var isDone = false

    func start(locale: Locale, events: SpeechCaptureEvents) async throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { throw SpeechCaptureError.unsupportedLanguage }
        // On the device or not at all: nothing spoken is sent to a server.
        guard recognizer.supportsOnDeviceRecognition else { throw SpeechCaptureError.unsupportedLanguage }
        guard recognizer.isAvailable else { throw SpeechCaptureError.unavailable }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.lock.withLock { self.heard = text }
                events.transcript(text)
            }
            if error != nil || result?.isFinal == true {
                // An error after the request ended is just the end of listening.
                if let error, self.lock.withLock({ self.request != nil }) { events.failed(error) }
                self.finish()
            }
        }
        lock.withLock {
            self.recognizer = recognizer
            self.request = request
            self.task = task
        }
        try microphone.start(level: events.level) { buffer in
            request.append(buffer)
        }
    }

    private func finish() {
        let waiting: CheckedContinuation<Void, Never>? = lock.withLock {
            isDone = true
            defer { done = nil }
            return done
        }
        waiting?.resume()
    }

    func stop() async -> String {
        microphone.stop()
        let request: SFSpeechAudioBufferRecognitionRequest? = lock.withLock {
            defer { self.request = nil }
            return self.request
        }
        request?.endAudio()
        // Wait briefly for the last words, then take what there is.
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.finish()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyDone: Bool = lock.withLock {
                if isDone { return true }
                done = continuation
                return false
            }
            if alreadyDone { continuation.resume() }
        }
        timeout.cancel()
        let (task, text): (SFSpeechRecognitionTask?, String) = lock.withLock {
            defer { self.task = nil; self.recognizer = nil }
            return (self.task, self.heard)
        }
        task?.cancel()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
