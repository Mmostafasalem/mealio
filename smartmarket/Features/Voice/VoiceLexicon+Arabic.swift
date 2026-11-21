import Foundation

extension VoiceLexicon {

    /// Arabic (Modern Standard, with common Gulf, Egyptian and Levantine words).
    ///
    /// Text is first reduced to plain letters: vowel marks and the stretching
    /// line go, the alef forms become ا, ة becomes ه and ى becomes ي, and Arabic
    /// digits become 0–9. Every word below is written in that reduced form.
    /// "And" is written onto the next word (وخبز), so it is split off before
    /// foods are separated; the article ال is dropped when a word is looked up.
    static let arabic = VoiceLexicon(
        clean: { text in
            var text = text
            // Vowel marks (tashkeel) and tatweel.
            text = text.replacingOccurrences(of: "[\u{064B}-\u{065F}\u{0670}\u{0640}]", with: "", options: .regularExpression)
            for (from, to) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ٱ", "ا"), ("ة", "ه"), ("ى", "ي"), ("ؤ", "و"), ("ئ", "ي")] {
                text = text.replacingOccurrences(of: from, with: to)
            }
            // Arabic-Indic digits.
            let digits = Array("٠١٢٣٤٥٦٧٨٩")
            for (value, digit) in digits.enumerated() {
                text = text.replacingOccurrences(of: String(digit), with: String(value))
            }
            return text.replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: "؟", with: " ")
        },
        fillers: [
            #"^(?:يا |مرحبا |اهلا |هاي )?نورلو(?: ,)? "#,
            #"^(?:من فضلك|لو سمحت|ممكن|هل يمكنك ان|هل يمكنك|اريد ان|ابغي ان|ابي|عايز|بدي) "#,
            #" (?:من فضلك|لو سمحت|شكرا|شكرا لك)$"#,
        ],
        calorieWords: ["سعر", "كالوري", "سعرات"],
        calorieCues: ["باقي", "متبقي", "بقي", "تبقي", "المتبقيه", "اقدر اكل"],
        exercisePatterns: [
            #"^(?:كيف|كيفيه|طريقه) (?:اعمل|اسوي|العب|امارس|اودي|اداء|عمل|تمرين) (?:تمرين )?(?:ال)?(.+)$"#,
            #"^(?:ورني|اعرض|اظهر|افتح)(?: لي)? تمرين (?:ال)?(.+)$"#,
        ],
        exerciseNoise: ["بشكل", "صحيح", "تمرين", "من", "فضلك"],
        exercises: [
            VoiceTranslation("push up", "ضغط", "تمرين الضغط", "بوش اب"), VoiceTranslation("squat", "قرفصاء", "سكوات", "سكواط"),
            VoiceTranslation("plank", "بلانك", "لوح"), VoiceTranslation("pull up", "عقله", "سحب"),
            VoiceTranslation("lunge", "طعن", "لانج", "اندفاع"), VoiceTranslation("deadlift", "رفعه مميته", "ديدلفت"),
            VoiceTranslation("bench press", "بنش", "ضغط الصدر", "بنش برس"), VoiceTranslation("sit up", "بطن", "معده"),
            VoiceTranslation("burpee", "بيربي"), VoiceTranslation("jumping jacks", "قفز"), VoiceTranslation("crunch", "كرنش"),
        ],
        workoutNouns: ["تمرين", "تمارين", "تمرينه", "جلسه", "تدريب", "تدريبه", "حصه", "روتين", "برنامج"],
        workoutVerbs: ["ابدا", "ابدئي", "جهز", "اعمل", "سوي", "اريد", "ابغي", "ابي", "عايز", "بدي", "انشي", "اصنع", "اعطني", "جديد", "جديده"],
        workoutCues: ["اريد", "ابغي", "عايز", "بدي", "خلينا"],
        workoutKinds: [
            (.cardio, ["كارديو", "جري", "ركض", "هروله", "تحمل", "دراجه"]),
            (.mobility, ["تمدد", "اطاله", "اطالات", "يوغا", "مرونه", "استشفاء"]),
            (.gym, ["جيم", "نادي", "اوزان", "قوه", "حديد", "مقاومه", "دمبل"]),
            (.home, ["منزلي", "منزليه", "بيت", "البيت", "منزل", "المنزل", "بالبيت", "بدون"]),
        ],
        minuteWords: "دقيقه|دقايق|دقائق|دقيقتين|د",
        hourWords: "ساعه|ساعات",
        halfHourPhrases: ["نصف ساعه", "نص ساعه"],
        oneHourPhrases: ["لمده ساعه", "ساعه واحده", "ساعه"],
        cartPatterns: [
            #"^(?:اضف|ضيف|ضع|حط|احط|زود) (.+?) (?:الي|في|علي|ل)? ?(?:ال)?(?:سله التسوق|سله|عربه التسوق|عربه|سلتي)$"#,
            #"^(?:اضف|ضيف|ضع|حط) (.+?) (?:للسله|بالسله|لسلتي|للعربه)$"#,
        ],
        checklistPatterns: [
            #"^(?:اضف|ضيف|اكتب|سجل|حط|ضع) (.+?) (?:الي|في|علي|ل)? ?(?:ال)?(?:قائمه التسوق|قائمه المشتريات|قائمه|قائمتي|مشتريات)$"#,
            #"^(?:اضف|ضيف|اكتب|سجل|حط|ضع) (.+?) (?:للقائمه|بالقائمه|لقائمتي|لقائمه التسوق|للمشتريات)$"#,
            #"^(?:ذكرني ان اشتري|ذكرني اشتري|لازم اشتري|احتاج ان اشتري|احتاج اشتري|محتاج اشتري|يجب ان اشتري|اشتري|اشتر|نحتاج|لازم نشتري) (.+)$"#,
            #"^(?:خلص|خلصت|نفذ|نفذت|انتهي|انتهت|ما عندنا|ما في) (?:ال)?(.+)$"#,
        ],
        openPatterns: [
            #"^(?:افتح|افتحي|اعرض|اظهر|روح الي|روح علي|اذهب الي|ورني|خذني الي|انتقل الي)(?: لي)? (?:صفحه |شاشه )?(?:ال)?(.+)$"#,
        ],
        screenNoise: ["صفحه", "شاشه", "تبويب"],
        screens: [
            (.home, ["رئيسيه", "صفحه الرئيسيه", "يوم", "ملخص", "بدايه"]),
            (.meals, ["وجبات", "خطه الوجبات", "خطه الاكل", "جدول الوجبات", "خطه", "وصفات"]),
            (.shop, ["متجر", "سوق", "محل", "منتجات", "كتالوج"]),
            (.train, ["تمارين", "تدريب", "رياضه", "لياقه"]),
            (.cart, ["سله", "عربه", "سله التسوق", "سلتي"]),
            (.checklist, ["قائمه", "قائمه التسوق", "قائمه المشتريات", "مشتريات", "قائمتي"]),
            (.profile, ["ملف الشخصي", "ملفي", "اعدادات", "حساب", "حسابي"]),
            (.logFood, ["سجل الطعام", "سجل الاكل", "تسجيل الطعام"]),
            (.chat, ["محادثه", "شات", "مساعد"]),
            (.scan, ["ماسح", "ماسح الباركود", "باركود", "كاميرا"]),
        ],
        mealPrefix: #"(?:علي|في|مع|عند|ك|ل)? ?"#,
        mealSuffix: #"(?: اليوم| الصبح| الليله)?"#,
        meals: [
            (.breakfast, ["للفطور", "الفطور", "فطور", "للافطار", "الافطار", "افطار", "فطوري"]),
            (.lunch, ["للغداء", "الغداء", "غداء", "للغدا", "الغدا", "غدا", "غدائي"]),
            (.dinner, ["للعشاء", "العشاء", "عشاء", "للعشا", "العشا", "عشا", "عشائي"]),
            (.snack, ["كوجبه خفيفه", "وجبه خفيفه", "للسناك", "سناك", "تصبيره", "للتصبيره", "كسناك"]),
        ],
        foodVerbs: [
            "لقد اكلت", "انا اكلت", "اكلت للتو", "اكلت الان", "اكلت", "تناولت", "لقد تناولت", "شربت", "لقد شربت", "انا شربت",
            "سجل اني اكلت", "سجلي", "سجل", "اضف", "ضيف", "دون", "اكتب", "كلت", "اكلنا", "افطرت", "تغديت", "تعشيت",
        ].sorted { $0.count > $1.count },
        separators: #" (?:ثم|زائد|وكمان|وايضا|وكذلك|مع جانب من) "#,
        amountRewrites: [
            // Dual forms carry their own "two".
            (#"(?<=^| )بيضتين(?= |$)|(?<=^| )بيضتان(?= |$)"#, "2 بيضه"), (#"(?<=^| )تفاحتين(?= |$)"#, "2 تفاح"), (#"(?<=^| )موزتين(?= |$)"#, "2 موز"),
            (#"(?<=^| )كوبين(?= |$)"#, "2 كوب"), (#"(?<=^| )ملعقتين(?= |$)"#, "2 ملعقه"), (#"(?<=^| )شريحتين(?= |$)"#, "2 شريحه"),
            (#"(?<=^| )قطعتين(?= |$)"#, "2 قطعه"), (#"(?<=^| )حبتين(?= |$)"#, "2 حبه"), (#"(?<=^| )كاسين(?= |$)"#, "2 كاس"),
            (#"(?<=^| )علبتين(?= |$)"#, "2 علبه"), (#"(?<=^| )تمرتين(?= |$)"#, "2 تمر"), (#"(?<=^| )رغيفين(?= |$)"#, "2 رغيف"),
            // Spoon sizes are two words.
            (#"(?<=^| )(?:ملعقه|ملاعق) (?:كبيره|طعام|اكل)(?= |$)"#, "ملعقهكبيره"), (#"(?<=^| )(?:ملعقه|ملاعق) (?:صغيره|شاي)(?= |$)"#, "ملعقهصغيره"),
            (#"(\d+) ونصف"#, "$1.5"), (#"(\d+) ونص(?= |$)"#, "$1.5"), (#"(\d+) وربع"#, "$1.25"),
            (#"(?<=^| )(?:نصف|نص)(?= |$)"#, "0.5"), (#"(?<=^| )ربع(?= |$)"#, "0.25"), (#"(?<=^| )(?:شويه|قليل من|بعض)(?= |$)"#, ""),
            // "And" written onto the next word, except in words that begin with و themselves.
            (#" و(?!جبه|جبات|رق|افل|احد|احده)(?=[\p{L}\d]{2,})"#, " , "),
        ],
        units: [
            "غرام": .gram, "جرام": .gram, "غ": .gram, "جم": .gram, "غم": .gram, "غرامات": .gram, "جرامات": .gram,
            "كيلو": .kilogram, "كيلوغرام": .kilogram, "كيلوجرام": .kilogram, "كغ": .kilogram, "كجم": .kilogram,
            "مل": .millilitre, "ملليلتر": .millilitre, "مليلتر": .millilitre, "ملي": .millilitre,
            "لتر": .litre, "ليتر": .litre,
            "كوب": .cup, "اكواب": .cup, "فنجان": .cup, "مج": .cup,
            "ملعقهكبيره": .tablespoon, "ملعقه": .tablespoon, "ملاعق": .tablespoon,
            "ملعقهصغيره": .teaspoon,
            "كاس": .glass, "كاسه": .glass, "كوبايه": .glass,
            "صحن": .bowl, "طبق": .bowl, "زبديه": .bowl, "سلطانيه": .bowl,
            "علبه": .can, "علب": .can,
            "زجاجه": .bottle, "قاروره": .bottle, "قنينه": .bottle, "ازازه": .bottle,
            "شريحه": .slice, "شرايح": .slice, "شريحتين": .slice,
            "قطعه": .piece, "قطع": .piece, "حبه": .piece, "حبات": .piece, "رغيف": .piece,
            "حفنه": .handful, "قبضه": .handful,
            "حصه": .serving, "حصص": .serving,
        ],
        ofWords: ["من"],
        oneArticles: [],
        leadingNoise: ["حوالي", "تقريبا", "من", "نحو", "قرابه"],
        trailingNoise: ["اليوم", "الان", "ايضا", "كمان", "فضلك", "سمحت"],
        numbers: [
            "صفر": 0, "واحد": 1, "واحده": 1, "اثنين": 2, "اثنان": 2, "اثنتين": 2, "اتنين": 2, "ثنتين": 2,
            "ثلاث": 3, "ثلاثه": 3, "تلاته": 3, "اربع": 4, "اربعه": 4, "خمس": 5, "خمسه": 5, "ست": 6, "سته": 6,
            "سبع": 7, "سبعه": 7, "ثمان": 8, "ثماني": 8, "ثمانيه": 8, "تمانيه": 8, "تسع": 9, "تسعه": 9,
            "عشر": 10, "عشره": 10, "احد عشر": 11, "اثنا عشر": 12, "عشرين": 20, "عشرون": 20, "ثلاثين": 30, "ثلاثون": 30,
            "اربعين": 40, "اربعون": 40, "خمسين": 50, "خمسون": 50, "ستين": 60, "ستون": 60, "سبعين": 70, "سبعون": 70,
            "ثمانين": 80, "ثمانون": 80, "تسعين": 90, "تسعون": 90, "مئتين": 200, "ميتين": 200, "مئتان": 200,
            "ثلاثمئه": 300, "ثلاثميه": 300, "اربعمئه": 400, "خمسمئه": 500, "خمسميه": 500,
        ],
        hundredWords: ["مئه", "ميه", "مايه", "مائه"],
        numberJoiners: [],
        attachedJoiner: "و",
        foods: [
            VoiceTranslation("greek yogurt", "زبادي يوناني", "لبن يوناني"), VoiceTranslation("chicken breast", "صدر دجاج", "صدور دجاج", "صدر الدجاج"),
            VoiceTranslation("olive oil", "زيت زيتون", "زيت الزيتون"), VoiceTranslation("peanut butter", "زبده فول سوداني", "زبده الفول السوداني"),
            VoiceTranslation("orange juice", "عصير برتقال", "عصير البرتقال"), VoiceTranslation("apple juice", "عصير تفاح"),
            VoiceTranslation("ground beef", "لحم مفروم", "لحمه مفرومه"), VoiceTranslation("french fries", "بطاطس مقليه", "بطاطا مقليه"),
            VoiceTranslation("ice cream", "ايس كريم", "بوظه", "مثلجات"), VoiceTranslation("cottage cheese", "جبنه قريش", "جبن قريش"),
            VoiceTranslation("sweet potato", "بطاطا حلوه", "بطاطس حلوه"), VoiceTranslation("protein shake", "مخفوق بروتين", "بروتين شيك", "شيك بروتين"),
            VoiceTranslation("lentil soup", "شوربه عدس", "شوربه العدس"), VoiceTranslation("pita bread", "خبز عربي", "خبز لبناني", "خبز بلدي"),
            VoiceTranslation("egg", "بيضه", "بيض", "بيضات"), VoiceTranslation("bread", "خبز", "عيش", "رغيف"), VoiceTranslation("bread white toasted", "توست"),
            VoiceTranslation("milk", "حليب", "لبن"), VoiceTranslation("butter", "زبده"), VoiceTranslation("cheese", "جبن", "جبنه", "اجبان"),
            VoiceTranslation("yogurt", "زبادي", "روب", "لبن زبادي"), VoiceTranslation("labneh", "لبنه"),
            VoiceTranslation("chicken breast", "دجاج", "فراخ", "دجاجه"), VoiceTranslation("turkey breast", "ديك رومي", "حبش"),
            VoiceTranslation("beef", "لحم بقري", "لحم بقر", "لحم", "لحمه"), VoiceTranslation("lamb", "لحم ضان", "لحم خروف", "خروف"),
            VoiceTranslation("beef steak", "ستيك", "شريحه لحم"), VoiceTranslation("salmon", "سلمون"), VoiceTranslation("tuna", "تونه", "تونا"),
            VoiceTranslation("fish", "سمك", "سمكه"), VoiceTranslation("shrimp", "جمبري", "روبيان", "قريدس"),
            VoiceTranslation("rice", "ارز", "رز"), VoiceTranslation("pasta", "معكرونه", "مكرونه", "باستا"), VoiceTranslation("potato", "بطاطس", "بطاطا"),
            VoiceTranslation("lentils", "عدس"), VoiceTranslation("beans", "فاصوليا", "فول", "لوبيا"), VoiceTranslation("chickpeas", "حمص حب", "حمص مسلوق"),
            VoiceTranslation("hummus", "حمص"), VoiceTranslation("falafel", "فلافل", "طعميه"), VoiceTranslation("oatmeal", "شوفان"),
            VoiceTranslation("apple", "تفاح", "تفاحه"), VoiceTranslation("banana", "موز", "موزه"), VoiceTranslation("orange", "برتقال", "برتقاله"),
            VoiceTranslation("dates", "تمر", "تمور", "تمره", "تمرات", "بلح"), VoiceTranslation("strawberries", "فراوله"), VoiceTranslation("grapes", "عنب"),
            VoiceTranslation("watermelon", "بطيخ"), VoiceTranslation("mango", "مانجو", "مانجا"), VoiceTranslation("avocado", "افوكادو"),
            VoiceTranslation("tomato", "طماطم", "بندوره"), VoiceTranslation("cucumber", "خيار"), VoiceTranslation("carrot", "جزر"),
            VoiceTranslation("onion", "بصل"), VoiceTranslation("pepper", "فلفل"), VoiceTranslation("spinach", "سبانخ"), VoiceTranslation("lettuce salad", "سلطه", "سلطه خضراء", "خس"),
            VoiceTranslation("almonds", "لوز"), VoiceTranslation("walnuts", "جوز", "عين جمل"), VoiceTranslation("nuts", "مكسرات"), VoiceTranslation("peanuts", "فول سوداني"),
            VoiceTranslation("honey", "عسل"), VoiceTranslation("jam", "مربي"), VoiceTranslation("sugar", "سكر"),
            VoiceTranslation("milk chocolate candy", "شوكولاته", "شوكولا", "شكولاته"), VoiceTranslation("cookie", "بسكويت", "كوكيز"), VoiceTranslation("cake", "كيك", "كعكه"),
            VoiceTranslation("pizza", "بيتزا"), VoiceTranslation("hamburger", "برجر", "برغر", "همبرجر"), VoiceTranslation("sandwich", "ساندويتش", "سندويش", "شطيره"),
            VoiceTranslation("soup", "شوربه", "حساء"), VoiceTranslation("coffee", "قهوه"), VoiceTranslation("tea hot leaf black", "شاي"),
            VoiceTranslation("water", "ماء", "مياه", "ميه", "مويه"), VoiceTranslation("juice", "عصير"), VoiceTranslation("cola", "كولا", "بيبسي"),
            VoiceTranslation("oil", "زيت"), VoiceTranslation("cream", "كريمه", "قشطه"), VoiceTranslation("olives", "زيتون"),
        ],
        wordPrefixes: ["ال", "لل", "بال", "وال"]
    )
}
