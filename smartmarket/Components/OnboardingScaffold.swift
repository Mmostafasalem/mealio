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
                        .frame(width: geo.size.width * vm.progress(of: step))
                }
            }
            .frame(height: 4)

            Text("\(vm.number(of: step)) / \(vm.totalSteps)" as String)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.labelSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(vm.number(of: step)) of \(vm.totalSteps)" as String)
    }
}

// MARK: - Next button

/// The pinned primary action. Pushes the screen after `from` onto the onboarding
/// path, or finishes onboarding ("Get started") when `from` is the last screen
/// the chosen features need.
struct OnboardingNextButton: View {
    @Bindable var vm: OnboardingViewModel
    let from: OnboardingStep
    let identifier: String

    var body: some View {
        Button { vm.continueFrom(from) } label: {
            Text(vm.step(after: from) == nil ? "Get started" : "Next").primaryButtonLabel()
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Option row

/// A choice card: icon tile, title and optional detail. For a single choice the
/// outline alone shows it; `multiSelect` (several can be on) adds a check box.
struct OnboardingOptionRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var multiSelect = false
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
                    .background(Color.surfaceSecondary,
                                in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: Spacing.sm)

                if let trailing {
                    Text(trailing)
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                if multiSelect { checkBox }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(minHeight: 68)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.progress : Color.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
        .animation(reduceMotion ? .reducedFade : .snappyValue, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A rounded check box: filled with a white tick when on, an empty outline when off.
    private var checkBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isSelected ? Color.progress : Color.labelTertiary, lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.progress)
                .opacity(isSelected ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.onAccent)
                .scaleEffect(isSelected ? 1 : 0.4)
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
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
