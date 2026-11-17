import Charts
import SwiftUI

// MARK: - Progress
//
// What workout mode logged: totals, weekly volume, records, every exercise
// with its own chart, and every finished workout with its sets.

struct TrainingProgressView: View {
    @State private var log = TrainingLogStore.shared
    @AppStorage(Constants.Storage.weightUnit) private var unit: WeightUnit = .kg

    var body: some View {
        List {
            Section {
                HStack(spacing: Spacing.sm) {
                    tile("\(log.workouts.count)", "Workouts")
                    tile("\(thisWeek.count)", "This week")
                    tile("\(log.workouts.reduce(0) { $0 + $1.records.count })", "Records")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if !log.workouts.isEmpty {
                Section("Weight lifted per week") {
                    Chart(weeklyVolume, id: \.week) { point in
                        BarMark(x: .value("Week", point.week, unit: .weekOfYear), y: .value("Lifted", display(point.kg)))
                            .foregroundStyle(Color.ringCalories.gradient)
                            .cornerRadius(6)
                    }
                    .chartYAxisLabel(unit.suffix)
                    .frame(height: 180)
                    .padding(.vertical, Spacing.xs)
                    .accessibilityLabel("Weight lifted per week for the last eight weeks")
                }
            }

            let records = log.workouts.flatMap(\.records).sorted { $0.date > $1.date }
            if !records.isEmpty {
                Section("Recent records") {
                    ForEach(records.prefix(6)) { r in
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "trophy.fill").foregroundStyle(Color.brandAmber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.exercise).font(.subheadline.weight(.semibold))
                                Text(r.text(unit: unit)).font(.footnote).foregroundStyle(Color.labelSecondary)
                            }
                            Spacer()
                            Text(r.date.formatted(.dateTime.day().month(.abbreviated))).font(.footnote).foregroundStyle(Color.labelSecondary)
                        }
                    }
                }
            }

            if !exerciseNames.isEmpty {
                Section("Exercises") {
                    ForEach(exerciseNames, id: \.self) { name in
                        NavigationLink { ExerciseProgressView(name: name) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(.subheadline.weight(.semibold))
                                Text(exerciseSubtitle(name)).font(.footnote).foregroundStyle(Color.labelSecondary)
                            }
                        }
                        .accessibilityIdentifier("progress.exercise.\(name)")
                    }
                }
            }

            Section("Workouts") {
                if log.workouts.isEmpty {
                    Text("Workouts you do in workout mode show up here, with every set.")
                        .font(.subheadline).foregroundStyle(Color.labelSecondary)
                }
                ForEach(log.workouts) { w in
                    NavigationLink { LoggedWorkoutView(workout: w) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(w.title).font(.subheadline.weight(.semibold))
                                if !w.records.isEmpty { Image(systemName: "trophy.fill").font(.caption).foregroundStyle(Color.brandAmber) }
                            }
                            Text("\(w.finishedAt.formatted(date: .abbreviated, time: .shortened)) · \(TrainingFormat.duration(Int(w.duration))) · \(w.setsDone) sets")
                                .font(.footnote).foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { log.remove(w) } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Progress")
        .accessibilityIdentifier("progress.list")
    }

    private var thisWeek: [LoggedWorkout] {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return log.workouts.filter { $0.finishedAt >= start }
    }

    /// The last eight weeks, oldest first, with empty weeks as zero.
    private var weeklyVolume: [(week: Date, kg: Double)] {
        let cal = Calendar.current
        let thisStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<8).reversed().map { back in
            let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisStart) ?? thisStart
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return (start, log.workouts.filter { $0.finishedAt >= start && $0.finishedAt < end }.reduce(0) { $0 + $1.volumeKg })
        }
    }

    private func display(_ kg: Double) -> Double { unit == .kg ? kg : kg / WeightUnit.kgPerPound }

    /// Every exercise logged, most recently done first.
    private var exerciseNames: [String] {
        var seen = Set<String>(), names: [String] = []
        for w in log.workouts { for e in w.exercises where seen.insert(TrainingLogStore.key(e.name)).inserted { names.append(e.name) } }
        return names
    }

    private func exerciseSubtitle(_ name: String) -> String {
        let history = log.history(of: name)
        let b = log.bests(of: name)
        let best: String
        switch history.first?.exercise.tracking {
        case .weightReps: best = b.heaviest.map { "best \(TrainingFormat.weight($0, unit))" } ?? ""
        case .reps: best = b.reps.map { "best \($0) reps" } ?? ""
        case .time: best = b.seconds.map { "best \(TrainingFormat.duration($0))" } ?? ""
        case nil: best = ""
        }
        return ["\(history.count) time\(history.count == 1 ? "" : "s")", best].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

// MARK: - One exercise

struct ExerciseProgressView: View {
    let name: String
    @State private var log = TrainingLogStore.shared
    @AppStorage(Constants.Storage.weightUnit) private var unit: WeightUnit = .kg

    private var history: [(date: Date, exercise: LoggedExercise)] { log.history(of: name) }
    private var tracking: ExerciseTracking { history.first?.exercise.tracking ?? .reps }

    /// One point per session, oldest first: the best weight, reps or time that day.
    private var points: [(date: Date, value: Double)] {
        history.reversed().map { entry in
            let b = TrainingLogStore.bests(of: entry.exercise.doneSets)
            let value: Double
            switch tracking {
            case .weightReps: value = (b.heaviest ?? 0) / (unit == .kg ? 1 : WeightUnit.kgPerPound)
            case .reps: value = Double(b.reps ?? 0)
            case .time: value = Double(b.seconds ?? 0)
            }
            return (entry.date, value)
        }
    }

    var body: some View {
        List {
            Section {
                let b = log.bests(of: name)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        switch tracking {
                        case .weightReps:
                            best("Heaviest", b.heaviest.map { TrainingFormat.weight($0, unit) })
                            best("Est. 1-rep max", b.oneRepMax.map { TrainingFormat.weight($0, unit) })
                        case .reps:
                            best("Most reps", b.reps.map(String.init))
                        case .time:
                            best("Longest", b.seconds.map(TrainingFormat.duration))
                        }
                        best("Sessions", "\(history.count)")
                    }
                    if points.count > 1 {
                        Chart(points, id: \.date) { p in
                            LineMark(x: .value("Date", p.date), y: .value(chartLabel, p.value))
                                .foregroundStyle(Color.ringCalories)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", p.date), y: .value(chartLabel, p.value))
                                .foregroundStyle(Color.ringCalories)
                        }
                        .chartYAxisLabel(chartLabel)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .frame(height: 200)
                        .padding(.top, Spacing.sm)
                    } else {
                        Text("Do it once more to see your progress on a chart.")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Section("Every time") {
                ForEach(Array(history.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                        Text(entry.exercise.doneSets.map { TrainingFormat.set($0, tracking: tracking, unit: unit) }.joined(separator: "  ·  "))
                            .font(.footnote).foregroundStyle(Color.labelSecondary).monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chartLabel: String {
        switch tracking {
        case .weightReps: return unit.suffix
        case .reps: return "reps"
        case .time: return "seconds"
        }
    }

    private func best(_ label: String, _ value: String?) -> some View {
        VStack(spacing: 4) {
            Text(value ?? "–").font(.system(.headline, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

// MARK: - One finished workout

struct LoggedWorkoutView: View {
    let workout: LoggedWorkout
    @AppStorage(Constants.Storage.weightUnit) private var unit: WeightUnit = .kg

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.title).font(.title3.weight(.bold))
                    Text("\(workout.finishedAt.formatted(date: .complete, time: .shortened))")
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                    Text("\(TrainingFormat.duration(Int(workout.duration))) · \(workout.setsDone) sets\(workout.volumeKg > 0 ? " · \(TrainingFormat.weight(workout.volumeKg, unit)) lifted" : "")")
                        .font(.subheadline)
                }
            }
            if !workout.records.isEmpty {
                Section("Records") {
                    ForEach(workout.records) { r in
                        Label("\(r.exercise): \(r.text(unit: unit))", systemImage: "trophy.fill").font(.subheadline)
                    }
                }
            }
            ForEach(workout.exercises) { ex in
                Section(ex.name) {
                    ForEach(Array(ex.doneSets.enumerated()), id: \.offset) { i, set in
                        HStack {
                            Text("Set \(i + 1)").foregroundStyle(Color.labelSecondary)
                            Spacer()
                            Text(TrainingFormat.set(set, tracking: ex.tracking, unit: unit)).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}
