import SwiftUI

// MARK: - Number entry dialog
//
// A dialog with the number keyboard for typing a value instead of stepping to it
// (a food's amount, its calories). The field starts empty with the current value as
// its hint, so typing replaces it. An optional second button undoes an override.

private struct NumberEntry: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let current: String
    let message: String
    let keyboard: UIKeyboardType
    let identifier: String
    let resetTitle: String?
    let onReset: (() -> Void)?
    let apply: (String) -> Void

    @State private var text = ""

    func body(content: Content) -> some View {
        // Each dialog lives on its own background view: two alerts on one view show only one.
        content.background { Color.clear.alert(title, isPresented: $isPresented) {
            TextField(current, text: $text)
                .keyboardType(keyboard)
                .accessibilityIdentifier(identifier + ".field")
            Button("Cancel", role: .cancel) { text = "" }
            if let resetTitle, let onReset {
                Button(resetTitle) { text = ""; onReset() }
                    .accessibilityIdentifier(identifier + ".reset")
            }
            Button("Set") {
                let typed = text
                text = ""
                if !typed.trimmingCharacters(in: .whitespaces).isEmpty { apply(typed) }
            }
            .accessibilityIdentifier(identifier + ".set")
        } message: {
            Text(message)
        } }
    }
}

extension View {
    /// Shows a number dialog while `isPresented` is true; `apply` gets the typed text.
    func numberEntry(isPresented: Binding<Bool>, title: String, current: String, message: String,
                     keyboard: UIKeyboardType = .decimalPad, identifier: String,
                     resetTitle: String? = nil, onReset: (() -> Void)? = nil,
                     apply: @escaping (String) -> Void) -> some View {
        modifier(NumberEntry(isPresented: isPresented, title: title, current: current, message: message,
                             keyboard: keyboard, identifier: identifier, resetTitle: resetTitle,
                             onReset: onReset, apply: apply))
    }
}
