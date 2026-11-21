import SwiftUI
import Observation

/// Drives the voice sheet: listen → understand → (confirm) → do → undo.
///
/// One tap starts it. Listening ends by itself when the person stops talking,
/// and a command that matched completely saves itself after a short countdown,
/// so nothing else needs touching; anything the person does on the review card
/// stops the countdown.
@MainActor
@Observable
final class VoiceCommandModel {

    enum Phase: Equatable {
        case starting
        /// The speech model for this language is being downloaded (first use only).
        case preparing
        case listening
        case thinking
        case review
        case done
        case failed(String)
        /// Photo mode: waiting for the person to take or choose a photo.
        case choosingPhoto
        /// Photo mode: online AI is naming the foods in the photo.
        case readingPhoto
    }

    /// Opened to log a meal from a photo instead of listening.
    let photoMode: Bool
    /// The review card came from a photo read by online AI (shown on the card; never saves by itself).
    private(set) var fromPhoto = false

    init(photoMode: Bool = false) {
        self.photoMode = photoMode
    }

    private(set) var phase: Phase = .starting
    private(set) var transcript = ""
    /// Microphone loudness, 0…1, for the listening animation.
    private(set) var level: Double = 0
    private(set) var plan: VoicePlan?
    private(set) var message = ""
    /// A voice has been heard (engines without live text report this instead of words).
    private(set) var hasSpoken = false
    /// False while the offline model listens: its text only arrives at the end.
    private(set) var showsLiveText = true
    /// Seconds until a complete command saves itself; nil when it won't.
    private(set) var countdown: Int?
    private(set) var canUndo = false
    /// The reading allowed for misheard words, so it waits for a tap.
    private var guessed = false
    /// Which model helped when the rule book couldn't place the phrase (shown on the card).
    private(set) var helper: VoiceInterpreter.Source?
    /// The microphone or speech permission was refused; the sheet offers Settings.
    private(set) var permissionDenied = false

    /// Called when a command leads somewhere (a screen, a workout, an exercise).
    var onNavigate: (VoiceNavigation) -> Void = { _ in }
    /// Called when the sheet should close by itself.
    var onFinished: () -> Void = {}

    @ObservationIgnored private var engine: (any SpeechEngine)?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var undo: (() -> Void)?
    @ObservationIgnored private var lastHeardAt = Date()
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var session = 0

    /// Quiet for this long after speaking ends the listening.
    static let endOfSpeech: TimeInterval = 1.6
    /// Nothing heard at all for this long gives up.
    static let nothingHeard: TimeInterval = 8
    static let autoConfirmSeconds = 4
    /// The offline model hears any loud sound as a voice, so a noisy room would
    /// never end the listening: it stops here whatever is heard.
    static let longestOfflineListening: TimeInterval = 30

    /// The language being listened for (chosen in Profile).
    private(set) var language = VoiceLanguage.current

    /// A phrase handed in by a UI test (`-NourloVoiceTestPhrase "…"`): the microphone is skipped.
    static var testPhrase: String? {
        guard NourloTips.isUITesting() else { return nil }
        return UserDefaults.standard.string(forKey: "NourloVoiceTestPhrase")
    }

    // MARK: Listening

    func start() {
        cancelTimers()
        stopEngine()
        session += 1
        let session = session
        transcript = ""
        plan = nil
        message = ""
        level = 0
        canUndo = false
        undo = nil
        permissionDenied = false
        helper = nil
        fromPhoto = false
        hasSpoken = false
        language = VoiceLanguage.current
        if photoMode {
            phase = .choosingPhoto
            return
        }
        phase = .starting
        if let phrase = Self.testPhrase {
            transcript = phrase
            understand(phrase)
            return
        }
        Task { await listen(session: session) }
    }

    private func listen(session: Int) async {
        let locale = language.locale
        let route = await SpeechCapture.route(for: language)
        guard let choice = SpeechCapture.engine(for: route, language: language) else {
            fail(route == .none(offlineModelWouldHelp: true) ? SpeechCaptureError.needsOfflineModel : SpeechCaptureError.unsupportedLanguage)
            return
        }
        showsLiveText = route != .offlineModel
        do {
            try await SpeechCapture.requestPermissions(needsSpeechAuthorization: choice.needsSpeechAuthorization)
            guard session == self.session else { return }
            engine = choice.engine
            let events = SpeechCaptureEvents(
                transcript: { text in Task { @MainActor [weak self] in self?.heard(text, session: session) } },
                level: { value in Task { @MainActor [weak self] in self?.setLevel(Double(value), session: session) } },
                preparing: { on in Task { @MainActor [weak self] in self?.setPreparing(on, session: session) } },
                failed: { error in Task { @MainActor [weak self] in self?.engineFailed(error, session: session) } },
                voice: { Task { @MainActor [weak self] in self?.heardVoice(session: session) } }
            )
            try await choice.engine.start(locale: locale, events: events)
            guard session == self.session else {
                _ = await choice.engine.stop()
                return
            }
            startedAt = Date()
            lastHeardAt = Date()
            phase = .listening
            watch(session: session)
        } catch {
            guard session == self.session else { return }
            fail(error)
        }
    }

    private func heard(_ text: String, session: Int) {
        guard session == self.session, phase == .listening || phase == .preparing, text != transcript else { return }
        transcript = text
        lastHeardAt = Date()
    }

    /// The offline model gives no text until the end; a voice is all there is to go on.
    private func heardVoice(session: Int) {
        guard session == self.session, phase == .listening else { return }
        hasSpoken = true
        lastHeardAt = Date()
    }

    private func setLevel(_ value: Double, session: Int) {
        guard session == self.session, phase == .listening else { return }
        // Fast up, slow down, so the orb doesn't flicker between words.
        level = value > level ? value : level * 0.85 + value * 0.15
    }

    private func setPreparing(_ on: Bool, session: Int) {
        guard session == self.session else { return }
        if on, phase == .starting { phase = .preparing }
    }

    private func engineFailed(_ error: Error, session: Int) {
        guard session == self.session, phase == .listening else { return }
        // Whatever was heard before the error is still worth using.
        if transcript.isEmpty { fail(error) } else { stopListening() }
    }

    /// Ends listening when the person has stopped talking (or never started).
    private func watch(session: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, session == self.session, self.phase == .listening else { return }
                let now = Date()
                let quietFor = now.timeIntervalSince(self.lastHeardAt)
                let spoke = !self.transcript.isEmpty || self.hasSpoken
                if spoke, quietFor > Self.endOfSpeech { self.stopListening(); return }
                if !self.showsLiveText, now.timeIntervalSince(self.startedAt) > Self.longestOfflineListening { self.stopListening(); return }
                if !spoke, now.timeIntervalSince(self.startedAt) > Self.nothingHeard { self.stopListening(); return }
            }
        }
    }

    /// Tapping the orb, or the end of speech.
    func stopListening() {
        guard phase == .listening else { return }
        watchdog?.cancel()
        phase = .thinking
        level = 0
        let session = session
        let engine = engine
        self.engine = nil
        Task {
            let final = await engine?.stop() ?? ""
            guard session == self.session else { return }
            // The final pass can be shorter than what was shown; keep the fuller one.
            let text = final.count >= transcript.count ? final : transcript
            transcript = text
            // Reading the recording failed: say so, instead of "I didn't hear anything".
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let error = engine?.lastError {
                fail(error)
                return
            }
            understand(text)
        }
    }

    // MARK: Understanding

    private func understand(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed("I didn't hear anything. Tap the microphone and try again.")
            return
        }
        var plan = VoiceCommandRunner.plan(for: VoiceRuleBook.parse(trimmed, language: language), language: language)
        // Nothing placed as heard: allow for a misheard word or two before asking a model.
        guessed = false
        if Self.needsHelp(plan) {
            let loose = VoiceCommandRunner.plan(for: VoiceRuleBook.parse(trimmed, language: language, tolerant: true), language: language)
            if Self.isBetter(loose, than: plan) {
                plan = loose
                guessed = true
            }
        }
        // The rules placed it: done, with no model involved.
        guard Self.needsHelp(plan), Self.testPhrase == nil, VoiceInterpreter.isAvailable(for: language) else {
            present(plan)
            return
        }
        phase = .thinking
        let session = session
        Task {
            let result = await VoiceInterpreter.interpret(trimmed, language: language)
            guard session == self.session else { return }
            // The model's foods and products come back with English names.
            if let result {
                let helped = VoiceCommandRunner.plan(for: result.command, language: .english)
                if Self.isBetter(helped, than: plan) {
                    helper = result.source
                    present(helped)
                    return
                }
            }
            present(plan)
        }
    }

    private func present(_ plan: VoicePlan) {
        self.plan = plan
        if plan.needsConfirmation {
            phase = .review
            // A model's reading, or one that allowed for misheard words, is shown for a tap;
            // only the rules' exact readings save by themselves.
            if plan.isComplete, helper == nil, !fromPhoto, !guessed, !plan.isGuessed { startCountdown() }
        } else {
            run(plan)
        }
    }

    // MARK: Photo

    static let nothingInPhoto = "I couldn't make out any food in that photo."

    /// Sends a photo to online AI, which names the foods and guesses their grams.
    /// Nothing is logged here: the foods go to the review card and wait for a tap.
    func readPhoto(_ image: UIImage) {
        guard photoMode else { return }
        cancelTimers()
        session += 1
        let session = session
        plan = nil
        message = ""
        phase = .readingPhoto
        Task {
            let encoded = await Task.detached(priority: .userInitiated) {
                MealPhotoEncoder.base64JPEG(from: image)
            }.value
            guard session == self.session else { return }
            guard let encoded else {
                phase = .failed("That photo couldn't be read. Try another one.")
                return
            }
            do {
                let response = try await APIService.shared.readFoodPhoto(base64: encoded)
                guard session == self.session else { return }
                start(photoFoods: response.phrases)
            } catch {
                guard session == self.session else { return }
                phase = .failed(Self.photoFailure(error))
            }
        }
    }

    /// The foods online AI saw, as name and grams, shown on the review card as a model's
    /// reading: matched to the on-device food data and saved only on a tap.
    func start(photoFoods: [VoiceFoodPhrase]) {
        cancelTimers()
        guessed = false
        helper = nil
        fromPhoto = true
        let plan = VoiceCommandRunner.plan(for: .logFood(items: photoFoods, slot: nil))
        guard !photoFoods.isEmpty, case .food(let matches, _, _) = plan, !matches.isEmpty else {
            self.plan = nil
            phase = .failed(Self.nothingInPhoto)
            return
        }
        present(plan)
    }

    private static func photoFailure(_ error: Error) -> String {
        switch error {
        case let account as AIAccountError:
            return account.errorDescription ?? "Online AI isn't available right now. Please try again later."
        case APIError.aiConsentRequired:
            return "Turn on online AI in Profile to read meal photos."
        case APIError.unverifiedAIResponse:
            return "Online AI isn't available right now. Please try again later."
        default:
            return "Couldn't reach Nourlo. Check your connection and try again."
        }
    }

    /// The rule book left something unplaced: the whole phrase, or some of its foods or products.
    static func needsHelp(_ plan: VoicePlan) -> Bool {
        switch plan {
        case .notUnderstood: return true
        case .food(_, let missing, _), .cart(_, let missing): return !missing.isEmpty
        default: return false
        }
    }

    /// A model's reading replaces the rules' only when it places more of what was said.
    static func isBetter(_ helped: VoicePlan, than plan: VoicePlan) -> Bool {
        func unplaced(_ plan: VoicePlan) -> Int {
            switch plan {
            case .notUnderstood: return .max
            case .food(let matches, let missing, _): return matches.isEmpty ? .max : missing.count
            case .cart(let items, let missing): return items.isEmpty ? .max : missing.count
            default: return 0
            }
        }
        return unplaced(helped) < unplaced(plan)
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = Self.autoConfirmSeconds
        // A UI test confirms by hand, so it never races the timer.
        guard Self.testPhrase == nil else { countdown = nil; return }
        // VoiceOver and Switch Control take longer than the countdown: wait for a tap.
        guard !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { countdown = nil; return }
        let session = session
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, session == self.session, self.phase == .review, let left = self.countdown else { return }
                if left <= 1 { self.confirm(); return }
                self.countdown = left - 1
            }
        }
    }

    /// Any touch on the review card: the person is deciding, so nothing saves by itself.
    func holdCountdown() {
        countdownTask?.cancel()
        countdown = nil
    }

    // MARK: Review edits

    func setSlot(_ slot: MealSlot) {
        guard case .food(let matches, let missing, _) = plan else { return }
        holdCountdown()
        plan = .food(matches: matches, missing: missing, slot: slot)
    }

    func choose(_ food: NutritionFood, for match: VoiceFoodMatch) {
        updateMatch(match) { item in
            item.food = food
            let resolved = VoiceAmounts.amount(for: item.phrase, food: food)
            item.amount = resolved.amount
            item.estimated = resolved.estimated
        }
    }

    /// One step up or down: 10 g (25 g from 100 g), or half a serving.
    func nudge(_ match: VoiceFoodMatch, up: Bool) {
        updateMatch(match) { item in
            let step: Double = item.food.basis == .serving ? 0.5 : (item.amount >= 100 ? 25 : 10)
            let next = item.amount + (up ? step : -step)
            item.amount = min(max(next, item.food.minimumAmount), item.food.maximumAmount)
            item.estimated = false
        }
    }

    func remove(_ match: VoiceFoodMatch) {
        guard case .food(var matches, let missing, let slot) = plan else { return }
        holdCountdown()
        matches.removeAll { $0.id == match.id }
        plan = .food(matches: matches, missing: missing, slot: slot)
    }

    private func updateMatch(_ match: VoiceFoodMatch, _ change: (inout VoiceFoodMatch) -> Void) {
        guard case .food(var matches, let missing, let slot) = plan,
              let index = matches.firstIndex(where: { $0.id == match.id }) else { return }
        holdCountdown()
        change(&matches[index])
        plan = .food(matches: matches, missing: missing, slot: slot)
    }

    /// True when the review card has something that can be saved.
    var canConfirm: Bool {
        switch plan {
        case .food(let matches, _, _): return !matches.isEmpty
        case .cart(let items, _): return !items.isEmpty
        case .checklist(let names): return !names.isEmpty
        default: return false
        }
    }

    // MARK: Doing it

    func confirm() {
        guard phase == .review, let plan, canConfirm else { return }
        holdCountdown()
        run(plan)
    }

    private func run(_ plan: VoicePlan) {
        let outcome = VoiceCommandRunner.perform(plan)
        message = outcome.message
        undo = outcome.undo
        canUndo = outcome.undo != nil
        if case .notUnderstood = plan {
            phase = .failed(outcome.message)
            return
        }
        phase = .done
        if let navigation = outcome.navigation {
            onNavigate(navigation)
            return
        }
        // Answers stay until dismissed; saved changes close by themselves.
        guard canUndo, Self.testPhrase == nil else { return }
        let session = session
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard let self, !Task.isCancelled, session == self.session, self.phase == .done else { return }
            self.onFinished()
        }
    }

    func undoLast() {
        closeTask?.cancel()
        undo?()
        undo = nil
        canUndo = false
        message = "Undone."
    }

    // MARK: Ending

    private func fail(_ error: Error) {
        // The microphone must not stay live behind an error message.
        stopEngine()
        if let capture = error as? SpeechCaptureError, capture == .microphoneDenied || capture == .speechDenied {
            permissionDenied = true
        }
        phase = .failed((error as? LocalizedError)?.errorDescription ?? "Dictation couldn't start. Please try again.")
    }

    private func cancelTimers() {
        watchdog?.cancel()
        countdownTask?.cancel()
        closeTask?.cancel()
        countdown = nil
    }

    /// Lets go of the engine and stops its microphone.
    private func stopEngine() {
        guard let engine else { return }
        self.engine = nil
        Task { _ = await engine.stop() }
    }

    /// The sheet is going away: stop the microphone, keep whatever was saved.
    func cancel() {
        cancelTimers()
        session += 1
        stopEngine()
    }
}

extension SpeechCaptureError: Equatable {
    nonisolated static func == (a: SpeechCaptureError, b: SpeechCaptureError) -> Bool {
        switch (a, b) {
        case (.microphoneDenied, .microphoneDenied), (.speechDenied, .speechDenied),
             (.unsupportedLanguage, .unsupportedLanguage), (.unavailable, .unavailable),
             (.needsOfflineModel, .needsOfflineModel), (.transcriptionFailed, .transcriptionFailed): return true
        case let (.audio(x), .audio(y)): return x == y
        default: return false
        }
    }
}
