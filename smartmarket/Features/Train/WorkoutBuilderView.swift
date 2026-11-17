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

    var step: WorkoutExercise {
        WorkoutExercise(name: name, sets: sets, reps: tracking == .time ? "\(seconds) sec" : "\(reps)", minutes: 0,
                        restSeconds: restSeconds, note: "", tracking: tracking,
                        weightKg: tracking == .weightReps && weightKg > 0 ? weightKg : nil)
    }

    init(name: String, tracking: ExerciseTracking) {
        self.name = name
        self.tracking = tracking
        if tracking == .time { restSeconds = 30 }
    }

    init(step: WorkoutExercise) {
        name = step.name
        tracking = ExerciseTracking.guess(for: step)
        sets = max(step.sets, 1)
        let number = Int(step.reps.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "")
        reps = number ?? 10
        seconds = WorkoutModeModel.seconds(in: step)
        weightKg = step.weightKg ?? 0
        restSeconds = step.restSeconds
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
                ExercisePickerView { picked in items.append(contentsOf: picked) }
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
        items = w.exercises.map(BuilderItem.init(step:))
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let workout = Workout(id: editing?.id ?? UUID(),
                              title: name.isEmpty ? "My \(kind.title.lowercased()) workout" : name,
                              summary: "Built by you · \(items.count) exercise\(items.count == 1 ? "" : "s")",
                              kind: kind, level: editing?.level ?? .intermediate, durationMinutes: minutes,
                              warmup: editing?.warmup ?? "5 minutes of easy movement to warm up.",
                              cooldown: editing?.cooldown ?? "A few minutes of easy stretching.",
                              exercises: items.map(\.step),
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
                        Stepper("Time: \(TrainingFormat.duration(item.seconds))", value: $item.seconds, in: 5...3600, step: 5)
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

    private var library: [Exercise] {
        Exercise.catalog.filter { e in
            (focus == nil || e.focus == focus)
                && (query.isEmpty || e.name.localizedStandardContains(query) || e.muscles.localizedStandardContains(query))
        }
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
                        row(name: e.name, detail: "\(e.muscles) · \(e.equipment)",
                            tracking: ExerciseTracking.guess(for: WorkoutExercise(name: e.name, sets: 3, reps: e.prescription.contains("min") || e.prescription.contains("sec") ? e.prescription : "10", minutes: 0, restSeconds: 60, note: "")))
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
                NewExerciseView { e in chosen.append(BuilderItem(name: e.name, tracking: e.tracking)) }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func row(name: String, detail: String, tracking: ExerciseTracking) -> some View {
        let isChosen = chosen.contains { $0.name == name }
        return Button {
            if isChosen { chosen.removeAll { $0.name == name } } else { chosen.append(BuilderItem(name: name, tracking: tracking)) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.labelPrimary)
                    Text(detail).font(.footnote).foregroundStyle(Color.labelSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: isChosen ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? Color.ringProtein : Color.labelTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("picker.exercise.\(name)")
    }

    private func chip(_ label: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(on ? Color.dullPink : Color.surfaceSecondary, in: Capsule())
                .foregroundStyle(on ? Color.onAccent : Color.labelPrimary)
        }
        .buttonStyle(.plain)
    }
}

/// A new exercise of the person's own: its name, the muscles, and how it's measured.
private struct NewExerciseView: View {
    let onCreate: (CustomExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscles = ""
    @State private var tracking: ExerciseTracking = .weightReps

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, e.g. Landmine press", text: $name).accessibilityIdentifier("newExercise.name")
                TextField("Muscles (optional)", text: $muscles)
                Picker("Measured by", selection: $tracking) {
                    ForEach(ExerciseTracking.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(CustomExerciseStore.shared.add(name: name, muscles: muscles, tracking: tracking))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("newExercise.create")
                }
            }
        }
    }
}
