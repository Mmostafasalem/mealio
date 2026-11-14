import SwiftUI

/// Everything needed to explain one exercise.
struct ExerciseGuide: Identifiable {
    let id = UUID()
    let name: String
    /// `nil` when the movement isn't one the app can draw.
    let motion: ExerciseMotion?
    /// The hand-drawn frames, when the exercise has them (shown in place of the posed figure).
    let drawing: ExerciseDrawing?
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
        drawing = ExerciseDrawings.shared.drawing(forExercise: exercise.id)
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
        drawing = known.flatMap { ExerciseDrawings.shared.drawing(forExercise: $0.id) }
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

                    if let drawing = guide.drawing {
                        ExerciseDrawingDemo(drawing: drawing)
                            .frame(maxWidth: .infinity)
                            .frame(height: 300)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))

                        HStack(spacing: Spacing.sm) {
                            keyFrame(number: 1, label: "Start") { ExerciseDrawingCanvas(drawing: drawing, frame: 0).aspectRatio(1, contentMode: .fit) }
                            Image(systemName: "arrow.right")
                                .font(.headline)
                                .foregroundStyle(Color.labelSecondary)
                                .accessibilityHidden(true)
                            keyFrame(number: 2, label: "Finish") {
                                ExerciseDrawingCanvas(drawing: drawing, frame: drawing.frames.count - 1).aspectRatio(1, contentMode: .fit)
                            }
                        }

                        if let credit = ExerciseDrawings.shared.credit {
                            // The drawings are CC BY-SA 4.0: their authors are credited wherever they are shown.
                            Link(credit.text, destination: credit.link)
                                .font(.caption2)
                                .foregroundStyle(Color.labelSecondary)
                                .multilineTextAlignment(.leading)
                        }
                    } else if let motion = guide.motion {
                        ExerciseDemo(motion: motion)
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))

                        HStack(spacing: Spacing.sm) {
                            keyFrame(number: 1, label: motion.isContinuous ? "One side" : "Start") { ExerciseFrame(motion: motion, finish: false) }
                            Image(systemName: "arrow.right")
                                .font(.headline)
                                .foregroundStyle(Color.labelSecondary)
                                .accessibilityHidden(true)
                            keyFrame(number: 2, label: motion.isContinuous ? "Other side" : "Finish") { ExerciseFrame(motion: motion, finish: true) }
                        }

                        Label("Drag the figure to look around it.", systemImage: "hand.draw")
                            .font(.footnote)
                            .foregroundStyle(Color.labelSecondary)
                        if let clip = motion.clip {
                            // Captured movement is credited to whoever recorded it, as its licence asks.
                            Link(clip.credit.text, destination: clip.credit.link)
                                .font(.caption2)
                                .foregroundStyle(Color.labelSecondary)
                                .multilineTextAlignment(.leading)
                        }
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

    private func keyFrame<Picture: View>(number: Int, label: String, @ViewBuilder picture: () -> Picture) -> some View {
        VStack(spacing: Spacing.xs) {
            picture()
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
