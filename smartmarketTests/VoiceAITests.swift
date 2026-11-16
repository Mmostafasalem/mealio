import XCTest
@testable import smartmarket

/// The AI fallback: a model fills in a form, and only a sound form becomes a command.
@MainActor
final class VoiceAITests: XCTestCase {

    private func reply(_ json: String) -> VoiceAIReply? { VoiceAIReply.parse(json) }

    private let empty = #""foods":[],"meal":"none","items":[],"workout_kind":"none","minutes":0,"screen":"none","exercise":"""#

    func testAFoodFormBecomesAFoodCommand() {
        let json = #"{"intent":"log_food","foods":[{"name":"Scrambled Eggs","quantity":2,"unit":"none"},{"name":"rice","quantity":0,"unit":"cup"},{"name":"toast","quantity":0,"unit":"none"}],"meal":"breakfast","items":[],"workout_kind":"none","minutes":0,"screen":"none","exercise":""}"#
        XCTAssertEqual(reply(json)?.command,
                       .logFood(items: [VoiceFoodPhrase(name: "scrambled eggs", quantity: 2, unit: nil),
                                        VoiceFoodPhrase(name: "rice", quantity: 1, unit: .cup),
                                        VoiceFoodPhrase(name: "toast", quantity: nil, unit: nil)], slot: .breakfast))
    }

    func testOtherIntents() {
        XCTAssertEqual(reply(#"{"intent":"add_to_cart","foods":[],"meal":"none","items":["Milk","eggs"],"workout_kind":"none","minutes":0,"screen":"none","exercise":""}"#)?.command,
                       .addToCart(["milk", "eggs"]))
        XCTAssertEqual(reply(#"{"intent":"add_to_checklist","foods":[],"meal":"none","items":["Duona"],"workout_kind":"none","minutes":0,"screen":"none","exercise":""}"#)?.command,
                       .addToChecklist(["Duona"]))
        XCTAssertEqual(reply(#"{"intent":"start_workout","foods":[],"meal":"none","items":[],"workout_kind":"cardio","minutes":25,"screen":"none","exercise":""}"#)?.command,
                       .startWorkout(kind: .cardio, minutes: 25))
        XCTAssertEqual(reply(#"{"intent":"open_screen","foods":[],"meal":"none","items":[],"workout_kind":"none","minutes":0,"screen":"cart","exercise":""}"#)?.command,
                       .open(.cart))
        XCTAssertEqual(reply(#"{"intent":"show_exercise","foods":[],"meal":"none","items":[],"workout_kind":"none","minutes":0,"screen":"none","exercise":"Push Up"}"#)?.command,
                       .showExercise("push up"))
        XCTAssertEqual(reply("{\"intent\":\"calories_left\",\(empty)}")?.command, .caloriesLeft)
    }

    func testUnusableFormsChangeNothing() {
        XCTAssertNil(reply("{\"intent\":\"unknown\",\(empty)}")?.command)
        // The key field is empty or out of range.
        XCTAssertNil(reply("{\"intent\":\"log_food\",\(empty)}")?.command)
        XCTAssertNil(reply("{\"intent\":\"open_screen\",\(empty)}")?.command)
        XCTAssertNil(reply("{\"intent\":\"delete_everything\",\(empty)}")?.command)
        XCTAssertNil(reply(#"{"intent":"log_food","foods":[{"name":"rice","quantity":-5,"unit":"gram"}],"meal":"none","items":[],"workout_kind":"none","minutes":0,"screen":"none","exercise":""}"#)?.command)
        // Not a form at all.
        XCTAssertNil(reply("I can't help with that."))
        XCTAssertNil(reply(#"{"intent":"log_food"}"#))
    }

    func testAReplyWrappedInWordsOrAFenceIsStillRead() {
        let json = "Here you go:\n```json\n{\"intent\":\"calories_left\",\(empty)}\n```"
        XCTAssertEqual(reply(json)?.command, .caloriesLeft)
    }

    func testTheSchemaClosesEveryObjectAndRequiresEveryField() throws {
        let schema = VoiceAIReply.schema
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(schema["required"] as? [String])), Set(properties.keys))
        let foods = try XCTUnwrap(properties["foods"] as? [String: Any])
        let food = try XCTUnwrap(foods["items"] as? [String: Any])
        XCTAssertEqual(food["additionalProperties"] as? Bool, false)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: schema))
    }

    // MARK: A model's reading against the rules'

    func testAModelsReadingReplacesTheRulesOnlyWhenItPlacesMore() {
        let food = NutritionFood(id: "usda:1", name: "Egg", brand: nil, basis: .grams, kcal: 140, protein: 12, carbs: 1, fat: 10,
                                 source: .usda, sourceID: "1", sourceDate: nil)
        let match = VoiceFoodMatch(phrase: VoiceFoodPhrase(name: "egg", quantity: 1, unit: nil), food: food, amount: 50, alternatives: [food], estimated: true)
        let partial = VoicePlan.food(matches: [match], missing: ["shakshuka"], slot: .breakfast)
        let full = VoicePlan.food(matches: [match, match], missing: [], slot: .breakfast)
        XCTAssertTrue(VoiceCommandModel.needsHelp(.notUnderstood("?")))
        XCTAssertTrue(VoiceCommandModel.needsHelp(partial))
        XCTAssertFalse(VoiceCommandModel.needsHelp(full))
        XCTAssertFalse(VoiceCommandModel.needsHelp(.open(.cart)))
        XCTAssertTrue(VoiceCommandModel.isBetter(full, than: partial))
        XCTAssertTrue(VoiceCommandModel.isBetter(.open(.cart), than: .notUnderstood("?")))
        XCTAssertFalse(VoiceCommandModel.isBetter(partial, than: full))
        XCTAssertFalse(VoiceCommandModel.isBetter(.notUnderstood("?"), than: partial))
        XCTAssertFalse(VoiceCommandModel.isBetter(.food(matches: [], missing: ["x"], slot: .lunch), than: partial))
    }

    // MARK: The person's own key

    func testRequestsCarryTheKeyOnlyInTheProvidersHeader() throws {
        let base = try XCTUnwrap(URL(string: "https://api.anthropic.com"))
        let claude = try VoiceAIKeyStore.request(provider: .anthropic, base: base, model: "claude-opus-5-5", key: "sk-test", text: "two eggs")
        XCTAssertEqual(claude.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(claude.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(claude.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertNil(claude.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(claude.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual(claude.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual((output["format"] as? [String: Any])?["type"] as? String, "json_schema")
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["temperature"])
        XCTAssertFalse(String(data: try XCTUnwrap(claude.httpBody), encoding: .utf8)?.contains("sk-test") ?? true)

        // A model without server-side fallback is sent without the parameter.
        let small = try VoiceAIKeyStore.request(provider: .anthropic, base: base, model: "claude-haiku-5-5", key: "k", text: "x")
        XCTAssertNil(small.value(forHTTPHeaderField: "anthropic-beta"))

        let other = try VoiceAIKeyStore.request(provider: .openAI, base: try XCTUnwrap(URL(string: "https://api.openai.com/v1")),
                                                model: "some-model", key: "sk-other", text: "two eggs")
        XCTAssertEqual(other.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(other.value(forHTTPHeaderField: "Authorization"), "Bearer sk-other")
        XCTAssertNil(other.value(forHTTPHeaderField: "x-api-key"))
    }

    func testRepliesAreReadPerProviderAndRefusalsAreNotCommands() throws {
        let form = "{\\\"intent\\\":\\\"calories_left\\\",\\\"foods\\\":[],\\\"meal\\\":\\\"none\\\",\\\"items\\\":[],\\\"workout_kind\\\":\\\"none\\\",\\\"minutes\\\":0,\\\"screen\\\":\\\"none\\\",\\\"exercise\\\":\\\"\\\"}"
        let claude = Data("{\"stop_reason\":\"end_turn\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"\"},{\"type\":\"text\",\"text\":\"\(form)\"}]}".utf8)
        XCTAssertEqual(try VoiceAIKeyStore.reply(from: claude, provider: .anthropic).command, .caloriesLeft)
        let refused = Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)
        XCTAssertThrowsError(try VoiceAIKeyStore.reply(from: refused, provider: .anthropic)) { XCTAssertEqual($0 as? VoiceAIKeyStore.KeyError, .declined) }
        let cut = Data(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"{"}]}"#.utf8)
        XCTAssertThrowsError(try VoiceAIKeyStore.reply(from: cut, provider: .anthropic)) { XCTAssertEqual($0 as? VoiceAIKeyStore.KeyError, .unreadable) }
        let other = Data("{\"choices\":[{\"message\":{\"content\":\"\(form)\"}}]}".utf8)
        XCTAssertEqual(try VoiceAIKeyStore.reply(from: other, provider: .openAI).command, .caloriesLeft)
    }

    func testAKeyNeedsSignInAndAnHTTPSAddress() throws {
        let suite = "VoiceAITests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var signedIn = false
        let store = VoiceAIKeyStore(defaults: defaults, isSignedIn: { signedIn })
        store.remove()
        defer { store.remove() }
        XCTAssertThrowsError(try store.save(provider: .anthropic, model: "claude-opus-5-5", baseURL: "https://api.anthropic.com", key: "k")) {
            XCTAssertEqual($0 as? VoiceAIKeyStore.KeyError, .notSignedIn)
        }
        signedIn = true
        XCTAssertThrowsError(try store.save(provider: .custom, model: "m", baseURL: "http://example.com", key: "k")) {
            XCTAssertEqual($0 as? VoiceAIKeyStore.KeyError, .badAddress)
        }
        XCTAssertThrowsError(try store.save(provider: .anthropic, model: "", baseURL: "https://api.anthropic.com", key: "k")) {
            XCTAssertEqual($0 as? VoiceAIKeyStore.KeyError, .notConfigured)
        }
        XCTAssertFalse(store.isUsable)
        XCTAssertNil(VoiceAIKeyStore.endpointBase("ftp://example.com"))
        XCTAssertNotNil(VoiceAIKeyStore.endpointBase("https://example.com/v1"))
    }
}
