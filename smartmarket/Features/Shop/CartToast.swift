import SwiftUI

// MARK: - Cart toast
//
// The floating "View cart" card over the catalogue, like the cart bar in Uber Eats
// or DoorDash: a rounded, elevated brand-coloured card with side margins, above
// the tab bar. It springs up when the cart gets its first item, gives a small bounce
// each time an item is added, and goes when the cart is empty. Put it in the list's
// `safeAreaInset(edge: .bottom)` so the last rows can scroll clear of it.
// Reduce Motion: it fades in and out and doesn't bounce.

struct CartToast: View {
    @State private var cart = ShoppingCartService.shared
    /// Counts additions, to bounce the card.
    @State private var bumps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Own container so the insert/remove animation is scoped to the card.
        VStack(spacing: 0) {
            if cart.itemCount > 0 {
                card
                    .padding(.leading, Spacing.lg)
                    .padding(.trailing, Spacing.lg + QuickActionsDock.trailingClearance)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                    .transition(reduceMotion ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94, anchor: .bottom)))
            }
        }
        .animation(reduceMotion ? .reducedFade : .spring(response: 0.42, dampingFraction: 0.74), value: cart.itemCount > 0)
        .onChange(of: cart.itemCount) { old, new in
            if new > old, old > 0, !reduceMotion { bumps &+= 1 }
        }
    }

    private var budgetHint: String? {
        guard cart.budgetFraction > 0.01 else { return nil }
        return cart.budgetRemaining < 0
            ? (Money.format(eur: -cart.budgetRemaining) + " over budget")
            : "\(Int(cart.budgetFraction * 100))% of budget"
    }

    private var card: some View {
        NavigationLink(destination: CartView()) {
            HStack(spacing: Spacing.md) {
                Text("\(cart.itemCount)" as String)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(cart.itemCount)))
                    .foregroundStyle(Color.progress)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 32, minHeight: 32)
                    .background(Color.onAccent, in: Capsule())

                VStack(alignment: .leading, spacing: 1) {
                    Text("View cart")
                        .font(.headline)
                    if let budgetHint {
                        Label(budgetHint, systemImage: cart.budgetRemaining < 0 ? "exclamationmark.circle.fill" : "chart.pie.fill")
                            .font(.caption2.weight(.medium))
                            .labelStyle(BudgetLabelStyle())
                            .opacity(0.78)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    }
                }

                Spacer(minLength: Spacing.sm)

                Text(Money.format(eur: cart.total))
                    .font(.headline.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText(value: cart.total))
                    .lineLimit(1)
                    .fixedSize()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.7)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.onAccent)
            .padding(.leading, Spacing.md)
            .padding(.trailing, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(minHeight: 60)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.progress)
                    .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .animation(reduceMotion ? nil : .snappyValue, value: cart.itemCount)
        }
        .buttonStyle(ScalePressStyle())
        .keyframeAnimator(initialValue: 1.0, trigger: bumps) { content, scale in
            content.scaleEffect(scale, anchor: .bottom)
        } keyframes: { _ in
            SpringKeyframe(1.045, duration: 0.12, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("View cart")
        .accessibilityValue("\(cart.itemCount) items, " + Money.format(eur: cart.total)
                            + (budgetHint.map { ", " + $0 } ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("shop.viewCart")
    }
}

private struct BudgetLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
