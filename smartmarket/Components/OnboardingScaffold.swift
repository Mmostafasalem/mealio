import SwiftUI

// MARK: - Onboarding scaffold
//
// The one frame every onboarding screen sits in: a round back button, a thin
// progress line with "3 / 11", one big question, the answer in the middle and
// the action pinned to the bottom. One question per screen, nothing to scroll.

struct OnboardingScaffold<Content: View, Footer: View>: View {

    @Bindable var vm: OnboardingViewModel
    let step: OnboardingStep
    let title: String
    var subtitle: String? = nil
    /// Side padding for the answer area; lists that run edge to edge pass 0.
    var contentPadding: CGFloat = Spacing.xl
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        GeometryReader { geo in
            // Keep the last action a thumb's width clear of the screen edge on
            // phones with and without a home indicator.
            page(bottomPadding: max(Spacing.lg, 40 - geo.safeAreaInsets.bottom))
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationBarHidden(true)
        // Screens are built to fit without scrolling, so very large text is capped here.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func page(bottomPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.lg)

            // Laid out as an overlay so tall content can never push the
            // pinned actions off the screen.
            Color.clear
                .overlay(alignment: .top) {
                    content()
                        .padding(.horizontal, contentPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .clipped()

            VStack(spacing: Spacing.sm) { footer() }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .padding(.bottom, bottomPadding)
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.lg) {
            Button {
                if !vm.path.isEmpty { vm.path.removeLast() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
            }
            .buttonStyle(ScalePressStyle())
            .accessibilityLabel("Back")
            .opacity(vm.path.isEmpty ? 0 : 1)
            .disabled(vm.path.isEmpty)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceSecondary)
                    Capsule().fill(Color.labelPrimary)
                        .frame(width: geo.size.width * step.progress)
                }
            }
            .frame(height: 4)

            Text("\(step.number) / \(OnboardingStep.total)")
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.labelSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(step.number) of \(OnboardingStep.total)")
    }
}

// MARK: - Next button

/// The pinned primary action. Pushes `next` onto the onboarding path.
struct OnboardingNextButton: View {
    @Bindable var vm: OnboardingViewModel
    let next: OnboardingStep
    var title: String = "Next"
    let identifier: String

    var body: some View {
        Button { vm.advance(to: next) } label: {
            Text(title).primaryButtonLabel()
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Option row

/// A single-choice card: icon tile, title, optional detail and a radio mark.
struct OnboardingOptionRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.brandLight : Color.surfaceSecondary,
                                in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: Spacing.sm)

                if let trailing {
                    Text(trailing)
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.labelSecondary)
                }

                ZStack {
                    Circle().strokeBorder(isSelected ? Color.progress : Color.labelTertiary, lineWidth: 1.5)
                    Circle().fill(Color.progress).padding(5).scaleEffect(isSelected ? 1 : 0.01).opacity(isSelected ? 1 : 0)
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(minHeight: 68)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.progress : Color.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
        .animation(reduceMotion ? .reducedFade : .snappyValue, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Stacks option rows, and only falls back to scrolling if they truly can't fit
/// (small phone with enlarged text).
struct OnboardingOptionList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: Spacing.md) { content() }
            ScrollView { VStack(spacing: Spacing.md) { content() } }
                .scrollIndicators(.hidden)
        }
    }
}

/// Big number with a small unit beside it, shown above a ruler.
struct OnboardingReadout: View {
    let number: String
    var unit: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(number)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.labelPrimary)
                .contentTransition(.numericText())
            if !unit.isEmpty {
                Text(unit)
                    .font(.title3)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .animation(.snappyValue, value: number)
        .accessibilityHidden(true)
    }
}
