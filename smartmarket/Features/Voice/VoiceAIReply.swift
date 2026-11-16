import Foundation

/// What an AI model returns when the rule book couldn't place a phrase.
///
/// The model never acts: it only fills in this form, which becomes the same
/// `VoiceCommand` the rule book produces, so everything after it (matching the
/// food, the review card, undo) is identical. Every field is always present;
/// "none", 0 and "" mean "not said".
struct VoiceAIReply: Codable, Equatable {
    struct Food: Codable, Equatable {
        var name: String
        var quantity: Double
        var unit: String
    }

    var intent: String
    var foods: [Food]
    var meal: String
    var items: [String]
    var workoutKind: String
    var minutes: Int
    var screen: String
    var exercise: String

    enum CodingKeys: String, CodingKey {
        case intent, foods, meal, items, minutes, screen, exercise
        case workoutKind = "workout_kind"
    }

    static let intents = ["log_food", "add_to_cart", "add_to_checklist", "start_workout", "open_screen", "show_exercise", "calories_left", "unknown"]
    static let meals = ["none", "breakfast", "lunch", "dinner", "snack"]
    static let workoutKinds = ["none", "gym", "cardio", "home", "mobility"]
    static let units = ["none"] + VoiceUnit.allCases.map(\.rawValue)
    static let screens = ["none"] + VoiceScreen.allCases.map(\.rawValue)

    /// The task, told the same way to every model.
    static let instructions = """
    You turn one spoken request to a food and fitness app into a filled-in form. You never answer the request yourself.

    Choose `intent`:
    - log_food: the person ate, drank, or wants to log food or drink.
    - add_to_cart: add products to the in-app shopping cart or basket.
    - add_to_checklist: something to buy, a shopping or grocery list, or running out of something.
    - start_workout: build or start a workout or training session.
    - open_screen: go to a part of the app.
    - show_exercise: how to do a named exercise.
    - calories_left: how many calories remain today.
    - unknown: anything else, including questions you would have to answer.

    Fill the fields the intent needs and leave the rest empty ("none", 0, "", []):
    - foods (log_food): one entry per food or drink. `name` is the plain, common English name of the food, translated if it was said in another language, without amounts or cooking instructions ("scrambled eggs", "chicken breast", "greek yogurt"). `quantity` is the number said, or 0 if none. `unit` is the unit said, or "none" for a plain count ("2 eggs") or no amount.
    - meal (log_food): the meal named, or "none".
    - items (add_to_cart, add_to_checklist): product names. For add_to_cart use plain English names; for add_to_checklist keep the person's own words.
    - workout_kind and minutes (start_workout): the kind named ("gym" for weights or strength, "cardio" for running or cycling, "home" for bodyweight or no equipment, "mobility" for stretching or yoga) or "none"; the length in minutes, or 0.
    - screen (open_screen): home, meals (meal plan, recipes), shop (the store), train (workouts), cart, checklist (grocery list), profile (settings, account), logFood (the food logger), chat (the assistant), scan (barcode scanner).
    - exercise (show_exercise): the exercise's common English name.

    Never invent a food, amount or product that was not said.
    """

    /// JSON Schema for models that take one (every object closed, every field required).
    static var schema: [String: Any] {
        func string(_ values: [String]? = nil) -> [String: Any] {
            values.map { ["type": "string", "enum": $0] } ?? ["type": "string"]
        }
        let food: [String: Any] = [
            "type": "object",
            "properties": ["name": string(), "quantity": ["type": "number"], "unit": string(units)],
            "required": ["name", "quantity", "unit"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "intent": string(intents),
                "foods": ["type": "array", "items": food],
                "meal": string(meals),
                "items": ["type": "array", "items": string()],
                "workout_kind": string(workoutKinds),
                "minutes": ["type": "integer"],
                "screen": string(screens),
                "exercise": string(),
            ],
            "required": ["intent", "foods", "meal", "items", "workout_kind", "minutes", "screen", "exercise"],
            "additionalProperties": false,
        ]
    }

    /// Reads a reply from model text, tolerating a code fence or words around the JSON.
    static func parse(_ text: String) -> VoiceAIReply? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VoiceAIReply.self, from: data)
    }

    /// The command this form describes, or nil when it describes nothing usable
    /// (so a model's "unknown", or a form with its key field empty, changes nothing).
    var command: VoiceCommand? {
        func clean(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        switch intent {
        case "log_food":
            let phrases: [VoiceFoodPhrase] = foods.compactMap { food in
                let name = clean(food.name)
                guard !name.isEmpty, name.count <= 80, food.quantity.isFinite, food.quantity >= 0, food.quantity <= 10_000 else { return nil }
                let unit = VoiceUnit(rawValue: food.unit)
                // A unit with no number means one of it ("a cup of rice").
                let quantity: Double? = food.quantity > 0 ? food.quantity : (unit == nil ? nil : 1)
                return VoiceFoodPhrase(name: name, quantity: quantity, unit: unit)
            }
            guard !phrases.isEmpty else { return nil }
            return .logFood(items: Array(phrases.prefix(12)), slot: MealSlot(rawValue: meal))
        case "add_to_cart":
            let names = items.map(clean).filter { !$0.isEmpty && $0.count <= 80 }
            return names.isEmpty ? nil : .addToCart(Array(names.prefix(20)))
        case "add_to_checklist":
            let names = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.count <= 80 }
            return names.isEmpty ? nil : .addToChecklist(Array(names.prefix(20)))
        case "start_workout":
            return .startWorkout(kind: ExerciseKind(rawValue: workoutKind), minutes: minutes > 0 ? minutes : nil)
        case "open_screen":
            return VoiceScreen(rawValue: screen).map(VoiceCommand.open)
        case "show_exercise":
            let name = clean(exercise)
            return name.isEmpty ? nil : .showExercise(name)
        case "calories_left":
            return .caloriesLeft
        default:
            return nil
        }
    }
}
