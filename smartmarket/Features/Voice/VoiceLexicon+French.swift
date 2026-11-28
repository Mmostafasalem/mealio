import Foundation

extension VoiceLexicon {

    /// French. Accents are folded first (é→e, ç→c), "œ" is written "oe", "l'" and
    /// "d'" become "le"/"de" so the next word stands alone ("d'eau" → "de eau"),
    /// and number compounds are joined into one word ("vingt-cinq" → "vingtcinq").
    /// Not yet checked by a native speaker.
    static let french = VoiceLexicon(
        clean: { text in
            var text = text.replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "æ", with: "ae")
            text = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            text = text.replacingOccurrences(of: "’", with: "'")
            text = text.replacingOccurrences(of: #"(?<=^| )([ld])'(?=\p{L})"#, with: "$1e ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?<=^| )(vingt|trente|quarante|cinquante|soixante)[- ]et[- ](un|une|onze)(?=[- ]|$)"#,
                                             with: "$1et$2", options: .regularExpression)
            // "quatre" joins only "vingt" (quatre-vingts is 80); "quatre cinq" stays two numbers.
            text = text.replacingOccurrences(of: #"(?<=^| )quatre[- ](vingts?)(?=[- ]|$)"#, with: "quatre$1", options: .regularExpression)
            let tens = "dix|vingt|trente|quarante|cinquante|soixante|quatrevingt"
            let units = "un|une|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze|treize|quatorze|quinze|seize|vingts?"
            for _ in 0..<2 {
                text = text.replacingOccurrences(of: "(?<=^| )(" + tens + ")[- ](" + units + ")(?=[- ]|$)", with: "$1$2", options: .regularExpression)
            }
            return text
        },
        fillers: [
            #"^(?:hey |salut |ok |dis |bonjour )?nourlo(?: ,)? "#,
            #"^(?:s'il te plait|s'il vous plait|peux tu|pourrais tu|tu peux|tu pourrais|est ce que tu peux|je voudrais|je veux|j'aimerais) "#,
            #" (?:s'il te plait|s'il vous plait|merci|stp|svp)$"#,
        ],
        calorieWords: ["calori", "kcal"],
        calorieCues: ["reste", "restent", "il me reste", "encore", "puis je manger", "je peux encore"],
        exercisePatterns: [
            #"^(?:montre moi |explique moi |apprends moi )?comment (?:bien faire|faire|on fait|je fais|faut il faire|se fait|se font) (?:un |une |des |le |la |les |de )?(.+)$"#,
            #"^(?:montre|ouvre|affiche)(?: moi)? (?:le |la )?exercice (?:de |du |des )?(.+)$"#,
        ],
        exerciseNoise: ["correctement", "bien", "exercice", "stp", "svp"],
        exercises: [
            VoiceTranslation("push up", "pompe*"), VoiceTranslation("squat", "squat*", "flexion* de jambes", "accroupissement*"),
            VoiceTranslation("plank", "planche*", "gainage"), VoiceTranslation("lunge", "fente*"),
            VoiceTranslation("pull up", "traction*"), VoiceTranslation("deadlift", "souleve de terre"),
            VoiceTranslation("bench press", "developpe couche"), VoiceTranslation("sit up", "abdo*", "redressement* assis"),
            VoiceTranslation("burpee", "burpee*"), VoiceTranslation("jumping jacks", "jumping jack*"),
            VoiceTranslation("crunch", "crunch*"), VoiceTranslation("bicep curl", "curl biceps", "curl de biceps", "curl*"),
            VoiceTranslation("shoulder press", "developpe militaire", "developpe epaules"), VoiceTranslation("row", "rowing", "tirage"),
        ],
        workoutNouns: ["entrainement", "entrainements", "seance", "seances", "programme", "routine", "workout", "musculation"],
        workoutVerbs: ["commence", "commencer", "demarre", "demarrer", "lance", "lancer", "cree", "creer", "fais", "faire", "planifie",
                       "donne", "genere", "veux", "voudrais", "besoin", "nouvel", "nouveau", "nouvelle", "autre"],
        workoutCues: ["je veux", "j'ai besoin", "on fait", "allons"],
        workoutKinds: [
            (.cardio, ["cardio", "course", "courir", "running", "jogging", "footing", "hiit", "velo", "endurance", "marche"]),
            (.mobility, ["etirement", "etirements", "stretching", "yoga", "mobilite", "souplesse", "recuperation"]),
            (.gym, ["salle", "muscu", "musculation", "poids", "force", "halteres", "barre", "gym"]),
            (.home, ["maison", "domicile", "corps", "materiel"]),
        ],
        minuteWords: "minutes|minute|mins|min|mn",
        hourWords: "heures|heure|h",
        halfHourPhrases: ["demi heure"],
        oneHourPhrases: ["une heure"],
        cartPatterns: [
            #"^(?:ajoute|ajouter|ajoutez|mets|mettre|met|rajoute|place) (.+?) (?:au|a mon|dans le|dans mon|dans la|a la|dans ma) (?:panier|caddie|chariot)$"#,
        ],
        checklistPatterns: [
            #"^(?:ajoute|ajouter|ajoutez|mets|ecris|note|noter|rajoute|inscris) (.+?) (?:a la|a ma|sur la|sur ma|dans la|dans ma) liste(?: de courses| des courses| de course)?$"#,
            #"^(?:je dois|il faut|il me faut|j'ai besoin de|rappelle moi de|n'oublie pas de|je dois encore) acheter (.+)$"#,
            #"^(?:achete|acheter|achetez) (.+)$"#,
            #"^(?:il n'y a plus de|il n'y a plus|on n'a plus de|je n'ai plus de|on a plus de|plus de) (.+)$"#,
        ],
        openPatterns: [
            #"^(?:ouvre|ouvrir|affiche|afficher|montre|va a|aller a|va dans|va sur|passe a|emmene moi a)(?: moi)? (?:mon |ma |mes |le |la |les |au |aux )?(.+)$"#,
        ],
        screenNoise: ["ecran", "onglet", "page", "section"],
        screens: [
            (.home, ["accueil", "aujourd'hui", "resume", "tableau de bord"]),
            (.meals, ["repas", "plan de repas", "menus", "menu", "recettes", "plan", "planning"]),
            (.shop, ["boutique", "magasin", "catalogue", "produits"]),
            (.train, ["entrainements", "exercices", "sport", "fitness"]),
            (.cart, ["panier", "caddie", "chariot"]),
            (.checklist, ["liste", "liste de courses", "liste des courses", "courses"]),
            (.profile, ["profil", "reglages", "parametres", "compte"]),
            (.logFood, ["journal", "journal alimentaire", "journal des repas"]),
            (.chat, ["chat", "assistant"]),
            (.scan, ["scanner", "code barre", "code barres", "camera"]),
        ],
        mealPrefix: #"(?:au|pour le|pour mon|pour|a|en|comme|du|pendant le|au cours du|dans le|dans mon)? ?(?:mon |le |la |ce |un )?"#,
        mealSuffix: #"(?: de aujourd'hui| aujourd'hui| ce matin| ce midi| ce soir)?"#,
        meals: [
            (.breakfast, ["petit dejeuner", "petit dej", "petitdejeuner"]),
            (.lunch, ["dejeuner", "midi"]),
            (.dinner, ["diner", "souper"]),
            (.snack, ["en cas", "encas", "gouter", "collation", "snack"]),
        ],
        foodVerbs: [
            "je viens de manger", "je viens de boire", "je viens de prendre", "j'ai mange", "j'ai bu", "j'ai pris", "j'ai avale",
            "je mange", "je bois", "je prends", "on a mange", "nous avons mange", "ajoute", "ajouter", "ajoutez", "note", "noter",
            "enregistre", "enregistrer", "rajoute", "mets", "inscris", "mange", "bu",
        ].sorted { $0.count > $1.count },
        separators: #" (?:et|plus|avec|puis|ainsi que|aussi|ensuite) "#,
        amountRewrites: [
            (#"(\d+) et demie?"#, "$1.5"), (#"(\d+) et quart"#, "$1.25"),
            (#"\b(?:un|une) demie?\b"#, "0.5"), (#"\bla moitie de (?:un |une )?"#, "0.5 "), (#"\bdemie?\b"#, "0.5"),
            (#"\bun quart (?:de )?"#, "0.25 "), (#"\bquelques\b"#, "3"), (#"\bun peu de\b"#, ""),
        ],
        units: [
            "g": .gram, "gr": .gram, "gramme": .gram, "grammes": .gram,
            "kg": .kilogram, "kilo": .kilogram, "kilos": .kilogram, "kilogramme": .kilogram, "kilogrammes": .kilogram,
            "ml": .millilitre, "millilitre": .millilitre, "millilitres": .millilitre, "cl": .millilitre,
            "l": .litre, "litre": .litre, "litres": .litre,
            "tasse": .cup, "tasses": .cup, "mug": .cup, "bol": .bowl, "bols": .bowl, "assiette": .bowl, "assiettes": .bowl,
            "cuillere": .tablespoon, "cuilleres": .tablespoon, "cuilleree": .tablespoon, "cuillerees": .tablespoon,
            "verre": .glass, "verres": .glass, "canette": .can, "canettes": .can, "boite": .can, "boites": .can,
            "bouteille": .bottle, "bouteilles": .bottle, "tranche": .slice, "tranches": .slice,
            "morceau": .piece, "morceaux": .piece, "piece": .piece, "pieces": .piece,
            "poignee": .handful, "poignees": .handful, "portion": .serving, "portions": .serving, "part": .serving, "parts": .serving,
        ],
        ofWords: ["de", "du", "des"],
        oneArticles: ["un", "une"],
        leadingNoise: ["le", "la", "les", "du", "de", "des", "mon", "ma", "mes", "environ", "encore", "juste", "presque"],
        trailingNoise: ["aussi", "aujourd'hui", "maintenant", "merci", "stp", "svp"],
        numbers: VoiceLexicon.frenchNumbers,
        hundredWords: ["cent", "cents"],
        numberJoiners: [],
        attachedJoiner: nil,
        foods: [
            VoiceTranslation("greek yogurt", "yaourt grec", "yogourt grec"), VoiceTranslation("chicken breast", "blanc de poulet", "blancs de poulet", "filet de poulet", "escalope de poulet"),
            VoiceTranslation("olive oil", "huile de olive"), VoiceTranslation("peanut butter", "beurre de cacahuete", "beurre de cacahuetes", "beurre de arachide"),
            VoiceTranslation("orange juice", "jus de orange"), VoiceTranslation("apple juice", "jus de pomme"),
            VoiceTranslation("ground beef", "boeuf hache", "viande hachee", "steak hache"), VoiceTranslation("french fries", "frites", "pommes frites"),
            VoiceTranslation("potato chips", "chips"), VoiceTranslation("ice cream", "glace", "glaces", "creme glacee"),
            VoiceTranslation("cottage cheese", "fromage cottage", "cottage"), VoiceTranslation("cream cheese", "fromage a tartiner", "fromage frais"),
            VoiceTranslation("sweet potato", "patate douce", "patates douces"), VoiceTranslation("protein shake", "shake proteine", "shaker de proteines", "boisson proteinee"),
            VoiceTranslation("oatmeal", "flocons de avoine", "porridge", "avoine", "bouillie de avoine"), VoiceTranslation("cereal ready-to-eat", "cereales", "cereale"),
            VoiceTranslation("corn flakes", "corn flakes", "petales de mais"), VoiceTranslation("cereal ready-to-eat", "muesli", "granola"),
            VoiceTranslation("whole wheat bread", "pain complet"), VoiceTranslation("bread white toasted", "toast", "toasts", "pain grille", "biscotte", "biscottes"),
            VoiceTranslation("bread roll", "petit pain", "petits pains"), VoiceTranslation("green tea", "the vert"),
            VoiceTranslation("hot chocolate", "chocolat chaud"), VoiceTranslation("sparkling water", "eau gazeuse", "eau petillante"),
            VoiceTranslation("egg scrambled", "oeufs brouilles"), VoiceTranslation("egg", "oeuf", "oeufs"),
            VoiceTranslation("bread", "pain", "pains", "baguette", "baguettes"), VoiceTranslation("milk", "lait"), VoiceTranslation("butter", "beurre"),
            VoiceTranslation("cheese", "fromage", "fromages"), VoiceTranslation("yogurt", "yaourt", "yaourts", "yogourt", "yoghourt"),
            VoiceTranslation("kefir", "kefir"), VoiceTranslation("cream", "creme", "creme fraiche"), VoiceTranslation("sour cream", "creme aigre"),
            VoiceTranslation("chicken breast", "poulet"), VoiceTranslation("turkey breast", "dinde", "blanc de dinde"),
            VoiceTranslation("beef", "boeuf"), VoiceTranslation("pork", "porc"), VoiceTranslation("lamb", "agneau"),
            VoiceTranslation("beef steak", "steak", "steaks", "entrecote", "bifteck"), VoiceTranslation("ham", "jambon"),
            VoiceTranslation("bacon", "bacon", "lardons"), VoiceTranslation("sausage", "saucisse", "saucisses", "saucisson"),
            VoiceTranslation("salmon", "saumon"), VoiceTranslation("tuna", "thon"), VoiceTranslation("cod", "cabillaud", "morue"),
            VoiceTranslation("sardines", "sardine", "sardines"), VoiceTranslation("fish", "poisson", "poissons"),
            VoiceTranslation("shrimp", "crevette", "crevettes"), VoiceTranslation("rice", "riz"), VoiceTranslation("pasta", "pates", "pate", "macaronis"),
            VoiceTranslation("spaghetti cooked", "spaghetti", "spaghettis"), VoiceTranslation("potato", "pomme de terre", "pommes de terre", "patate", "patates"),
            VoiceTranslation("lentils", "lentille", "lentilles"), VoiceTranslation("beans", "haricot", "haricots"), VoiceTranslation("chickpeas", "pois chiche", "pois chiches"),
            VoiceTranslation("peas", "petits pois", "pois"), VoiceTranslation("corn", "mais"), VoiceTranslation("tofu", "tofu"),
            VoiceTranslation("quinoa", "quinoa"), VoiceTranslation("couscous", "couscous", "semoule"),
            VoiceTranslation("apple", "pomme", "pommes"), VoiceTranslation("banana", "banane", "bananes"), VoiceTranslation("orange", "orange", "oranges"),
            VoiceTranslation("tangerine", "mandarine", "mandarines", "clementine", "clementines"), VoiceTranslation("lemon", "citron", "citrons"),
            VoiceTranslation("strawberries", "fraise", "fraises"), VoiceTranslation("blueberries", "myrtille", "myrtilles"), VoiceTranslation("raspberries", "framboise", "framboises"),
            VoiceTranslation("grapes", "raisin", "raisins"), VoiceTranslation("pear", "poire", "poires"), VoiceTranslation("peach", "peche", "peches"),
            VoiceTranslation("plum", "prune", "prunes"), VoiceTranslation("cherries", "cerise", "cerises"), VoiceTranslation("watermelon", "pasteque"),
            VoiceTranslation("melon", "melon"), VoiceTranslation("pineapple", "ananas"), VoiceTranslation("mango", "mangue", "mangues"),
            VoiceTranslation("kiwi", "kiwi", "kiwis"), VoiceTranslation("avocado", "avocat", "avocats"), VoiceTranslation("dates", "datte", "dattes"),
            VoiceTranslation("raisins", "raisins secs"), VoiceTranslation("tomato", "tomate", "tomates"), VoiceTranslation("cucumber", "concombre", "concombres"),
            VoiceTranslation("carrot", "carotte", "carottes"), VoiceTranslation("onion", "oignon", "oignons"), VoiceTranslation("garlic", "ail"),
            VoiceTranslation("pepper", "poivron", "poivrons"), VoiceTranslation("spinach", "epinard", "epinards"), VoiceTranslation("broccoli", "brocoli", "brocolis"),
            VoiceTranslation("cauliflower", "chou fleur"), VoiceTranslation("cabbage", "chou"), VoiceTranslation("zucchini", "courgette", "courgettes"),
            VoiceTranslation("eggplant", "aubergine", "aubergines"), VoiceTranslation("lettuce salad", "salade", "salade verte", "laitue"),
            VoiceTranslation("mushrooms", "champignon", "champignons"), VoiceTranslation("almonds", "amande", "amandes"),
            VoiceTranslation("walnuts", "noix"), VoiceTranslation("peanuts", "cacahuete", "cacahuetes", "arachides"), VoiceTranslation("nuts", "fruits a coque", "noisettes"),
            VoiceTranslation("honey", "miel"), VoiceTranslation("jam", "confiture"), VoiceTranslation("sugar", "sucre"),
            VoiceTranslation("milk chocolate candy", "chocolat"), VoiceTranslation("cookie", "biscuit", "biscuits", "cookie", "cookies"),
            VoiceTranslation("cake", "gateau", "gateaux", "tarte"), VoiceTranslation("candy", "bonbon", "bonbons"), VoiceTranslation("popcorn", "popcorn", "pop corn"),
            VoiceTranslation("crackers", "crackers"), VoiceTranslation("pizza", "pizza", "pizzas"), VoiceTranslation("hamburger", "hamburger", "burger", "burgers"),
            VoiceTranslation("hot dog", "hot dog"), VoiceTranslation("sandwich", "sandwich", "sandwichs", "croque monsieur"),
            VoiceTranslation("soup", "soupe", "potage", "veloute"), VoiceTranslation("coffee", "cafe", "cafes", "expresso"),
            VoiceTranslation("tea hot leaf black", "the"), VoiceTranslation("water", "eau"), VoiceTranslation("juice", "jus"),
            VoiceTranslation("beer", "biere", "bieres"), VoiceTranslation("wine", "vin"), VoiceTranslation("cola", "cola", "coca"),
            VoiceTranslation("oil", "huile"), VoiceTranslation("flour", "farine"), VoiceTranslation("croissant", "croissant", "croissants"),
            VoiceTranslation("pancake", "crepe", "crepes", "pancake", "pancakes"), VoiceTranslation("hummus", "houmous"),
        ],
        shoppingVerbs: ["achete", "acheter", "achetez"],
        mealPrepositions: ["au", "pour", "a", "en", "comme", "du", "pendant", "dans"]
    )

    /// zéro … quatre-vingt-dix-neuf, written as one word once the hyphens are joined.
    private static let frenchNumbers: [String: Double] = {
        var table: [String: Double] = [
            "zero": 0, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
            "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16, "dixsept": 17, "dixhuit": 18, "dixneuf": 19,
        ]
        let units: [(String, Double)] = [("deux", 2), ("trois", 3), ("quatre", 4), ("cinq", 5), ("six", 6), ("sept", 7), ("huit", 8), ("neuf", 9)]
        for (ten, value) in [("vingt", 20.0), ("trente", 30), ("quarante", 40), ("cinquante", 50), ("soixante", 60)] {
            table[ten] = value
            table[ten + "etun"] = value + 1
            table[ten + "etune"] = value + 1
            for (unit, small) in units { table[ten + unit] = value + small }
        }
        let teens: [(String, Double)] = [("dix", 10), ("onze", 11), ("douze", 12), ("treize", 13), ("quatorze", 14), ("quinze", 15),
                                         ("seize", 16), ("dixsept", 17), ("dixhuit", 18), ("dixneuf", 19)]
        table["soixanteetonze"] = 71
        for (teen, small) in teens { table["soixante" + teen] = 60 + small }
        table["quatrevingt"] = 80
        table["quatrevingts"] = 80
        for (unit, small) in [("un", 1.0)] + units { table["quatrevingt" + unit] = 80 + small }
        for (teen, small) in teens { table["quatrevingt" + teen] = 80 + small }
        return table
    }()
}
