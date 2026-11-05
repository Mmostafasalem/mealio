import SwiftUI

// MARK: - Shared press style
//
// Tactile scale + opacity on press, used by the app's buttons. (The card-level
// `pressable()` in ViewModifiers.swift scales only; this adds the opacity dip
// that reads well on filled/tinted buttons.)

struct ScalePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? .none : .snappyValue, value: configuration.isPressed)
    }
}

// MARK: - Primary button
//
// Filled brand CTA. Handles disabled + inline loading (prevents double-submit),
// keeps a ≥52pt height for a comfortable tap target, and is Dynamic-Type safe.

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView().tint(Color.onAccent)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(Color.onAccent)
            .background(
                Color.coral,
                in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .disabled(isLoading)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Secondary button
//
// Tinted, low-emphasis action. Same ergonomics as PrimaryButton.

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(Color.brandPrimary)
            .background(
                Color.brandPrimary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
    }
}

// MARK: - Primary CTA label styling
//
// For use inside a NavigationLink (where a Button action isn't available) so its
// label matches PrimaryButton's filled look. Pass `enabled: false` for a disabled
// appearance.

extension View {
    func primaryButtonLabel(enabled: Bool = true) -> some View {
        self
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(Color.onAccent)
            .background(
                Color.coral,
                in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
            )
            .opacity(enabled ? 1 : 0.45)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        PrimaryButton(title: "Get Started", systemImage: "arrow.right") {}
        PrimaryButton(title: "Loading", isLoading: true) {}
        PrimaryButton(title: "Disabled") {}.disabled(true)
        SecondaryButton(title: "Maybe later", systemImage: "clock") {}
    }
    .padding()
}
