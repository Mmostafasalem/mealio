import SwiftUI

// MARK: - Shared layout
//
// One layout for the empty and error states, so sizes match everywhere: a
// quiet icon, a title in the label colour, a short message and a button of a
// comfortable fixed width (it never shrinks to its text).

private struct StateLayout: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, systemImage: actionIcon, action: action)
                    .frame(maxWidth: 260)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        // Centred in whatever space the screen gives it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty state
//
// Friendly "nothing here yet" placeholder. SF Symbols only. Optional call-to-action.

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        StateLayout(icon: icon, iconColor: .labelSecondary, title: title, message: message,
                    actionTitle: actionTitle, action: action)
    }
}

// MARK: - Error state
//
// Error message + Retry. Only the icon carries the danger tint, so it doesn't
// read like a normal empty state while the title stays easy to read.

struct ErrorStateView: View {
    var title: String = "Something went wrong"
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        StateLayout(icon: "exclamationmark.triangle.fill", iconColor: .brandDanger, title: title, message: message,
                    actionTitle: retry == nil ? nil : "Try Again", actionIcon: "arrow.clockwise", action: retry)
    }
}

// MARK: - Loading state
//
// Reusable shimmer skeleton — a stack of redacted rows. Use while first content
// loads so the screen is never blank.

struct LoadingStateView: View {
    var rows: Int = 4

    var body: some View {
        VStack(spacing: Spacing.md) {
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(Color.surfaceElevated)
                    .frame(height: 64)
                    .shimmer()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .accessibilityLabel("Loading")
    }
}

// MARK: - Offline badge
//
// Subtle "Offline" pill so cached/fallback content isn't mistaken for live data.

struct OfflineBadge: View {
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "wifi.slash")
            Text("Offline")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.brandAmber)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.brandAmberLight, in: Capsule())
        .accessibilityLabel("Offline — showing saved data")
    }
}

#Preview("States") {
    VStack(spacing: Spacing.xl) {
        OfflineBadge()
        LoadingStateView(rows: 2)
        EmptyStateView(icon: "basket", title: "No groceries nearby",
                       message: "Pull down to refresh.",
                       actionTitle: "Refresh") {}
    }
    .padding()
}
