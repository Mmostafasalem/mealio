import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - When the rule book isn't enough
//
// The rule book handles the phrases it knows, instantly and offline. A phrase
// it can't place goes, in this order, to:
//
//  1. Apple Intelligence, on the phone (iOS 26, a supported iPhone, the
//     feature turned on, and a language the model speaks). Nothing leaves the
//     device.
//  2. The person's own AI key, if they are signed in and have added one in
//     Profile. Only the text of the phrase is sent, to the provider they chose.
//
// Either one only fills in a `VoiceAIReply`; the app decides what to do with it.

@MainActor
enum VoiceInterpreter {

    enum Source: String { case appleIntelligence, ownKey }

    struct Result {
        let command: VoiceCommand
        let source: Source
    }

    /// True when some model could be asked right now.
    static func isAvailable(for language: VoiceLanguage) -> Bool {
        AppleIntelligence.status(for: language) == .available || VoiceAIKeyStore.shared.isUsable
    }

    static func interpret(_ text: String, language: VoiceLanguage) async -> Result? {
        let phrase = String(text.prefix(400))
        if AppleIntelligence.status(for: language) == .available,
           let command = await AppleIntelligence.interpret(phrase)?.command {
            return Result(command: command, source: .appleIntelligence)
        }
        if VoiceAIKeyStore.shared.isUsable,
           let command = try? await VoiceAIKeyStore.shared.interpret(phrase).command {
            return Result(command: command, source: .ownKey)
        }
        return nil
    }
}

// MARK: - Apple Intelligence

@MainActor
enum AppleIntelligence {

    enum Status: Equatable {
        case available
        /// This iPhone or iOS version can't run it.
        case unsupportedDevice
        /// The iPhone can, but Apple Intelligence is off in Settings.
        case turnedOff
        /// It is on; the model is still downloading.
        case notReady
        /// It is on, but doesn't know this language.
        case unsupportedLanguage

        var explanation: String {
            switch self {
            case .available: return "On. Phrases the rules don't know are understood on this iPhone."
            case .unsupportedDevice: return "Not available on this iPhone or iOS version."
            case .turnedOff: return "Turn on Apple Intelligence in Settings to use it here."
            case .notReady: return "Apple Intelligence is still getting ready. Try again later."
            case .unsupportedLanguage: return "Apple Intelligence doesn't support this language yet."
            }
        }
    }

    static func status(for language: VoiceLanguage) -> Status {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .unsupportedDevice }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(language.locale) ? .available : .unsupportedLanguage
        case .unavailable(.deviceNotEligible): return .unsupportedDevice
        case .unavailable(.appleIntelligenceNotEnabled): return .turnedOff
        case .unavailable(.modelNotReady): return .notReady
        case .unavailable: return .unsupportedDevice
        }
        #else
        return .unsupportedDevice
        #endif
    }

    static func interpret(_ text: String) async -> VoiceAIReply? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        do {
            // A fresh session each time: one phrase, no memory of the last.
            let session = LanguageModelSession(instructions: VoiceAIReply.instructions)
            let response = try await session.respond(to: "The spoken request:\n\(text)", generating: AppleVoiceForm.self,
                                                     options: GenerationOptions(sampling: .greedy))
            return response.content.reply
        } catch {
            appLog("[Voice] Apple Intelligence couldn't interpret:", error)
            return nil
        }
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
/// `VoiceAIReply` as Apple's model fills it in (guided generation keeps every field to its allowed values).
@available(iOS 26.0, *)
@Generable
struct AppleVoiceForm {
    @Guide(description: "What the person wants", .anyOf(["log_food", "add_to_cart", "add_to_checklist", "start_workout", "open_screen", "show_exercise", "calories_left", "unknown"]))
    var intent: String
    @Guide(description: "For log_food: one entry per food or drink that was said. Otherwise empty.", .maximumCount(12))
    var foods: [AppleVoiceFood]
    @Guide(description: "For log_food: the meal that was named", .anyOf(["none", "breakfast", "lunch", "dinner", "snack"]))
    var meal: String
    @Guide(description: "For add_to_cart or add_to_checklist: the product names. Otherwise empty.", .maximumCount(20))
    var items: [String]
    @Guide(description: "For start_workout: the kind that was named", .anyOf(["none", "gym", "cardio", "home", "mobility"]))
    var workoutKind: String
    @Guide(description: "For start_workout: the length in minutes, or 0 if none was said", .range(0...300))
    var minutes: Int
    @Guide(description: "For open_screen: the part of the app", .anyOf(["none", "home", "meals", "shop", "train", "cart", "checklist", "profile", "logFood", "chat", "scan"]))
    var screen: String
    @Guide(description: "For show_exercise: the exercise's common English name. Otherwise empty.")
    var exercise: String

    var reply: VoiceAIReply {
        VoiceAIReply(intent: intent,
                     foods: foods.map { VoiceAIReply.Food(name: $0.name, quantity: $0.quantity, unit: $0.unit) },
                     meal: meal, items: items, workoutKind: workoutKind, minutes: minutes, screen: screen, exercise: exercise)
    }
}

@available(iOS 26.0, *)
@Generable
struct AppleVoiceFood {
    @Guide(description: "The plain, common English name of the food, with no amount")
    var name: String
    @Guide(description: "The number that was said, or 0 if none", .range(0...10000))
    var quantity: Double
    @Guide(description: "The unit that was said, or none", .anyOf(["none", "gram", "kilogram", "ounce", "pound", "millilitre", "litre", "cup", "tablespoon", "teaspoon", "glass", "bowl", "can", "bottle", "slice", "piece", "handful", "serving"]))
    var unit: String
}
#endif
