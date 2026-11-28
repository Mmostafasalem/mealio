import Foundation

/// Cuts Chinese and Japanese, which are written without spaces, into the words
/// a lexicon knows, so the rule book can read them like any other language.
///
/// At each character the longest known word starting there wins ("三文鱼",
/// salmon, before the numeral "三"). A run of numerals that no word covers
/// becomes digits ("两" → "2", "三十" → "30"), and a counter right after a
/// number goes ("两个鸡蛋" → "2 鸡蛋", "卵2個" → "卵 2"). Characters no word
/// covers stay together as one unknown word. Latin letters and digits keep
/// their own spaces.
nonisolated struct VoiceSegmenter {
    /// Words the patterns use that no other list holds ("购物车", "加到").
    var extraWords: [String] = []
    /// Counting words dropped after a number: 个, 只, 個, つ, 本, 枚 …
    var counters: Set<String> = []
    /// Particles dropped wherever they stand on their own (を, は, 的 …).
    var dropped: Set<String> = []

    /// Numerals written as characters, and what each is worth.
    static let digits: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "兩": 2, "三": 3, "四": 4, "五": 5,
        "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    static let multipliers: [Character: Int] = ["十": 10, "百": 100, "千": 1000]

    func segment(_ text: String, vocabulary: Set<String>) -> String {
        let longest = vocabulary.map(\.count).max() ?? 1
        let chars = Array(text)
        var tokens: [String] = []
        var unknown = ""
        var latin = ""
        func flush() {
            if !unknown.isEmpty { tokens.append(unknown); unknown = "" }
            if !latin.isEmpty { tokens.append(latin); latin = "" }
        }
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == " " {
                flush()
                index += 1
                continue
            }
            guard Self.isWrittenWithoutSpaces(char) else {
                if !unknown.isEmpty { tokens.append(unknown); unknown = "" }
                latin.append(char)
                index += 1
                continue
            }
            if !latin.isEmpty { tokens.append(latin); latin = "" }
            // The longest known word starting here.
            // A counter counts as a word only right after a number ("2個").
            let afterNumber = unknown.isEmpty && tokens.last.flatMap(Double.init) != nil
            var word: String?
            for length in stride(from: min(max(longest, 2), chars.count - index), through: 1, by: -1) {
                let candidate = String(chars[index..<(index + length)])
                if vocabulary.contains(candidate) || dropped.contains(candidate) || (afterNumber && counters.contains(candidate)) {
                    word = candidate
                    break
                }
            }
            let numeral = Self.numeralRun(chars, from: index)
            if let numeral, numeral.length > (word?.count ?? 0) {
                if !unknown.isEmpty { tokens.append(unknown); unknown = "" }
                tokens.append(numeral.value == numeral.value.rounded() ? String(Int(numeral.value)) : String(numeral.value))
                index += numeral.length
                // "两个", "2個": the counter after a number says nothing more.
                if let counter = counters.sorted(by: { $0.count > $1.count }).first(where: { Self.starts(chars, at: index, with: $0) }) {
                    index += counter.count
                }
                continue
            }
            if let word {
                if !unknown.isEmpty { tokens.append(unknown); unknown = "" }
                let isCounter = counters.contains(word) && tokens.last.flatMap(Double.init) != nil
                if !isCounter && !dropped.contains(word) { tokens.append(word) }
                index += word.count
                continue
            }
            unknown.append(char)
            index += 1
        }
        flush()
        // A counter after digits that came in as digits ("2个"): drop it too.
        var result: [String] = []
        for token in tokens {
            if counters.contains(token), let last = result.last, Double(last) != nil { continue }
            if dropped.contains(token) { continue }
            result.append(token)
        }
        return result.joined(separator: " ")
    }

    /// Full-width digits and Latin letters as plain ones ("２個" → "2個"); kana stay as they are.
    static func plainDigits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0xFF01...0xFF5E).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0xFEE0) ?? scalar : scalar
        }))
    }

    /// Writes words the segmenter cut apart together again: "全麦 面包" → "全麦面包".
    static func rejoin(_ text: String) -> String {
        var output = ""
        let chars = Array(text)
        for (index, char) in chars.enumerated() {
            if char == " ", index > 0, index + 1 < chars.count,
               isWrittenWithoutSpaces(chars[index - 1]), isWrittenWithoutSpaces(chars[index + 1]) {
                continue
            }
            output.append(char)
        }
        return output
    }

    /// Han characters, hiragana, katakana and the long vowel mark.
    static func isWrittenWithoutSpaces(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF66...0xFF9F: return true
            default: return false
            }
        }
    }

    private static func starts(_ chars: [Character], at index: Int, with word: String) -> Bool {
        let word = Array(word)
        guard index + word.count <= chars.count else { return false }
        return Array(chars[index..<(index + word.count)]) == word
    }

    /// The numerals starting at `index`: "三十五" is 35, "两" is 2, "半" alone is a half.
    static func numeralRun(_ chars: [Character], from index: Int) -> (value: Double, length: Int)? {
        if chars[index] == "半" { return (0.5, 1) }
        var length = 0
        var total = 0
        var current = 0
        var sawDigit = false
        while index + length < chars.count {
            let char = chars[index + length]
            if let digit = digits[char] {
                current = current * 10 + digit
                sawDigit = true
            } else if let multiplier = multipliers[char] {
                total += max(current, 1) * multiplier
                current = 0
                sawDigit = true
            } else {
                break
            }
            length += 1
        }
        guard sawDigit, length > 0 else { return nil }
        return (Double(total + current), length)
    }
}
