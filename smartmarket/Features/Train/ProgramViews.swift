import SwiftUI

// MARK: - Programmes on the Train tab
//
// A "Programmes" section: the programme you follow (with its next day ready to
// start) and cards for every programme. A programme's page lists its days; each
// day opens as an ordinary workout, so it runs in workout mode and logs as usual.

struct ProgramsSection: View {
    /// Opens a programme day's workout.
    let open: (Workout) -> Void
    @State private var programs = ProgramStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Programmes").font(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.sm)
                NavigationLink { ProgramListView() } label: {
                    Text("See all")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("See all programmes")
                .accessibilityIdentifier("train.programmes.all")
            }

            if let program = programs.program, let index = programs.nextDayIndex {
                CurrentProgramCard(program: program, dayIndex: index, week: programs.week) {
                    open(program.workout(day: index))
                }
            } else {
                Text("Plans to follow week after week. Start one and Nourlo keeps track of the next day.")
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(WorkoutProgram.all) { program in
                        NavigationLink { ProgramDetailView(program: program) } label: {
                            ProgramCard(program: program, isCurrent: programs.isCurrent(program))
                        }
                        .buttonStyle(ScalePressStyle())
                        .accessibilityIdentifier("program." + program.id)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .scrollClipDisabled()
        }
    }
}

/// The programme being followed: where you are and a button for the next day.
private struct CurrentProgramCard: View {
    let program: WorkoutProgram
    let dayIndex: Int
    let week: Int
    let onStart: () -> Void

    var body: some View {
        let workout = program.workout(day: dayIndex)
        VStack(alignment: .leading, spacing: Spacing.md) {
            NavigationLink { ProgramDetailView(program: program) } label: {
                HStack(spacing: Spacing.md) {
                    ProgramSymbol(symbol: program.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your programme · week \(week)" as String)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.labelSecondary)
                        Text(program.name)
                            .font(.headline)
                            .foregroundStyle(Color.labelPrimary)
                            .multilineTextAlignment(.leading)
                        Text("Next: \(program.dayLabel(dayIndex))" as String)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.labelPrimary)
                        Text("\(workout.exercises.count) exercises · about \(workout.durationMinutes) min" as String)
                            .font(.footnote)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your programme, \(program.name), week \(week). Next: \(program.dayLabel(dayIndex))" as String)
            .accessibilityHint("Shows the programme's days")
            .accessibilityIdentifier("train.program.current")

            PrimaryButton(title: "Start day \(dayIndex + 1)", systemImage: "play.fill", action: onStart)
                .accessibilityLabel("Start \(program.dayLabel(dayIndex))" as String)
                .accessibilityIdentifier("train.program.next")
        }
        .padding(Spacing.lg)
        .premiumCard()
    }
}

private struct ProgramSymbol: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(Color.almond)
            .frame(width: 44, height: 44)
            .background(Color.rhino, in: RoundedRectangle(cornerRadius: Radius.chip))
            .accessibilityHidden(true)
    }
}

/// A programme in the horizontal row of cards.
private struct ProgramCard: View {
    let program: WorkoutProgram
    let isCurrent: Bool
    @ScaledMetric(relativeTo: .headline) private var width: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                ProgramSymbol(symbol: program.symbol)
                Spacer(minLength: Spacing.xs)
                if isCurrent {
                    Text("Following")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.brandLight, in: Capsule())
                        .foregroundStyle(Color.labelPrimary)
                }
            }
            Text(program.name)
                .font(.headline)
                .foregroundStyle(Color.labelPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)
            Text(program.facts)
                .font(.footnote)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)
        }
        .padding(Spacing.md)
        .frame(width: min(width, 280), alignment: .topLeading)
        .premiumCard(radius: Radius.tile)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(program.name), \(program.facts)\(isCurrent ? ", following" : "")" as String)
        .accessibilityHint("Shows the programme's days")
    }
}

// MARK: - All programmes

struct ProgramListView: View {
    @State private var programs = ProgramStore.shared

    var body: some View {
        List {
            ForEach(ProgramCategory.allCases) { category in
                let items = WorkoutProgram.all.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items) { program in
                            NavigationLink { ProgramDetailView(program: program) } label: {
                                HStack(alignment: .top, spacing: Spacing.md) {
                                    ProgramSymbol(symbol: program.symbol)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(program.name).font(.headline)
                                        Text(program.facts)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(Color.labelSecondary)
                                        Text(program.summary)
                                            .font(.footnote)
                                            .foregroundStyle(Color.labelSecondary)
                                            .lineLimit(3)
                                        if programs.isCurrent(program) {
                                            Label("Following", systemImage: "checkmark.circle.fill")
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(Color.labelPrimary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .accessibilityElement(children: .combine)
                            }
                            .accessibilityIdentifier("programList." + program.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Programmes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
    }
}

// MARK: - One programme

struct ProgramDetailView: View {
    let program: WorkoutProgram
    @State private var programs = ProgramStore.shared
    @State private var openDay: Workout?
    @State private var confirmSwitch = false
    @State private var confirmStop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCurrent: Bool { programs.isCurrent(program) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(program.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(program.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                    FlowLayout(spacing: Spacing.sm) {
                        fact("calendar", "\(program.daysPerWeek) days a week")
                        fact("chart.bar.fill", program.level.title)
                        fact("list.number", "\(program.days.count) different days")
                    }
                    Label(program.equipment, systemImage: "wrench.and.screwdriver")
                        .font(.footnote)
                        .foregroundStyle(Color.labelSecondary)
                    if program.days.count < program.daysPerWeek {
                        Text("Go through the days in order and start again from day 1: about \(program.daysPerWeek) sessions a week." as String)
                            .font(.footnote)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    if isCurrent, let label = programs.nextDayLabel {
                        Label("You're following this programme · week \(programs.week) · next: \(label)" as String,
                              systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.labelPrimary)
                            .accessibilityIdentifier("program.following")
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Section {
                ForEach(Array(program.days.enumerated()), id: \.element.id) { index, day in
                    let workout = program.workout(day: index)
                    let isNext = isCurrent && programs.nextDayIndex == index
                    Button { openDay = workout } label: {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: Spacing.sm) {
                                    Text(program.dayLabel(index))
                                        .font(.headline)
                                        .foregroundStyle(Color.labelPrimary)
                                    if isNext {
                                        Text("Next")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Color.brandLight, in: Capsule())
                                            .foregroundStyle(Color.labelPrimary)
                                    }
                                }
                                Text("\(workout.exercises.count) exercise\(workout.exercises.count == 1 ? "" : "s") · about \(workout.durationMinutes) min" as String)
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.labelPrimary)
                                Text(day.steps.map { "\($0.exercise) \(stepText($0))" }.joined(separator: "\n"))
                                    .font(.footnote)
                                    .foregroundStyle(Color.labelSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: Spacing.sm)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.labelTertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens the day's workout")
                    .accessibilityIdentifier("program.day.\(index + 1)")
                    .contextMenu {
                        if isCurrent && !isNext {
                            Button { programs.setNextDay(index) } label: {
                                Label("Make this the next day", systemImage: "arrow.uturn.right")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if isCurrent && !isNext {
                            Button("Do next") { programs.setNextDay(index) }
                        }
                    }
                }
            } header: {
                Text("Days")
            } footer: {
                Text(isCurrent
                     ? "Finish a day, or mark it as done, and the next one comes up. Swipe a day to do it next instead."
                     : "Tap a day to see its exercises and try it. Start the programme to keep track of the next day.")
            }

            Section {
                Label(WorkoutBuilder.safetyNote, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }

            if isCurrent {
                Section {
                    Button("Skip to the next day") { programs.advance() }
                        .accessibilityIdentifier("program.skip")
                    Button("Stop following", role: .destructive) { confirmStop = true }
                        .accessibilityIdentifier("program.stop")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Programme")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .navigationDestination(item: $openDay) { WorkoutDetailView(workout: $0, localReason: nil) }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isCurrent, let index = programs.nextDayIndex {
                    PrimaryButton(title: "Start day \(index + 1)", systemImage: "play.fill") {
                        openDay = program.workout(day: index)
                    }
                    .accessibilityLabel("Start \(program.dayLabel(index))" as String)
                    .accessibilityIdentifier("program.startNext")
                } else {
                    PrimaryButton(title: "Start this programme", systemImage: "flag.fill") {
                        if programs.program != nil { confirmSwitch = true } else { start() }
                    }
                    .accessibilityHint("Keeps track of which day comes next")
                    .accessibilityIdentifier("program.start")
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
        }
        .sensoryFeedback(.success, trigger: isCurrent)
        .confirmationDialog("Switch programme?", isPresented: $confirmSwitch, titleVisibility: .visible) {
            Button("Follow \(program.name) instead" as String) { start() }
            Button("Keep the current one", role: .cancel) {}
        } message: {
            Text("You're following \(programs.program?.name ?? "another programme"). Your logged workouts stay." as String)
        }
        .confirmationDialog("Stop following this programme?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop following", role: .destructive) {
                withAnimation(reduceMotion ? .reducedFade : .snappyValue) { programs.stop() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your logged workouts stay.")
        }
    }

    private func start() {
        withAnimation(reduceMotion ? .reducedFade : .snappyValue) { programs.start(program) }
    }

    /// "4 × 8", "20 min", "1 × 100 arm beats" written plainly.
    private func stepText(_ step: ProgramStep) -> String {
        if step.minutes > 0 { return "\(step.minutes) min" }
        return step.sets > 1 ? "\(step.sets) × \(step.reps)" : step.reps
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
        .accessibilityElement(children: .combine)
    }
}
