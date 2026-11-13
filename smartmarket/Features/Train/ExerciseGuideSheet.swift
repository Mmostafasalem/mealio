import SwiftUI

/// Everything needed to explain one exercise.
struct ExerciseGuide: Identifiable {
    let id = UUID()
    let name: String
    /// `nil` when the movement isn't one the app can draw.
    let motion: ExerciseMotion?
    /// How to do it, one instruction per step.
    let steps: [String]
    var muscles: String? = nil
    var equipment: String? = nil
    var level: String? = nil
    /// What to do in this workout, e.g. "3 × 10 · rest 60 sec".
    var prescription: String? = nil

    init(exercise: Exercise) {
        name = exercise.name
        motion = exercise.motion
        steps = Self.sentences(exercise.howTo)
        muscles = exercise.muscles
        equipment = exercise.equipment
        level = exercise.level.title
        prescription = "Typical: \(exercise.prescription)"
    }

    /// A step in a workout. Uses the catalogue entry when the name matches one.
    init(step: WorkoutExercise) {
        let known = Exercise.catalog.first { $0.name.caseInsensitiveCompare(step.name) == .orderedSame }
        name = step.name
        motion = known?.motion ?? ExerciseMotion.matching(name: step.name)
        let cue = step.note.isEmpty ? (known?.howTo ?? "") : step.note
        steps = Self.sentences(cue)
        muscles = known?.muscles
        equipment = known?.equipment
        prescription = step.restSeconds > 0 ? "\(step.prescription) · rest \(step.restSeconds) sec" : step.prescription
    }

    private static func sentences(_ text: String) -> [String] {
        text.split(whereSeparator: { ".;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() + "." }
    }
}

/// A full-screen explanation of one exercise: the movement playing large,
/// the start and finish positions side by side, then numbered steps.
struct ExerciseGuideSheet: View {
    let guide: ExerciseGuide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(guide.name)
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.labelPrimary)
                        if let muscles = guide.muscles {
                            Text("Works: \(muscles)").font(.subheadline).foregroundStyle(Color.labelSecondary)
                        }
                        if let prescription = guide.prescription, !prescription.isEmpty {
                            Text(prescription)
                                .font(.headline).monospacedDigit()
                                .foregroundStyle(Color.labelPrimary)
                                .padding(.top, Spacing.xs)
                        }
                    }

                    if let motion = guide.motion {
                        ExerciseDemo(motion: motion)
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))

                        HStack(spacing: Spacing.sm) {
                            keyFrame(motion, finish: false, number: 1, label: motion.isContinuous ? "One side" : "Start")
                            Image(systemName: "arrow.right")
                                .font(.headline)
                                .foregroundStyle(Color.labelSecondary)
                                .accessibilityHidden(true)
                            keyFrame(motion, finish: true, number: 2, label: motion.isContinuous ? "Other side" : "Finish")
                        }

                        HStack(spacing: Spacing.sm) {
                            Circle().fill(Color.progress).frame(width: 10, height: 10)
                            Text("Pink shows the part of the body that moves.")
                                .font(.footnote).foregroundStyle(Color.labelSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if !guide.steps.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("How to do it").font(.sectionTitle)
                            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                                    Text("\(index + 1)")
                                        .font(.footnote.weight(.bold)).monospacedDigit()
                                        .foregroundStyle(Color.onAccent)
                                        .frame(width: 24, height: 24)
                                        .background(Color.dullPink, in: Circle())
                                    Text(step).font(.body).foregroundStyle(Color.labelPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    if guide.equipment != nil || guide.level != nil {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            if let equipment = guide.equipment { Label("Equipment: \(equipment)", systemImage: "wrench.and.screwdriver") }
                            if let level = guide.level { Label("Level: \(level)", systemImage: "chart.bar.fill") }
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                    }

                    Label(WorkoutBuilder.safetyNote, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(Spacing.xl)
            }
            .background(Color.surfaceGrouped.ignoresSafeArea())
            .navigationTitle("How to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("exerciseGuide.done")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func keyFrame(_ motion: ExerciseMotion, finish: Bool, number: Int, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            ExerciseFrame(motion: motion, finish: finish)
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
            Text("\(number). \(label)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) position")
    }
}

#Preview {
    ExerciseGuideSheet(guide: ExerciseGuide(exercise: Exercise.catalog[0]))
}
