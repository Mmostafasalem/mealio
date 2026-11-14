import SwiftUI

/// One workout: what to do, in order, with save and "done" actions.
struct WorkoutDetailView: View {

    let workout: Workout
    /// Shown when this session was built on the phone instead of by AI.
    let localReason: String?
    @State private var guideCache = GuideCache()
    @State private var store = WorkoutStore.shared
    @State private var session = WorkoutSession.shared
    @State private var markedDone = false
    @State private var guide: ExerciseGuide?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var weight: Double { AppState.shared.userProfile.weight }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(workout.title)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    if !workout.summary.isEmpty {
                        Text(workout.summary).font(.subheadline).foregroundStyle(Color.labelSecondary)
                    }
                    FlowLayout(spacing: Spacing.sm) {
                        fact(workout.kind.symbol, workout.kind.title)
                        fact("clock", "\(workout.durationMinutes) min")
                        fact("chart.bar.fill", workout.level.title)
                        fact("flame.fill", "~\(workout.estimatedCalories(weightKg: weight)) kcal")
                    }
                    Label(workout.isFromAI ? "Written by online AI for your stats and request" : (localReason ?? "Built on your phone"),
                          systemImage: workout.isFromAI ? "sparkles" : "iphone")
                        .font(.footnote)
                        .foregroundStyle(Color.labelSecondary)
                        .accessibilityIdentifier("workout.source")
                }
                .padding(.vertical, Spacing.xs)
            }

            if !workout.warmup.isEmpty {
                Section("Warm-up") { Text(workout.warmup).font(.subheadline) }
            }

            Section {
                ForEach(Array(zip(workout.exercises, guides).enumerated()), id: \.offset) { index, pair in
                    let (exercise, item) = pair
                    Button { guide = item } label: {
                        HStack(alignment: .center, spacing: Spacing.md) {
                            if let drawing = item.drawing {
                                ExerciseDrawingCanvas(drawing: drawing, frame: 1)
                                    .padding(4)
                                    .frame(width: 72, height: 72)
                                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                            } else if item.drawingPending {
                                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                    .fill(Color.surfaceSecondary)
                                    .frame(width: 72, height: 72)
                            } else if let motion = item.motion {
                                ExerciseFrame(motion: motion, finish: true)
                                    .padding(4)
                                    .frame(width: 72, height: 72)
                                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(index + 1). \(exercise.name)")
                                    .font(.headline)
                                    .foregroundStyle(Color.labelPrimary)
                                    .multilineTextAlignment(.leading)
                                Text(item.prescription ?? exercise.prescription)
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.labelPrimary)
                                if currentStep == index {
                                    Label("Doing now", systemImage: "figure.strengthtraining.traditional")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color.labelPrimary)
                                } else {
                                    Text("How to do it")
                                        .font(.footnote)
                                        .foregroundStyle(Color.labelSecondary)
                                }
                            }
                            Spacer(minLength: Spacing.sm)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout.step.\(index + 1)")
                }
            } header: {
                Text("Exercises")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Tap an exercise to see the movement and step-by-step notes.")
                    // The drawings are CC BY-SA 4.0: credited wherever one is shown (not for
                    // steps that show the posed figure instead).
                    if guides.contains(where: { $0.drawing != nil }) { ExerciseDrawingCredit() }
                }
            }

            if !workout.cooldown.isEmpty {
                Section("Cool-down") { Text(workout.cooldown).font(.subheadline) }
            }

            Section {
                Label(workout.safetyNote, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if store.isSaved(workout) { store.remove(workout) } else { store.save(workout) }
                } label: {
                    Image(systemName: store.isSaved(workout) ? "bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(store.isSaved(workout) ? "Remove from saved" : "Save workout")
                .accessibilityIdentifier("workout.save")
            }
        }
        .sheet(item: $guide) { ExerciseGuideSheet(guide: $0) }
        .safeAreaInset(edge: .bottom) {
            Group {
                if let state = runningState {
                    sessionStrip(state)
                } else {
                    startActions
                }
            }
            .sensoryFeedback(.success, trigger: markedDone)
            .sensoryFeedback(.success, trigger: session.finishCount)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Session

    /// This workout's session while it's running here.
    private var runningState: WorkoutSessionState? {
        session.isRunning(workout) ? session.state : nil
    }

    /// The step being done now, for the "Doing now" mark in the list.
    private var currentStep: Int? { runningState?.index }

    /// Before starting: start the guided session, or just log it as done.
    @ViewBuilder private var startActions: some View {
        if isDone {
            PrimaryButton(title: "Logged for today", systemImage: "checkmark") {}
                .disabled(true)
                .accessibilityIdentifier("workout.done")
        } else {
            VStack(spacing: Spacing.xs) {
                PrimaryButton(title: "Start workout", systemImage: "play.fill") {
                    withAnimation(reduceMotion ? .reducedFade : .snappyValue) { session.start(workout) }
                }
                .accessibilityHint("Steps through the exercises one at a time")
                .accessibilityIdentifier("workout.start")
                Button("Mark as done") {
                    store.complete(workout, weightKg: weight)      // once per workout per day
                    withAnimation(reduceMotion ? .reducedFade : .snappyValue) { markedDone = true }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("workout.done")
            }
        }
    }

    /// While running: where you are, the time so far, Next and Finish.
    private func sessionStrip(_ state: WorkoutSessionState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(NourloWidgetFormat.stepPosition(index: state.index, total: state.steps.count))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.labelSecondary)
                Spacer(minLength: Spacing.sm)
                Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.labelPrimary)
                    .accessibilityLabel("Elapsed time")
                Button {
                    withAnimation(reduceMotion ? .reducedFade : .snappyValue) { session.cancel() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.labelTertiary)
                        .frame(minWidth: 44, minHeight: 32)
                }
                .accessibilityLabel("Stop without logging")
                .accessibilityIdentifier("workout.session.stop")
            }
            if let step = state.current {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.name)
                        .font(.headline)
                        .foregroundStyle(Color.labelPrimary)
                    if !step.detail.isEmpty {
                        Text(step.detail)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("workout.session.current")
            }
            HStack(spacing: Spacing.sm) {
                if state.canAdvance {
                    SecondaryButton(title: "Next", systemImage: "forward.fill") {
                        withAnimation(reduceMotion ? .reducedFade : .snappyValue) { session.next() }
                    }
                    .accessibilityHint("Moves on to the next exercise")
                    .accessibilityIdentifier("workout.session.next")
                }
                PrimaryButton(title: "Finish", systemImage: "checkmark") {
                    withAnimation(reduceMotion ? .reducedFade : .snappyValue) { session.finish() }
                }
                .accessibilityHint("Logs this workout as done")
                .accessibilityIdentifier("workout.session.finish")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workout in progress")
    }

    /// One guide per step, matched to the catalogue the first time they're needed
    /// and kept, not rebuilt on every redraw (or every time a parent builds this view).
    private var guides: [ExerciseGuide] { guideCache.guides(for: workout) }

    private final class GuideCache {
        private var workoutID: UUID?
        private var built: [ExerciseGuide] = []
        func guides(for workout: Workout) -> [ExerciseGuide] {
            if workoutID != workout.id {
                built = workout.exercises.map { ExerciseGuide(step: $0) }
                workoutID = workout.id
            }
            return built
        }
    }

    /// Done now, or already logged today (e.g. a saved workout opened again).
    private var isDone: Bool { markedDone || store.isCompletedToday(workout) }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
        }
            .font(.footnote.weight(.medium))
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.surfaceSecondary, in: Capsule())
            .foregroundStyle(Color.labelPrimary)
    }
}

/// Completed sessions, newest first.
struct WorkoutHistoryView: View {
    @State private var store = WorkoutStore.shared

    var body: some View {
        List {
            ForEach(store.completed) { session in
                HStack(spacing: Spacing.md) {
                    Image(systemName: session.kind.symbol)
                        .foregroundStyle(Color.labelPrimary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                        Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.minutes) min · ~\(session.calories) kcal")
                            .font(.caption).foregroundStyle(Color.labelSecondary)
                    }
                }
                .swipeActions { Button("Delete", role: .destructive) { store.removeCompleted(session) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
    }
}

// MARK: - Exercise library

struct ExerciseLibraryView: View {
    @State private var query = ""
    @State private var kind: ExerciseKind?
    @State private var guide: ExerciseGuide?

    private func filtered() -> [Exercise] {
        Exercise.catalog.filter { exercise in
            (kind == nil || exercise.kind == kind)
                && (query.isEmpty || exercise.name.localizedStandardContains(query)
                    || exercise.muscles.localizedStandardContains(query))
        }
    }

    var body: some View {
        let exercises = filtered()        // once per redraw, not once per use
        let drawings = ExerciseDrawingsStatus.shared
        return List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ChoiceChip(label: "All", isSelected: kind == nil) { kind = nil }
                        ForEach(ExerciseKind.allCases) { option in
                            ChoiceChip(label: option.title, isSelected: kind == option) { kind = option }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: Spacing.lg, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
            Section {
                if exercises.isEmpty {
                    Text("No exercise matches your search.").foregroundStyle(Color.labelSecondary)
                }
                ForEach(exercises) { exercise in
                    Button { guide = ExerciseGuide(exercise: exercise) } label: {
                        HStack(spacing: Spacing.md) {
                            if let drawing = drawings.drawing(forExercise: exercise.id) {
                                ExerciseDrawingCanvas(drawing: drawing, frame: 1)
                                    .padding(4)
                                    .frame(width: 60, height: 60)
                                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                            } else if drawings.isPending(forExercise: exercise.id) {
                                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                    .fill(Color.surfaceSecondary)
                                    .frame(width: 60, height: 60)
                            } else if let motion = exercise.motion {
                                ExerciseFrame(motion: motion, finish: true)
                                    .padding(4)
                                    .frame(width: 60, height: 60)
                                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).font(.headline).foregroundStyle(Color.labelPrimary)
                                Text("\(exercise.kind.title) · \(exercise.muscles)")
                                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                            }
                            Spacer(minLength: Spacing.sm)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exercise." + exercise.id)
                }
            } header: {
                // The drawings are CC BY-SA 4.0: credited wherever they are shown, here above the list.
                ExerciseDrawingCredit().textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .searchable(text: $query, prompt: "Search exercises or muscles")
        .sheet(item: $guide) { ExerciseGuideSheet(guide: $0) }
    }
}
