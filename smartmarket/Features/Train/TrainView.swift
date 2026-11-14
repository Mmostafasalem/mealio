import SwiftUI
import Observation

// MARK: - Train tab
//
// Build a workout around your stats and what you ask for, keep the ones you
// like, tick them off, and browse the exercise library. Online AI writes the
// session when it's on and available; otherwise it's built on the phone.

@MainActor
@Observable
final class TrainViewModel {
    var kind: ExerciseKind = .home
    var level: ExerciseLevel = .beginner
    var focus: ExerciseFocus = .fullBody
    var minutes: Double = 30
    var wishes = ""

    private(set) var isGenerating = false
    /// Why the last session was built on the phone instead of by AI.
    private(set) var localReason: String?
    var generated: Workout?

    func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        let profile = AppState.shared.userProfile
        let request = WorkoutRequest(kind: kind, level: level, minutes: Int(minutes), focus: focus,
                                     wishes: wishes, profile: profile)
        do {
            generated = try await APIService.shared.generateWorkout(request)
            localReason = nil
        } catch {
            let hadWishes = !request.request.isEmpty
            if case APIError.aiConsentRequired = error {
                localReason = "Built on your phone. Turn on online AI in Profile to have sessions written around your request."
            } else {
                localReason = "Online AI wasn't available, so this was built on your phone."
                    + (hadWishes ? " Your note wasn't used." : "")
            }
            generated = WorkoutBuilder.build(kind: kind, level: level, minutes: Int(minutes),
                                             focus: focus, goal: profile.weightGoal)
        }
    }
}

struct TrainView: View {

    @State private var vm = TrainViewModel()
    @State private var store = WorkoutStore.shared
    @FocusState private var wishesFocused: Bool
    @State private var showLibrary = false
    @State private var guide: ExerciseGuide?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    weekCard
                    builderCard
                    if !store.saved.isEmpty { savedSection }
                    exerciseBrowser
                    if !store.completed.isEmpty {
                        NavigationLink { WorkoutHistoryView() } label: {
                            TrainLinkRow(symbol: "clock.fill", title: "History",
                                         detail: "\(store.completed.count) completed session\(store.completed.count == 1 ? "" : "s")")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { GrainyGradient().ignoresSafeArea() }
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showLibrary) { ExerciseLibraryView() }
            .sheet(item: $guide) { ExerciseGuideSheet(guide: $0) }
            .navigationDestination(item: $vm.generated) { workout in
                WorkoutDetailView(workout: workout, localReason: vm.localReason)
            }
        }
    }

    // MARK: Exercise browser

    /// The exercise library as a card you drill into in place:
    /// type → exercises → one exercise.
    private var exerciseBrowser: some View {
        var pages: [String: StackPanelPage] = [:]
        pages["root"] = StackPanelPage(title: "Exercises", sections: [
            StackPanelSection(rows: ExerciseKind.allCases.map { kind in
                StackPanelRow(id: kind.rawValue, label: kind.title, symbol: kind.symbol,
                              detail: "\(Exercise.catalog.filter { $0.kind == kind }.count)", to: "kind." + kind.rawValue)
            }),
            StackPanelSection(rows: [
                StackPanelRow(id: "search", label: "Search all exercises", symbol: "magnifyingglass",
                              action: { showLibrary = true }),
            ]),
        ])
        for kind in ExerciseKind.allCases {
            let exercises = Exercise.catalog.filter { $0.kind == kind }
            // Strength work is grouped by body area; cardio and mobility are one list.
            let groups: [(String?, [Exercise])] = exercises.contains { $0.focus != nil }
                ? ExerciseFocus.allCases.compactMap { focus in
                    let matching = exercises.filter { $0.focus == focus }
                    return matching.isEmpty ? nil : (focus.title, matching)
                }
                : [(nil, exercises)]
            pages["kind." + kind.rawValue] = StackPanelPage(title: kind.title, sections: groups.map { title, items in
                StackPanelSection(title: title, rows: items.map { exercise in
                    StackPanelRow(id: exercise.id, label: exercise.name, detail: exercise.level.title, to: "exercise." + exercise.id)
                })
            })
            for exercise in exercises {
                pages["exercise." + exercise.id] = StackPanelPage(title: exercise.name, sections: [
                    StackPanelSection(rows: [
                        StackPanelRow(id: exercise.id + ".works", label: "Works", detail: exercise.muscles),
                        StackPanelRow(id: exercise.id + ".kit", label: "Equipment", detail: exercise.equipment),
                        StackPanelRow(id: exercise.id + ".typical", label: "Typical", detail: exercise.prescription),
                    ]),
                    StackPanelSection(rows: [
                        StackPanelRow(id: exercise.id + ".howto", label: "Show how to do it", symbol: "play.circle.fill",
                                      action: { guide = ExerciseGuide(exercise: exercise) }),
                    ]),
                ])
            }
        }
        return StackPanel(pages: pages, root: "root")
    }

    // MARK: This week

    private var weekCard: some View {
        let week = store.thisWeek
        return HStack(spacing: Spacing.lg) {
            weekStat("\(week.count)", week.count == 1 ? "session" : "sessions")
            Divider().frame(height: 36)
            weekStat("\(week.reduce(0) { $0 + $1.minutes })", "minutes")
            Divider().frame(height: 36)
            weekStat("~\(week.reduce(0) { $0 + $1.calories })", "kcal")
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .premiumCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last 7 days: \(week.count) sessions, \(week.reduce(0) { $0 + $1.minutes }) minutes, about \(week.reduce(0) { $0 + $1.calories }) kilocalories")
    }

    private func weekStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.labelPrimary)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Builder

    private var builderCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Build a workout").font(.sectionTitle)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible())], spacing: Spacing.sm) {
                ForEach(ExerciseKind.allCases) { kind in
                    KindTile(kind: kind, isSelected: vm.kind == kind) { vm.kind = kind }
                }
            }

            VStack(spacing: Spacing.xs) {
                caption("Length")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(vm.minutes))")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("min").font(.headline).foregroundStyle(Color.labelSecondary)
                }
                .animation(.snappyValue, value: vm.minutes)
                .accessibilityHidden(true)
                RulerPicker(value: $vm.minutes, range: 10...90, step: 5, majorEvery: 2, midEvery: 1, spacing: 22,
                            accessibilityName: "Duration", spokenValue: { "\(Int($0)) minutes" })
                    .frame(height: 96)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                caption("Level")
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(ExerciseLevel.allCases) { level in
                        ChoiceChip(label: level.title, isSelected: vm.level == level) { vm.level = level }
                            .accessibilityIdentifier("train.level." + level.rawValue)
                    }
                }
            }

            if vm.kind == .gym || vm.kind == .home {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    caption("Focus")
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(ExerciseFocus.allCases) { focus in
                            ChoiceChip(label: focus.title, isSelected: vm.focus == focus) { vm.focus = focus }
                        }
                    }
                }
                .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 6) {
                caption("Anything specific?")
                TextField("e.g. only dumbbells, easy on the knees", text: $vm.wishes, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($wishesFocused)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .strokeBorder(wishesFocused ? Color.labelPrimary : Color.hairline, lineWidth: wishesFocused ? 1.5 : 1))
                    .accessibilityIdentifier("train.wishes")
                Text("Used when online AI writes the session.")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }

            PrimaryButton(title: vm.isGenerating ? "Building…" : "Generate workout",
                          systemImage: "sparkles", isLoading: vm.isGenerating) {
                wishesFocused = false
                Task { await vm.generate() }
            }
            .accessibilityIdentifier("train.generate")
        }
        .padding(Spacing.lg)
        .premiumCard()
        .animation(.snappyValue, value: vm.kind)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Saved

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Saved workouts").font(.sectionTitle)
            ForEach(store.saved) { workout in
                NavigationLink { WorkoutDetailView(workout: workout, localReason: nil) } label: {
                    TrainLinkRow(symbol: workout.kind.symbol, title: workout.title,
                                 detail: "\(workout.durationMinutes) min · \(workout.exercises.count) exercises · \(workout.level.title)")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Pieces

private struct KindTile: View {
    let kind: ExerciseKind
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: kind.symbol)
                    .font(.title3)
                    .foregroundStyle(Color.labelPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.headline).foregroundStyle(Color.labelPrimary)
                    Text(kind.detail)
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(Spacing.md)
            .background(isSelected ? Color.brandLight : Color.surface,
                        in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .strokeBorder(isSelected ? Color.progress : Color.hairline, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("train.kind." + kind.rawValue)
    }
}

struct ChoiceChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(isSelected ? Color.dullPink : Color.surfaceSecondary, in: Capsule())
                .foregroundStyle(isSelected ? Color.onAccent : Color.labelPrimary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappyValue, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TrainLinkRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.almond)
                .frame(width: 44, height: 44)
                .background(Color.rhino, in: RoundedRectangle(cornerRadius: Radius.chip))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.headline).foregroundStyle(Color.labelPrimary)
                    .multilineTextAlignment(.leading)
                Text(detail).font(.footnote).foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.labelSecondary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(radius: Radius.tile)
        .contentShape(Rectangle())
    }
}

#Preview { TrainView() }
