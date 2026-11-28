import XCTest
@testable import smartmarket

/// The rule book in every language: Lithuanian's case endings, and the five
/// languages added for testers (Spanish, French, Russian, Chinese, Japanese).
@MainActor
final class VoiceLanguagesTests: XCTestCase {

    private func food(_ name: String, _ quantity: Double? = nil, _ unit: VoiceUnit? = nil) -> VoiceFoodPhrase {
        VoiceFoodPhrase(name: name, quantity: quantity, unit: unit)
    }

    // MARK: Lithuanian (TestFlight report)

    /// "Pridėk sausus pusryčius su pienu prie pusryčių": the review card showed
    /// "Couldn't find: pride sausus su pienu prie pusryciu". It is cereal and milk, for breakfast.
    func testLithuanianCerealWithMilkForBreakfast() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .lithuanian) }
        let cerealAndMilk = VoiceCommand.logFood(items: [food("cereal ready-to-eat"), food("milk")], slot: .breakfast)
        XCTAssertEqual(parse("Pridėk sausus pusryčius su pienu prie pusryčių"), cerealAndMilk)
        // Without accents, as some speech models write it.
        XCTAssertEqual(parse("Pridek sausus pusrycius su pienu prie pusryciu"), cerealAndMilk)
        // Misheard verb: allowed for in the tolerant reading.
        XCTAssertEqual(VoiceRuleBook.parse("Pridė sausus pusryčius su pienu prie pusryčių", language: .lithuanian, tolerant: true), cerealAndMilk)
        // "pusryčius" after "sausus" is the food, not the meal.
        XCTAssertEqual(parse("Įdėk sausus pusryčius su pienu"),
                       .logFood(items: [food("cereal ready-to-eat"), food("milk")], slot: nil))
        XCTAssertEqual(parse("Pridėk avižinę košę su pienu prie pusryčių"),
                       .logFood(items: [food("oatmeal"), food("milk")], slot: .breakfast))
        XCTAssertEqual(parse("Suvalgiau du kiaušinius ir bananą pusryčiams"),
                       .logFood(items: [food("egg", 2), food("banana")], slot: .breakfast))
    }

    func testLithuanianCaseEndingsVerbsAndWith() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .lithuanian) }
        XCTAssertEqual(parse("Užrašyk grikius su vištiena pietums"),
                       .logFood(items: [food("buckwheat groats cooked"), food("chicken breast")], slot: .lunch))
        XCTAssertEqual(parse("Įdėk varškę su medumi į užkandį"),
                       .logFood(items: [food("cottage cheese"), food("honey")], slot: .snack))
        XCTAssertEqual(parse("Gėriau kefyrą su duona užkandžiui"),
                       .logFood(items: [food("kefir"), food("bread")], slot: .snack))
        XCTAssertEqual(parse("Išgėriau kavos su pienu"), .logFood(items: [food("coffee"), food("milk")], slot: nil))
        XCTAssertEqual(parse("Valgiau jogurtą su sūriu vakarienei"),
                       .logFood(items: [food("yogurt"), food("cheese")], slot: .dinner))
        XCTAssertEqual(parse("Pridėkite ryžius ir makaronus prie vakarienės"),
                       .logFood(items: [food("rice"), food("pasta")], slot: .dinner))
        XCTAssertEqual(parse("Užregistruok obuolį užkandžio"), .logFood(items: [food("apple")], slot: .snack))
        XCTAssertEqual(parse("Suvalgiau kiaušinį su sviestu ir arbatą pietų"),
                       .logFood(items: [food("egg"), food("butter"), food("tea hot leaf black")], slot: .lunch))
        // A dish named with "su" stays whole; "du su puse" is two and a half.
        XCTAssertEqual(parse("Suvalgiau cepelinus su varške vakarienei"),
                       .logFood(items: [food("cepelinai su varske")], slot: .dinner))
        XCTAssertEqual(parse("Valgiau du su puse kiaušinio"), .logFood(items: [food("egg", 2.5)], slot: nil))
        // A known food heard exactly is never taken for a misheard meal.
        XCTAssertEqual(VoiceRuleBook.parse("Išgėriau kavos su pienu", language: .lithuanian, tolerant: true),
                       .logFood(items: [food("coffee"), food("milk")], slot: nil))
    }

    /// The tester's phrase finds real foods, so the card no longer says "Couldn't find".
    func testLithuanianPhraseFindsFoodsInTheCatalogue() {
        let plan = VoiceCommandRunner.plan(for: VoiceRuleBook.parse("Pridėk sausus pusryčius su pienu prie pusryčių", language: .lithuanian),
                                           language: .lithuanian)
        guard case .food(let matches, let missing, let slot) = plan else { return XCTFail("expected a food plan, got \(plan)") }
        XCTAssertEqual(missing, [])
        XCTAssertEqual(slot, .breakfast)
        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(matches[0].food.name.lowercased().contains("cereal"), matches[0].food.name)
        XCTAssertTrue(matches[1].food.name.lowercased().hasPrefix("milk"), matches[1].food.name)
    }

    // MARK: New languages

    func testSpanish() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .spanish) }
        XCTAssertEqual(parse("Añade dos huevos al desayuno"), .logFood(items: [food("egg", 2)], slot: .breakfast))
        XCTAssertEqual(parse("Me comí un plátano"), .logFood(items: [food("banana")], slot: nil))
        XCTAssertEqual(parse("Añade leche al carrito"), .addToCart(["milk"]))
        XCTAssertEqual(parse("Registra 30 minutos de correr"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("Comí 200 gramos de pollo con arroz para la cena"),
                       .logFood(items: [food("chicken breast", 200, .gram), food("rice")], slot: .dinner))
        XCTAssertEqual(parse("Bebí un vaso de leche"), .logFood(items: [food("milk", 1, .glass)], slot: nil))
        XCTAssertEqual(parse("Empieza un entrenamiento de cardio de treinta y cinco minutos"), .startWorkout(kind: .cardio, minutes: 35))
        XCTAssertEqual(parse("Tengo que comprar pan y queso"), .addToChecklist(["pan", "queso"]))
        XCTAssertEqual(parse("Abre el carrito"), .open(.cart))
        XCTAssertEqual(parse("¿Cuántas calorías me quedan?"), .caloriesLeft)
        XCTAssertEqual(parse("Cómo se hacen las sentadillas"), .showExercise("squat"))
    }

    func testFrench() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .french) }
        XCTAssertEqual(parse("Ajoute deux œufs au petit déjeuner"), .logFood(items: [food("egg", 2)], slot: .breakfast))
        XCTAssertEqual(parse("J'ai mangé une banane"), .logFood(items: [food("banana")], slot: nil))
        XCTAssertEqual(parse("Ajoute du lait au panier"), .addToCart(["milk"]))
        XCTAssertEqual(parse("Note 30 minutes de course"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("J'ai bu un verre d'eau"), .logFood(items: [food("water", 1, .glass)], slot: nil))
        XCTAssertEqual(parse("J'ai mangé vingt-cinq grammes d'amandes au goûter"),
                       .logFood(items: [food("almonds", 25, .gram)], slot: .snack))
        XCTAssertEqual(parse("Il me reste combien de calories ?"), .caloriesLeft)
        XCTAssertEqual(parse("Comment faire des pompes"), .showExercise("push up"))
        XCTAssertEqual(parse("Ouvre les réglages"), .open(.profile))
    }

    func testRussian() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .russian) }
        XCTAssertEqual(parse("Добавь два яйца на завтрак"), .logFood(items: [food("egg", 2)], slot: .breakfast))
        XCTAssertEqual(parse("Я съел банан"), .logFood(items: [food("banana")], slot: nil))
        XCTAssertEqual(parse("Добавь молоко в корзину"), .addToCart(["milk"]))
        XCTAssertEqual(parse("Запиши 30 минут бега"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("Я выпила стакан молока"), .logFood(items: [food("milk", 1, .glass)], slot: nil))
        XCTAssertEqual(parse("Съел 200 грамм курицы с рисом на обед"),
                       .logFood(items: [food("chicken breast", 200, .gram), food("rice")], slot: .lunch))
        XCTAssertEqual(parse("Сколько калорий у меня осталось?"), .caloriesLeft)
        XCTAssertEqual(parse("Как делать отжимания"), .showExercise("push up"))
        XCTAssertEqual(parse("Открой настройки"), .open(.profile))
        XCTAssertEqual(parse("Начни тренировку на полчаса"), .startWorkout(kind: nil, minutes: 30))
    }

    func testChinese() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .chinese) }
        XCTAssertEqual(parse("早餐加两个鸡蛋"), .logFood(items: [food("egg", 2)], slot: .breakfast))
        XCTAssertEqual(parse("把两个鸡蛋加到早餐里"), .logFood(items: [food("egg", 2)], slot: .breakfast))
        XCTAssertEqual(parse("我吃了一个香蕉"), .logFood(items: [food("banana", 1)], slot: nil))
        XCTAssertEqual(parse("把牛奶加到购物车"), .addToCart(["milk"]))
        XCTAssertEqual(parse("记录跑步30分钟"), .startWorkout(kind: .cardio, minutes: 30))
        // 杯 and 碗 are units; 个 after a number is only a counter.
        XCTAssertEqual(parse("我喝了一杯牛奶"), .logFood(items: [food("milk", 1, .glass)], slot: nil))
        XCTAssertEqual(parse("加一碗米饭到午餐"), .logFood(items: [food("rice", 1, .bowl)], slot: .lunch))
        XCTAssertEqual(parse("午饭吃了200克鸡胸肉和米饭"),
                       .logFood(items: [food("chicken breast", 200, .gram), food("rice")], slot: .lunch))
        XCTAssertEqual(parse("吃了半个苹果"), .logFood(items: [food("apple", 0.5)], slot: nil))
        // Words that hold a numeral stay whole: 三文鱼 (salmon), 三明治 (sandwich).
        XCTAssertEqual(parse("我吃了三文鱼和三明治"), .logFood(items: [food("salmon"), food("sandwich")], slot: nil))
        XCTAssertEqual(parse("开始三十分钟的有氧训练"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("我需要买面包和鸡蛋"), .addToChecklist(["面包", "鸡蛋"]))
        XCTAssertEqual(parse("我还剩多少卡路里"), .caloriesLeft)
        XCTAssertEqual(parse("怎么做俯卧撑"), .showExercise("push up"))
        XCTAssertEqual(parse("打开购物车"), .open(.cart))
    }

    func testJapanese() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .japanese) }
        XCTAssertEqual(parse("朝食に卵を2個追加して"), .logFood(items: [food("egg", 2)], slot: .breakfast))
        XCTAssertEqual(parse("朝ごはんに卵を二つ追加して"), .logFood(items: [food("egg", 2)], slot: .breakfast))
        XCTAssertEqual(parse("バナナを食べた"), .logFood(items: [food("banana")], slot: nil))
        XCTAssertEqual(parse("バナナを1本食べました"), .logFood(items: [food("banana", 1)], slot: nil))
        XCTAssertEqual(parse("牛乳をカートに追加して"), .addToCart(["milk"]))
        XCTAssertEqual(parse("ランニングを30分記録して"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("コーヒーを1杯飲んだ"), .logFood(items: [food("coffee", 1, .glass)], slot: nil))
        XCTAssertEqual(parse("鶏むね肉を２００グラム夕食に追加して"), .logFood(items: [food("chicken breast", 200, .gram)], slot: .dinner))
        XCTAssertEqual(parse("昼ごはんにご飯と味噌汁を食べた"), .logFood(items: [food("rice"), food("soup miso")], slot: .lunch))
        XCTAssertEqual(parse("りんご半分を食べた"), .logFood(items: [food("apple", 0.5)], slot: nil))
        XCTAssertEqual(parse("30分の有酸素トレーニングを始めて"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("牛乳を買わなきゃ"), .addToChecklist(["牛乳"]))
        XCTAssertEqual(parse("あと何カロリー食べられる？"), .caloriesLeft)
        XCTAssertEqual(parse("腕立て伏せのやり方を教えて"), .showExercise("push up"))
        XCTAssertEqual(parse("設定を開いて"), .open(.profile))
    }

    /// The common phrases from the brief, in every language: two eggs for breakfast,
    /// a banana, milk to the cart, 30 minutes of running.
    func testTheSamePhrasesInEveryLanguage() {
        let phrases: [VoiceLanguage: [String]] = [
            .english: ["add two eggs to breakfast", "I ate a banana", "add milk to the cart", "log 30 minutes of running"],
            .german: ["Füge zwei Eier zum Frühstück hinzu", "Ich habe eine Banane gegessen", "Leg Milch in den Warenkorb", "Trage 30 Minuten Laufen ein"],
            .spanish: ["Añade dos huevos al desayuno", "Me comí un plátano", "Añade leche al carrito", "Registra 30 minutos de correr"],
            .french: ["Ajoute deux œufs au petit déjeuner", "J'ai mangé une banane", "Ajoute du lait au panier", "Note 30 minutes de course"],
            .russian: ["Добавь два яйца на завтрак", "Я съел банан", "Добавь молоко в корзину", "Запиши 30 минут бега"],
            .lithuanian: ["Pridėk du kiaušinius prie pusryčių", "Suvalgiau bananą", "Įdėk pieną į krepšelį", "Užrašyk 30 minučių bėgimo"],
            .chinese: ["早餐加两个鸡蛋", "我吃了香蕉", "把牛奶加到购物车", "记录跑步30分钟"],
            .japanese: ["朝食に卵を2個追加して", "バナナを食べた", "牛乳をカートに追加して", "ランニングを30分記録して"],
        ]
        for (language, list) in phrases {
            let eggs = VoiceRuleBook.parse(list[0], language: language)
            guard case .logFood(let items, let slot) = eggs else { XCTFail("\(language): \(eggs)"); continue }
            XCTAssertEqual(slot, .breakfast, "\(language)")
            XCTAssertEqual(items.first?.quantity, 2, "\(language)")
            XCTAssertTrue(items.first?.name.hasPrefix("egg") == true, "\(language): \(items)")
            XCTAssertEqual(VoiceRuleBook.parse(list[1], language: language), .logFood(items: [food("banana")], slot: nil), "\(language)")
            XCTAssertEqual(VoiceRuleBook.parse(list[2], language: language), .addToCart(["milk"]), "\(language)")
            XCTAssertEqual(VoiceRuleBook.parse(list[3], language: language), .startWorkout(kind: .cardio, minutes: 30), "\(language)")
        }
    }

    // MARK: Lexicons

    /// Every English name a lexicon translates to is found in Nourlo's food list.
    func testEveryTranslatedFoodIsInTheCatalogue() {
        var missing: [String] = []
        var checked = Set<String>()
        for language in VoiceLanguage.allCases {
            for line in language.lexicon.foods where checked.insert(line.english).inserted {
                if VoiceFoodRanker.foods(for: line.english, limit: 1, recentIDs: []).isEmpty { missing.append(line.english) }
            }
        }
        XCTAssertEqual(missing, [], "not found: \(missing)")
    }

    func testLexiconsCoverTheCommonFoodsAndNumbers() {
        for language in VoiceLanguage.allCases where language != .english {
            let lexicon = language.lexicon
            let names = Set(lexicon.foods.map(\.english))
            if [.spanish, .french, .russian, .chinese, .japanese].contains(language) {
                XCTAssertGreaterThanOrEqual(lexicon.foods.flatMap(\.forms).count, 120, "\(language)")
            }
            for common in ["egg", "milk", "bread", "banana", "apple", "rice", "chicken breast", "coffee", "water", "cheese"] {
                XCTAssertTrue(names.contains(common), "\(language) has no word for \(common)")
            }
            XCTAssertFalse(lexicon.exercises.isEmpty, "\(language)")
        }
        // Words for one to ten, as the rule book reads them.
        let ten: [VoiceLanguage: String] = [
            .spanish: "uno dos tres cuatro cinco seis siete ocho nueve diez", .french: "un deux trois quatre cinq six sept huit neuf dix",
            .russian: "один два три четыре пять шесть семь восемь девять десять",
        ]
        for (language, words) in ten {
            let digits = VoiceRuleBook.numberWordsToDigits(VoiceRuleBook.normalize(words, language.lexicon), language.lexicon)
            if language == .french {
                XCTAssertEqual(digits, "un 2 3 4 5 6 7 8 9 10", "\(language)") // "un" is the article, as "a" is in English
            } else {
                XCTAssertEqual(digits, "1 2 3 4 5 6 7 8 9 10", "\(language)")
            }
        }
        XCTAssertEqual(VoiceRuleBook.normalize("十", VoiceLexicon.chinese), "10")
        XCTAssertEqual(VoiceRuleBook.normalize("三十五", VoiceLexicon.chinese), "35")
        XCTAssertEqual(VoiceRuleBook.normalize("两个", VoiceLexicon.chinese), "2")
        XCTAssertEqual(VoiceRuleBook.normalize("ふたつ", VoiceLexicon.japanese), "ふたつ")
        XCTAssertEqual(VoiceRuleBook.numberWordsToDigits("ふたつ", VoiceLexicon.japanese), "2")
    }

    // MARK: Cutting Chinese and Japanese into words

    func testSegmenterCutsTextWithoutSpaces() {
        XCTAssertEqual(VoiceRuleBook.normalize("我吃了两个鸡蛋和一杯牛奶", VoiceLexicon.chinese), "我吃了 2 鸡蛋 和 1 杯 牛奶")
        XCTAssertEqual(VoiceRuleBook.normalize("卵を2個と牛乳を1杯", VoiceLexicon.japanese), "卵 2 と 牛乳 1 杯")
        XCTAssertEqual(VoiceRuleBook.normalize("鸡蛋、牛奶", VoiceLexicon.chinese), "鸡蛋 , 牛奶")
        // Unknown characters stay together as one word, and are written together again.
        XCTAssertEqual(VoiceRuleBook.parse("我吃了螺蛳粉", language: .chinese), .logFood(items: [food("螺蛳粉")], slot: nil))
        XCTAssertEqual(VoiceSegmenter.rejoin("全麦 面包 and bread"), "全麦面包 and bread")
        XCTAssertEqual(VoiceSegmenter.plainDigits("２００グラム"), "200グラム")
    }

    // MARK: The picker

    func testLanguagesAreNamedInTheirOwnLanguage() {
        XCTAssertEqual(VoiceLanguage.allCases.count, 9)
        XCTAssertEqual(VoiceLanguage.allCases.map(\.name),
                       ["English", "Deutsch", "Español", "Français", "Русский", "Lietuvių", "العربية", "中文", "日本語"])
        XCTAssertEqual(VoiceLanguage.chinese.locale.identifier, "zh-CN")
        XCTAssertEqual(VoiceLanguage.japanese.locale.identifier, "ja-JP")
        XCTAssertEqual(VoiceLanguage(rawValue: "zh"), .chinese)
        // The offline model covers the European ones only.
        XCTAssertTrue(OfflineSpeechModel.languages.isSuperset(of: [.spanish, .french, .russian, .lithuanian]))
        XCTAssertFalse(OfflineSpeechModel.languages.contains(.chinese))
        XCTAssertFalse(OfflineSpeechModel.languages.contains(.japanese))
    }

    func testMissingSpeechIsExplainedInProfile() {
        XCTAssertNil(VoiceSettingsView.missingRouteHelp(.appleSpeech, language: .japanese))
        XCTAssertTrue(VoiceSettingsView.missingRouteHelp(.none(offlineModelWouldHelp: true), language: .lithuanian)?.contains("offline model") == true)
        let japanese = VoiceSettingsView.missingRouteHelp(.none(offlineModelWouldHelp: false), language: .japanese) ?? ""
        XCTAssertTrue(japanese.contains("日本語") && japanese.contains("Dictation"), japanese)
        XCTAssertEqual(SpeechCapture.localeCandidates(for: .chinese).map(\.identifier), ["zh-CN", "zh-Hans"])
    }
}
