import Foundation

// MARK: - Exercise catalogue
//
// A small, well-known set of exercises the app ships with. It powers the
// exercise library and the on-device workout builder (used when online AI is
// off or unavailable). General fitness information, not medical advice.

enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
    case gym, cardio, home, mobility
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gym:      return "Gym"
        case .cardio:   return "Cardio"
        case .home:     return "Home"
        case .mobility: return "Mobility"
        }
    }

    var detail: String {
        switch self {
        case .gym:      return "Weights and machines"
        case .cardio:   return "Running, cycling, intervals"
        case .home:     return "Bodyweight, little or no kit"
        case .mobility: return "Stretching and joints"
        }
    }

    var symbol: String {
        switch self {
        case .gym:      return "dumbbell.fill"
        case .cardio:   return "figure.run"
        case .home:     return "house.fill"
        case .mobility: return "figure.flexibility"
        }
    }

    /// Rough energy cost (MET) of a typical session of this kind, for the
    /// "about N kcal" estimate. Compendium of Physical Activities ballparks.
    var met: Double {
        switch self {
        case .gym:      return 4.5
        case .cardio:   return 7.5
        case .home:     return 4.0
        case .mobility: return 2.5
        }
    }
}

enum ExerciseLevel: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ExerciseFocus: String, Codable, CaseIterable, Identifiable {
    case fullBody, upper, lower, core
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullBody: return "Full body"
        case .upper:    return "Upper body"
        case .lower:    return "Lower body"
        case .core:     return "Core"
        }
    }
}

struct Exercise: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: ExerciseKind
    /// `nil` for cardio and whole-body mobility work.
    let focus: ExerciseFocus?
    let muscles: String
    let equipment: String
    let level: ExerciseLevel
    /// Typical prescription, e.g. "3 × 10" or "20 min".
    let prescription: String
    /// One or two sentences on how to do it well.
    let howTo: String

    static let catalog: [Exercise] = [
        // Gym
        .init(id: "back-squat", name: "Back squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Barbell, rack", level: .intermediate, prescription: "3 × 8", howTo: "Brace, sit between your hips and keep your whole foot planted. Stand up by driving the floor away."),
        .init(id: "goblet-squat", name: "Goblet squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Dumbbell or kettlebell", level: .beginner, prescription: "3 × 10", howTo: "Hold the weight at your chest, elbows down. Squat as deep as you can keep your chest tall."),
        .init(id: "romanian-deadlift", name: "Romanian deadlift", kind: .gym, focus: .lower, muscles: "Hamstrings, glutes", equipment: "Barbell or dumbbells", level: .intermediate, prescription: "3 × 10", howTo: "Soft knees, push your hips back and slide the weight down your thighs. Stop when your back would round."),
        .init(id: "leg-press", name: "Leg press", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Leg press machine", level: .beginner, prescription: "3 × 12", howTo: "Lower until your knees are about 90 degrees, keep your lower back on the pad and don't lock out hard."),
        .init(id: "walking-lunge", name: "Walking lunge", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Dumbbells", level: .intermediate, prescription: "3 × 10 each side", howTo: "Take a long step, drop the back knee toward the floor and push through the front heel."),
        .init(id: "bench-press", name: "Bench press", kind: .gym, focus: .upper, muscles: "Chest, triceps, shoulders", equipment: "Barbell, bench", level: .intermediate, prescription: "3 × 8", howTo: "Shoulder blades pinched, feet planted. Lower to mid-chest and press back over your shoulders."),
        .init(id: "dumbbell-bench-press", name: "Dumbbell bench press", kind: .gym, focus: .upper, muscles: "Chest, triceps", equipment: "Dumbbells, bench", level: .beginner, prescription: "3 × 10", howTo: "Lower the dumbbells beside your chest with elbows about 45 degrees out, then press up and slightly in."),
        .init(id: "overhead-press", name: "Overhead press", kind: .gym, focus: .upper, muscles: "Shoulders, triceps", equipment: "Barbell or dumbbells", level: .intermediate, prescription: "3 × 8", howTo: "Squeeze glutes and ribs down. Press straight up and finish with the weight over the middle of your foot."),
        .init(id: "lat-pulldown", name: "Lat pulldown", kind: .gym, focus: .upper, muscles: "Lats, biceps", equipment: "Cable machine", level: .beginner, prescription: "3 × 12", howTo: "Pull the bar to your upper chest by driving your elbows down. Control it all the way up."),
        .init(id: "seated-row", name: "Seated cable row", kind: .gym, focus: .upper, muscles: "Mid-back, biceps", equipment: "Cable machine", level: .beginner, prescription: "3 × 12", howTo: "Sit tall, pull the handle to your lower ribs and squeeze your shoulder blades together."),
        .init(id: "dumbbell-row", name: "One-arm dumbbell row", kind: .gym, focus: .upper, muscles: "Lats, mid-back", equipment: "Dumbbell, bench", level: .beginner, prescription: "3 × 10 each side", howTo: "Flat back, pull the dumbbell toward your hip and lower it under control."),
        .init(id: "cable-woodchop", name: "Cable woodchop", kind: .gym, focus: .core, muscles: "Obliques", equipment: "Cable machine", level: .intermediate, prescription: "3 × 10 each side", howTo: "Rotate through your trunk, not your arms, and keep your hips facing forward."),
        .init(id: "hanging-knee-raise", name: "Hanging knee raise", kind: .gym, focus: .core, muscles: "Abs, hip flexors", equipment: "Pull-up bar", level: .intermediate, prescription: "3 × 10", howTo: "Hang with shoulders active, curl your knees to your chest without swinging."),
        // Home
        .init(id: "bodyweight-squat", name: "Bodyweight squat", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "None", level: .beginner, prescription: "3 × 15", howTo: "Feet shoulder-width, sit back and down, keep heels on the floor and knees over toes."),
        .init(id: "reverse-lunge", name: "Reverse lunge", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "None", level: .beginner, prescription: "3 × 10 each side", howTo: "Step back, lower both knees to about 90 degrees and drive up through the front foot."),
        .init(id: "glute-bridge", name: "Glute bridge", kind: .home, focus: .lower, muscles: "Glutes, hamstrings", equipment: "None", level: .beginner, prescription: "3 × 15", howTo: "Push through your heels until hips are level with knees and shoulders. Pause, then lower."),
        .init(id: "step-up", name: "Step-up", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "Sturdy step or chair", level: .beginner, prescription: "3 × 10 each side", howTo: "Stand up on the top leg without pushing off the bottom foot. Lower slowly."),
        .init(id: "push-up", name: "Push-up", kind: .home, focus: .upper, muscles: "Chest, triceps, core", equipment: "None", level: .beginner, prescription: "3 × 10", howTo: "Body in one line from head to heels. Lower your chest to the floor; use your knees if needed."),
        .init(id: "pike-push-up", name: "Pike push-up", kind: .home, focus: .upper, muscles: "Shoulders, triceps", equipment: "None", level: .intermediate, prescription: "3 × 8", howTo: "Hips high in an upside-down V. Lower the top of your head between your hands and press back."),
        .init(id: "chair-dip", name: "Chair dip", kind: .home, focus: .upper, muscles: "Triceps", equipment: "Sturdy chair", level: .beginner, prescription: "3 × 10", howTo: "Hands on the chair edge, lower until elbows are about 90 degrees and keep shoulders away from your ears."),
        .init(id: "superman", name: "Superman hold", kind: .home, focus: .upper, muscles: "Lower back, glutes", equipment: "None", level: .beginner, prescription: "3 × 20 sec", howTo: "Lying face down, lift arms and legs a little and hold while looking at the floor."),
        .init(id: "plank", name: "Plank", kind: .home, focus: .core, muscles: "Abs, shoulders", equipment: "None", level: .beginner, prescription: "3 × 30 sec", howTo: "Elbows under shoulders, squeeze glutes and keep hips level with your shoulders."),
        .init(id: "dead-bug", name: "Dead bug", kind: .home, focus: .core, muscles: "Deep abs", equipment: "None", level: .beginner, prescription: "3 × 8 each side", howTo: "Lower back pressed to the floor. Extend the opposite arm and leg slowly, then switch."),
        .init(id: "mountain-climber", name: "Mountain climber", kind: .home, focus: .core, muscles: "Abs, hip flexors", equipment: "None", level: .intermediate, prescription: "3 × 30 sec", howTo: "From a push-up position, drive knees to chest one at a time while keeping hips low."),
        .init(id: "burpee", name: "Burpee", kind: .home, focus: .fullBody, muscles: "Whole body", equipment: "None", level: .advanced, prescription: "3 × 8", howTo: "Squat, kick back to a plank, return and jump. Step instead of jumping to make it easier."),
        // Cardio
        .init(id: "brisk-walk", name: "Brisk walk", kind: .cardio, focus: nil, muscles: "Heart, legs", equipment: "None", level: .beginner, prescription: "30 min", howTo: "Walk fast enough that you can talk but not sing. Swing your arms and stay tall."),
        .init(id: "easy-run", name: "Easy run", kind: .cardio, focus: nil, muscles: "Heart, legs", equipment: "Running shoes", level: .beginner, prescription: "20 min", howTo: "Keep a pace where you can hold a conversation. Take walk breaks whenever you need them."),
        .init(id: "run-intervals", name: "Run intervals", kind: .cardio, focus: nil, muscles: "Heart, legs", equipment: "Running shoes", level: .intermediate, prescription: "6 × 1 min hard, 2 min easy", howTo: "Hard means you could only say a few words. Jog or walk the easy parts fully."),
        .init(id: "cycling", name: "Steady cycling", kind: .cardio, focus: nil, muscles: "Heart, quads", equipment: "Bike or exercise bike", level: .beginner, prescription: "30 min", howTo: "Spin at a steady effort you could keep up for an hour. Keep your shoulders relaxed."),
        .init(id: "rowing", name: "Rowing machine", kind: .cardio, focus: nil, muscles: "Heart, back, legs", equipment: "Rower", level: .intermediate, prescription: "15 min", howTo: "Push with the legs first, then lean back and pull. Reverse the order on the way forward."),
        .init(id: "jump-rope", name: "Jump rope", kind: .cardio, focus: nil, muscles: "Heart, calves", equipment: "Rope", level: .intermediate, prescription: "8 × 45 sec on, 30 sec off", howTo: "Small jumps on the balls of your feet, wrists turning the rope."),
        .init(id: "stair-climb", name: "Stair climbing", kind: .cardio, focus: nil, muscles: "Heart, glutes", equipment: "Stairs or stepper", level: .beginner, prescription: "15 min", howTo: "Use the whole foot on each step and keep a pace you can sustain."),
        .init(id: "swimming", name: "Swimming", kind: .cardio, focus: nil, muscles: "Heart, whole body", equipment: "Pool", level: .intermediate, prescription: "20 min", howTo: "Alternate easy lengths with short rests. Breathe out fully under water."),
        // Mobility
        .init(id: "cat-cow", name: "Cat-cow", kind: .mobility, focus: nil, muscles: "Spine", equipment: "None", level: .beginner, prescription: "2 × 10", howTo: "On hands and knees, slowly round your back up, then let it sag while lifting your chest."),
        .init(id: "worlds-greatest-stretch", name: "World's greatest stretch", kind: .mobility, focus: nil, muscles: "Hips, upper back", equipment: "None", level: .beginner, prescription: "2 × 5 each side", howTo: "From a deep lunge, drop the inside elbow toward the floor, then rotate that arm up to the ceiling."),
        .init(id: "hip-flexor-stretch", name: "Hip flexor stretch", kind: .mobility, focus: nil, muscles: "Hip flexors", equipment: "None", level: .beginner, prescription: "2 × 30 sec each side", howTo: "Half-kneeling, tuck your tailbone and shift forward until the front of the hip stretches."),
        .init(id: "hamstring-stretch", name: "Hamstring stretch", kind: .mobility, focus: nil, muscles: "Hamstrings", equipment: "None", level: .beginner, prescription: "2 × 30 sec each side", howTo: "Leg straight in front, hinge from the hips with a long back until you feel the stretch."),
        .init(id: "thoracic-rotation", name: "Thoracic rotation", kind: .mobility, focus: nil, muscles: "Upper back", equipment: "None", level: .beginner, prescription: "2 × 8 each side", howTo: "On hands and knees, one hand behind your head. Rotate that elbow down, then up to the ceiling."),
        .init(id: "shoulder-circles", name: "Shoulder circles", kind: .mobility, focus: nil, muscles: "Shoulders", equipment: "None", level: .beginner, prescription: "2 × 10 each way", howTo: "Slow, large circles with straight arms. Keep your ribs still."),
        .init(id: "childs-pose", name: "Child's pose", kind: .mobility, focus: nil, muscles: "Back, hips", equipment: "None", level: .beginner, prescription: "1 min", howTo: "Knees wide, sit back onto your heels and reach your arms forward. Breathe slowly."),
        .init(id: "ankle-rocks", name: "Ankle rocks", kind: .mobility, focus: nil, muscles: "Ankles, calves", equipment: "None", level: .beginner, prescription: "2 × 10 each side", howTo: "Half-kneeling, drive the front knee over the toes while the heel stays down."),
    ]
}

// MARK: - Workouts

struct WorkoutExercise: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    /// 0 for a single timed block.
    let sets: Int
    /// "10", "8 each side", "30 sec", or a pace description for cardio.
    let reps: String
    /// Minutes for timed or cardio blocks; 0 for sets and reps.
    let minutes: Int
    let restSeconds: Int
    let note: String

    /// "3 × 10", "12 min", or "3 × 30 sec".
    var prescription: String {
        if minutes > 0 { return reps.isEmpty ? "\(minutes) min" : "\(minutes) min · \(reps)" }
        if sets > 1 { return "\(sets) × \(reps)" }
        return reps
    }
}

struct Workout: Codable, Hashable, Identifiable {
    var id = UUID()
    let title: String
    let summary: String
    let kind: ExerciseKind
    let level: ExerciseLevel
    let durationMinutes: Int
    let warmup: String
    let cooldown: String
    let exercises: [WorkoutExercise]
    let safetyNote: String
    /// "ai" when the online service wrote it, "local" when built on this device.
    var source: String = "local"
    var createdAt = Date()

    var isFromAI: Bool { source == "ai" }

    /// Rough energy use for someone of this weight (MET × kg × hours).
    func estimatedCalories(weightKg: Double) -> Int {
        Int((kind.met * max(weightKg, 30) * Double(durationMinutes) / 60).rounded())
    }
}

/// What the person asked for. Sent to the AI service, or used on device.
struct WorkoutRequest: Codable {
    struct Person: Codable {
        let age: Int
        let gender: String
        let weight: Double
        let height: Double
        let activityLevel: String
        let goal: String
    }

    let kind: String
    let level: String
    let minutes: Int
    let focus: String
    let equipment: [String]
    /// The person's own words: what they want from this session.
    let request: String
    let user: Person

    init(kind: ExerciseKind, level: ExerciseLevel, minutes: Int, focus: ExerciseFocus,
         wishes: String, profile: UserProfile) {
        self.kind = kind.rawValue
        self.level = level.rawValue
        self.minutes = minutes
        self.focus = focus.title
        self.equipment = []
        self.request = String(wishes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        self.user = Person(age: profile.age, gender: profile.gender.rawValue, weight: profile.weight,
                           height: profile.height, activityLevel: profile.activityLevel.rawValue,
                           goal: profile.weightGoal.rawValue)
    }
}

/// The service's reply. Mirrors `handle_workout` in the backend.
struct WorkoutResponse: Codable {
    let title: String
    let summary: String
    let kind: String
    let level: String
    let durationMinutes: Int
    let warmup: String
    let cooldown: String
    let exercises: [WorkoutExercise]
    let safetyNote: String

    func workout(source: String) -> Workout? {
        guard !title.isEmpty, !exercises.isEmpty else { return nil }
        return Workout(title: title, summary: summary, kind: ExerciseKind(rawValue: kind) ?? .home,
                       level: ExerciseLevel(rawValue: level) ?? .beginner, durationMinutes: durationMinutes,
                       warmup: warmup, cooldown: cooldown, exercises: exercises, safetyNote: safetyNote,
                       source: source)
    }
}

/// A session the person marked as done.
struct CompletedWorkout: Codable, Hashable, Identifiable {
    var id = UUID()
    let title: String
    let kind: ExerciseKind
    let minutes: Int
    let calories: Int
    var date = Date()
}
