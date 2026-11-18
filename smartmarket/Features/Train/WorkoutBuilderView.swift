import Observation
import SwiftUI

// MARK: - Exercises people add themselves

struct CustomExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var muscles: String
    var tracking: ExerciseTracking
}

@MainActor
@Observable
final class CustomExerciseStore {
    static let shared = CustomExerciseStore()
    private(set) var exercises: [CustomExercise] = []
    @ObservationIgnored private let defaults: UserDefaults
    private let key = "customExercises_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        exercises = ResilientStorage.loadArray(CustomExercise.self, key: key, defaults: defaults)
    }

    /// Re-reads storage (after Delete All Data).
    func reload() {
        exercises = ResilientStorage.loadArray(CustomExercise.self, key: key, defaults: defaults)
    }

    func exercise(named name: String) -> CustomExercise? {
        let wanted = TrainingLogStore.key(name)
        return exercises.first { TrainingLogStore.key($0.name) == wanted }
    }

    @discardableResult
    func add(name: String, muscles: String, tracking: ExerciseTracking) -> CustomExercise {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = exercise(named: clean) { return existing }
        let new = CustomExercise(name: clean, muscles: muscles.trimmingCharacters(in: .whitespacesAndNewlines), tracking: tracking)
        exercises.insert(new, at: 0)
        persist()
        return new
    }

    func remove(_ exercise: CustomExercise) {
        exercises.removeAll { $0.id == exercise.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(exercises) { defaults.set(data, forKey: key) }
    }
}

// MARK: - Building a workout

/// One exercise in the workout being built, with its targets.
struct BuilderItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var tracking: ExerciseTracking
    var sets = 3
    var reps = 10
    var seconds = 30
    var weightKg: Double = 0
    var restSeconds = 60
    /// The step being edited. Its how-to note, the words after its number ("each side")
    /// and a timed block's description are kept, so editing doesn't rewrite it.
    private(set) var source: WorkoutExercise? = nil

    var step: WorkoutExercise {
        guard let source else {
            return WorkoutExercise(name: name, sets: sets, reps: tracking == .time ? "\(seconds) sec" : "\(reps)", minutes: 0,
                                   restSeconds: restSeconds, note: "", tracking: tracking,
                                   weightKg: tracking == .weightReps && weightKg > 0 ? weightKg : nil)
        }
        // Nothing changed: the step goes back exactly as it was.
        if sameTargets(as: BuilderItem(step: source)) { return source }
        let weight = tracking == .weightReps && weightKg > 0 ? weightKg : nil
        // A block written in minutes ("12 min · conversational pace") stays one when it still is whole minutes.
        if tracking == .time, source.minutes > 0, (sets * seconds) % 60 == 0 {
            return WorkoutExercise(name: name, sets: sets, reps: source.reps, minutes: sets * seconds / 60,
                                   restSeconds: restSeconds, note: source.note, tracking: tracking, weightKg: weight)
        }
        let suffix = source.minutes > 0 ? "" : Self.suffix(of: WorkoutModeModel.prescription(source).each)
        return WorkoutExercise(name: name, sets: sets, reps: (tracking == .time ? "\(seconds) sec" : "\(reps)") + suffix,
                               minutes: 0, restSeconds: restSeconds, note: source.note, tracking: tracking, weightKg: weight)
    }

    private func sameTargets(as other: BuilderItem) -> Bool {
        name == other.name && tracking == other.tracking && sets == other.sets && reps == other.reps
            && seconds == other.seconds && weightKg == other.weightKg && restSeconds == other.restSeconds
    }

    /// The words after the amount: "10 each side" and "30 sec each side" → " each side".
    static func suffix(of each: String) -> String {
        guard let amount = each.range(of: #"^\s*\d+\s*(seconds?|secs?|minutes?|mins?)?"#,
                                      options: [.regularExpression, .caseInsensitive]) else { return "" }
        let words = each[amount.upperBound...].trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? "" : " " + words
    }

    init(name: String, tracking: ExerciseTracking) {
        self.name = name
        self.tracking = tracking
        if tracking == .time { restSeconds = 30 }
    }

    init(step: WorkoutExercise) {
        name = step.name
        tracking = ExerciseTracking.guess(for: step)
        let parsed = WorkoutModeModel.prescription(step)
        sets = max(parsed.sets, 1)
        let number = Int(parsed.each.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "")
        reps = number ?? 10
        seconds = WorkoutModeModel.seconds(in: step)
        weightKg = step.weightKg ?? 0
        restSeconds = step.restSeconds
        source = step
    }

    /// Rough time: about 3 s a rep (or the set's time), plus the rests between sets.
    var estimatedSeconds: Int {
        let work = tracking == .time ? seconds : reps * 3
        return sets * work + max(sets - 1, 0) * restSeconds + 45
    }
}

struct WorkoutBuilderView: View {
    /// Pass a saved workout to edit it; nil builds a new one.
    var editing: Workout? = nil
    var onSaved: (Workout) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Constants.Storage.weightUnit) private var unit: WeightUnit = .kg
    @State private var title = ""
    @State private var kind: ExerciseKind = .gym
    @State private var items: [BuilderItem] = []
    @State private var picking = false
    @State private var editingItem: BuilderItem?

    private var minutes: Int { max(5, Int((Double(items.reduce(0) { $0 + $1.estimatedSeconds }) / 60).rounded())) }
    private var canSave: Bool { !items.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout name, e.g. Push day", text: $title)
                        .font(.headline)
                        .accessibilityIdentifier("builder.title")
                    Picker("Type", selection: $kind) {
                        ForEach(ExerciseKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(items) { item in
                        Button { editingItem = item } label: { itemRow(item) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    Button { picking = true } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill").font(.headline)
                    }
                    .accessibilityIdentifier("builder.addExercise")
                } header: {
                    Text("Exercises")
                } footer: {
                    Text(items.isEmpty ? "Add exercises from the library or make your own."
                                       : "About \(minutes) min. Tap an exercise to set its sets, reps, weight and rest; drag to reorder.")
                }
            }
            .environment(\.editMode, .constant(items.count > 1 ? .active : .inactive))
            .listStyle(.insetGrouped)
            .navigationTitle(editing == nil ? "New workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                        .accessibilityIdentifier("builder.save")
                }
            }
            .sheet(isPresented: $picking) {
                // One row per exercise name: a step's name is its identity in the workout.
                ExercisePickerView { picked in
                    for item in picked where !items.contains(where: { TrainingLogStore.key($0.name) == TrainingLogStore.key(item.name) }) {
                        items.append(item)
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                BuilderItemEditor(item: item, unit: unit) { updated in
                    if let i = items.firstIndex(where: { $0.id == updated.id }) { items[i] = updated }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear(perform: load)
        }
    }

    private func itemRow(_ item: BuilderItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.labelPrimary)
            Text(summary(item)).font(.footnote).foregroundStyle(Color.labelSecondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func summary(_ item: BuilderItem) -> String {
        let work: String
        switch item.tracking {
        case .weightReps: work = "\(item.sets) × \(item.reps)" + (item.weightKg > 0 ? " @ \(TrainingFormat.weight(item.weightKg, unit))" : "")
        case .reps: work = "\(item.sets) × \(item.reps)"
        case .time: work = "\(item.sets) × \(TrainingFormat.duration(item.seconds))"
        }
        return "\(work) · rest \(item.restSeconds) s"
    }

    private func load() {
        guard items.isEmpty, let w = editing else { return }
        title = w.title
        kind = w.kind
        items = w.exercises.map { BuilderItem(step: $0) }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = items.map { $0.step }
        // Saved with nothing changed: the workout stays as it was (a generated one isn't relabelled).
        if let editing, editing.title == name, editing.kind == kind, editing.exercises == steps {
            dismiss()
            return
        }
        let workout = Workout(id: editing?.id ?? UUID(),
                              title: name.isEmpty ? "My \(kind.title.lowercased()) workout" : name,
                              summary: "Built by you · \(items.count) exercise\(items.count == 1 ? "" : "s")",
                              kind: kind, level: editing?.level ?? .intermediate, durationMinutes: minutes,
                              warmup: editing?.warmup ?? "5 minutes of easy movement to warm up.",
                              cooldown: editing?.cooldown ?? "A few minutes of easy stretching.",
                              exercises: steps,
                              safetyNote: "Stop if anything hurts. General fitness guidance, not medical advice.",
                              source: "custom")
        WorkoutStore.shared.update(workout)
        onSaved(workout)
        dismiss()
    }
}

/// Sets, reps or time, weight and rest for one exercise.
private struct BuilderItemEditor: View {
    @State var item: BuilderItem
    let unit: WeightUnit
    let onDone: (BuilderItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Measured by", selection: $item.tracking) {
                        ForEach(ExerciseTracking.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Stepper("Sets: \(item.sets)", value: $item.sets, in: 1...20)
                    if item.tracking == .time {
                        // Up to two hours, for long steady blocks; whole minutes once past ten.
                        Stepper("Time: \(TrainingFormat.duration(item.seconds))", value: $item.seconds, in: 5...7200,
                                step: item.seconds >= 600 ? 60 : 5)
                    } else {
                        Stepper("Reps: \(item.reps)", value: $item.reps, in: 1...100)
                    }
                    if item.tracking == .weightReps {
                        Stepper("Weight: \(item.weightKg > 0 ? TrainingFormat.weight(item.weightKg, unit) : "none yet")",
                                value: $item.weightKg, in: 0...500, step: unit == .kg ? 2.5 : WeightUnit.kgPerPound * 5)
                    }
                    Stepper("Rest: \(item.restSeconds) s", value: $item.restSeconds, in: 0...600, step: 15)
                } footer: {
                    if item.tracking == .weightReps {
                        Text("Leave the weight empty to start from what you lifted last time.")
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(item); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Picking exercises

struct ExercisePickerView: View {
    let onAdd: ([BuilderItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var custom = CustomExerciseStore.shared
    @State private var query = ""
    @State private var focus: ExerciseFocus?
    @State private var chosen: [BuilderItem] = []
    @State private var creating = false

    /// Library exercises, without ones an own exercise of the same name stands in for.
    private var library: [Exercise] {
        Exercise.catalog.filter { e in
            (focus == nil || e.focus == focus)
                && (query.isEmpty || e.name.localizedStandardContains(query) || e.muscles.localizedStandardContains(query))
                && custom.exercise(named: e.name) == nil
        }
    }

    /// How a library exercise is measured: timed when its usual prescription is.
    static func tracking(of e: Exercise) -> ExerciseTracking {
        let timed = e.prescription.contains("min") || e.prescription.contains("sec")
        return ExerciseTracking.guess(for: WorkoutExercise(name: e.name, sets: 3, reps: timed ? e.prescription : "10",
                                                           minutes: 0, restSeconds: 60, note: ""))
    }

    private func isChosen(_ name: String) -> Bool {
        chosen.contains { TrainingLogStore.key($0.name) == TrainingLogStore.key(name) }
    }

    /// Adds an exercise to the choice once, however it was picked.
    private func choose(_ name: String, _ tracking: ExerciseTracking) {
        guard !isChosen(name) else { return }
        chosen.append(BuilderItem(name: name, tracking: tracking))
    }

    private var mine: [CustomExercise] {
        custom.exercises.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.muscles.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            chip("All", focus == nil) { focus = nil }
                            ForEach(ExerciseFocus.allCases) { f in chip(f.title, focus == f) { focus = f } }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    Button { creating = true } label: {
                        Label("Make a new exercise", systemImage: "plus.square.dashed").font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("picker.newExercise")
                }
                if !mine.isEmpty {
                    Section("Your exercises") {
                        ForEach(mine) { e in
                            row(name: e.name, detail: [e.muscles, e.tracking.title].filter { !$0.isEmpty }.joined(separator: " · "),
                                tracking: e.tracking)
                        }
                        .onDelete { offsets in offsets.map { mine[$0] }.forEach(custom.remove) }
                    }
                }
                Section("Library") {
                    ForEach(library) { e in
                        row(name: e.name, detail: "\(e.muscles) · \(e.equipment)", tracking: Self.tracking(of: e))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search exercises or muscles")
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            // Always reachable, even while searching (the search bar takes over the top bar).
            .safeAreaInset(edge: .bottom) {
                if !chosen.isEmpty {
                    PrimaryButton(title: "Add \(chosen.count) exercise\(chosen.count == 1 ? "" : "s")", systemImage: "plus") {
                        onAdd(chosen); dismiss()
                    }
                    .accessibilityIdentifier("picker.add")
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.sm)
                    .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $creating) {
                NewExerciseView { name, tracking in choose(name, tracking) }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func row(name: String, detail: String, tracking: ExerciseTracking) -> some View {
        let picked = isChosen(name)
        return Button {
            if picked {
                chosen.removeAll { TrainingLogStore.key($0.name) == TrainingLogStore.key(name) }
            } else {
                choose(name, tracking)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.labelPrimary)
                    Text(detail).font(.footnote).foregroundStyle(Color.labelSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: picked ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(picked ? Color.ringProtein : Color.labelTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("picker.exercise.\(name)")
    }

    private func chip(_ label: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(on ? Color.dullPink : Color.surfaceSecondary, in: Capsule())
                .foregroundStyle(on ? Color.onAccent : Color.labelPrimary)
        }
        .buttonStyle(.plain)
    }
}

/// A new exercise of the person's own: its name, the muscles, and how it's measured.
/// A name the library or the person's own exercises already have isn't made twice:
/// the form says so, and its button adds the existing exercise instead.
private struct NewExerciseView: View {
    /// The exercise to add to the workout: its name and how it's measured.
    let onCreate: (String, ExerciseTracking) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscles = ""
    @State private var tracking: ExerciseTracking = .weightReps

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The exercise that already has this name, if any.
    private var existing: (name: String, tracking: ExerciseTracking, own: Bool)? {
        guard !cleanName.isEmpty else { return nil }
        if let own = CustomExerciseStore.shared.exercise(named: cleanName) { return (own.name, own.tracking, true) }
        if let known = Exercise.closestMatch(name: cleanName) { return (known.name, ExercisePickerView.tracking(of: known), false) }
        return nil
    }

    var body: some View {
        let existing = self.existing
        return NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Sled push", text: $name).accessibilityIdentifier("newExercise.name")
                    if existing == nil {
                        TextField("Muscles (optional)", text: $muscles)
                        Picker("Measured by", selection: $tracking) {
                            ForEach(ExerciseTracking.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                } footer: {
                    if let existing {
                        Text(existing.own
                             ? "You already have an exercise called \(existing.name). It won't be made twice; Add puts it in the workout."
                             : "\(existing.name) is already in the library. It won't be made twice; Add puts it in the workout.")
                            .foregroundStyle(Color.brandDanger)
                            .accessibilityIdentifier("newExercise.clash")
                    }
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Create" : "Add") {
                        if let existing {
                            onCreate(existing.name, existing.tracking)
                        } else {
                            let made = CustomExerciseStore.shared.add(name: cleanName, muscles: muscles, tracking: tracking)
                            onCreate(made.name, made.tracking)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(cleanName.isEmpty)
                    .accessibilityIdentifier("newExercise.create")
                }
            }
        }
    }
}
