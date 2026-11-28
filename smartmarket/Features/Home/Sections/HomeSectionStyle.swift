import SwiftUI

// MARK: - Home sections
//
// TestFlight B4: "everything here looks the same … it should clarify which part
// belongs to which, maybe more colors more icons, more charts, some call to action
// buttons". Each Home section has its own colour and icon badge, a tinted band
// behind its header, and one call-to-action button in that colour. The colours
// are the theme's macro-ring colours (mint, sky/gold, violet …), so they never
// clash with the accent, which stays for calories and the quick-actions button.

enum HomeSection {
    case meals, groceries, training, activity

    var color: Color {
        switch self {
        case .meals: return .ringProtein
        case .groceries: return .ringCarbs
        case .training, .activity: return .ringFat
        }
    }
}

/// A section's header: a filled icon badge in the section's colour, the title, and an optional line under it.
struct HomeSectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let section: HomeSection
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Color(white: 0.07))
                .frame(width: 40, height: 40)
                .background(section.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            trailing()
        }
    }
}

extension HomeSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String, section: HomeSection) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, section: section) { EmptyView() }
    }
}

/// The section's call to action: a full-width button filled with the section's colour.
struct HomeSectionButton: View {
    let title: String
    let symbol: String
    let section: HomeSection
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { HomeSectionButtonLabel(title: title, symbol: symbol, section: section, prominent: prominent) }
            .buttonStyle(ScalePressStyle())
    }
}

struct HomeSectionButtonLabel: View {
    let title: String
    let symbol: String
    let section: HomeSection
    var prominent = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(prominent ? Color(white: 0.07) : Color.labelPrimary)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(prominent ? section.color : section.color.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
    }
}

extension View {
    /// A Home section card: the shared card surface washed with the section's
    /// colour (a flat tint, no gradient), so each section reads as its own.
    func homeSectionCard(_ section: HomeSection) -> some View {
        self
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(section.color.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .premiumCard()
    }
}
