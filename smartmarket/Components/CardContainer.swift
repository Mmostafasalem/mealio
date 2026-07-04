import SwiftUI

// MARK: - Card container
//
// Standard elevated card surface with consistent padding. Wraps the existing
// `premiumCard()` so every card in the app shares one radius / shadow / inset.

struct CardContainer<Content: View>: View {
    var padding: CGFloat = Spacing.lg
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: alignment, spacing: Spacing.md) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .premiumCard()
    }
}

// MARK: - Section header
//
// Title + optional trailing action ("See all"). Uses the shared typography role.

struct AppSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(.primary)
            Spacer(minLength: Spacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandPrimary)
                    .buttonStyle(ScalePressStyle())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Stat pill
//
// Compact value + label chip (macros, quick stats). Tint carries meaning.

struct StatPill: View {
    let title: String
    let value: String
    var tint: Color = .brandPrimary

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.statValue)
                .foregroundStyle(tint)
            Text(title)
                .font(.captionText)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
