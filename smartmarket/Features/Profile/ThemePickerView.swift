import SwiftUI

/// Profile › Appearance: the colour theme, as a row of round swatches under the lamp.
/// A tap switches the whole app at once (with a short cross-fade and a tick).
struct ThemePickerView: View {
    @State private var store = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: Spacing.sm, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Colour").font(.subheadline.weight(.semibold))
                Spacer()
                Text(store.theme.name)
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                    .accessibilityHidden(true)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
                ForEach(AppTheme.allCases) { theme in swatch(theme) }
            }
        }
        .sensoryFeedback(.selection, trigger: store.theme)
    }

    private func swatch(_ theme: AppTheme) -> some View {
        let chosen = store.theme == theme
        let colors = ThemeStore.colors(for: theme)
        return Button {
            guard !chosen else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { store.theme = theme }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(colors.accent)
                    Circle().strokeBorder(Color.labelPrimary.opacity(0.12), lineWidth: 1)
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.system(size: side * 0.4, weight: .bold))
                            .foregroundStyle(colors.onAccent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: side, height: side)
                .padding(3)
                .overlay(Circle().strokeBorder(chosen ? Color.labelPrimary : .clear, lineWidth: 2))
                Text(theme.name)
                    .font(.caption2)
                    .foregroundStyle(chosen ? Color.labelPrimary : Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.name)
        .accessibilityHint(chosen ? "" : "Changes Nourlo's colour")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("profile.theme." + theme.rawValue)
    }
}
