import SwiftUI

/// Workout mode: one exercise at a time, a set at a time. Weight and reps are
/// filled from last time; Complete set starts the rest; the last set moves on to
/// the next exercise; Finish saves everything and shows what was achieved.
struct WorkoutModeView: View {
    @State var model: WorkoutModeModel
    var onClose: () -> Void

    @AppStorage(Constants.Storage.weightUnit) private var unit: WeightUnit = .kg
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var guide: ExerciseGuide?
    @State private var confirmLeave = false
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        enum Field { case weight, reps, seconds }
        let set: Int
        let field: Field
        var id: String { "\(set)-\(field)" }
    }

    var body: some View {
        ZStack {
            Color.surfaceGrouped.ignoresSafeArea()
            if let result = model.result {
                WorkoutSummaryView(workout: result, unit: unit, onDone: onClose)
                    .transition(.opacity)
            } else {
                running
            }
        }
        .animation(reduceMotion ? .reducedFade : .smoothCard, value: model.result == nil)
        .sheet(item: $guide) { ExerciseGuideSheet(guide: $0) }
        .sensoryFeedback(.success, trigger: model.setCount)
        .sensoryFeedback(.warning, trigger: model.restDoneCount)
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.recordCount)
        .confirmationDialog("Leave this workout?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Finish and save") { withAnimation { model.finish() } }
            Button("Discard workout", role: .destructive) { model.discard(); onClose() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("\(model.setsDone) of \(model.setsTotal) sets are done.")
        }
    }

    // MARK: - Running

    private var running: some View {
        VStack(spacing: 0) {
            header
            exerciseStrip
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let ex = model.current {
                        exerciseCard(ex)
                        setsCard(ex)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
            .scrollDismissesKeyboard(.immediately)
            bottomBar
        }
        .overlay(alignment: .bottom) { if model.restEndsAt != nil { restCard.padding(Spacing.lg).padding(.bottom, 96) } }
        .animation(reduceMotion ? .reducedFade : .smoothCard, value: model.restEndsAt)
        .animation(reduceMotion ? .reducedFade : .smoothCard, value: model.exerciseIndex)
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Button { confirmLeave = true } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Color.labelPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surface, in: Circle())
            }
            .accessibilityLabel("Leave workout")
            .accessibilityIdentifier("workoutMode.close")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.workout.title).font(.headline).lineLimit(1)
                Text("Exercise \(model.exerciseIndex + 1) of \(model.exercises.count) · \(model.setsDone)/\(model.setsTotal) sets")
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Text(timerInterval: model.startedAt...Date.distantFuture, countsDown: false)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .accessibilityLabel("Elapsed time")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }

    /// Every exercise as a pill: done, now, or still to come. Tap to jump.
    private var exerciseStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(model.exercises.enumerated()), id: \.element.id) { index, ex in
                        let done = ex.sets.allSatisfy(\.done)
                        let now = index == model.exerciseIndex
                        Button { model.go(to: index) } label: {
                            HStack(spacing: 6) {
                                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ringProtein) }
                                Text(ex.name).lineLimit(1)
                            }
                            .font(.subheadline.weight(now ? .semibold : .medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(now ? Color.dullPink : Color.surface, in: Capsule())
                            .foregroundStyle(now ? Color.onAccent : Color.labelPrimary)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityIdentifier("workoutMode.exercise.\(index + 1)")
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .onChange(of: model.exerciseIndex) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
        }
        .padding(.bottom, Spacing.xs)
    }

    // MARK: - The exercise

    private func exerciseCard(_ ex: LoggedExercise) -> some View {
        let item = ExerciseGuide(step: model.workout.exercises.first { $0.name == ex.name }
                                 ?? WorkoutExercise(name: ex.name, sets: ex.sets.count, reps: "", minutes: 0, restSeconds: ex.restSeconds, note: ""))
        let bests = TrainingLogStore.shared.bests(of: ex.name)
        return Button { guide = item } label: {
            HStack(alignment: .center, spacing: Spacing.md) {
                Group {
                    if let drawing = item.drawing {
                        ExerciseDrawingCanvas(drawing: drawing, frame: 1).padding(6)
                    } else if let motion = item.motion {
                        ExerciseFrame(motion: motion, finish: true).padding(6)
                    } else {
                        Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle).foregroundStyle(Color.labelSecondary)
                    }
                }
                .frame(width: 96, height: 96)
                .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name).font(.title3.weight(.bold)).foregroundStyle(Color.labelPrimary).multilineTextAlignment(.leading)
                    if let muscles = item.muscles, !muscles.isEmpty {
                        Text(muscles).font(.subheadline).foregroundStyle(Color.labelSecondary)
                    }
                    Text("Target \(ex.target)\(ex.restSeconds > 0 ? " · rest \(ex.restSeconds) s" : "")")
                        .font(.footnote.weight(.medium)).foregroundStyle(Color.labelSecondary)
                    if let best = bestText(bests, ex.tracking) {
                        Label(best, systemImage: "trophy.fill").font(.footnote.weight(.semibold)).foregroundStyle(Color.brandAmber)
                    }
                    Text("How to do it").font(.footnote.weight(.semibold)).foregroundStyle(Color.labelPrimary).underline()
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workoutMode.howTo")
    }

    private func bestText(_ b: ExerciseBests, _ tracking: ExerciseTracking) -> String? {
        switch tracking {
        case .weightReps: return b.heaviest.map { "Best \(TrainingFormat.weight($0, unit))" }
        case .reps:       return b.reps.map { "Best \($0) reps" }
        case .time:       return b.seconds.map { "Best \(TrainingFormat.duration($0))" }
        }
    }

    // MARK: - Sets

    private func setsCard(_ ex: LoggedExercise) -> some View {
        let previous = TrainingLogStore.shared.lastSets(of: ex.name)
        return VStack(spacing: 0) {
            HStack {
                Text("Set").frame(width: 40, alignment: .leading)
                Text("Last time").frame(maxWidth: .infinity, alignment: .leading)
                switch ex.tracking {
                case .weightReps: Text(unit.suffix).frame(width: 96); Text("Reps").frame(width: 76)
                case .reps:       Text("Reps").frame(width: 96)
                case .time:       Text("Time").frame(width: 96)
                }
                Color.clear.frame(width: 40, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.labelSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            ForEach(Array(ex.sets.enumerated()), id: \.element.id) { index, set in
                setRow(ex, set: set, index: index, previous: previous.indices.contains(index) ? previous[index] : nil)
                if index < ex.sets.count - 1 { Divider().padding(.leading, Spacing.md) }
            }

            HStack {
                Button { model.addSet() } label: { Label("Add set", systemImage: "plus") }
                    .accessibilityIdentifier("workoutMode.addSet")
                Spacer()
                if ex.sets.count > 1, let last = ex.sets.indices.last, !ex.sets[last].done {
                    Button(role: .destructive) { model.removeSet(last) } label: { Label("Remove last", systemImage: "minus") }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.labelPrimary)
            .padding(Spacing.md)
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .alert(editTitle, isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            EditField(initial: editInitial, keyboard: editing?.field == .weight ? .decimalPad : .numberPad) { text in
                apply(text)
            }
        } message: { Text(editMessage) }
    }

    private func setRow(_ ex: LoggedExercise, set: LoggedSet, index: Int, previous: LoggedSet?) -> some View {
        let isCurrent = index == model.currentSetIndex
        let record = model.isRecord(set, in: ex)
        return HStack(spacing: 0) {
            ZStack {
                Circle().fill(set.done ? Color.ringProtein : (isCurrent ? Color.dullPink : Color.surfaceSecondary))
                    .frame(width: 30, height: 30)
                Text("\(index + 1)").font(.footnote.weight(.bold))
                    .foregroundStyle(set.done || isCurrent ? Color.onAccent : Color.labelPrimary)
            }
            .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(previous.map { TrainingFormat.set($0, tracking: ex.tracking, unit: unit) } ?? "–")
                    .font(.footnote).foregroundStyle(Color.labelSecondary).lineLimit(1)
                if record { Text("PR").font(.caption2.weight(.heavy)).foregroundStyle(Color.brandAmber) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch ex.tracking {
            case .weightReps:
                valueCell(weightText(set.weightKg ?? 0), width: 96, done: set.done) { editing = EditTarget(set: index, field: .weight) }
                    .accessibilityIdentifier("workoutMode.weight.\(index + 1)")
                valueCell("\(set.reps ?? 0)", width: 76, done: set.done) { editing = EditTarget(set: index, field: .reps) }
                    .accessibilityIdentifier("workoutMode.reps.\(index + 1)")
            case .reps:
                valueCell("\(set.reps ?? 0)", width: 96, done: set.done) { editing = EditTarget(set: index, field: .reps) }
                    .accessibilityIdentifier("workoutMode.reps.\(index + 1)")
            case .time:
                valueCell(TrainingFormat.duration(set.seconds ?? 0), width: 96, done: set.done) { editing = EditTarget(set: index, field: .seconds) }
            }
            Button {
                if set.done { model.reopen(index) } else if isCurrent { model.completeSet() }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.done ? Color.ringProtein : (isCurrent ? Color.labelPrimary : Color.labelTertiary))
                    .frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!set.done && !isCurrent)
            .accessibilityLabel(set.done ? "Set \(index + 1) done. Tap to edit." : "Complete set \(index + 1)")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(isCurrent ? Color.dullPink.opacity(0.08) : Color.clear)
    }

    private func valueCell(_ text: String, width: CGFloat, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(done ? Color.labelSecondary : Color.labelPrimary)
                .frame(width: width - 10, height: 40)
                .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: width)
    }

    private func weightText(_ kg: Double) -> String {
        let v = unit == .kg ? kg : kg / WeightUnit.kgPerPound
        return v.rounded() == v ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    // MARK: Typing a value

    private var editTitle: String {
        switch editing?.field {
        case .weight: return "Weight (\(unit.suffix))"
        case .reps: return "Reps"
        case .seconds: return "Time (seconds)"
        case nil: return ""
        }
    }
    private var editMessage: String { "Set \((editing?.set ?? 0) + 1)" }
    private var editInitial: String {
        guard let e = editing, let ex = model.current, ex.sets.indices.contains(e.set) else { return "" }
        let s = ex.sets[e.set]
        switch e.field {
        case .weight: return weightText(s.weightKg ?? 0)
        case .reps: return "\(s.reps ?? 0)"
        case .seconds: return "\(s.seconds ?? 0)"
        }
    }
    private func apply(_ text: String) {
        guard let e = editing, let n = TypedNumber.parse(text) else { return }
        switch e.field {
        case .weight: model.setWeight(unit == .kg ? n : n * WeightUnit.kgPerPound, set: e.set)
        case .reps: model.setReps(Int(n.rounded()), set: e.set)
        case .seconds: model.setSeconds(Int(n.rounded()), set: e.set)
        }
        editing = nil
    }

    // MARK: - Rest

    private var restCard: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = max(0, (model.restEndsAt ?? context.date).timeIntervalSince(context.date))
            let fraction = model.restLength > 0 ? left / Double(model.restLength) : 0
            HStack(spacing: Spacing.lg) {
                ZStack {
                    Circle().stroke(Color.ringProtein.opacity(0.18), lineWidth: 8)
                    Circle().trim(from: 0, to: fraction).stroke(Color.ringProtein, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(TrainingFormat.duration(Int(left.rounded(.up))))
                        .font(.system(.headline, design: .rounded)).monospacedDigit()
                }
                .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rest").font(.headline)
                    if let ex = model.current, let i = model.currentSetIndex {
                        Text("Next: \(ex.name), set \(i + 1)").font(.footnote).foregroundStyle(Color.labelSecondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: Spacing.xs) {
                    Button("+15 s") { model.addRest(15) }
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 64, minHeight: 36)
                        .background(Color.surfaceSecondary, in: Capsule())
                    Button("Skip") { model.skipRest() }
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 64, minHeight: 36)
                        .background(Color.surfaceSecondary, in: Capsule())
                        .accessibilityIdentifier("workoutMode.skipRest")
                }
                .foregroundStyle(Color.labelPrimary)
            }
            .padding(Spacing.lg)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Bottom

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            if let ex = model.current, ex.tracking == .time, model.currentSetIndex != nil {
                timedControls
            } else if model.currentSetIndex != nil {
                PrimaryButton(title: "Complete set", systemImage: "checkmark") { model.completeSet() }
                    .accessibilityIdentifier("workoutMode.completeSet")
            } else if !model.isLastExercise && !model.allDone {
                PrimaryButton(title: "Next exercise", systemImage: "forward.fill") { model.go(to: model.exerciseIndex + 1) }
            }
            if model.allDone {
                PrimaryButton(title: "Finish workout", systemImage: "flag.checkered") { withAnimation { model.finish() } }
                    .accessibilityIdentifier("workoutMode.finish")
            } else {
                Button("Finish early") { confirmLeave = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(minHeight: 36)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }

    private var timedControls: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left: Int = {
                if let end = model.timerEndsAt { return max(0, Int(end.timeIntervalSince(context.date).rounded(.up))) }
                if let ex = model.current, let i = model.currentSetIndex { return ex.sets[i].seconds ?? 0 }
                return 0
            }()
            HStack(spacing: Spacing.md) {
                Text(TrainingFormat.duration(left))
                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .frame(minWidth: 110)
                if model.timerRunning {
                    SecondaryButton(title: "Pause", systemImage: "pause.fill") { model.pauseTimer() }
                } else {
                    PrimaryButton(title: "Start", systemImage: "play.fill") { model.startTimer() }
                        .accessibilityIdentifier("workoutMode.startTimer")
                }
                Button { model.completeSet() } label: {
                    Image(systemName: "checkmark").font(.headline).frame(width: 52, height: 52)
                        .background(Color.surface, in: Circle())
                }
                .foregroundStyle(Color.labelPrimary)
                .accessibilityLabel("Mark set done")
            }
        }
    }
}

/// The alert's text field, started with the current value.
private struct EditField: View {
    let initial: String
    let keyboard: UIKeyboardType
    let apply: (String) -> Void
    @State private var text = ""

    var body: some View {
        // Starts empty with the current value as the hint, so typing replaces it.
        TextField(initial, text: $text)
            .keyboardType(keyboard)
            .accessibilityIdentifier("workoutMode.valueField")
        Button("Cancel", role: .cancel) {}
        Button("Set") { if !text.isEmpty { apply(text) } }
    }
}

// MARK: - Summary

struct WorkoutSummaryView: View {
    let workout: LoggedWorkout
    let unit: WeightUnit
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    MascotGuideView(mood: .flex, size: 170, trigger: 1, hint: "Flexing for you.")
                        .padding(.top, Spacing.xl)
                    VStack(spacing: 6) {
                        Text("Workout done").font(.system(.largeTitle, design: .rounded).weight(.bold))
                        Text(workout.title).font(.headline).foregroundStyle(Color.labelSecondary)
                    }
                    HStack(spacing: Spacing.md) {
                        stat(TrainingFormat.duration(Int(workout.duration)), "Time")
                        stat("\(workout.setsDone)", "Sets")
                        stat(workout.volumeKg > 0 ? TrainingFormat.weight(workout.volumeKg, unit) : "–", "Lifted")
                    }
                    if !workout.records.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Label("New personal records", systemImage: "trophy.fill")
                                .font(.headline).foregroundStyle(Color.brandAmber)
                            ForEach(workout.records) { r in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.exercise).font(.subheadline.weight(.semibold))
                                    Text(r.text(unit: unit)).font(.footnote).foregroundStyle(Color.labelSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(Spacing.lg)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .accessibilityIdentifier("workoutSummary.records")
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(workout.exercises) { ex in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ex.name).font(.subheadline.weight(.semibold))
                                Text(ex.doneSets.map { TrainingFormat.set($0, tracking: ex.tracking, unit: unit) }.joined(separator: "  ·  "))
                                    .font(.footnote).foregroundStyle(Color.labelSecondary).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Spacing.lg)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                .padding(.horizontal, Spacing.lg)
            }
            PrimaryButton(title: "Done", systemImage: "checkmark") { onDone() }
                .accessibilityIdentifier("workoutSummary.done")
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.sm)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}
