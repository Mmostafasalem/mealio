import SwiftUI

/// One workout: what to do, in order, with save and "done" actions.
struct WorkoutDetailView: View {

    let workout: Workout
    /// Shown when this session was built on the phone instead of by AI.
    let localReason: String?

    @State private var store = WorkoutStore.shared
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
                ForEach(Array(workout.exercises.enumerated()), id: \.offset) { index, exercise in
                    let item = ExerciseGuide(step: exercise)
                    Button { guide = item } label: {
                        HStack(alignment: .center, spacing: Spacing.md) {
                            if let motion = item.motion {
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
                                Text("How to do it")
                                    .font(.footnote)
                                    .foregroundStyle(Color.labelSecondary)
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
                Text("Tap an exercise to see the movement and step-by-step notes.")
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
            PrimaryButton(title: markedDone ? "Logged for today" : "Mark as done",
                          systemImage: markedDone ? "checkmark" : "checkmark.circle") {
                store.complete(workout, weightKg: weight)
                withAnimation(reduceMotion ? .reducedFade : .snappyValue) { markedDone = true }
            }
            .disabled(markedDone)
            .sensoryFeedback(.success, trigger: markedDone)
            .accessibilityIdentifier("workout.done")
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
        }
    }

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

    private var exercises: [Exercise] {
        Exercise.catalog.filter { exercise in
            (kind == nil || exercise.kind == kind)
                && (query.isEmpty || exercise.name.localizedStandardContains(query)
                    || exercise.muscles.localizedStandardContains(query))
        }
    }

    var body: some View {
        List {
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
                            if let motion = exercise.motion {
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
