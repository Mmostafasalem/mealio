import Foundation

// MARK: - Workout programmes
//
// Multi-day plans people follow week after week (push / pull / legs, upper / lower,
// Pilates, HYROX …). Every day is a list of catalogue exercises with sets, reps or
// time and rest, turned into an ordinary `Workout` so it runs in workout mode and
// logs like any other session. All on the device. General fitness information, not
// medical advice.

/// One exercise in a programme day. `exercise` is a catalogue name (`Exercise.named`).
struct ProgramStep: Hashable {
    let exercise: String
    let sets: Int
    /// "8", "10 each side", "30 sec", "25 m"; for a timed block, how to pace it.
    let reps: String
    /// Minutes for a timed block (a run, a row); 0 for sets and reps.
    var minutes: Int = 0
    let rest: Int

    static func sets(_ exercise: String, _ sets: Int, _ reps: String, rest: Int) -> ProgramStep {
        ProgramStep(exercise: exercise, sets: sets, reps: reps, rest: rest)
    }

    static func block(_ exercise: String, minutes: Int, _ pace: String) -> ProgramStep {
        ProgramStep(exercise: exercise, sets: 1, reps: pace, minutes: minutes, rest: 0)
    }
}

struct ProgramDay: Hashable, Identifiable {
    let id: String
    /// Short name: "Push", "Upper A", "Stations".
    let title: String
    let kind: ExerciseKind
    let steps: [ProgramStep]
}

enum ProgramCategory: String, CaseIterable, Identifiable {
    case strength, home, pilates, hyrox, running
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: return "Gym splits"
        case .home:     return "At home"
        case .pilates:  return "Pilates"
        case .hyrox:    return "HYROX"
        case .running:  return "Running"
        }
    }

    var symbol: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .home:     return "house.fill"
        case .pilates:  return "figure.pilates"
        case .hyrox:    return "figure.cross.training"
        case .running:  return "figure.run"
        }
    }
}

struct WorkoutProgram: Hashable, Identifiable {
    let id: String
    let name: String
    let summary: String
    let category: ProgramCategory
    /// Training days in a week. Can be more than `days.count` when the days repeat
    /// (the Arnold split runs its three days twice a week).
    let daysPerWeek: Int
    let level: ExerciseLevel
    let equipment: String
    let days: [ProgramDay]

    var symbol: String { category.symbol }

    /// "3 days a week · Intermediate".
    var facts: String { "\(daysPerWeek) day\(daysPerWeek == 1 ? "" : "s") a week · \(level.title)" }

    /// "Day 2 · Pull".
    func dayLabel(_ index: Int) -> String {
        guard days.indices.contains(index) else { return "" }
        return "Day \(index + 1) · \(days[index].title)"
    }

    /// The day as a workout to run in workout mode. The same day always gives the same
    /// workout (id and content), so a session left running resumes and is logged once a day.
    func workout(day index: Int) -> Workout {
        let index = min(max(index, 0), days.count - 1)
        let day = days[index]
        let exercises = day.steps.map { step -> WorkoutExercise in
            let known = Exercise.named(step.exercise)
            return WorkoutExercise(name: known?.name ?? step.exercise, sets: step.sets, reps: step.reps,
                                   minutes: step.minutes, restSeconds: step.rest, note: known?.howTo ?? "")
        }
        let warmupSeconds = 8 * 60
        return Workout(
            id: Self.stableID("\(id)|\(day.id)"),
            title: "\(name): \(dayLabel(index))",
            summary: summary,
            kind: day.kind, level: level,
            durationMinutes: Workout.estimatedMinutes(of: exercises, extraSeconds: warmupSeconds),
            warmup: warmup, cooldown: cooldown,
            exercises: exercises, safetyNote: WorkoutBuilder.safetyNote)
    }

    private var warmup: String {
        switch category {
        case .pilates: return "A minute of easy breathing lying down, then a few pelvic tilts and cat-cows."
        case .running: return "5 minutes of brisk walking, building to an easy jog."
        case .hyrox:   return "5 minutes of easy rowing or jogging, then a few light reps of the first station."
        case .strength, .home: return "5 minutes of easy movement, then one light set of the first exercise."
        }
    }

    private var cooldown: String {
        switch category {
        case .pilates: return "Child's pose and a few slow breaths."
        case .running, .hyrox: return "5 minutes of easy walking, then stretch your calves and hips."
        case .strength, .home: return "3 minutes of slow breathing and light stretching."
        }
    }

    /// A UUID made from a string, the same on every launch (FNV-1a, twice).
    static func stableID(_ key: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
            return hash
        }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * UInt64(i))) }
        for i in 0..<8 { bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * UInt64(i))) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40            // version 4 layout
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - The programmes

extension WorkoutProgram {

    static func named(id: String) -> WorkoutProgram? { all.first { $0.id == id } }

    private typealias S = ProgramStep

    // Days shared by more than one programme.
    private static let push = ProgramDay(id: "push", title: "Push", kind: .gym, steps: [
        S.sets("Bench press", 4, "8", rest: 120), S.sets("Overhead press", 3, "8", rest: 90),
        S.sets("Incline dumbbell press", 3, "10", rest: 90), S.sets("Lateral raise", 3, "12", rest: 60),
        S.sets("Triceps pushdown", 3, "12", rest: 60),
    ])
    private static let pull = ProgramDay(id: "pull", title: "Pull", kind: .gym, steps: [
        S.sets("Deadlift", 3, "5", rest: 150), S.sets("Lat pulldown", 3, "10", rest: 90),
        S.sets("Barbell row", 3, "8", rest: 90), S.sets("Face pull", 3, "15", rest: 60),
        S.sets("Biceps curl", 3, "12", rest: 60), S.sets("Hammer curl", 2, "12", rest: 60),
    ])
    private static let legs = ProgramDay(id: "legs", title: "Legs", kind: .gym, steps: [
        S.sets("Back squat", 4, "6", rest: 150), S.sets("Romanian deadlift", 3, "8", rest: 120),
        S.sets("Leg press", 3, "12", rest: 90), S.sets("Lying leg curl", 3, "12", rest: 60),
        S.sets("Standing calf raise", 4, "12", rest: 60), S.sets("Hanging knee raise", 3, "12", rest: 60),
    ])

    static let all: [WorkoutProgram] = [
        WorkoutProgram(
            id: "ppl-3", name: "Push, pull, legs",
            summary: "Pushing muscles one day, pulling the next, legs the third. A classic way to train every muscle once a week.",
            category: .strength, daysPerWeek: 3, level: .intermediate, equipment: "Gym: barbell, dumbbells, cables",
            days: [push, pull, legs]),
        WorkoutProgram(
            id: "ppl-6", name: "Push, pull, legs twice a week",
            summary: "The same split run twice, with a different version of each day, so every muscle is trained twice a week.",
            category: .strength, daysPerWeek: 6, level: .advanced, equipment: "Gym: barbell, dumbbells, cables, machines",
            days: [
                ProgramDay(id: "push-a", title: "Push A", kind: .gym, steps: push.steps),
                ProgramDay(id: "pull-a", title: "Pull A", kind: .gym, steps: pull.steps),
                ProgramDay(id: "legs-a", title: "Legs A", kind: .gym, steps: legs.steps),
                ProgramDay(id: "push-b", title: "Push B", kind: .gym, steps: [
                    S.sets("Overhead press", 4, "6", rest: 120), S.sets("Incline bench press", 3, "8", rest: 90),
                    S.sets("Cable fly", 3, "12", rest: 60), S.sets("Cable lateral raise", 3, "15", rest: 60),
                    S.sets("Overhead triceps extension", 3, "12", rest: 60),
                ]),
                ProgramDay(id: "pull-b", title: "Pull B", kind: .gym, steps: [
                    S.sets("Pull-up", 4, "8", rest: 120), S.sets("Seated cable row", 3, "10", rest: 90),
                    S.sets("One-arm dumbbell row", 3, "10 each side", rest: 60), S.sets("Rear delt fly", 3, "15", rest: 60),
                    S.sets("Preacher curl", 3, "10", rest: 60),
                ]),
                ProgramDay(id: "legs-b", title: "Legs B", kind: .gym, steps: [
                    S.sets("Front squat", 3, "8", rest: 150), S.sets("Bulgarian split squat", 3, "10 each side", rest: 90),
                    S.sets("Hip thrust", 3, "10", rest: 90), S.sets("Leg extension", 3, "12", rest: 60),
                    S.sets("Seated leg curl", 3, "12", rest: 60), S.sets("Seated calf raise", 4, "15", rest: 45),
                ]),
            ]),
        WorkoutProgram(
            id: "upper-lower", name: "Upper / lower",
            summary: "Upper body and lower body take turns over four days: a heavier day and a lighter day for each.",
            category: .strength, daysPerWeek: 4, level: .intermediate, equipment: "Gym: barbell, dumbbells, cables",
            days: [
                ProgramDay(id: "upper-a", title: "Upper A", kind: .gym, steps: [
                    S.sets("Bench press", 4, "6", rest: 150), S.sets("Barbell row", 4, "6", rest: 120),
                    S.sets("Overhead press", 3, "8", rest: 90), S.sets("Lat pulldown", 3, "10", rest: 90),
                    S.sets("Biceps curl", 2, "12", rest: 60), S.sets("Triceps pushdown", 2, "12", rest: 60),
                ]),
                ProgramDay(id: "lower-a", title: "Lower A", kind: .gym, steps: [
                    S.sets("Back squat", 4, "6", rest: 150), S.sets("Romanian deadlift", 3, "8", rest: 120),
                    S.sets("Walking lunge", 3, "10 each side", rest: 90), S.sets("Standing calf raise", 3, "12", rest: 60),
                    S.sets("Plank", 3, "45 sec", rest: 45),
                ]),
                ProgramDay(id: "upper-b", title: "Upper B", kind: .gym, steps: [
                    S.sets("Incline dumbbell press", 3, "10", rest: 90), S.sets("Pull-up", 3, "8", rest: 90),
                    S.sets("Seated dumbbell press", 3, "10", rest: 90), S.sets("Seated cable row", 3, "10", rest: 90),
                    S.sets("Lateral raise", 3, "15", rest: 45), S.sets("Hammer curl", 2, "12", rest: 60),
                    S.sets("Overhead triceps extension", 2, "12", rest: 60),
                ]),
                ProgramDay(id: "lower-b", title: "Lower B", kind: .gym, steps: [
                    S.sets("Deadlift", 3, "5", rest: 180), S.sets("Leg press", 3, "12", rest: 90),
                    S.sets("Lying leg curl", 3, "12", rest: 60), S.sets("Bulgarian split squat", 3, "10 each side", rest: 90),
                    S.sets("Seated calf raise", 3, "15", rest: 45), S.sets("Hanging knee raise", 3, "12", rest: 60),
                ]),
            ]),
        WorkoutProgram(
            id: "full-body-3", name: "Full body",
            summary: "Three short sessions that each work the whole body. A good first gym programme.",
            category: .strength, daysPerWeek: 3, level: .beginner, equipment: "Gym: dumbbells, cables, machines",
            days: [
                ProgramDay(id: "full-a", title: "Full body A", kind: .gym, steps: [
                    S.sets("Goblet squat", 3, "10", rest: 90), S.sets("Dumbbell bench press", 3, "10", rest: 90),
                    S.sets("Lat pulldown", 3, "10", rest: 90), S.sets("Romanian deadlift", 3, "10", rest: 90),
                    S.sets("Plank", 3, "30 sec", rest: 45),
                ]),
                ProgramDay(id: "full-b", title: "Full body B", kind: .gym, steps: [
                    S.sets("Leg press", 3, "12", rest: 90), S.sets("Overhead press", 3, "10", rest: 90),
                    S.sets("Seated cable row", 3, "10", rest: 90), S.sets("Hip thrust", 3, "10", rest: 90),
                    S.sets("Dead bug", 3, "8 each side", rest: 45),
                ]),
                ProgramDay(id: "full-c", title: "Full body C", kind: .gym, steps: [
                    S.sets("Walking lunge", 3, "10 each side", rest: 90), S.sets("Incline dumbbell press", 3, "10", rest: 90),
                    S.sets("One-arm dumbbell row", 3, "10 each side", rest: 60), S.sets("Lying leg curl", 3, "12", rest: 60),
                    S.sets("Lateral raise", 2, "12", rest: 45), S.sets("Side plank", 3, "20 sec each side", rest: 45),
                ]),
            ]),
        WorkoutProgram(
            id: "five-by-five", name: "5 × 5 strength",
            summary: "Two short barbell days, A and B, taken in turn three times a week. Add a little weight each time all five sets go well.",
            category: .strength, daysPerWeek: 3, level: .beginner, equipment: "Barbell, rack, bench",
            days: [
                ProgramDay(id: "five-a", title: "Workout A", kind: .gym, steps: [
                    S.sets("Back squat", 5, "5", rest: 180), S.sets("Bench press", 5, "5", rest: 180),
                    S.sets("Barbell row", 5, "5", rest: 180),
                ]),
                ProgramDay(id: "five-b", title: "Workout B", kind: .gym, steps: [
                    S.sets("Back squat", 5, "5", rest: 180), S.sets("Overhead press", 5, "5", rest: 180),
                    S.sets("Deadlift", 1, "5", rest: 180),
                ]),
            ]),
        WorkoutProgram(
            id: "bro-split", name: "Bro split",
            summary: "One muscle group a day over five days: chest, back, shoulders, arms and legs. Lots of sets for each.",
            category: .strength, daysPerWeek: 5, level: .intermediate, equipment: "Gym: barbell, dumbbells, cables, machines",
            days: [
                ProgramDay(id: "chest", title: "Chest", kind: .gym, steps: [
                    S.sets("Bench press", 4, "8", rest: 120), S.sets("Incline dumbbell press", 3, "10", rest: 90),
                    S.sets("Dumbbell fly", 3, "12", rest: 60), S.sets("Pec deck", 3, "12", rest: 60),
                    S.sets("Chest dip", 3, "10", rest: 90),
                ]),
                ProgramDay(id: "back", title: "Back", kind: .gym, steps: [
                    S.sets("Deadlift", 3, "5", rest: 180), S.sets("Pull-up", 3, "8", rest: 120),
                    S.sets("Barbell row", 3, "8", rest: 90), S.sets("Seated cable row", 3, "10", rest: 90),
                    S.sets("Straight-arm pulldown", 3, "12", rest: 60),
                ]),
                ProgramDay(id: "shoulders", title: "Shoulders", kind: .gym, steps: [
                    S.sets("Overhead press", 4, "8", rest: 120), S.sets("Arnold press", 3, "10", rest: 90),
                    S.sets("Lateral raise", 4, "12", rest: 45), S.sets("Rear delt fly", 3, "15", rest: 45),
                    S.sets("Barbell shrug", 3, "12", rest: 60),
                ]),
                ProgramDay(id: "arms", title: "Arms", kind: .gym, steps: [
                    S.sets("EZ-bar curl", 3, "10", rest: 60), S.sets("Close-grip bench press", 3, "8", rest: 90),
                    S.sets("Hammer curl", 3, "12", rest: 60), S.sets("Skull crusher", 3, "10", rest: 60),
                    S.sets("Preacher curl", 3, "12", rest: 60), S.sets("Rope triceps pushdown", 3, "12", rest: 60),
                ]),
                ProgramDay(id: "legs", title: "Legs", kind: .gym, steps: [
                    S.sets("Back squat", 4, "8", rest: 150), S.sets("Romanian deadlift", 3, "10", rest: 120),
                    S.sets("Leg press", 3, "12", rest: 90), S.sets("Leg extension", 3, "12", rest: 60),
                    S.sets("Lying leg curl", 3, "12", rest: 60), S.sets("Standing calf raise", 4, "15", rest: 45),
                ]),
            ]),
        WorkoutProgram(
            id: "arnold-split", name: "Arnold split",
            summary: "Chest and back, then shoulders and arms, then legs, done twice a week. Demanding: for people used to training.",
            category: .strength, daysPerWeek: 6, level: .advanced, equipment: "Gym: barbell, dumbbells, cables, pull-up bar",
            days: [
                ProgramDay(id: "chest-back", title: "Chest and back", kind: .gym, steps: [
                    S.sets("Bench press", 4, "8", rest: 120), S.sets("Pull-up", 4, "8", rest: 120),
                    S.sets("Incline dumbbell press", 3, "10", rest: 90), S.sets("Barbell row", 3, "10", rest: 90),
                    S.sets("Dumbbell fly", 3, "12", rest: 60), S.sets("T-bar row", 3, "10", rest: 90),
                ]),
                ProgramDay(id: "shoulders-arms", title: "Shoulders and arms", kind: .gym, steps: [
                    S.sets("Overhead press", 4, "8", rest: 120), S.sets("Lateral raise", 3, "12", rest: 45),
                    S.sets("Rear delt fly", 3, "12", rest: 45), S.sets("Biceps curl", 3, "10", rest: 60),
                    S.sets("Skull crusher", 3, "10", rest: 60), S.sets("Hammer curl", 3, "12", rest: 60),
                    S.sets("Triceps pushdown", 3, "12", rest: 60),
                ]),
                ProgramDay(id: "legs", title: "Legs", kind: .gym, steps: [
                    S.sets("Back squat", 4, "8", rest: 150), S.sets("Romanian deadlift", 3, "10", rest: 120),
                    S.sets("Walking lunge", 3, "10 each side", rest: 90), S.sets("Leg extension", 3, "12", rest: 60),
                    S.sets("Lying leg curl", 3, "12", rest: 60), S.sets("Standing calf raise", 4, "15", rest: 45),
                    S.sets("Hanging leg raise", 3, "10", rest: 60),
                ]),
            ]),
        WorkoutProgram(
            id: "home-start", name: "Home start",
            summary: "Three gentle bodyweight sessions to build a habit. No kit: a mat, a wall, a chair and a towel.",
            category: .home, daysPerWeek: 3, level: .beginner, equipment: "No kit: mat, wall, chair, towel",
            days: [
                ProgramDay(id: "home-1", title: "Legs and push", kind: .home, steps: [
                    S.sets("Bodyweight squat", 3, "12", rest: 45), S.sets("Knee push-up", 3, "8", rest: 45),
                    S.sets("Glute bridge", 3, "12", rest: 45), S.sets("Superman hold", 3, "20 sec", rest: 30),
                    S.sets("Plank", 3, "20 sec", rest: 30),
                ]),
                ProgramDay(id: "home-2", title: "Pull and core", kind: .home, steps: [
                    S.sets("Reverse lunge", 3, "8 each side", rest: 45), S.sets("Incline push-up", 3, "10", rest: 45),
                    S.sets("Towel row", 3, "10", rest: 45), S.sets("Dead bug", 3, "8 each side", rest: 30),
                    S.sets("Jumping jacks", 3, "30 sec", rest: 30),
                ]),
                ProgramDay(id: "home-3", title: "Whole body", kind: .home, steps: [
                    S.sets("Step-up", 3, "10 each side", rest: 45), S.sets("Wall push-up", 3, "12", rest: 30),
                    S.sets("Bird dog", 3, "8 each side", rest: 30), S.sets("Wall sit", 3, "30 sec", rest: 45),
                    S.block("Marching", minutes: 5, "steady pace, arms swinging"),
                ]),
            ]),
        WorkoutProgram(
            id: "pilates-beginner", name: "Mat Pilates for beginners",
            summary: "The first exercises of the classical mat order, slow and controlled: breathing, a steady pelvis and a strong centre.",
            category: .pilates, daysPerWeek: 3, level: .beginner, equipment: "A mat",
            days: [
                ProgramDay(id: "pilates-b-1", title: "Foundations", kind: .home, steps: [
                    S.sets("The hundred", 1, "100 arm beats", rest: 20), S.sets("Roll-up", 1, "6 slow reps", rest: 20),
                    S.sets("Single-leg circles", 1, "5 each way, each leg", rest: 20),
                    S.sets("Rolling like a ball", 1, "8", rest: 20), S.sets("Single-leg stretch", 2, "8 each side", rest: 20),
                    S.sets("Spine stretch forward", 1, "5 slow reps", rest: 15), S.sets("Shoulder bridge", 2, "8", rest: 30),
                ]),
                ProgramDay(id: "pilates-b-2", title: "Back and hips", kind: .home, steps: [
                    S.sets("Swan", 2, "6", rest: 20), S.sets("Side kick series", 2, "10 each side", rest: 20),
                    S.sets("Shoulder bridge", 3, "8", rest: 30), S.sets("Saw", 1, "5 each side", rest: 15),
                    S.sets("Spine twist", 1, "5 each side", rest: 15), S.sets("Plank", 2, "30 sec", rest: 30),
                    S.sets("Mermaid stretch", 1, "4 each side", rest: 15),
                ]),
                ProgramDay(id: "pilates-b-3", title: "Core flow", kind: .home, steps: [
                    S.sets("The hundred", 1, "100 arm beats", rest: 20), S.sets("Single-leg stretch", 2, "8 each side", rest: 20),
                    S.sets("Single-leg circles", 1, "5 each way, each leg", rest: 20),
                    S.sets("Rolling like a ball", 1, "8", rest: 20), S.sets("Swan", 2, "6", rest: 20),
                    S.sets("Side kick series", 1, "10 each side", rest: 20),
                    S.sets("Spine stretch forward", 1, "5 slow reps", rest: 15),
                ]),
            ]),
        WorkoutProgram(
            id: "pilates-intermediate", name: "Mat Pilates: core and control",
            summary: "The fuller mat order with the harder abdominal series, the teaser and plank work. For people who know the basics.",
            category: .pilates, daysPerWeek: 3, level: .intermediate, equipment: "A mat",
            days: [
                ProgramDay(id: "pilates-i-1", title: "Classical order", kind: .home, steps: [
                    S.sets("The hundred", 1, "100 arm beats", rest: 15), S.sets("Roll-up", 1, "6 slow reps", rest: 15),
                    S.sets("Single-leg circles", 1, "5 each way, each leg", rest: 15),
                    S.sets("Rolling like a ball", 1, "8", rest: 15), S.sets("Single-leg stretch", 1, "10 each side", rest: 15),
                    S.sets("Double-leg stretch", 1, "8", rest: 15), S.sets("Pilates scissors", 1, "8 each side", rest: 15),
                    S.sets("Criss-cross", 1, "8 each side", rest: 15), S.sets("Spine stretch forward", 1, "5 slow reps", rest: 15),
                    S.sets("Open-leg rocker", 1, "6", rest: 15), S.sets("Saw", 1, "5 each side", rest: 15),
                    S.sets("Swan", 1, "6", rest: 15),
                ]),
                ProgramDay(id: "pilates-i-2", title: "Strength", kind: .home, steps: [
                    S.sets("Pilates swimming", 3, "30 sec", rest: 20), S.sets("Leg pull front", 2, "6 each leg", rest: 30),
                    S.sets("Side plank", 2, "30 sec each side", rest: 30), S.sets("Shoulder bridge", 3, "8 each leg", rest: 30),
                    S.sets("Double-leg stretch", 2, "10", rest: 20), S.sets("Criss-cross", 2, "10 each side", rest: 20),
                    S.sets("Teaser", 3, "3", rest: 30),
                ]),
                ProgramDay(id: "pilates-i-3", title: "Core focus", kind: .home, steps: [
                    S.sets("The hundred", 1, "100 arm beats", rest: 15), S.sets("Double-leg stretch", 2, "8", rest: 20),
                    S.sets("Pilates scissors", 2, "8 each side", rest: 20), S.sets("Criss-cross", 2, "8 each side", rest: 20),
                    S.sets("Teaser", 2, "4", rest: 30), S.sets("Hollow body hold", 3, "20 sec", rest: 30),
                    S.sets("Spine twist", 1, "5 each side", rest: 15), S.sets("Mermaid stretch", 1, "4 each side", rest: 15),
                ]),
            ]),
        WorkoutProgram(
            id: "hyrox", name: "HYROX training",
            summary: "Running plus the eight race stations: SkiErg, sled push and pull, burpee broad jumps, rowing, farmers carry, sandbag lunges and wall balls.",
            category: .hyrox, daysPerWeek: 4, level: .intermediate,
            equipment: "Gym: SkiErg, rower, sled, sandbag, medicine ball, dumbbells",
            days: [
                ProgramDay(id: "hyrox-run", title: "Running intervals", kind: .cardio, steps: [
                    S.block("Run intervals", minutes: 30, "6 × 800 m at race pace, 2 min easy between"),
                    S.sets("Wall ball", 3, "15", rest: 60),
                ]),
                ProgramDay(id: "hyrox-stations", title: "Station strength", kind: .gym, steps: [
                    S.sets("Sled push", 4, "25 m", rest: 90), S.sets("Sled pull", 4, "25 m", rest: 90),
                    S.sets("Sandbag lunge", 3, "20 m", rest: 90), S.sets("Dumbbell farmer carry", 4, "50 m", rest: 60),
                    S.sets("Wall ball", 3, "20", rest: 60),
                ]),
                ProgramDay(id: "hyrox-engine", title: "Engine", kind: .cardio, steps: [
                    S.block("SkiErg", minutes: 10, "4 × 500 m, 1 min easy between"),
                    S.block("Rowing machine", minutes: 10, "4 × 500 m, 1 min easy between"),
                    S.sets("Burpee broad jump", 4, "10", rest: 60),
                    S.block("Easy run", minutes: 20, "conversational pace"),
                ]),
                ProgramDay(id: "hyrox-race", title: "Race practice", kind: .gym, steps: [
                    S.block("Easy run", minutes: 8, "1 km steady, then straight into the stations"),
                    S.block("SkiErg", minutes: 5, "1000 m"), S.sets("Sled push", 2, "25 m", rest: 60),
                    S.sets("Sled pull", 2, "25 m", rest: 60), S.sets("Burpee broad jump", 1, "40 m", rest: 60),
                    S.block("Rowing machine", minutes: 5, "1000 m"), S.block("Dumbbell farmer carry", minutes: 3, "200 m"),
                    S.sets("Sandbag lunge", 1, "50 m", rest: 60), S.sets("Wall ball", 1, "50, in sets of 10", rest: 0),
                    S.block("Run intervals", minutes: 16, "4 × 1 km at race pace, 1 min walk between"),
                ]),
            ]),
        WorkoutProgram(
            id: "run-5k", name: "Run 5 km",
            summary: "Three runs a week: run-walk intervals, an easy run and a longer run. Repeat the week until 30 minutes feels easy.",
            category: .running, daysPerWeek: 3, level: .beginner, equipment: "Running shoes",
            days: [
                ProgramDay(id: "run-walk", title: "Run-walk", kind: .cardio, steps: [
                    S.block("Run intervals", minutes: 21, "1 min jog, 2 min walk, 7 times"),
                ]),
                ProgramDay(id: "run-easy", title: "Easy run", kind: .cardio, steps: [
                    S.block("Easy run", minutes: 20, "slow enough to talk"),
                ]),
                ProgramDay(id: "run-long", title: "Long run", kind: .cardio, steps: [
                    S.block("Long run", minutes: 30, "easy; walk breaks are fine"),
                ]),
            ]),
    ]
}
