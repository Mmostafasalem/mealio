import SwiftUI

/// Today's three quests, the streak and this week's days. Quests tick
/// themselves as the person logs food, trains or shops; a row takes them to
/// where it gets done.
struct DailyQuestCard: View {
    let state: LoopState
    var onOpen: (QuestDestination) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var doneCount: Int { state.quests.filter(\.isDone).count }

    private var subtitle: String {
        if state.perfectToday { return "3 for 3. Nourlo is thrilled." }
        if state.todayKept { return "Today counts. Go for a perfect day?" }
        return "One quest and today counts."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HomeCardTitle(title: "Today's quests", symbol: "checkmark.seal.fill")
                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.labelSecondary)
                        .padding(.leading, HomeGrid.textInset)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)
                streakBadge
            }

            VStack(spacing: Spacing.sm) {
                ForEach(state.quests) { quest in
                    Button { onOpen(quest.destination) } label: { QuestRow(quest: quest) }
                        .buttonStyle(ScalePressStyle())
                        .accessibilityIdentifier("quest.\(quest.id.rawValue)")
                }
            }

            WeekDots(days: state.week)
                .padding(.leading, HomeGrid.textInset)
        }
        .padding(Spacing.lg)
        .premiumCard()
        .animation(reduceMotion ? nil : .snappyValue, value: doneCount)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.quests")
    }

    private var streakBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if state.streak == 0 {
                Text("Start a streak")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.labelSecondary)
            } else {
                HStack(spacing: 4) {
                    Text("\(state.streak)")
                        .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(state.streak == 1 ? "day" : "days")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            if state.saversHeld > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<state.saversHeld, id: \.self) { _ in
                        Image(systemName: "shield.fill").font(.caption2)
                    }
                    Text("saver\(state.saversHeld == 1 ? "" : "s")").font(.caption2.weight(.medium))
                }
                .foregroundStyle(Color.brandPrimary)
            }
        }
        .foregroundStyle(Color.labelPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((state.streak == 0 ? "No streak yet" : "\(state.streak)-day streak") + (state.saversHeld > 0 ? ", \(state.saversHeld) streak saver\(state.saversHeld == 1 ? "" : "s")" : ""))
        .accessibilityIdentifier("quests.streak")
    }
}

private struct QuestRow: View {
    let quest: Quest

    private var progressText: String {
        if quest.isDone { return "Done" }
        if quest.goal <= 1 { return "To do" }
        let unit = quest.unit.isEmpty ? "" : " \(quest.unit)"
        return "\(Int(quest.current)) / \(Int(quest.goal))\(unit)"
    }

    var body: some View {
        HStack(spacing: HomeGrid.gap) {
            ZStack {
                Circle().fill(quest.isDone ? Color.progress : Color.surface)
                Circle().strokeBorder(quest.isDone ? Color.clear : Color.hairline, lineWidth: 1)
                Image(systemName: quest.isDone ? "checkmark" : quest.symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(quest.isDone ? Color.onAccent : Color.labelPrimary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: HomeGrid.icon, height: HomeGrid.icon)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(quest.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(quest.isDone ? Color.labelSecondary : Color.labelPrimary)
                        .lineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    Text(progressText)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(quest.isDone ? Color.labelPrimary : Color.labelSecondary)
                        .contentTransition(.numericText())
                }
                if quest.goal > 1 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.progressTrack)
                            Capsule().fill(Color.progress).frame(width: geo.size.width * quest.fraction)
                        }
                    }
                    .frame(height: 5)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.labelSecondary.opacity(0.6))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quest, \(quest.title), " + (quest.goal > 1 ? "\(Int(quest.current)) of \(Int(quest.goal)) \(quest.unit), " : "") + (quest.isDone ? "done" : "not done"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct WeekDots: View {
    let days: [WeekDot]
    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, dot in
                VStack(spacing: 4) {
                    marker(dot).frame(width: 20, height: 20)
                    Text(Self.letters[index % 7])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(days.filter { $0 == .kept || $0 == .today(kept: true) }.count) days counted")
    }

    @ViewBuilder private func marker(_ dot: WeekDot) -> some View {
        switch dot {
        case .kept, .today(kept: true):
            Circle().fill(Color.progress)
                .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.onAccent))
        case .saved:
            Circle().fill(Color.progress.opacity(0.25))
                .overlay(Image(systemName: "shield.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.labelPrimary))
        case .today(kept: false):
            Circle().strokeBorder(Color.progress, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        case .open:
            Circle().strokeBorder(Color.hairline, lineWidth: 1.5)
        case .future:
            Circle().fill(Color.hairline.opacity(0.5)).frame(width: 6, height: 6)
        }
    }
}
