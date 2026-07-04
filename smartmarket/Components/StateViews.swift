import SwiftUI

// MARK: - Empty state
//
// Friendly "nothing here yet" placeholder built on iOS 17 ContentUnavailableView.
// SF Symbols only. Optional call-to-action.

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
            }
        }
    }
}

// MARK: - Error state
//
// Error message + Retry. Distinct destructive-tinted icon so it doesn't read
// like a normal empty state.

struct ErrorStateView: View {
    var title: String = "Something went wrong"
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.brandDanger)
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
            }
        }
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
        EmptyStateView(icon: "tag", title: "No deals nearby",
                       message: "Check back soon for fresh discounts.",
                       actionTitle: "Refresh") {}
    }
    .padding()
}
