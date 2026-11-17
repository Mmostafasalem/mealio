import SwiftUI

// MARK: - Type a number instead of dragging
//
// Every ruler has one of these beside it: a small "Type" button that asks for
// the number in a dialog with the number keyboard. The caller turns the text
// into its own value (units, range, step) in `apply`.

struct TypeNumberButton: View {
    /// The dialog's title, e.g. "Your weight".
    let title: String
    /// What the number is in, shown as the placeholder and the hint: "kg", "minutes".
    let unit: String
    /// The current value as text, so the field starts filled.
    let current: String
    var hint: String? = nil
    var keyboard: UIKeyboardType = .decimalPad
    var identifier: String = "typeNumber"
    let apply: (String) -> Void

    @State private var showing = false
    @State private var text = ""

    var body: some View {
        Button {
            text = ""
            showing = true
        } label: {
            Label("Type", systemImage: "keyboard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Color.surfaceElevated, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel("Type \(title.lowercased())")
        .accessibilityIdentifier(identifier)
        .alert(title, isPresented: $showing) {
            // Empty, with the current value as the hint, so typing replaces it.
            TextField(current.isEmpty ? unit : current, text: $text)
                .keyboardType(keyboard)
                .accessibilityIdentifier(identifier + ".field")
            Button("Cancel", role: .cancel) {}
            Button("Set") { if !text.isEmpty { apply(text) } }
                .accessibilityIdentifier(identifier + ".set")
        } message: {
            Text(hint ?? "Enter a number in \(unit).")
        }
    }
}

enum TypedNumber {
    /// "72,5" and "72.5" both read as 72.5; anything without a number is nil.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let match = cleaned.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(cleaned[match])
    }

    /// A height in feet and inches as total inches: "5'11", "5 11", "5ft 11in", "5.11" → 71;
    /// one small number is feet ("6" → 72), one large number is inches ("70" → 70).
    static func inches(_ text: String) -> Double? {
        let numbers = text.replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted)
            .filter { !$0.isEmpty }.compactMap(Double.init)
        switch numbers.count {
        case 0: return nil
        case 1: return numbers[0] <= 8 ? numbers[0] * 12 : numbers[0]
        default: return numbers[0] * 12 + min(numbers[1], 11)
        }
    }

    /// Clamped to the range and rounded to the step, so a typed value lands on a ruler tick.
    static func fitted(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let snapped = (value / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}
