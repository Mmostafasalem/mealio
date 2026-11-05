import SwiftUI

/// Home hero header — greeting, avatar, date, and a quick-stats strip.
/// Presentation only; reads from the shared `HomeViewModel`.
struct HomeHeaderView: View {
    let vm: HomeViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color.brandHeader, Color.brandHeaderMid],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)

            // Decorative blurred circle
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 200, height: 200)
                .offset(x: 140, y: -30)
                .blur(radius: 20)

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    avatar

                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting)
                            .font(.caption).fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(profileName.isEmpty ? "Welcome!" : profileName)
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    if !NetworkMonitor.shared.isOnline { OfflineBadge() }
                    datePill
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, 58)
                .padding(.bottom, Spacing.xl)

                quickStatsStrip
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity)
        // Fade the header into the grouped background so cards appear to emerge.
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, Color.surfaceGrouped], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .allowsHitTesting(false)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(.white.opacity(0.2)).frame(width: 48, height: 48)
            Text(profileName.prefix(1).uppercased())
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    private var datePill: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Date(), format: .dateTime.weekday(.abbreviated))
                .font(.caption2).foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
            Text(Date(), format: .dateTime.day().month(.abbreviated))
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }

    private var quickStatsStrip: some View {
        HStack(spacing: 0) {
            quickStat(label: "Today", value: "\(vm.consumed) kcal", icon: "flame.fill", color: .brandAmber)
            statDivider
            quickStat(label: "Goal", value: "\(vm.goal) kcal", icon: "target", color: .white)
            statDivider
            quickStat(label: "Catalog", value: "\(vm.nearbyDeals.count) items",
                      icon: "basket.fill", color: Color(hex: "#86EFAC"), isRefreshing: vm.isRefreshing)
        }
    }

    private var statDivider: some View {
        Divider().frame(height: 30).overlay(Color.white.opacity(0.2))
    }

    private func quickStat(label: String, value: String, icon: String, color: Color, isRefreshing: Bool = false) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.xs) {
                    Text(value)
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.white)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText())
                    if isRefreshing {
                        ProgressView().scaleEffect(0.45).tint(.white.opacity(0.7))
                    }
                }
                Text(label).font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappyValue, value: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Helpers

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var profileName: String {
        let name = AppState.shared.userProfile.name
        return name.isEmpty ? "there" : name
    }
}
