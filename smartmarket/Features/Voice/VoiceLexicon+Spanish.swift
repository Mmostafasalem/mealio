import Foundation

extension VoiceLexicon {

    /// Spanish (Spain and Latin America). Accents are folded first (á→a, ñ→n),
    /// so every word below is written without them, and the tens are joined to
    /// their units ("treinta y cinco" → "treintaycinco") so a number stays one word.
    /// Not yet checked by a native speaker.
    static let spanish = VoiceLexicon(
        clean: { text in
            var text = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            text = text.replacingOccurrences(
                of: #"\b(treinta|cuarenta|cincuenta|sesenta|setenta|ochenta|noventa) y (un|uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve)\b"#,
                with: "$1y$2", options: .regularExpression)
            return text
        },
        fillers: [
            #"^(?:oye |hola |ok |vale |hey )?nourlo(?: ,)? "#,
            #"^(?:por favor|puedes|podrias|me puedes|quiero que|quiero|quisiera|me gustaria|vamos a) "#,
            #" (?:por favor|gracias|porfa)$"#,
        ],
        calorieWords: ["calori", "kcal"],
        calorieCues: ["quedan", "queda", "restan", "me faltan", "puedo comer", "todavia", "aun"],
        exercisePatterns: [
            #"^(?:muestrame |ensename |explicame |dime )?como (?:se hace|se hacen|hago|hacer|se hace bien|hago bien) (?:un |una |el |la |los |las |unas |unos )?(.+)$"#,
            #"^(?:muestra|muestrame|abre|ensename) (?:el )?ejercicio (?:de |del )?(.+)$"#,
        ],
        exerciseNoise: ["bien", "correctamente", "correcto", "por", "favor", "ejercicio"],
        exercises: [
            VoiceTranslation("push up", "flexion*", "lagartija*"), VoiceTranslation("squat", "sentadilla*"),
            VoiceTranslation("plank", "plancha*"), VoiceTranslation("lunge", "zancada*", "estocada*"),
            VoiceTranslation("pull up", "dominada*"), VoiceTranslation("deadlift", "peso muerto"),
            VoiceTranslation("bench press", "press de banca", "press banca"), VoiceTranslation("sit up", "abdominal*"),
            VoiceTranslation("burpee", "burpee*"), VoiceTranslation("jumping jacks", "saltos de tijera", "jumping jacks"),
            VoiceTranslation("crunch", "crunch*", "encogimiento*"), VoiceTranslation("bicep curl", "curl de biceps", "curl biceps"),
            VoiceTranslation("shoulder press", "press de hombros", "press militar"), VoiceTranslation("row", "remo"),
        ],
        workoutNouns: ["entrenamiento", "entrenamientos", "entreno", "rutina", "rutinas", "sesion", "workout"],
        workoutVerbs: ["empieza", "empezar", "comienza", "comenzar", "inicia", "iniciar", "crea", "crear", "haz", "hacer", "planifica",
                       "dame", "genera", "quiero", "necesito", "nuevo", "nueva", "otro", "otra"],
        workoutCues: ["quiero", "necesito", "vamos"],
        workoutKinds: [
            (.cardio, ["cardio", "correr", "carrera", "running", "trotar", "footing", "hiit", "bici", "bicicleta", "ciclismo", "resistencia", "caminar"]),
            (.mobility, ["estiramiento", "estiramientos", "estirar", "yoga", "movilidad", "flexibilidad", "recuperacion"]),
            (.gym, ["gimnasio", "gym", "pesas", "fuerza", "mancuernas", "barra", "musculacion"]),
            (.home, ["casa", "corporal", "equipo"]),
        ],
        minuteWords: "minutos|minuto|mins|min",
        hourWords: "horas|hora|h",
        halfHourPhrases: ["media hora"],
        oneHourPhrases: ["una hora"],
        cartPatterns: [
            #"^(?:anade|anadir|agrega|agregar|pon|poner|mete|meter|echa|incluye) (.+?) (?:al|a mi|en el|en mi|a la|en la) (?:carrito|carro|cesta)(?: de la compra| de compras)?$"#,
        ],
        checklistPatterns: [
            #"^(?:anade|anadir|agrega|agregar|pon|apunta|anota|escribe) (.+?) (?:a la|a mi|en la|en mi) lista(?: de la compra| de compras| de la compra)?$"#,
            #"^(?:tengo que|necesito|hay que|recuerdame|no olvides|acuerdate de) comprar (.+)$"#,
            #"^(?:compra|comprar) (.+)$"#,
            #"^(?:se me acabo|se me acabaron|se acabo|se acabaron|no queda|no quedan|no hay|ya no hay|ya no tengo|no tengo) (?:mas )?(.+)$"#,
        ],
        openPatterns: [
            #"^(?:abre|abrir|muestra|muestrame|ve a|ir a|vamos a|llevame a|cambia a|ensename)(?: me)? (?:mi |mis |el |la |los |las |al )?(.+)$"#,
        ],
        screenNoise: ["pantalla", "pestana", "pagina", "seccion"],
        screens: [
            (.home, ["inicio", "hoy", "resumen", "principal"]),
            (.meals, ["comidas", "plan de comidas", "menu", "menus", "recetas", "plan semanal", "plan"]),
            (.shop, ["tienda", "catalogo", "productos"]),
            (.train, ["entrenamientos", "ejercicios", "fitness", "deporte"]),
            (.cart, ["carrito", "carro", "cesta", "carrito de la compra"]),
            (.checklist, ["lista", "lista de la compra", "lista de compras"]),
            (.profile, ["perfil", "ajustes", "configuracion", "cuenta"]),
            (.logFood, ["diario", "diario de comidas", "registro de comidas"]),
            (.chat, ["chat", "asistente"]),
            (.scan, ["escaner", "codigo de barras", "camara"]),
        ],
        mealPrefix: #"(?:para el|para la|para|al|a la|en el|en la|en|de|del|como)? ?(?:mi |el |la |un |una )?"#,
        mealSuffix: #"(?: de hoy| hoy| esta manana| esta noche)?"#,
        meals: [
            (.breakfast, ["desayuno"]),
            (.lunch, ["almuerzo", "comida"]),
            (.dinner, ["cena"]),
            (.snack, ["merienda", "tentempie", "snack", "picoteo", "aperitivo"]),
        ],
        foodVerbs: [
            "me acabo de comer", "acabo de comer", "acabo de tomar", "acabo de beber", "me he comido", "he comido", "he tomado", "he bebido",
            "me comi", "me tome", "me bebi", "comi", "tome", "bebi", "estoy comiendo", "estoy tomando", "estoy bebiendo", "desayune", "cene",
            "almorce", "registra", "registrar", "anota", "anotar", "apunta", "apuntar", "anade", "anadir", "agrega", "agregar", "guarda", "pon", "mete",
        ].sorted { $0.count > $1.count },
        separators: #" (?:y|e|mas|tambien|ademas|con|junto con|luego) "#,
        amountRewrites: [
            (#"(\d+) y medio"#, "$1.5"), (#"(\d+) y media"#, "$1.5"), (#"(\d+) y cuarto"#, "$1.25"),
            (#"\b(?:medio|media)\b"#, "0.5"), (#"\bun cuarto(?: de)?\b"#, "0.25"), (#"\bun par de\b"#, "2"),
            (#"\b(?:unos pocos|unas pocas|algunos|algunas|unos cuantos|unas cuantas)\b"#, "3"), (#"\bun poco de\b"#, ""),
        ],
        units: [
            "g": .gram, "gr": .gram, "gramo": .gram, "gramos": .gram,
            "kg": .kilogram, "kilo": .kilogram, "kilos": .kilogram, "kilogramo": .kilogram, "kilogramos": .kilogram,
            "ml": .millilitre, "mililitro": .millilitre, "mililitros": .millilitre,
            "l": .litre, "litro": .litre, "litros": .litre,
            "taza": .cup, "tazas": .cup, "tazon": .bowl, "tazones": .bowl,
            "cucharada": .tablespoon, "cucharadas": .tablespoon, "cucharadita": .teaspoon, "cucharaditas": .teaspoon,
            "vaso": .glass, "vasos": .glass, "copa": .glass, "copas": .glass,
            "bol": .bowl, "boles": .bowl, "cuenco": .bowl, "cuencos": .bowl, "plato": .bowl, "platos": .bowl,
            "lata": .can, "latas": .can, "botella": .bottle, "botellas": .bottle,
            "rebanada": .slice, "rebanadas": .slice, "loncha": .slice, "lonchas": .slice, "rodaja": .slice, "rodajas": .slice,
            "trozo": .piece, "trozos": .piece, "pieza": .piece, "piezas": .piece, "unidad": .piece, "unidades": .piece,
            "punado": .handful, "punados": .handful, "racion": .serving, "raciones": .serving, "porcion": .serving, "porciones": .serving,
        ],
        ofWords: ["de", "del"],
        oneArticles: ["un", "una", "uno"],
        leadingNoise: ["el", "la", "los", "las", "unos", "unas", "algo", "mi", "mis", "de", "del", "aproximadamente", "unos", "sobre", "casi", "solo"],
        trailingNoise: ["hoy", "ahora", "tambien", "gracias", "porfa"],
        numbers: VoiceLexicon.spanishNumbers,
        hundredWords: ["cien", "ciento", "cientos"],
        numberJoiners: ["y"],
        attachedJoiner: nil,
        foods: [
            VoiceTranslation("greek yogurt", "yogur griego", "yogurt griego"), VoiceTranslation("chicken breast", "pechuga de pollo", "pechugas de pollo", "pechuga"),
            VoiceTranslation("olive oil", "aceite de oliva"), VoiceTranslation("peanut butter", "mantequilla de cacahuete", "mantequilla de mani", "crema de cacahuete"),
            VoiceTranslation("orange juice", "zumo de naranja", "jugo de naranja"), VoiceTranslation("apple juice", "zumo de manzana", "jugo de manzana"),
            VoiceTranslation("ground beef", "carne picada", "carne molida"), VoiceTranslation("french fries", "patatas fritas", "papas fritas"),
            VoiceTranslation("potato chips", "patatas chips", "chips"), VoiceTranslation("ice cream", "helado", "helados"),
            VoiceTranslation("cottage cheese", "requeson", "queso cottage"), VoiceTranslation("cream cheese", "queso crema", "queso para untar"),
            VoiceTranslation("sweet potato", "boniato", "boniatos", "batata", "batatas", "camote", "camotes"),
            VoiceTranslation("protein shake", "batido de proteinas", "batido de proteina", "batido proteico"),
            VoiceTranslation("oatmeal", "avena", "gachas de avena", "copos de avena"), VoiceTranslation("cereal ready-to-eat", "cereales", "cereal"),
            VoiceTranslation("corn flakes", "copos de maiz"), VoiceTranslation("cereal ready-to-eat", "muesli", "granola"),
            VoiceTranslation("whole wheat bread", "pan integral"), VoiceTranslation("bread white toasted", "tostada", "tostadas", "pan tostado"),
            VoiceTranslation("bread roll", "panecillo", "panecillos", "bollo", "bollos"), VoiceTranslation("green tea", "te verde"),
            VoiceTranslation("hot chocolate", "chocolate caliente", "cacao"), VoiceTranslation("sparkling water", "agua con gas"),
            VoiceTranslation("egg scrambled", "huevos revueltos", "revuelto"), VoiceTranslation("egg", "huevo", "huevos"),
            VoiceTranslation("bread", "pan", "panes", "barra de pan"), VoiceTranslation("milk", "leche"), VoiceTranslation("butter", "mantequilla"),
            VoiceTranslation("cheese", "queso", "quesos"), VoiceTranslation("yogurt", "yogur", "yogures", "yogurt", "yogurts"),
            VoiceTranslation("kefir", "kefir"), VoiceTranslation("cream", "nata", "crema de leche"), VoiceTranslation("sour cream", "crema agria"),
            VoiceTranslation("chicken breast", "pollo"), VoiceTranslation("turkey breast", "pavo", "pechuga de pavo"),
            VoiceTranslation("beef", "ternera", "carne de res", "res", "vacuno"), VoiceTranslation("pork", "cerdo", "carne de cerdo"),
            VoiceTranslation("lamb", "cordero"), VoiceTranslation("beef steak", "filete", "filetes", "bistec", "chuleta"),
            VoiceTranslation("ham", "jamon", "jamon york", "jamon serrano"), VoiceTranslation("bacon", "bacon", "beicon", "tocino", "panceta"),
            VoiceTranslation("sausage", "salchicha", "salchichas", "chorizo"), VoiceTranslation("salmon", "salmon"),
            VoiceTranslation("tuna", "atun"), VoiceTranslation("cod", "bacalao"), VoiceTranslation("sardines", "sardina", "sardinas"),
            VoiceTranslation("fish", "pescado", "pez"), VoiceTranslation("shrimp", "gamba", "gambas", "camaron", "camarones", "langostinos"),
            VoiceTranslation("rice", "arroz"), VoiceTranslation("pasta", "pasta", "macarrones", "fideos"), VoiceTranslation("spaghetti cooked", "espagueti", "espaguetis"),
            VoiceTranslation("potato", "patata", "patatas", "papa", "papas"), VoiceTranslation("lentils", "lenteja", "lentejas"),
            VoiceTranslation("beans", "judia", "judias", "frijol", "frijoles", "alubias"), VoiceTranslation("chickpeas", "garbanzo", "garbanzos"),
            VoiceTranslation("peas", "guisante", "guisantes", "chicharos"), VoiceTranslation("corn", "maiz", "elote"), VoiceTranslation("tofu", "tofu"),
            VoiceTranslation("quinoa", "quinoa", "quinua"), VoiceTranslation("couscous", "cuscus"),
            VoiceTranslation("apple", "manzana", "manzanas"), VoiceTranslation("banana", "platano", "platanos", "banana", "bananas", "banano"),
            VoiceTranslation("orange", "naranja", "naranjas"), VoiceTranslation("tangerine", "mandarina", "mandarinas"),
            VoiceTranslation("lemon", "limon", "limones"), VoiceTranslation("strawberries", "fresa", "fresas", "frutilla", "frutillas"),
            VoiceTranslation("blueberries", "arandano", "arandanos"), VoiceTranslation("raspberries", "frambuesa", "frambuesas"),
            VoiceTranslation("grapes", "uva", "uvas"), VoiceTranslation("pear", "pera", "peras"), VoiceTranslation("peach", "melocoton", "melocotones", "durazno", "duraznos"),
            VoiceTranslation("plum", "ciruela", "ciruelas"), VoiceTranslation("cherries", "cereza", "cerezas"), VoiceTranslation("watermelon", "sandia"),
            VoiceTranslation("melon", "melon"), VoiceTranslation("pineapple", "pina", "anana"), VoiceTranslation("mango", "mango", "mangos"),
            VoiceTranslation("kiwi", "kiwi", "kiwis"), VoiceTranslation("avocado", "aguacate", "aguacates", "palta", "paltas"),
            VoiceTranslation("dates", "datil", "datiles"), VoiceTranslation("raisins", "pasas", "uvas pasas"),
            VoiceTranslation("tomato", "tomate", "tomates"), VoiceTranslation("cucumber", "pepino", "pepinos"), VoiceTranslation("carrot", "zanahoria", "zanahorias"),
            VoiceTranslation("onion", "cebolla", "cebollas"), VoiceTranslation("garlic", "ajo", "ajos"), VoiceTranslation("pepper", "pimiento", "pimientos"),
            VoiceTranslation("spinach", "espinaca", "espinacas"), VoiceTranslation("broccoli", "brocoli"), VoiceTranslation("cauliflower", "coliflor"),
            VoiceTranslation("cabbage", "col", "repollo"), VoiceTranslation("zucchini", "calabacin", "calabacines"), VoiceTranslation("eggplant", "berenjena", "berenjenas"),
            VoiceTranslation("lettuce salad", "ensalada", "lechuga"), VoiceTranslation("mushrooms", "champinon", "champinones", "setas", "hongos"),
            VoiceTranslation("almonds", "almendra", "almendras"), VoiceTranslation("walnuts", "nuez", "nueces"), VoiceTranslation("peanuts", "cacahuete", "cacahuetes", "mani"),
            VoiceTranslation("nuts", "frutos secos"), VoiceTranslation("honey", "miel"), VoiceTranslation("jam", "mermelada"), VoiceTranslation("sugar", "azucar"),
            VoiceTranslation("milk chocolate candy", "chocolate"), VoiceTranslation("cookie", "galleta", "galletas"), VoiceTranslation("cake", "pastel", "tarta", "bizcocho"),
            VoiceTranslation("candy", "caramelo", "caramelos", "golosinas"), VoiceTranslation("popcorn", "palomitas"), VoiceTranslation("crackers", "galletas saladas"),
            VoiceTranslation("pizza", "pizza", "pizzas"), VoiceTranslation("hamburger", "hamburguesa", "hamburguesas"), VoiceTranslation("hot dog", "perrito caliente", "hot dog"),
            VoiceTranslation("sandwich", "sandwich", "bocadillo", "bocadillos", "emparedado"), VoiceTranslation("soup", "sopa", "caldo"),
            VoiceTranslation("coffee", "cafe", "cafes", "cafe solo"), VoiceTranslation("tea hot leaf black", "te"),
            VoiceTranslation("water", "agua"), VoiceTranslation("juice", "zumo", "jugo"), VoiceTranslation("beer", "cerveza", "cervezas"),
            VoiceTranslation("wine", "vino"), VoiceTranslation("cola", "cola", "coca cola", "refresco de cola"), VoiceTranslation("oil", "aceite"),
            VoiceTranslation("flour", "harina"), VoiceTranslation("croissant", "cruasan", "croissant"), VoiceTranslation("pancake", "tortita", "tortitas", "panqueque", "panqueques", "crepe"),
            VoiceTranslation("hummus", "hummus"), VoiceTranslation("tortilla", "tortilla", "tortillas"),
        ],
        shoppingVerbs: ["compra", "comprar"],
        mealPrepositions: ["para", "al", "a", "en", "de", "del", "como"]
    )

    /// cero … noventa y nueve, the "veinti-" words and the joined tens ("treintaycinco").
    private static let spanishNumbers: [String: Double] = {
        var table: [String: Double] = [
            "cero": 0, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
            "nueve": 9, "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15, "dieciseis": 16, "diecisiete": 17,
            "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiun": 21, "veintiuno": 21, "veintiuna": 21,
        ]
        let units: [(String, Double)] = [("dos", 2), ("tres", 3), ("cuatro", 4), ("cinco", 5), ("seis", 6), ("siete", 7), ("ocho", 8), ("nueve", 9)]
        for (unit, value) in units { table["veinti" + unit] = 20 + value }
        let tens: [(String, Double)] = [("treinta", 30), ("cuarenta", 40), ("cincuenta", 50), ("sesenta", 60), ("setenta", 70), ("ochenta", 80), ("noventa", 90)]
        for (ten, value) in tens {
            table[ten] = value
            for (unit, small) in [("un", 1.0), ("uno", 1), ("una", 1)] + units { table[ten + "y" + unit] = value + small }
        }
        return table
    }()
}
