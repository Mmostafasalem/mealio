import SwiftUI

/// One workout: what to do, in order, with save and "done" actions.
struct WorkoutDetailView: View {

    let workout: Workout
    /// Shown when this session was built on the phone instead of by AI.
    let localReason: String?

    @State private var store = WorkoutStore.shared
    @State private var markedDone = false
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

            Section("Exercises") {
                ForEach(Array(workout.exercises.enumerated()), id: \.offset) { index, exercise in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        stepMarker(index + 1, motion: ExerciseMotion.matching(name: exercise.name))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).font(.headline)
                            Text(exercise.restSeconds > 0
                                 ? "\(exercise.prescription) · rest \(exercise.restSeconds) sec"
                                 : exercise.prescription)
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                            if !exercise.note.isEmpty {
                                Text(exercise.note).font(.footnote).foregroundStyle(Color.labelSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
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

    /// The step number, on top of an animated demo when the movement is known.
    @ViewBuilder
    private func stepMarker(_ number: Int, motion: ExerciseMotion?) -> some View {
        let badge = Text("\(number)")
            .font(.footnote.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Color.onAccent)
            .frame(width: 24, height: 24)
            .background(Color.dullPink, in: Circle())
            .accessibilityHidden(true)
        if let motion {
            ExerciseDemo(motion: motion, reps: 3)
                .frame(width: 76, height: 76)
                .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .overlay(alignment: .topLeading) { badge.offset(x: -6, y: -6) }
        } else {
            badge
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
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
    }
}

// MARK: - Exercise library

struct ExerciseLibraryView: View {
    @State private var query = ""
    @State private var kind: ExerciseKind?
    @State private var expanded: Set<String> = []

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
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(exercise.id) },
                        set: { open in if open { expanded.insert(exercise.id) } else { expanded.remove(exercise.id) } }
                    )) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            if let motion = exercise.motion {
                                ExerciseDemo(motion: motion)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 170)
                                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                                Text("Tap the figure to replay.")
                                    .font(.caption)
                            }
                            Text(exercise.howTo).font(.subheadline).foregroundStyle(Color.labelPrimary)
                            Label(exercise.equipment, systemImage: "wrench.and.screwdriver")
                            Label("Typical: \(exercise.prescription)", systemImage: "repeat")
                            Label(exercise.level.title, systemImage: "chart.bar.fill")
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.labelSecondary)
                        .padding(.vertical, Spacing.xs)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: exercise.kind.symbol)
                                .foregroundStyle(Color.labelPrimary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).foregroundStyle(Color.labelPrimary)
                                Text(exercise.muscles).font(.caption).foregroundStyle(Color.labelSecondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("exercise." + exercise.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .searchable(text: $query, prompt: "Search exercises or muscles")
    }
}
