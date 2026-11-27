import Foundation

extension VoiceLexicon {

    /// German. Verbs often come last ("ich habe zwei Eier gegessen"), so the
    /// closing participles are dropped as trailing noise.
    static let german = VoiceLexicon(
        fillers: [
            #"^(?:hey|hallo|hi|ok|okay)? ?nourlo(?: ,)? "#,
            #"^(?:bitte|kannst du|könntest du|würdest du|ich möchte gerne|ich möchte|ich will|ich würde gerne|ich würde gern) "#,
            #" (?:bitte|danke|danke schön)$"#,
        ],
        calorieWords: ["kalorie", "kcal"],
        calorieCues: ["übrig", "noch", "verbleib", "darf ich"],
        exercisePatterns: [
            #"^(?:zeig mir |zeige mir |erklär mir |erkläre mir )?wie (?:mache ich|macht man|mach ich|geht|gehen|funktioniert|funktionieren) (?:einen |eine |ein |den |die |das )?(.+)$"#,
            #"^(?:zeig|zeige|öffne)(?: mir)? (?:die )?übung (.+)$"#,
        ],
        exerciseNoise: ["richtig", "korrekt", "bitte", "übung"],
        exercises: [
            VoiceTranslation("push up", "liegestütz*"), VoiceTranslation("squat", "kniebeuge*"),
            VoiceTranslation("plank", "planke", "plank", "unterarmstütz*"), VoiceTranslation("lunge", "ausfallschritt*"),
            VoiceTranslation("pull up", "klimmzug", "klimmzüge", "klimmzügen"), VoiceTranslation("deadlift", "kreuzheben"),
            VoiceTranslation("bench press", "bankdrücken"), VoiceTranslation("sit up", "sit ups", "situps", "rumpfbeuge*"),
            VoiceTranslation("burpee", "burpee*"), VoiceTranslation("jumping jacks", "hampelmann", "hampelmänner"),
            VoiceTranslation("crunch", "crunch*", "bauchpresse*"), VoiceTranslation("bicep curl", "bizepscurl*", "bizeps curl", "bizeps curls"),
            VoiceTranslation("shoulder press", "schulterdrücken"), VoiceTranslation("row", "rudern"),
        ],
        workoutNouns: ["training", "workout", "workouts", "einheit", "trainingseinheit", "trainingsplan", "programm", "übungen",
                       "krafttraining", "cardiotraining", "ausdauertraining", "heimtraining", "dehnprogramm"],
        workoutVerbs: ["starte", "start", "starten", "beginne", "beginnen", "erstelle", "erstellen", "mach", "mache", "machen", "plane",
                       "gib", "will", "möchte", "brauche", "neues", "neue", "neuen"],
        workoutCues: ["ich will", "ich möchte", "ich brauche", "lass uns"],
        workoutKinds: [
            (.cardio, ["cardio", "cardiotraining", "laufen", "lauf", "joggen", "ausdauer", "ausdauertraining", "hiit", "radfahren"]),
            (.mobility, ["dehnen", "dehnung", "dehnprogramm", "stretching", "yoga", "mobilität", "beweglichkeit", "regeneration"]),
            (.gym, ["gym", "fitnessstudio", "studio", "kraft", "krafttraining", "gewichte", "gewichten", "hanteln", "langhantel"]),
            (.home, ["zuhause", "hause", "heimtraining", "körpergewicht", "eigengewicht", "geräte"]),
        ],
        minuteWords: "minuten|minute|min",
        hourWords: "stunden|stunde|std",
        halfHourPhrases: ["halbe stunde", "halben stunde", "halbstündig"],
        oneHourPhrases: ["eine stunde", "einer stunde"],
        cartPatterns: [
            #"^(?:füge|füg|leg|lege|pack|packe|tu|tue|setz|setze) (.+?) (?:in den|in meinen|zum|zu meinem|in die) (?:warenkorb|einkaufswagen|korb)(?: hinzu| dazu)?$"#,
        ],
        checklistPatterns: [
            #"^(?:füge|füg|schreib|schreibe|setz|setze|pack|packe|notiere) (.+?) (?:auf die|auf meine|zur|zu meiner|in die|auf den) (?:einkaufsliste|einkaufszettel|liste|checkliste)(?: hinzu| dazu)?$"#,
            #"^(?:ich muss|ich muss noch|wir müssen|wir müssen noch|ich sollte|erinnere mich daran|erinner mich daran) (.+?) (?:kaufen|zu kaufen|besorgen|zu besorgen|holen)$"#,
            #"^(?:kauf|kaufe|besorg|besorge) (.+)$"#,
            #"^(?:wir haben|ich habe) (?:kein|keine|keinen) (.+?) mehr$"#,
            #"^(.+?) (?:ist|sind) (?:alle|aus|leer)$"#,
        ],
        openPatterns: [
            #"^(?:öffne|zeig|zeige|geh zu|gehe zu|geh zum|gehe zum|geh zur|gehe zur|wechsle zu|wechsle zum|wechsle zur)(?: mir)? (?:den |die |das |meinen |meine |mein |dem |der )?(.+)$"#,
        ],
        screenNoise: ["seite", "tab", "ansicht", "bildschirm"],
        screens: [
            (.home, ["start", "startseite", "heute", "übersicht", "home"]),
            (.meals, ["mahlzeiten", "essensplan", "speiseplan", "ernährungsplan", "wochenplan", "rezepte", "plan"]),
            (.shop, ["shop", "laden", "geschäft", "katalog", "produkte"]),
            (.train, ["training", "workouts", "übungen", "fitness", "trainings"]),
            (.cart, ["warenkorb", "einkaufswagen", "korb"]),
            (.checklist, ["einkaufsliste", "einkaufszettel", "liste", "checkliste"]),
            (.profile, ["profil", "einstellungen", "konto"]),
            (.logFood, ["ernährungstagebuch", "essenstagebuch", "tagebuch", "essen eintragen"]),
            (.chat, ["chat", "assistent", "assistenten", "ki chat"]),
            (.scan, ["scanner", "barcode scanner", "barcodescanner", "barcode", "kamera"]),
        ],
        mealPrefix: #"(?:zum|zu|zur|fürs|für das|für|als|beim|am|im)? ?(?:mein |meinem |meiner |heutigen |einen |ein )?"#,
        mealSuffix: #"(?: heute| heute morgen| heute abend)?"#,
        meals: [
            (.breakfast, ["frühstück"]),
            (.lunch, ["mittagessen", "mittag"]),
            (.dinner, ["abendessen", "abendbrot", "abend"]),
            (.snack, ["snacks", "snack", "zwischenmahlzeit", "imbiss"]),
        ],
        foodVerbs: [
            "ich habe gerade", "ich hab gerade", "ich habe eben", "ich habe", "ich hab", "ich hatte", "ich esse gerade", "ich esse",
            "ich trinke gerade", "ich trinke", "ich aß", "ich trank", "wir hatten", "wir haben",
            "trage ein", "trag ein", "trage", "trag", "füge hinzu", "füge", "füg", "logge", "notiere", "speichere", "erfasse",
            "protokolliere", "schreib auf", "schreibe auf", "eintragen", "hinzufügen", "gegessen", "getrunken",
        ].sorted { $0.count > $1.count },
        separators: #" (?:und|plus|sowie|außerdem|dann|dazu noch|und dazu) "#,
        amountRewrites: [
            (#"(\d+) einhalb"#, "$1.5"), (#"(\d+) und (?:ein|eine|einen) halbe[sn]?"#, "$1.5"),
            (#"\b(?:ein|eine|einen|einem) halbe[rsn]?\b"#, "0.5"), (#"\bhalbe[rsn]?\b"#, "0.5"),
            (#"\b(?:ein|eine|einen) viertel\b"#, "0.25"), (#"\bein paar\b"#, "3"), (#"\bein wenig\b"#, ""), (#"\bein bisschen\b"#, ""),
        ],
        units: [
            "g": .gram, "gramm": .gram, "gr": .gram,
            "kg": .kilogram, "kilo": .kilogram, "kilos": .kilogram, "kilogramm": .kilogram,
            "ml": .millilitre, "milliliter": .millilitre,
            "l": .litre, "liter": .litre,
            "tasse": .cup, "tassen": .cup, "becher": .cup,
            "el": .tablespoon, "esslöffel": .tablespoon,
            "tl": .teaspoon, "teelöffel": .teaspoon,
            "glas": .glass, "gläser": .glass,
            "schüssel": .bowl, "schüsseln": .bowl, "schale": .bowl, "schalen": .bowl, "teller": .bowl,
            "dose": .can, "dosen": .can,
            "flasche": .bottle, "flaschen": .bottle,
            "scheibe": .slice, "scheiben": .slice,
            "stück": .piece, "stücke": .piece, "stk": .piece,
            "handvoll": .handful,
            "portion": .serving, "portionen": .serving,
        ],
        ofWords: ["von", "vom"],
        oneArticles: ["ein", "eine", "einen", "einem", "einer"],
        leadingNoise: ["der", "die", "das", "den", "dem", "etwas", "mein", "meine", "meinen", "ungefähr", "circa", "ca", "etwa", "noch", "gerade", "von"],
        trailingNoise: ["bitte", "gegessen", "getrunken", "gehabt", "hinzu", "dazu", "heute", "jetzt", "ein", "danke", "auch", "eintragen", "hinzufügen", "auf"],
        numbers: VoiceLexicon.germanNumbers,
        hundredWords: ["hundert"],
        numberJoiners: ["und"],
        attachedJoiner: nil,
        foods: [
            VoiceTranslation("greek yogurt", "griechischer joghurt", "griechischen joghurt", "griechischem joghurt", "griechischer jogurt"),
            VoiceTranslation("chicken breast", "hähnchenbrust", "hühnerbrust", "hähnchenbrustfilet", "hühnchenbrust", "hähnchenbrüste"),
            VoiceTranslation("olive oil", "olivenöl"), VoiceTranslation("peanut butter", "erdnussbutter", "erdnussmus"),
            VoiceTranslation("orange juice", "orangensaft", "o saft"), VoiceTranslation("apple juice", "apfelsaft"),
            VoiceTranslation("ground beef", "hackfleisch", "rinderhack", "rinderhackfleisch", "gehacktes"),
            VoiceTranslation("french fries", "pommes", "pommes frites"), VoiceTranslation("potato chips", "kartoffelchips", "chips"),
            VoiceTranslation("ice cream", "eis", "eiscreme", "speiseeis"), VoiceTranslation("cottage cheese", "hüttenkäse", "körniger frischkäse"),
            VoiceTranslation("cream cheese", "frischkäse"), VoiceTranslation("sweet potato", "süßkartoffel", "süßkartoffeln"),
            VoiceTranslation("protein shake", "proteinshake", "eiweißshake", "protein shake"), VoiceTranslation("oatmeal", "haferflocken", "haferbrei", "porridge"),
            VoiceTranslation("whole wheat bread", "vollkornbrot"), VoiceTranslation("bread white toasted", "toast", "toastbrot"),
            VoiceTranslation("bread roll", "brötchen", "semmel", "semmeln"),
            VoiceTranslation("egg", "ei", "eier", "eiern"), VoiceTranslation("bread", "brot", "brote"),
            VoiceTranslation("milk", "milch"), VoiceTranslation("butter", "butter"), VoiceTranslation("cheese", "käse"),
            VoiceTranslation("yogurt", "joghurt", "jogurt", "naturjoghurt"), VoiceTranslation("cottage cheese", "quark", "magerquark"),
            VoiceTranslation("chicken breast", "hähnchen", "hühnchen", "huhn", "hähnchenfleisch"), VoiceTranslation("turkey breast", "pute", "putenbrust", "truthahn"),
            VoiceTranslation("beef", "rindfleisch", "rind"), VoiceTranslation("pork", "schweinefleisch", "schwein"),
            VoiceTranslation("beef steak", "steak", "rindersteak"), VoiceTranslation("ham", "schinken"), VoiceTranslation("bacon", "speck", "bacon"),
            VoiceTranslation("sausage", "wurst", "würstchen", "bratwurst", "würste"), VoiceTranslation("salmon", "lachs"),
            VoiceTranslation("tuna", "thunfisch"), VoiceTranslation("fish", "fisch"), VoiceTranslation("shrimp", "garnelen", "garnele", "shrimps"),
            VoiceTranslation("rice", "reis"), VoiceTranslation("pasta", "nudeln", "pasta"), VoiceTranslation("spaghetti cooked", "spaghetti"),
            VoiceTranslation("potato", "kartoffel", "kartoffeln"), VoiceTranslation("lentils", "linsen"), VoiceTranslation("beans", "bohnen"),
            VoiceTranslation("chickpeas", "kichererbsen"), VoiceTranslation("tofu", "tofu"),
            VoiceTranslation("apple", "apfel", "äpfel"), VoiceTranslation("banana", "banane", "bananen"), VoiceTranslation("orange", "orange", "orangen", "apfelsine"),
            VoiceTranslation("strawberries", "erdbeeren", "erdbeere"), VoiceTranslation("blueberries", "blaubeeren", "heidelbeeren"),
            VoiceTranslation("grapes", "trauben", "weintrauben"), VoiceTranslation("pear", "birne", "birnen"), VoiceTranslation("avocado", "avocado", "avocados"),
            VoiceTranslation("tomato", "tomate", "tomaten"), VoiceTranslation("cucumber", "gurke", "gurken"), VoiceTranslation("carrot", "karotte", "karotten", "möhre", "möhren"),
            VoiceTranslation("onion", "zwiebel", "zwiebeln"), VoiceTranslation("pepper", "paprika"), VoiceTranslation("spinach", "spinat"),
            VoiceTranslation("broccoli", "brokkoli"), VoiceTranslation("lettuce salad", "salat", "grüner salat"), VoiceTranslation("mushrooms", "pilze", "champignons"),
            VoiceTranslation("almonds", "mandeln"), VoiceTranslation("walnuts", "walnüsse"), VoiceTranslation("nuts", "nüsse"), VoiceTranslation("peanuts", "erdnüsse"),
            VoiceTranslation("honey", "honig"), VoiceTranslation("jam", "marmelade", "konfitüre"), VoiceTranslation("sugar", "zucker"),
            VoiceTranslation("milk chocolate candy", "schokolade"), VoiceTranslation("cookie", "keks", "kekse", "plätzchen"), VoiceTranslation("cake", "kuchen"),
            VoiceTranslation("pizza", "pizza"), VoiceTranslation("hamburger", "burger", "hamburger"), VoiceTranslation("sandwich", "sandwich", "belegtes brot"),
            VoiceTranslation("soup", "suppe"), VoiceTranslation("coffee", "kaffee"), VoiceTranslation("tea hot leaf black", "tee"),
            VoiceTranslation("water", "wasser", "mineralwasser"), VoiceTranslation("juice", "saft"), VoiceTranslation("beer", "bier"), VoiceTranslation("wine", "wein"),
            VoiceTranslation("cola", "cola", "coke"), VoiceTranslation("oil", "öl"), VoiceTranslation("cream", "sahne"), VoiceTranslation("flour", "mehl"),
            VoiceTranslation("cereal ready-to-eat", "müsli"), VoiceTranslation("pancake", "pfannkuchen", "pancakes"), VoiceTranslation("croissant", "croissant", "croissants"),
        ]
    )

    /// null … zwanzig, the tens, the one-word compounds ("fünfundzwanzig") and the hundreds.
    private static let germanNumbers: [String: Double] = {
        var table: [String: Double] = [
            "null": 0, "eins": 1, "zwei": 2, "zwo": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
            "zehn": 10, "elf": 11, "zwölf": 12, "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15, "sechzehn": 16, "siebzehn": 17,
            "achtzehn": 18, "neunzehn": 19, "anderthalb": 1.5, "eineinhalb": 1.5, "zweieinhalb": 2.5, "dreieinhalb": 3.5,
        ]
        let tens: [(String, Double)] = [("zwanzig", 20), ("dreißig", 30), ("vierzig", 40), ("fünfzig", 50), ("sechzig", 60),
                                        ("siebzig", 70), ("achtzig", 80), ("neunzig", 90)]
        let units: [(String, Double)] = [("ein", 1), ("zwei", 2), ("drei", 3), ("vier", 4), ("fünf", 5), ("sechs", 6),
                                         ("sieben", 7), ("acht", 8), ("neun", 9)]
        for (ten, value) in tens {
            table[ten] = value
            for (unit, small) in units { table[unit + "und" + ten] = value + small }
        }
        table["einhundert"] = 100
        for (unit, small) in units.dropFirst() { table[unit + "hundert"] = small * 100 }
        return table
    }()
}
