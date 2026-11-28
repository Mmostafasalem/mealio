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
        // Built on the phone from the catalogue (online AI is only for chat and recipes).
        localReason = nil
        generated = WorkoutBuilder.build(kind: kind, level: level, minutes: Int(minutes),
                                         focus: focus, goal: AppState.shared.userProfile.weightGoal)
    }
}

struct TrainView: View {

    @State private var vm = TrainViewModel()
    @State private var store = WorkoutStore.shared
    @State private var showLibrary = false
    @State private var guide: ExerciseGuide?
    @State private var building = false
    @State private var editingWorkout: Workout?
    /// Workout mode reopened for a workout still running (after the app was closed).
    @State private var resumed: WorkoutModeModel?
    /// A programme day opened from the Programmes section.
    @State private var programDay: Workout?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    if let running = WorkoutSession.shared.workout, WorkoutSession.shared.state != nil {
                        Button { resumed = WorkoutModeModel(workout: running) } label: {
                            TrainLinkRow(symbol: "figure.run", title: "Workout in progress",
                                         detail: "\(running.title) · tap to continue")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("train.resume")
                    }
                    weekCard
                    ProgramsSection { programDay = $0 }
                        .id(TourTarget.programmes).tourTarget(.programmes)
                    builderCard
                        .id(TourTarget.buildWorkout).tourTarget(.buildWorkout)
                    savedSection
                    exerciseBrowser
                        .id(TourTarget.exercises).tourTarget(.exercises)
                    NavigationLink { TrainingProgressView() } label: {
                        TrainLinkRow(symbol: "chart.line.uptrend.xyaxis", title: "Progress",
                                     detail: progressDetail)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("train.progress")
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
            .tourScrolling([.train], proxy: proxy)
            }
            .background { GrainyGradient().ignoresSafeArea() }
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { NourloToolbarItem() }
            .navigationDestination(isPresented: $showLibrary) { ExerciseLibraryView() }
            .sheet(item: $guide) { ExerciseGuideSheet(guide: $0) }
            .sheet(isPresented: $building) { WorkoutBuilderView() }
            .sheet(item: $editingWorkout) { WorkoutBuilderView(editing: $0) }
            .fullScreenCover(isPresented: Binding(get: { resumed != nil }, set: { if !$0 { resumed = nil } })) {
                if let resumed { WorkoutModeView(model: resumed) { self.resumed = nil } }
            }
            .navigationDestination(item: $vm.generated) { workout in
                WorkoutDetailView(workout: workout, localReason: vm.localReason)
            }
            .navigationDestination(item: $programDay) { WorkoutDetailView(workout: $0, localReason: nil) }
        }
        // "Start a cardio workout" from Siri or Shortcuts preselects that kind.
        .onAppear { applyRequestedKind() }
        .onChange(of: AppRouter.shared.workoutKind) { _, _ in applyRequestedKind() }
    }

    /// "12 workouts · 3 records", or what Progress will show once there's something.
    private var progressDetail: String {
        let log = TrainingLogStore.shared
        guard !log.workouts.isEmpty else { return "Sets, weights and records from workout mode" }
        let records = log.workouts.reduce(0) { $0 + $1.records.count }
        return "\(log.workouts.count) workout\(log.workouts.count == 1 ? "" : "s") logged" + (records > 0 ? " · \(records) record\(records == 1 ? "" : "s")" : "")
    }

    /// Applies a workout kind Siri or Shortcuts asked for (once).
    private func applyRequestedKind() {
        if let kind = AppRouter.shared.consumeWorkoutKind() { vm.kind = kind }
        if let minutes = AppRouter.shared.consumeWorkoutMinutes() { vm.minutes = Double(minutes) }
    }

    // MARK: Exercise browser

    /// The exercise library as a card you drill into in place. Its own view, built
    /// once, so the builder's controls (e.g. every ruler tick) don't rebuild 300+ pages.
    private var exerciseBrowser: some View {
        ExerciseBrowserCard(showLibrary: $showLibrary, guide: $guide)
    }

    // MARK: This week

    /// This week, from the person's own week start: the same week Progress counts.
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
        .accessibilityLabel("This week: \(week.count) sessions, \(week.reduce(0) { $0 + $1.minutes }) minutes, about \(week.reduce(0) { $0 + $1.calories }) kilocalories" as String)
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
                    Text("\(Int(vm.minutes))" as String)
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("min").font(.headline).foregroundStyle(Color.labelSecondary)
                }
                .animation(reduceMotion ? .reducedFade : .snappyValue, value: vm.minutes)
                .accessibilityHidden(true)
                TypeNumberButton(title: "Workout length", unit: "minutes", current: "\(Int(vm.minutes))",
                                 hint: "From 10 to 90 minutes.", keyboard: .numberPad, identifier: "train.minutes.type") { text in
                    if let m = TypedNumber.parse(text) { vm.minutes = TypedNumber.fitted(m, range: 10...90, step: 5) }
                }
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

            PrimaryButton(title: vm.isGenerating ? "Building…" : "Generate workout",
                          systemImage: "wand.and.stars", isLoading: vm.isGenerating) {
                Task { await vm.generate() }
            }
            .accessibilityIdentifier("train.generate")
        }
        .padding(Spacing.lg)
        .premiumCard()
        .animation(reduceMotion ? .reducedFade : .snappyValue, value: vm.kind)
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
            Text("My workouts").font(.sectionTitle)
            Button { building = true } label: {
                TrainLinkRow(symbol: "plus.square.on.square", title: "Create your own workout",
                             detail: "Pick exercises from the library or add your own")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("train.createWorkout")
            ForEach(store.saved) { workout in
                NavigationLink { WorkoutDetailView(workout: workout, localReason: nil) } label: {
                    TrainLinkRow(symbol: workout.source == "custom" ? "person.crop.circle.fill" : workout.kind.symbol, title: workout.title,
                                 detail: workout.source == "custom"
                                    ? "\(workout.durationMinutes) min · \(workout.exercises.count) exercises · built by you"
                                    : "\(workout.durationMinutes) min · \(workout.exercises.count) exercises · \(workout.level.title)")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { editingWorkout = workout } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { store.remove(workout) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }
}

// MARK: - Pieces

/// The exercise library as a card you drill into in place: muscle group (or type) →
/// exercises → one exercise. Depends only on the catalogue, so its pages are built
/// the first time it is drawn and kept.
private struct ExerciseBrowserCard: View {
    @Binding var showLibrary: Bool
    @Binding var guide: ExerciseGuide?
    @State private var cache = PageCache()
    /// Grouped by muscle (the default) or by type of training; remembered.
    @AppStorage("trainExercisesByMuscle_v1") private var byMuscle = true

    /// Holds the built pages; a plain reference so filling it doesn't redraw anything.
    private final class PageCache {
        var pages: [String: StackPanelPage]?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("Group exercises", selection: $byMuscle) {
                Text("By muscle").tag(true)
                Text("By type").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("train.exercises.grouping")
            // A new root starts the panel afresh, on its top page.
            StackPanel(pages: pages(), root: byMuscle ? "muscles" : "root")
                .id(byMuscle)
        }
    }

    private func pages() -> [String: StackPanelPage] {
        if let built = cache.pages { return built }
        // The rows' actions write through the bindings, which keep pointing at TrainView's state.
        let showLibrary = $showLibrary, guide = $guide
        let built = Self.makePages(search: { showLibrary.wrappedValue = true },
                                   open: { guide.wrappedValue = ExerciseGuide(exercise: $0) })
        cache.pages = built
        return built
    }

    private static func makePages(search: @escaping () -> Void,
                                  open: @escaping (Exercise) -> Void) -> [String: StackPanelPage] {
        let byKind = Dictionary(grouping: Exercise.catalog, by: \.kind)
        let byGroup = Dictionary(grouping: Exercise.catalog, by: \.muscleGroup)
        let searchRow = StackPanelRow(id: "search", label: "Search all exercises", symbol: "magnifyingglass", action: search)
        var pages: [String: StackPanelPage] = [:]

        // By muscle: each exercise under its main muscle group.
        pages["muscles"] = StackPanelPage(title: "Exercises", sections: [
            StackPanelSection(rows: MuscleGroup.allCases.compactMap { group in
                guard let count = byGroup[group]?.count, count > 0 else { return nil }
                return StackPanelRow(id: "muscle." + group.rawValue, label: group.title, symbol: group.symbol,
                                     detail: "\(count)", to: "muscle." + group.rawValue)
            }),
            StackPanelSection(rows: [searchRow]),
        ])
        for group in MuscleGroup.allCases {
            let exercises = byGroup[group] ?? []
            guard !exercises.isEmpty else { continue }
            // Split by type when the group mixes them (chest work in the gym and at home).
            let kinds = ExerciseKind.allCases.filter { kind in exercises.contains { $0.kind == kind } }
            let sections: [(String?, [Exercise])] = kinds.count > 1
                ? kinds.map { kind in (kind.title, exercises.filter { $0.kind == kind }) }
                : [(nil, exercises)]
            pages["muscle." + group.rawValue] = StackPanelPage(title: group.title, sections: sections.map { title, items in
                StackPanelSection(title: title, rows: items.map { exercise in
                    StackPanelRow(id: group.rawValue + "." + exercise.id, label: exercise.name,
                                  detail: exercise.level.title, to: "exercise." + exercise.id)
                })
            })
        }

        // By type.
        pages["root"] = StackPanelPage(title: "Exercises", sections: [
            StackPanelSection(rows: ExerciseKind.allCases.map { kind in
                StackPanelRow(id: kind.rawValue, label: kind.title, symbol: kind.symbol,
                              detail: "\(byKind[kind]?.count ?? 0)", to: "kind." + kind.rawValue)
            }),
            StackPanelSection(rows: [searchRow]),
        ])
        for kind in ExerciseKind.allCases {
            let exercises = byKind[kind] ?? []
            // Strength work is grouped by body area; cardio and mobility are one list.
            let byFocus = Dictionary(grouping: exercises.filter { $0.focus != nil }, by: { $0.focus! })
            let groups: [(String?, [Exercise])] = byFocus.isEmpty
                ? [(nil, exercises)]
                : ExerciseFocus.allCases.compactMap { focus in
                    guard let matching = byFocus[focus], !matching.isEmpty else { return nil }
                    return (focus.title, matching)
                }
            pages["kind." + kind.rawValue] = StackPanelPage(title: kind.title, sections: groups.map { title, items in
                StackPanelSection(title: title, rows: items.map { exercise in
                    StackPanelRow(id: exercise.id, label: exercise.name, detail: exercise.level.title, to: "exercise." + exercise.id)
                })
            })
            for exercise in exercises {
                pages["exercise." + exercise.id] = StackPanelPage(title: exercise.name, sections: [
                    StackPanelSection(rows: [
                        StackPanelRow(id: exercise.id + ".works", label: "Works", detail: exercise.muscles),
                        StackPanelRow(id: exercise.id + ".group", label: "Group",
                                      detail: "\(exercise.muscleGroup.title) · \(exercise.kind.title)"),
                        StackPanelRow(id: exercise.id + ".kit", label: "Equipment", detail: exercise.equipment),
                        StackPanelRow(id: exercise.id + ".typical", label: "Typical", detail: exercise.prescription),
                    ]),
                    StackPanelSection(rows: [
                        StackPanelRow(id: exercise.id + ".howto", label: "Show how to do it", symbol: "play.circle.fill",
                                      action: { open(exercise) }),
                    ]),
                ])
            }
        }
        return pages
    }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? .reducedFade : .snappyValue, value: isSelected)
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
