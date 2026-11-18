import SwiftUI

/// Everything needed to explain one exercise.
struct ExerciseGuide: Identifiable {
    let id = UUID()
    let name: String
    /// `nil` when the movement isn't one the app can draw.
    let motion: ExerciseMotion?
    /// The catalogue exercise whose hand-drawn frames to show (in place of the posed figure), if any.
    let drawingID: String?
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
        drawingID = exercise.id
        steps = Self.sentences(exercise.howTo)
        muscles = exercise.muscles
        equipment = exercise.equipment
        level = exercise.level.title
        prescription = "Typical: \(exercise.prescription)"
    }

    /// A step in a workout. Uses the catalogue entry when the name matches one.
    init(step: WorkoutExercise) {
        let known = Self.catalogueEntry(named: step.name)
        name = step.name
        motion = known?.motion ?? ExerciseMotion.matching(name: step.name)
        drawingID = known?.id
        let cue = step.note.isEmpty ? (known?.howTo ?? "") : step.note
        steps = Self.sentences(cue)
        muscles = known?.muscles
        equipment = known?.equipment
        prescription = step.restSeconds > 0 ? "\(step.prescription) · rest \(step.restSeconds) sec" : step.prescription
    }

    /// The catalogue exercise a step is: by its name, or for an interval block
    /// ("Jump rope intervals") by the drill it is made of.
    static func catalogueEntry(named name: String) -> Exercise? {
        if let known = Exercise.closestMatch(name: name) { return known }
        let suffix = " intervals"
        guard name.lowercased().hasSuffix(suffix) else { return nil }
        return Exercise.closestMatch(name: String(name.dropLast(suffix.count)))
    }

    /// The hand-drawn frames, once the drawings have loaded and this one's paths are
    /// built off the main thread (`nil` before, and for exercises without one).
    /// Reading it in a view's body updates the view when it is ready.
    @MainActor var drawing: ExerciseDrawing? {
        drawingID.flatMap { ExerciseDrawingsStatus.shared.drawing(forExercise: $0) }
    }

    /// True while a drawing for this exercise is still loading or being built, so a placeholder can stand in.
    @MainActor var drawingPending: Bool {
        drawingID.map { ExerciseDrawingsStatus.shared.isPending(forExercise: $0) } ?? false
    }

    /// What VoiceOver reads for the demo.
    var demoDescription: String {
        guard let muscles, !muscles.isEmpty else { return "Demonstration of \(name)" }
        return "Demonstration of \(name), works \(muscles.lowercased())"
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
                        ExerciseDrawingDemo(drawing: drawing, description: guide.demoDescription)
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

                        // The drawings are CC BY-SA 4.0: their authors are credited wherever they are shown.
                        ExerciseDrawingCredit()
                    } else if guide.drawingPending {
                        // The drawings are still loading (only right after launch): a quiet placeholder.
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Color.surface)
                            .overlay(ProgressView())
                            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
                            .frame(height: 300)
                            .accessibilityLabel("Loading the demonstration")
                    } else if let motion = guide.motion {
                        ExerciseDemo(motion: motion)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(guide.demoDescription)
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
