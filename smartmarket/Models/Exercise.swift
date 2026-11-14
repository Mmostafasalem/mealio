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
        .init(id: "superman", name: "Superman hold", kind: .home, focus: .core, muscles: "Lower back, glutes", equipment: "None", level: .beginner, prescription: "3 × 20 sec", howTo: "Lying face down, lift arms and legs a little and hold while looking at the floor."),
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
        // Captured-movement additions.
        .init(id: "lateral-raise", name: "Lateral raise", kind: .gym, focus: .upper, muscles: "Shoulders", equipment: "Dumbbells", level: .beginner, prescription: "3 × 12", howTo: "Lift the weights out to your sides until your arms are level with your shoulders, elbows soft. Lower slowly."),
        .init(id: "reverse-fly", name: "Bent-over reverse fly", kind: .gym, focus: .upper, muscles: "Rear shoulders, upper back", equipment: "Dumbbells", level: .beginner, prescription: "3 × 12", howTo: "Hinge forward with a flat back and open your arms out wide, squeezing your shoulder blades. Lower with control."),
        .init(id: "single-leg-deadlift", name: "Single-leg deadlift", kind: .home, focus: .lower, muscles: "Hamstrings, glutes", equipment: "None", level: .intermediate, prescription: "3 × 8 each side", howTo: "Stand on one leg and tip forward from the hip as the other leg lifts behind you. Keep your back flat and hips level."),
        .init(id: "side-lunge", name: "Side lunge", kind: .home, focus: .lower, muscles: "Quads, glutes, inner thighs", equipment: "None", level: .beginner, prescription: "3 × 10 each side", howTo: "Take a wide stance and sit back into one hip, keeping the other leg straight. Push back to the middle."),
        .init(id: "jump-squat", name: "Jump squat", kind: .home, focus: .lower, muscles: "Quads, glutes, calves", equipment: "None", level: .intermediate, prescription: "3 × 10", howTo: "Sink into a squat, then jump straight up. Land softly and go straight into the next one."),
        .init(id: "squat-and-reach", name: "Squat and reach", kind: .home, focus: .fullBody, muscles: "Legs, shoulders", equipment: "None", level: .beginner, prescription: "3 × 12", howTo: "Squat down and touch the floor, then stand tall and reach both arms overhead."),
        .init(id: "leg-extension-crunch", name: "Seated knee tuck", kind: .home, focus: .core, muscles: "Abs", equipment: "Mat", level: .beginner, prescription: "3 × 12", howTo: "Sit leaning back on your hands. Draw your knees in toward your chest, then stretch your legs out without letting your feet rest."),
        .init(id: "standing-knee-lift", name: "Standing knee lift", kind: .home, focus: .core, muscles: "Abs, obliques", equipment: "None", level: .beginner, prescription: "3 × 20", howTo: "Stand tall and lift one knee toward your chest as your arms come down to meet it. Alternate sides."),
        .init(id: "windmill-toe-touch", name: "Windmill toe touch", kind: .home, focus: .core, muscles: "Obliques, hamstrings", equipment: "None", level: .beginner, prescription: "3 × 16", howTo: "Feet wide, arms out. Fold and reach one hand to the opposite foot, stand up, then go the other way."),
        .init(id: "jumping-jack", name: "Jumping jacks", kind: .cardio, focus: nil, muscles: "Heart, calves, shoulders", equipment: "None", level: .beginner, prescription: "4 × 30 sec", howTo: "Jump your feet wide as your arms swing overhead, then jump back. Stay light on your feet."),
        .init(id: "high-knees", name: "High knees", kind: .cardio, focus: nil, muscles: "Heart, hip flexors, calves", equipment: "None", level: .beginner, prescription: "4 × 30 sec", howTo: "Run on the spot lifting each knee to hip height. Stay tall and pump your arms."),
        .init(id: "marching", name: "Marching", kind: .cardio, focus: nil, muscles: "Heart, legs", equipment: "None", level: .beginner, prescription: "5 min", howTo: "March with a high knee on every step and swing your arms from the elbows."),
        .init(id: "front-kick", name: "Front kicks", kind: .cardio, focus: nil, muscles: "Heart, quads, core", equipment: "None", level: .beginner, prescription: "3 × 30 sec", howTo: "Step and kick straight out in front, alternating legs. Keep your standing knee soft and your chest up."),
        .init(id: "skipping", name: "Skips", kind: .cardio, focus: nil, muscles: "Heart, calves", equipment: "None", level: .beginner, prescription: "3 × 40 sec", howTo: "Skip with a small hop on each step, driving the opposite knee and arm up."),
        .init(id: "shadow-boxing", name: "Shadow boxing", kind: .cardio, focus: nil, muscles: "Heart, shoulders, core", equipment: "None", level: .beginner, prescription: "3 × 2 min", howTo: "Stay light on your feet with your hands up and throw relaxed punches, turning your hips into each one."),
        .init(id: "side-shuffle", name: "Side shuffle", kind: .cardio, focus: nil, muscles: "Heart, glutes, quads", equipment: "None", level: .beginner, prescription: "3 × 30 sec", howTo: "Step sideways foot to foot in a slight squat, without crossing your feet."),
        .init(id: "overhead-arm-raise", name: "Overhead arm raise", kind: .mobility, focus: nil, muscles: "Shoulders", equipment: "None", level: .beginner, prescription: "2 × 12", howTo: "Sweep both arms out to the sides and up overhead, then lower them the same way. Keep your shoulders down."),
        .init(id: "leg-circles", name: "Standing leg circles", kind: .mobility, focus: nil, muscles: "Hips", equipment: "None", level: .beginner, prescription: "10 each side", howTo: "Balance on one leg and draw slow circles with the other knee. Hold on to something if you need to."),
        // Added with the drawings (Workout Guide): gym, chest and back
        .init(id: "incline-dumbbell-press", name: "Incline dumbbell press", kind: .gym, focus: .upper, muscles: "Upper chest, shoulders, triceps", equipment: "Dumbbells, incline bench", level: .beginner, prescription: "3 × 10", howTo: "Set the bench to about 30 degrees. Lower the dumbbells to the sides of your upper chest and press them back up over your shoulders."),
        .init(id: "dumbbell-fly", name: "Dumbbell fly", kind: .gym, focus: .upper, muscles: "Chest", equipment: "Dumbbells, bench", level: .intermediate, prescription: "3 × 12", howTo: "With a slight bend in your elbows, open your arms wide until you feel a stretch across the chest, then hug the weights back together."),
        .init(id: "cable-fly", name: "Cable fly", kind: .gym, focus: .upper, muscles: "Chest, front shoulders", equipment: "Cable machine", level: .intermediate, prescription: "3 × 12", howTo: "Step forward between the pulleys, soft elbows, and bring your hands together in front of your chest in a wide arc. Return slowly."),
        .init(id: "pec-deck", name: "Pec deck", kind: .gym, focus: .upper, muscles: "Chest", equipment: "Pec deck machine", level: .beginner, prescription: "3 × 12", howTo: "Sit tall with your back on the pad and squeeze the handles together in front of you. Let them open slowly without the weights touching."),
        .init(id: "close-grip-bench-press", name: "Close-grip bench press", kind: .gym, focus: .upper, muscles: "Triceps, chest", equipment: "Barbell, bench", level: .intermediate, prescription: "3 × 8", howTo: "Hold the bar about shoulder-width apart, keep your elbows close to your sides as you lower it to the lower chest, and press back up."),
        .init(id: "barbell-row", name: "Barbell row", kind: .gym, focus: .upper, muscles: "Mid-back, lats, biceps", equipment: "Barbell", level: .intermediate, prescription: "3 × 8", howTo: "Hinge forward with a flat back and pull the bar to your lower ribs, squeezing your shoulder blades together. Lower it under control."),
        .init(id: "face-pull", name: "Face pull", kind: .gym, focus: .upper, muscles: "Rear shoulders, upper back", equipment: "Cable machine, rope", level: .beginner, prescription: "3 × 15", howTo: "Pull the rope toward your face with your elbows high, pulling the ends apart beside your ears. Pause, then let it back slowly."),
        .init(id: "pull-up", name: "Pull-up", kind: .gym, focus: .upper, muscles: "Lats, biceps", equipment: "Pull-up bar", level: .advanced, prescription: "3 × 6", howTo: "Hang with an overhand grip a little wider than your shoulders and pull your chest toward the bar. Lower all the way down each time."),
        .init(id: "chin-up", name: "Chin-up", kind: .gym, focus: .upper, muscles: "Biceps, lats", equipment: "Pull-up bar", level: .intermediate, prescription: "3 × 6", howTo: "Hang with palms facing you, shoulder-width apart, and pull until your chin clears the bar. Lower slowly to straight arms."),
        .init(id: "straight-arm-pulldown", name: "Straight-arm pulldown", kind: .gym, focus: .upper, muscles: "Lats", equipment: "Cable machine", level: .beginner, prescription: "3 × 12", howTo: "With arms nearly straight, sweep the bar down from head height to your thighs, leading with the lats. Let it rise slowly."),
        // Gym, shoulders and arms
        .init(id: "arnold-press", name: "Arnold press", kind: .gym, focus: .upper, muscles: "Shoulders, triceps", equipment: "Dumbbells", level: .intermediate, prescription: "3 × 10", howTo: "Start with the dumbbells in front of your shoulders, palms facing you, and turn your palms forward as you press overhead. Reverse on the way down."),
        .init(id: "front-raise", name: "Front raise", kind: .gym, focus: .upper, muscles: "Front shoulders", equipment: "Dumbbells", level: .beginner, prescription: "3 × 12", howTo: "Lift the dumbbells straight in front of you to shoulder height with soft elbows, then lower them slowly. Don't swing."),
        .init(id: "upright-row", name: "Upright row", kind: .gym, focus: .upper, muscles: "Shoulders, traps", equipment: "Barbell", level: .intermediate, prescription: "3 × 10", howTo: "Pull the bar up close to your body to chest height, elbows leading and higher than your hands. Stop if your shoulders pinch."),
        .init(id: "shrug", name: "Barbell shrug", kind: .gym, focus: .upper, muscles: "Traps", equipment: "Barbell", level: .beginner, prescription: "3 × 12", howTo: "Hold the bar at arm's length and lift your shoulders straight up toward your ears. Hold a moment, then lower without rolling."),
        .init(id: "bicep-curl", name: "Biceps curl", kind: .gym, focus: .upper, muscles: "Biceps", equipment: "Dumbbells", level: .beginner, prescription: "3 × 12", howTo: "Keep your elbows by your sides and curl the dumbbells up, turning your palms up. Lower them all the way without swinging."),
        .init(id: "hammer-curl", name: "Hammer curl", kind: .gym, focus: .upper, muscles: "Biceps, forearms", equipment: "Dumbbells", level: .beginner, prescription: "3 × 12", howTo: "Hold the dumbbells with palms facing each other and curl them up, elbows still. Lower slowly."),
        .init(id: "preacher-curl", name: "Preacher curl", kind: .gym, focus: .upper, muscles: "Biceps", equipment: "Preacher bench", level: .beginner, prescription: "3 × 10", howTo: "Rest the backs of your arms on the pad and curl the weight up. Lower it until your arms are almost straight, slowly."),
        .init(id: "tricep-pushdown", name: "Triceps pushdown", kind: .gym, focus: .upper, muscles: "Triceps", equipment: "Cable machine", level: .beginner, prescription: "3 × 12", howTo: "Pin your elbows to your sides and push the handle down until your arms are straight. Let it come up to chest height under control."),
        .init(id: "skull-crusher", name: "Skull crusher", kind: .gym, focus: .upper, muscles: "Triceps", equipment: "Barbell or EZ bar, bench", level: .intermediate, prescription: "3 × 10", howTo: "Lying on the bench, bend only at the elbows to lower the bar toward your forehead, then straighten your arms. Keep your upper arms still."),
        .init(id: "overhead-tricep-extension", name: "Overhead triceps extension", kind: .gym, focus: .upper, muscles: "Triceps", equipment: "Cable or dumbbell", level: .beginner, prescription: "3 × 12", howTo: "With the weight behind your head and elbows pointing up, straighten your arms overhead. Lower slowly behind your head."),
        // Gym, legs
        .init(id: "deadlift", name: "Deadlift", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings, back", equipment: "Barbell", level: .advanced, prescription: "3 × 5", howTo: "Bar over mid-foot, flat back, chest up. Push the floor away and stand tall, then lower the bar by pushing your hips back first."),
        .init(id: "front-squat", name: "Front squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Barbell, rack", level: .advanced, prescription: "3 × 6", howTo: "Rest the bar on the front of your shoulders, elbows high. Squat down with a tall chest and drive back up through your whole foot."),
        .init(id: "bulgarian-split-squat", name: "Bulgarian split squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Dumbbells, bench", level: .intermediate, prescription: "3 × 8 each side", howTo: "Rest your back foot on a bench and lower straight down until your front thigh is about level. Push back up through the front heel."),
        .init(id: "hip-thrust", name: "Hip thrust", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Barbell, bench", level: .intermediate, prescription: "3 × 10", howTo: "Upper back on the bench, bar across your hips. Drive your hips up until your body is flat from knees to shoulders, squeeze, and lower."),
        .init(id: "leg-extension", name: "Leg extension", kind: .gym, focus: .lower, muscles: "Quads", equipment: "Leg extension machine", level: .beginner, prescription: "3 × 12", howTo: "Straighten your knees to lift the pad, pause at the top, and lower slowly. Keep your back against the seat."),
        .init(id: "lying-leg-curl", name: "Lying leg curl", kind: .gym, focus: .lower, muscles: "Hamstrings", equipment: "Leg curl machine", level: .beginner, prescription: "3 × 12", howTo: "Lie face down and curl your heels toward your glutes, hips pressed into the pad. Lower slowly."),
        .init(id: "standing-calf-raise", name: "Standing calf raise", kind: .gym, focus: .lower, muscles: "Calves", equipment: "Calf raise machine or step", level: .beginner, prescription: "3 × 15", howTo: "Rise up onto your toes as high as you can, pause, then lower your heels below the step for a stretch."),
        .init(id: "kettlebell-swing", name: "Kettlebell swing", kind: .gym, focus: .fullBody, muscles: "Glutes, hamstrings, core", equipment: "Kettlebell", level: .intermediate, prescription: "3 × 15", howTo: "Hinge at the hips and snap them forward to swing the bell to chest height. Your arms just guide it; the hips do the work."),
        // Home
        .init(id: "diamond-push-up", name: "Diamond push-up", kind: .home, focus: .upper, muscles: "Triceps, chest", equipment: "None", level: .intermediate, prescription: "3 × 8", howTo: "Put your hands together under your chest, thumbs and fingers forming a diamond, and lower your chest to your hands. Keep your body straight."),
        .init(id: "incline-push-up", name: "Incline push-up", kind: .home, focus: .upper, muscles: "Chest, triceps", equipment: "Bench or sturdy table", level: .beginner, prescription: "3 × 12", howTo: "Hands on a bench, body in a straight line. Lower your chest to the edge and push back up. The higher the surface, the easier."),
        .init(id: "wall-sit", name: "Wall sit", kind: .home, focus: .lower, muscles: "Quads", equipment: "A wall", level: .beginner, prescription: "3 × 40 sec", howTo: "Slide down the wall until your knees are bent to about 90 degrees and hold, back flat on the wall."),
        .init(id: "side-plank", name: "Side plank", kind: .home, focus: .core, muscles: "Obliques, shoulders", equipment: "Mat", level: .beginner, prescription: "3 × 30 sec each side", howTo: "Prop yourself on one forearm with your body in a straight line from head to feet and hold, hips up."),
        .init(id: "bicycle-crunch", name: "Bicycle crunch", kind: .home, focus: .core, muscles: "Abs, obliques", equipment: "Mat", level: .beginner, prescription: "3 × 20", howTo: "Lying on your back, bring one elbow toward the opposite knee as the other leg straightens, then switch in a slow pedalling rhythm."),
        .init(id: "russian-twist", name: "Russian twist", kind: .home, focus: .core, muscles: "Obliques, abs", equipment: "Optional weight", level: .beginner, prescription: "3 × 20", howTo: "Sit leaning back with a tall chest and turn your shoulders side to side, touching the floor beside each hip."),
        .init(id: "crunch", name: "Crunch", kind: .home, focus: .core, muscles: "Abs", equipment: "Mat", level: .beginner, prescription: "3 × 15", howTo: "Lying with knees bent, curl your shoulders off the floor by tightening your abs. Lower slowly; don't pull on your neck."),
        .init(id: "lying-leg-raise", name: "Lying leg raise", kind: .home, focus: .core, muscles: "Lower abs, hip flexors", equipment: "Mat", level: .intermediate, prescription: "3 × 12", howTo: "Lying flat with your lower back pressed down, raise your straight legs to vertical and lower them slowly without arching."),
        .init(id: "bird-dog", name: "Bird dog", kind: .home, focus: .core, muscles: "Core, glutes, lower back", equipment: "Mat", level: .beginner, prescription: "3 × 10 each side", howTo: "On hands and knees, reach one arm forward and the opposite leg back until both are level. Hold a moment and switch sides."),
        .init(id: "inverted-row", name: "Inverted row", kind: .home, focus: .upper, muscles: "Mid-back, biceps", equipment: "Low bar or sturdy table", level: .intermediate, prescription: "3 × 10", howTo: "Hang under a bar with a straight body and pull your chest up to it, squeezing your shoulder blades. Lower slowly."),
        .init(id: "donkey-kick", name: "Donkey kick", kind: .home, focus: .lower, muscles: "Glutes", equipment: "Mat", level: .beginner, prescription: "3 × 15 each side", howTo: "On hands and knees, keep the knee bent and press one foot up toward the ceiling until the thigh is level. Lower without arching your back."),
        .init(id: "v-up", name: "V-up", kind: .home, focus: .core, muscles: "Abs, hip flexors", equipment: "Mat", level: .advanced, prescription: "3 × 10", howTo: "From lying flat, lift your straight arms and legs at the same time to meet over your hips, then lower slowly."),
        // Cardio
        .init(id: "battle-ropes", name: "Battle ropes", kind: .cardio, focus: nil, muscles: "Heart, shoulders, core", equipment: "Battle ropes", level: .intermediate, prescription: "6 × 30 sec", howTo: "In a half squat, whip the ropes up and down in fast alternating waves from your shoulders. Keep your core braced."),
        .init(id: "bear-crawl", name: "Bear crawl", kind: .cardio, focus: nil, muscles: "Heart, shoulders, core, quads", equipment: "None", level: .intermediate, prescription: "4 × 30 sec", howTo: "On hands and feet with knees just off the floor, crawl forward moving opposite hand and foot together. Keep your back flat."),
        .init(id: "skater-hop", name: "Skater hops", kind: .cardio, focus: nil, muscles: "Heart, glutes, quads", equipment: "None", level: .intermediate, prescription: "3 × 30 sec", howTo: "Leap sideways from one foot to the other, landing softly and sweeping the back leg behind you."),
        .init(id: "plank-jack", name: "Plank jacks", kind: .cardio, focus: nil, muscles: "Heart, core, shoulders", equipment: "None", level: .intermediate, prescription: "3 × 30 sec", howTo: "In a high plank, jump your feet wide and back together like a jumping jack while your hips stay level."),
        .init(id: "elliptical", name: "Elliptical", kind: .cardio, focus: nil, muscles: "Heart, legs", equipment: "Elliptical machine", level: .beginner, prescription: "20 min", howTo: "Stand tall, push and pull the handles and keep a smooth, steady stride at a pace you can hold."),
        // Mobility
        .init(id: "doorway-chest-stretch", name: "Doorway chest stretch", kind: .mobility, focus: nil, muscles: "Chest, front shoulders", equipment: "A doorway", level: .beginner, prescription: "2 × 30 sec", howTo: "Forearms on the door frame at shoulder height, step one foot through until you feel a stretch across the chest. Breathe slowly."),
        .init(id: "standing-quad-stretch", name: "Standing quad stretch", kind: .mobility, focus: nil, muscles: "Quads, hip flexors", equipment: "None", level: .beginner, prescription: "30 sec each side", howTo: "Hold one foot behind you, knees together, and gently draw the heel toward your glute. Stand tall; hold a wall for balance."),
        .init(id: "butterfly-stretch", name: "Butterfly stretch", kind: .mobility, focus: nil, muscles: "Inner thighs, hips", equipment: "Mat", level: .beginner, prescription: "2 × 30 sec", howTo: "Sit with the soles of your feet together and let your knees fall open. Sit tall and lean forward a little from the hips."),
        .init(id: "cross-body-shoulder-stretch", name: "Cross-body shoulder stretch", kind: .mobility, focus: nil, muscles: "Rear shoulders, upper back", equipment: "None", level: .beginner, prescription: "30 sec each side", howTo: "Bring one straight arm across your chest and hold it with the other arm just above the elbow. Keep the shoulder down."),
        .init(id: "inchworm", name: "Inchworm", kind: .mobility, focus: nil, muscles: "Hamstrings, core, shoulders", equipment: "None", level: .beginner, prescription: "2 × 6", howTo: "From standing, fold forward, walk your hands out to a plank, then walk your feet up to your hands and stand."),
        // The rest of the Workout Guide drawings, added in full
        .init(id: "incline-bench-press", name: "Incline bench press", kind: .gym, focus: .upper, muscles: "Upper chest, shoulders, triceps", equipment: "Barbell, incline bench", level: .intermediate, prescription: "4 × 8", howTo: "Lower the bar under control to your upper chest, elbows angled about 45° from your body, then press it back over your shoulders. Keep your shoulder blades pinned and your feet planted."),
        .init(id: "decline-bench-press", name: "Decline bench press", kind: .gym, focus: .upper, muscles: "Lower chest, triceps, shoulders", equipment: "Barbell, decline bench", level: .intermediate, prescription: "4 × 8", howTo: "With your legs hooked in, lower the bar to your lower chest and press it straight back up. Use a spotter or safety arms, as the bar can't be dumped easily from this position."),
        .init(id: "machine-chest-press", name: "Machine chest press", kind: .gym, focus: .upper, muscles: "Chest, triceps, shoulders", equipment: "Chest press machine", level: .beginner, prescription: "3 × 12", howTo: "Set the seat so the handles line up with mid-chest, then press forward until your arms are almost straight. Return slowly, stopping before the weight stack touches."),
        .init(id: "seated-dumbbell-press", name: "Seated dumbbell press", kind: .gym, focus: .upper, muscles: "Shoulders, triceps", equipment: "Dumbbells, bench", level: .beginner, prescription: "3 × 10", howTo: "Sit tall against the upright bench and press the dumbbells from shoulder height until your arms are straight overhead. Lower them back to ear level without arching your lower back."),
        .init(id: "cable-lateral-raise", name: "Cable lateral raise", kind: .gym, focus: .upper, muscles: "Side delts, upper back", equipment: "Cable machine", level: .beginner, prescription: "3 × 12 each side", howTo: "Stand side-on to a low pulley and raise the handle out to shoulder height with a slight bend in your elbow. Lower it slowly and don't lean or swing to lift it."),
        .init(id: "rear-delt-fly", name: "Rear delt fly", kind: .gym, focus: .upper, muscles: "Rear delts, upper back", equipment: "Dumbbells", level: .beginner, prescription: "3 × 12", howTo: "Hinge forward with a flat back and raise the dumbbells out to your sides, leading with your elbows. Use a light weight and squeeze your shoulder blades at the top."),
        .init(id: "reverse-pec-deck", name: "Reverse pec deck", kind: .gym, focus: .upper, muscles: "Rear delts, upper back", equipment: "Pec deck machine", level: .beginner, prescription: "3 × 12", howTo: "Sit facing the pad and sweep the handles back until your arms are in line with your body. Keep your chest on the pad and return slowly without letting the stack slam."),
        .init(id: "t-bar-row", name: "T-bar row", kind: .gym, focus: .upper, muscles: "Back, biceps, rear delts", equipment: "T-bar row machine", level: .intermediate, prescription: "4 × 8", howTo: "Hinge to about 45° with a flat back and pull the handle towards your lower chest, driving your elbows back. Lower it under control and keep your back from rounding."),
        .init(id: "dumbbell-bent-over-row", name: "Dumbbell bent-over row", kind: .gym, focus: .upper, muscles: "Back, biceps, rear delts", equipment: "Dumbbells", level: .beginner, prescription: "3 × 10", howTo: "Hinge forward with soft knees and a flat back, then row both dumbbells to your hips. Squeeze your shoulder blades together and lower slowly without jerking your torso."),
        .init(id: "chest-supported-row", name: "Chest-supported row", kind: .gym, focus: .upper, muscles: "Back, biceps, rear delts", equipment: "Chest-supported row machine", level: .beginner, prescription: "3 × 10", howTo: "Rest your chest on the pad and pull the handles up until your elbows pass your sides. Keep your chest on the pad so your back, not momentum, moves the weight."),
        .init(id: "machine-row", name: "Machine row", kind: .gym, focus: .upper, muscles: "Back, biceps", equipment: "Row machine", level: .beginner, prescription: "3 × 12", howTo: "Sit tall with your chest against the pad and pull the handles to your torso, squeezing your shoulder blades together. Let your arms straighten slowly without hunching forward."),
        .init(id: "close-grip-lat-pulldown", name: "Close-grip lat pulldown", kind: .gym, focus: .upper, muscles: "Lats, biceps", equipment: "Cable machine, V-handle", level: .beginner, prescription: "3 × 10", howTo: "Hold the close-grip handle and pull it to your upper chest, driving your elbows down to your sides. Lean back only slightly and let it rise slowly until your arms are straight."),
        .init(id: "assisted-pull-up", name: "Assisted pull-up", kind: .gym, focus: .upper, muscles: "Lats, biceps", equipment: "Assisted pull-up machine", level: .beginner, prescription: "3 × 8", howTo: "Kneel on the pad, grip the bar wider than your shoulders and pull until your chin clears it. Lower all the way down with control; use less assistance as you get stronger."),
        .init(id: "weighted-pull-up", name: "Weighted pull-up", kind: .gym, focus: .upper, muscles: "Lats, biceps", equipment: "Pull-up bar, dip belt, plate", level: .advanced, prescription: "4 × 6", howTo: "Hang from the bar with the weight on a belt, then pull your chest toward the bar by driving your elbows down. Lower all the way under control and keep the weight from swinging."),
        .init(id: "hack-squat", name: "Hack squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Hack squat machine", level: .intermediate, prescription: "3 × 10", howTo: "Set your back flat on the pad and your feet shoulder-width on the platform, then bend your knees until your thighs are about parallel. Push through your whole foot to stand without locking your knees."),
        .init(id: "leg-curl", name: "Machine leg curl", kind: .gym, focus: .lower, muscles: "Hamstrings, calves", equipment: "Leg curl machine", level: .beginner, prescription: "3 × 12", howTo: "Lie face down with the pad just above your heels and curl your heels toward your glutes. Keep your hips pressed into the bench and lower slowly."),
        .init(id: "seated-leg-curl", name: "Seated leg curl", kind: .gym, focus: .lower, muscles: "Hamstrings, calves", equipment: "Seated leg curl machine", level: .beginner, prescription: "3 × 12", howTo: "Sit with the thigh pad snug and the lower pad behind your ankles, then pull your heels down and back under the seat. Return slowly without letting the weight stack slam."),
        .init(id: "good-morning", name: "Good morning", kind: .gym, focus: .lower, muscles: "Hamstrings, glutes, lower back", equipment: "Barbell", level: .intermediate, prescription: "3 × 10", howTo: "With the bar on your upper back and knees soft, push your hips back and lower your chest until you feel a hamstring stretch. Keep your back flat throughout and start light."),
        .init(id: "seated-calf-raise", name: "Seated calf raise", kind: .gym, focus: .lower, muscles: "Calves", equipment: "Seated calf raise machine", level: .beginner, prescription: "3 × 15", howTo: "Sit with the pad on your lower thighs and the balls of your feet on the step, then rise as high onto your toes as you can. Lower your heels slowly for a full stretch at the bottom."),
        .init(id: "cable-curl", name: "Cable curl", kind: .gym, focus: .upper, muscles: "Biceps, forearms", equipment: "Cable machine", level: .beginner, prescription: "3 × 12", howTo: "Stand facing a low pulley and curl the bar up to your shoulders with your elbows pinned at your sides. Lower it slowly without leaning back."),
        .init(id: "reverse-curl", name: "Reverse curl", kind: .gym, focus: .upper, muscles: "Forearms, biceps", equipment: "Barbell", level: .beginner, prescription: "3 × 12", howTo: "Hold the bar with an overhand grip and curl it up to your shoulders, keeping your elbows at your sides. Use a lighter weight than a normal curl and keep your wrists straight."),
        .init(id: "wrist-curl", name: "Wrist curl", kind: .gym, focus: .upper, muscles: "Forearms", equipment: "Barbell", level: .beginner, prescription: "3 × 15", howTo: "Hold the bar with your arms still and move only at the wrists, curling the bar up and lowering it slowly. Keep the weight light and the range smooth."),
        .init(id: "assisted-dip", name: "Seated dip machine", kind: .gym, focus: .upper, muscles: "Triceps, chest", equipment: "Dip machine", level: .beginner, prescription: "3 × 12", howTo: "Sit tall with your back against the pad and press the handles down until your arms are straight. Let them rise slowly until your elbows reach about 90 degrees."),
        .init(id: "cable-crunch", name: "Cable crunch", kind: .gym, focus: .core, muscles: "Abs", equipment: "Cable machine, rope", level: .intermediate, prescription: "3 × 12", howTo: "Kneel below a high pulley with the rope beside your head and crunch your ribs toward your hips. Keep your hips still so your abs, not your arms, do the pulling."),
        .init(id: "incline-cable-fly", name: "Incline cable fly", kind: .gym, focus: .upper, muscles: "Upper chest, shoulders", equipment: "Cable machine, incline bench", level: .intermediate, prescription: "3 × 12", howTo: "Lie on an incline bench between low pulleys and sweep the handles up and together over your chest with a soft bend in the elbows. Lower slowly until you feel a stretch, without letting the shoulders roll forward."),
        .init(id: "decline-dumbbell-press", name: "Decline dumbbell press", kind: .gym, focus: .upper, muscles: "Lower chest, triceps, shoulders", equipment: "Dumbbells, decline bench", level: .intermediate, prescription: "3 × 10", howTo: "Lock your legs in on a decline bench and press the dumbbells up over your lower chest. Lower them under control to chest level, elbows about 45° from your sides."),
        .init(id: "smith-machine-bench-press", name: "Smith machine bench press", kind: .gym, focus: .upper, muscles: "Chest, triceps, shoulders", equipment: "Smith machine, bench", level: .beginner, prescription: "3 × 10", howTo: "Set the bench so the bar lines up with your mid-chest, unhook it and lower it to touch lightly. Press back up without locking the elbows hard, and set the safety stops just above your chest."),
        .init(id: "landmine-press", name: "Landmine press", kind: .gym, focus: .upper, muscles: "Shoulders, upper chest, triceps", equipment: "Barbell, landmine", level: .beginner, prescription: "3 × 10 each side", howTo: "Hold the end of the bar at your shoulder in a staggered stance and press it up and forward until your arm is straight. Brace your core so you don't lean back, then lower it to your shoulder."),
        .init(id: "weighted-dip", name: "Weighted dip", kind: .gym, focus: .upper, muscles: "Triceps, chest, shoulders", equipment: "Dip bars, dip belt, plate", level: .advanced, prescription: "4 × 6", howTo: "Hang a plate from a dip belt, lower yourself until your upper arms are parallel to the floor, then press up to straight arms. Keep the chest up and the descent controlled; only add load once bodyweight dips feel easy."),
        .init(id: "machine-shoulder-press", name: "Machine shoulder press", kind: .gym, focus: .upper, muscles: "Shoulders, triceps", equipment: "Shoulder press machine", level: .beginner, prescription: "3 × 10", howTo: "Set the seat so the handles start at shoulder height and press them overhead until your arms are almost straight. Keep your back against the pad and lower slowly."),
        .init(id: "standing-dumbbell-press", name: "Standing dumbbell press", kind: .gym, focus: .upper, muscles: "Shoulders, triceps, core", equipment: "Dumbbells", level: .intermediate, prescription: "3 × 10", howTo: "Stand tall with the dumbbells at shoulder height and press them straight up until your arms are extended. Squeeze your glutes and brace your core so your lower back doesn't arch."),
        .init(id: "push-press", name: "Push press", kind: .gym, focus: .fullBody, muscles: "Shoulders, triceps, quads", equipment: "Barbell", level: .advanced, prescription: "4 × 5", howTo: "With the bar resting on your front shoulders, dip a few inches at the knees and drive up hard, using that push to press the bar overhead. Keep the dip short and straight down, torso upright."),
        .init(id: "machine-lateral-raise", name: "Machine lateral raise", kind: .gym, focus: .upper, muscles: "Side delts, traps", equipment: "Lateral raise machine", level: .beginner, prescription: "3 × 12", howTo: "Sit with your arms against the pads and raise them out to the sides until they reach shoulder height. Lead with the elbows, keep the shoulders down and lower slowly."),
        .init(id: "cable-front-raise", name: "Cable front raise", kind: .gym, focus: .upper, muscles: "Front delts, upper chest", equipment: "Cable machine", level: .beginner, prescription: "3 × 12 each side", howTo: "Stand beside a low pulley and raise the handle in front of you to shoulder height with a straight arm. Lower it slowly and don't swing your torso to lift it."),
        .init(id: "plate-front-raise", name: "Plate front raise", kind: .gym, focus: .upper, muscles: "Front delts, upper chest", equipment: "Weight plate", level: .beginner, prescription: "3 × 12", howTo: "Hold a plate by its sides at your thighs and raise it with straight arms to shoulder height. Pause, then lower under control without leaning back."),
        .init(id: "cable-rear-delt-fly", name: "Cable rear delt fly", kind: .gym, focus: .upper, muscles: "Rear delts, upper back", equipment: "Cable machine", level: .intermediate, prescription: "3 × 15", howTo: "Stand between two high pulleys holding the opposite cables crossed in front of you, then pull your arms out and back to the sides with a slight bend in the elbows. Move only at the shoulders and keep the weight light."),
        .init(id: "pendlay-row", name: "Pendlay row", kind: .gym, focus: .upper, muscles: "Upper back, rear delts", equipment: "Barbell", level: .advanced, prescription: "4 × 6", howTo: "Hinge until your torso is nearly parallel to the floor, then pull the bar from the floor to your lower chest and set it back down each rep. Keep your back flat and don't jerk your torso up."),
        .init(id: "meadows-row", name: "Meadows row", kind: .gym, focus: .upper, muscles: "Lats, upper back, biceps", equipment: "Barbell, landmine", level: .intermediate, prescription: "3 × 10 each side", howTo: "Stand side-on to the bar end, hinge forward and row the sleeve up toward your hip with an overhand grip. Keep your back flat and brace your free hand on your knee."),
        .init(id: "single-arm-cable-row", name: "Single-arm cable row", kind: .gym, focus: .upper, muscles: "Lats, upper back, biceps", equipment: "Cable machine", level: .beginner, prescription: "3 × 12 each side", howTo: "Stand in a split stance and pull the handle to your waist, driving the elbow back past your body. Keep your hips square and let the shoulder reach forward on the way back."),
        .init(id: "wide-grip-lat-pulldown", name: "Wide-grip lat pulldown", kind: .gym, focus: .upper, muscles: "Lats, biceps", equipment: "Lat pulldown machine", level: .beginner, prescription: "3 × 10", howTo: "Grip the bar wider than your shoulders and pull it to your upper chest, driving the elbows down. Lean back only slightly and control the bar on the way up."),
        .init(id: "assisted-chin-up", name: "Assisted chin-up", kind: .gym, focus: .upper, muscles: "Biceps, lats", equipment: "Assisted pull-up machine", level: .beginner, prescription: "3 × 8", howTo: "Kneel on the pad, grip the bar palms toward you and pull your chin over the bar. Lower slowly to straight arms; less counterweight makes it harder."),
        .init(id: "weighted-chin-up", name: "Weighted chin-up", kind: .gym, focus: .upper, muscles: "Biceps, lats", equipment: "Pull-up bar, dip belt", level: .advanced, prescription: "4 × 5", howTo: "Hang a plate from a dip belt, grip the bar palms toward you and pull your chin over it. Lower to full hang every rep and keep the weight from swinging."),
        .init(id: "rack-pull", name: "Rack pull", kind: .gym, focus: .lower, muscles: "Upper back, glutes, hamstrings", equipment: "Barbell, rack", level: .intermediate, prescription: "4 × 6", howTo: "Set the bar on the pins at knee height, hinge to grip it and stand up by driving your hips forward. Keep the bar against your thighs and your back flat."),
        .init(id: "back-extension", name: "Back extension", kind: .gym, focus: .core, muscles: "Lower back, glutes, hamstrings", equipment: "Back extension bench", level: .beginner, prescription: "3 × 12", howTo: "With hips on the pad, lower your chest toward the floor, then raise it until your body forms a straight line. Stop at straight; don't arch past it."),
        .init(id: "dumbbell-shrug", name: "Dumbbell shrug", kind: .gym, focus: .upper, muscles: "Traps", equipment: "Dumbbells", level: .beginner, prescription: "3 × 15", howTo: "Hold the dumbbells at your sides and lift your shoulders straight up toward your ears. Pause at the top and lower slowly without rolling the shoulders."),
        .init(id: "smith-machine-squat", name: "Smith machine squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Smith machine", level: .beginner, prescription: "3 × 10", howTo: "Set the bar on your upper back with feet slightly in front of it, then squat until your thighs are level with the floor. Push through your whole foot and keep your knees in line with your toes."),
        .init(id: "belt-squat", name: "Belt squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Belt squat machine", level: .beginner, prescription: "3 × 12", howTo: "Clip the belt around your hips, stand on the platform and squat down with your chest up. The load hangs from your hips, so your back stays free; drive up through your heels."),
        .init(id: "sumo-deadlift", name: "Sumo deadlift", kind: .gym, focus: .lower, muscles: "Glutes, quads, adductors", equipment: "Barbell", level: .intermediate, prescription: "4 × 6", howTo: "Take a wide stance with toes turned out and grip the bar inside your knees. Push the floor apart and stand up with a flat back, keeping the bar close."),
        .init(id: "trap-bar-deadlift", name: "Trap bar deadlift", kind: .gym, focus: .lower, muscles: "Glutes, quads, hamstrings", equipment: "Trap bar", level: .beginner, prescription: "4 × 8", howTo: "Stand inside the bar, grip the handles and stand up by pushing the floor away. Keep your chest up and back flat, and lower the same way."),
        .init(id: "split-squat", name: "Dumbbell split squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Dumbbells", level: .beginner, prescription: "3 × 10 each side", howTo: "Stand in a long stride with dumbbells at your sides and lower straight down until the back knee nearly touches the floor. Keep your torso upright and the front knee in line with your toes."),
        .init(id: "cable-kickback", name: "Cable glute kickback", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Cable machine, ankle strap", level: .beginner, prescription: "3 × 12 each side", howTo: "Strap the cable to one ankle, brace on the machine and kick that leg straight back until the hip is fully open. Squeeze the glute at the top and don't arch your lower back."),
        .init(id: "hip-abduction-machine", name: "Seated hip abduction machine", kind: .gym, focus: .lower, muscles: "Glutes, outer hips", equipment: "Hip abduction machine", level: .beginner, prescription: "3 × 15", howTo: "Sit tall with the pads on the outside of your knees and push your legs apart as far as you can. Pause, then let them return slowly without the weights slamming."),
        .init(id: "barbell-glute-bridge", name: "Barbell glute bridge", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings, core", equipment: "Barbell, pad", level: .intermediate, prescription: "3 × 10", howTo: "Lie on the floor with a padded barbell over your hips and drive through your heels to lift your hips until your body is straight from knees to shoulders. Squeeze your glutes at the top and keep your ribs down."),
        .init(id: "dumbbell-glute-bridge", name: "Dumbbell glute bridge", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Dumbbell, mat", level: .beginner, prescription: "3 × 12", howTo: "Lie on your back with a dumbbell held on your hips and push through your heels to raise them. Squeeze your glutes at the top and lower slowly without arching your back."),
        .init(id: "dumbbell-hip-thrust", name: "Dumbbell hip thrust", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Dumbbell, bench", level: .beginner, prescription: "3 × 12", howTo: "Rest your upper back on a bench with a dumbbell on your hips and drive your hips up until your thighs and torso are level. Tuck your chin and squeeze your glutes at the top."),
        .init(id: "smith-machine-hip-thrust", name: "Smith machine hip thrust", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings, core", equipment: "Smith machine, bench", level: .intermediate, prescription: "3 × 10", howTo: "Sit with your upper back against a bench and the padded bar over your hips, then drive your hips up until your body is level from knees to shoulders. Keep your shins vertical and lower under control."),
        .init(id: "smith-machine-romanian-deadlift", name: "Smith machine Romanian deadlift", kind: .gym, focus: .lower, muscles: "Hamstrings, glutes, lower back", equipment: "Smith machine", level: .intermediate, prescription: "3 × 10", howTo: "With a slight knee bend, push your hips back and slide the bar down your thighs until you feel a stretch in your hamstrings. Keep your back flat and drive your hips forward to stand."),
        .init(id: "dumbbell-romanian-deadlift", name: "Dumbbell Romanian deadlift", kind: .gym, focus: .lower, muscles: "Hamstrings, glutes, lower back", equipment: "Dumbbells", level: .beginner, prescription: "3 × 10", howTo: "Hold the dumbbells in front of your thighs, soften your knees and hinge at the hips to lower them along your legs. Keep your back flat and stop when your hamstrings are fully stretched."),
        .init(id: "kettlebell-romanian-deadlift", name: "Kettlebell Romanian deadlift", kind: .gym, focus: .lower, muscles: "Hamstrings, glutes, lower back", equipment: "Kettlebell", level: .beginner, prescription: "3 × 12", howTo: "Hold the kettlebell with both hands, soften your knees and push your hips back to lower it toward your shins. Keep your back flat and squeeze your glutes to stand tall."),
        .init(id: "cable-pull-through", name: "Cable pull-through", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings, lower back", equipment: "Cable machine, rope", level: .beginner, prescription: "3 × 12", howTo: "Face away from a low cable with the rope between your legs, hinge your hips back, then snap them forward to stand tall. Your arms just hold the rope; the hips do the work."),
        .init(id: "machine-glute-kickback", name: "Machine glute kickback", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Glute kickback machine", level: .beginner, prescription: "3 × 12 each side", howTo: "Brace on the handles and push the working leg back until your hip is fully extended. Squeeze the glute at the end and keep your lower back from arching."),
        .init(id: "cable-standing-hip-abduction", name: "Cable standing hip abduction", kind: .gym, focus: .lower, muscles: "Glutes, outer hips", equipment: "Cable machine, ankle strap", level: .beginner, prescription: "3 × 12 each side", howTo: "Strap the cable to your outside ankle and lift that leg out to the side, holding the machine for balance. Keep your torso upright and don't lean to swing the weight."),
        .init(id: "cable-standing-hip-adduction", name: "Cable hip adduction", kind: .gym, focus: .lower, muscles: "Adductors, core", equipment: "Cable machine, ankle strap", level: .beginner, prescription: "3 × 12 each side", howTo: "Stand side-on to a low cable with the strap on your inside ankle and sweep that leg across in front of your standing leg. Stand tall, hold the frame for balance and return slowly without letting the weight stack slam."),
        .init(id: "hip-adduction-machine", name: "Hip adduction machine", kind: .gym, focus: .lower, muscles: "Adductors", equipment: "Adduction machine", level: .beginner, prescription: "3 × 12", howTo: "Sit with your back against the pad and squeeze your knees together against the pads. Open back out slowly to a comfortable stretch, not a bounce."),
        .init(id: "smith-machine-bulgarian-split-squat", name: "Smith machine Bulgarian split squat", kind: .gym, focus: .lower, muscles: "Quads, glutes, core", equipment: "Smith machine, bench", level: .intermediate, prescription: "3 × 8 each side", howTo: "With the bar on your upper back and your rear foot on a bench, lower straight down until your front thigh is about parallel. Drive up through the whole front foot and keep the front knee tracking over your toes."),
        .init(id: "smith-machine-reverse-lunge", name: "Smith machine reverse lunge", kind: .gym, focus: .lower, muscles: "Quads, glutes, hamstrings", equipment: "Smith machine", level: .intermediate, prescription: "3 × 8 each side", howTo: "With the bar on your upper back, step one foot back and lower until the back knee nearly touches the floor. Push through the front heel to return and keep your chest up."),
        .init(id: "smith-machine-split-squat", name: "Smith machine split squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Smith machine", level: .beginner, prescription: "3 × 10 each side", howTo: "Set a long staggered stance under the bar and lower straight down until the back knee is just off the floor. Keep your weight over the front foot and stand up without locking the knee hard."),
        .init(id: "heel-elevated-goblet-squat", name: "Heel-elevated goblet squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Dumbbell, wedge or plates", level: .beginner, prescription: "3 × 10", howTo: "Rest your heels on a wedge or small plates, hold a dumbbell at your chest and squat down with your knees travelling forward over your toes. Keep your torso upright and your heels down as you stand."),
        .init(id: "dumbbell-sumo-squat", name: "Dumbbell sumo squat", kind: .gym, focus: .lower, muscles: "Glutes, adductors, quads", equipment: "Dumbbell", level: .beginner, prescription: "3 × 12", howTo: "Stand wide with your toes turned out and hold one dumbbell between your legs. Squat straight down, pushing your knees out over your toes, then squeeze your glutes to stand."),
        .init(id: "dumbbell-sumo-deadlift", name: "Dumbbell sumo deadlift", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings, adductors", equipment: "Dumbbells", level: .beginner, prescription: "3 × 10", howTo: "Take a wide stance with toes out and the dumbbells between your feet, then hinge and bend your knees to grip them with a flat back. Drive through your heels and push your hips forward to stand tall."),
        .init(id: "front-foot-elevated-split-squat", name: "Front-foot elevated split squat", kind: .gym, focus: .lower, muscles: "Quads, glutes", equipment: "Dumbbells, step or box", level: .intermediate, prescription: "3 × 8 each side", howTo: "Put your front foot on a low step, hold dumbbells at your sides and lower your back knee towards the floor. The raised foot lets you sink deeper; keep your front heel down and your torso tall."),
        .init(id: "deficit-reverse-lunge", name: "Deficit reverse lunge", kind: .gym, focus: .lower, muscles: "Glutes, quads, hamstrings", equipment: "Dumbbells, step", level: .intermediate, prescription: "3 × 8 each side", howTo: "Stand on a low step holding dumbbells and step one foot back to the floor, lowering until the back knee nearly touches down. Drive through the front heel to return to the step with control."),
        .init(id: "dumbbell-lateral-lunge", name: "Dumbbell lateral lunge", kind: .gym, focus: .lower, muscles: "Quads, glutes, adductors", equipment: "Dumbbells", level: .intermediate, prescription: "3 × 8 each side", howTo: "Holding dumbbells, take a big step to the side and sit your hips back over that foot while the other leg stays straight. Keep both feet flat and push off the bent leg to return."),
        .init(id: "dumbbell-curtsy-lunge", name: "Dumbbell curtsy lunge", kind: .gym, focus: .lower, muscles: "Glutes, quads", equipment: "Dumbbells", level: .intermediate, prescription: "3 × 8 each side", howTo: "Holding dumbbells, step one foot back and across behind the other, then bend both knees to lower. Keep your hips square and your front knee over your toes as you push back up."),
        .init(id: "landmine-squat", name: "Landmine squat", kind: .gym, focus: .lower, muscles: "Quads, glutes, core", equipment: "Barbell, landmine", level: .beginner, prescription: "3 × 10", howTo: "Hold the end of the landmine bar at your chest with both hands and lean slightly into it. Squat down between your knees, keeping your chest up, then drive through your feet to stand."),
        .init(id: "landmine-romanian-deadlift", name: "Landmine Romanian deadlift", kind: .gym, focus: .lower, muscles: "Hamstrings, glutes, lower back", equipment: "Barbell, landmine", level: .intermediate, prescription: "3 × 10", howTo: "Hold the bar end in front of your thighs with soft knees and push your hips back, sliding it down your legs until you feel your hamstrings stretch. Keep your back flat and squeeze your glutes to stand."),
        .init(id: "glute-focused-back-extension", name: "Glute-focused back extension", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings, lower back", equipment: "Hyperextension bench", level: .intermediate, prescription: "3 × 12", howTo: "Set the pad at your hips, round your upper back slightly and hinge down, then squeeze your glutes to lift until your body is in a straight line. Stop at straight; don't arch your lower back at the top."),
        .init(id: "reverse-hyperextension", name: "Reverse hyperextension", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings, lower back", equipment: "Reverse hyper machine", level: .intermediate, prescription: "3 × 12", howTo: "Lie face down with your hips at the edge of the pad and grip the handles. Squeeze your glutes to raise your legs to hip height, then lower them under control without swinging."),
        .init(id: "donkey-calf-raise", name: "Donkey calf raise", kind: .gym, focus: .lower, muscles: "Calves", equipment: "Donkey calf machine", level: .intermediate, prescription: "3 × 15", howTo: "Bend at the hips with the balls of your feet on the step and let your heels sink for a full stretch. Rise as high as you can onto your toes, pause, and lower slowly with straight knees."),
        .init(id: "leg-press-calf-raise", name: "Leg press calf raise", kind: .gym, focus: .lower, muscles: "Calves", equipment: "Leg press machine", level: .beginner, prescription: "3 × 15", howTo: "Place the balls of your feet on the bottom edge of the platform with your knees almost straight. Push the plate away by pointing your toes, then let your heels come back slowly; keep the safety stops on."),
        .init(id: "incline-dumbbell-curl", name: "Incline dumbbell curl", kind: .gym, focus: .upper, muscles: "Biceps, forearms", equipment: "Dumbbells, incline bench", level: .intermediate, prescription: "3 × 10", howTo: "Sit back on an incline bench and let your arms hang straight down. Curl the dumbbells up without letting your elbows drift forward, then lower them all the way to a full stretch."),
        .init(id: "concentration-curl", name: "Concentration curl", kind: .gym, focus: .upper, muscles: "Biceps, forearms", equipment: "Dumbbell, bench", level: .beginner, prescription: "3 × 10 each side", howTo: "Sit with your elbow braced against the inside of your thigh and curl the dumbbell towards your shoulder. Keep your upper arm still and lower slowly to a straight arm."),
        .init(id: "ez-bar-curl", name: "EZ-bar curl", kind: .gym, focus: .upper, muscles: "Biceps, forearms", equipment: "EZ bar", level: .beginner, prescription: "3 × 10", howTo: "Hold the angled grips with your elbows at your sides and curl the bar to your chest. Don't swing your hips; lower the bar slowly until your arms are straight."),
        .init(id: "spider-curl", name: "Spider curl", kind: .gym, focus: .upper, muscles: "Biceps, forearms", equipment: "Barbell, incline bench", level: .intermediate, prescription: "3 × 10", howTo: "Lie chest down on an incline bench with your arms hanging straight below your shoulders. Curl the bar up while keeping your upper arms vertical, squeeze, and lower under control."),
        .init(id: "rope-hammer-curl", name: "Rope hammer curl", kind: .gym, focus: .upper, muscles: "Biceps, forearms", equipment: "Cable machine, rope", level: .beginner, prescription: "3 × 12", howTo: "Hold the rope at a low pulley with your palms facing each other and curl it towards your shoulders. Keep your elbows pinned to your sides and lower slowly."),
        .init(id: "drag-curl", name: "Drag curl", kind: .gym, focus: .upper, muscles: "Biceps, forearms", equipment: "Barbell", level: .intermediate, prescription: "3 × 10", howTo: "Pull your elbows back as you curl so the bar slides up along your body to your lower chest. Keep the bar touching you the whole way and lower it slowly along the same path."),
        .init(id: "rope-tricep-pushdown", name: "Rope triceps pushdown", kind: .gym, focus: .upper, muscles: "Triceps", equipment: "Cable machine, rope", level: .beginner, prescription: "3 × 12", howTo: "Hold the rope at a high pulley with your elbows tucked at your sides and push it down until your arms are straight, spreading the ends apart at the bottom. Only your forearms move; let the rope back up slowly."),
        .init(id: "dumbbell-skull-crusher", name: "Dumbbell skull crusher", kind: .gym, focus: .upper, muscles: "Triceps", equipment: "Dumbbells, bench", level: .intermediate, prescription: "3 × 10", howTo: "Lie on a bench with the dumbbells held straight above your chest, palms facing in. Bend only at the elbows to lower the weights beside your head, then press them back up; keep your elbows pointing at the ceiling."),
        .init(id: "single-dumbbell-skullcrusher", name: "Single-arm skull crusher", kind: .gym, focus: .upper, muscles: "Triceps", equipment: "Dumbbell, bench", level: .intermediate, prescription: "3 × 10 each side", howTo: "Lie on a bench holding one dumbbell straight up above your shoulder. Bend the elbow to lower the weight towards the opposite shoulder, then straighten your arm; keep the upper arm still."),
        .init(id: "dumbbell-overhead-tricep-extension", name: "Seated dumbbell overhead extension", kind: .gym, focus: .upper, muscles: "Triceps", equipment: "Dumbbell, bench", level: .beginner, prescription: "3 × 12", howTo: "Sit tall and hold one dumbbell overhead with both hands. Lower it behind your head by bending your elbows, keeping them close to your head, then straighten your arms; brace your core so your back doesn't arch."),
        .init(id: "single-arm-dumbbell-tricep-extension", name: "Single-arm overhead dumbbell extension", kind: .gym, focus: .upper, muscles: "Triceps, shoulders", equipment: "Dumbbell", level: .beginner, prescription: "3 × 10 each side", howTo: "Hold the dumbbell overhead and lower it behind your head by bending only the elbow. Keep the elbow pointing up and your ribs down, then straighten the arm."),
        .init(id: "tricep-kickback", name: "Dumbbell triceps kickback", kind: .gym, focus: .upper, muscles: "Triceps", equipment: "Dumbbell, bench", level: .beginner, prescription: "3 × 12 each side", howTo: "Brace one hand and knee on a bench, keep your upper arm tight to your side and straighten the elbow to swing the dumbbell back. Only the forearm moves; lower it slowly."),
        .init(id: "wrist-extension", name: "Dumbbell wrist extension", kind: .gym, focus: .upper, muscles: "Forearms", equipment: "Dumbbell", level: .beginner, prescription: "3 × 15", howTo: "Hold the dumbbell with palms facing down and lift the back of your hands toward you by bending only at the wrists. Use a light weight and lower it slowly."),
        .init(id: "farmer-carry", name: "Dumbbell farmer carry", kind: .gym, focus: .fullBody, muscles: "Forearms, upper back, core", equipment: "Dumbbells", level: .beginner, prescription: "4 × 30 sec", howTo: "Pick up a heavy dumbbell in each hand and walk with short, steady steps. Stand tall with your shoulders back and don't let the weights pull you sideways."),
        .init(id: "pallof-press", name: "Pallof press", kind: .gym, focus: .core, muscles: "Abs, obliques", equipment: "Cable machine", level: .beginner, prescription: "3 × 10 each side", howTo: "Stand side-on to the cable, hold the handle at your chest and press it straight out. Don't let the cable twist your body; bring it back in slowly."),
        .init(id: "half-kneeling-pallof-press", name: "Half-kneeling Pallof press", kind: .gym, focus: .core, muscles: "Abs, obliques, glutes", equipment: "Cable machine", level: .intermediate, prescription: "3 × 10 each side", howTo: "Kneel on one knee side-on to the cable and press the handle straight out from your chest. Squeeze the glute of the down leg and keep your hips square."),
        .init(id: "cable-pallof-hold", name: "Cable Pallof hold", kind: .gym, focus: .core, muscles: "Abs, obliques", equipment: "Cable machine", level: .beginner, prescription: "3 × 30 sec each side", howTo: "Stand side-on to the cable and hold the handle at arm's length in front of your chest. Brace and keep your torso still so the cable can't turn you."),
        .init(id: "captains-chair-knee-raise", name: "Captain's chair knee raise", kind: .gym, focus: .core, muscles: "Abs", equipment: "Captain's chair", level: .intermediate, prescription: "3 × 12", howTo: "Support yourself on your forearms with your back against the pad and raise your knees toward your chest. Lower slowly and don't swing."),
        .init(id: "decline-sit-up", name: "Decline sit-up", kind: .gym, focus: .core, muscles: "Abs, quads", equipment: "Decline bench", level: .intermediate, prescription: "3 × 12", howTo: "Hook your feet under the pads, then curl your torso up toward your knees and lower back down under control. Keep your hands light on your head and don't pull your neck."),
        .init(id: "weighted-crunch", name: "Weighted crunch", kind: .gym, focus: .core, muscles: "Abs", equipment: "Weight plate", level: .beginner, prescription: "3 × 12", howTo: "Lie with knees bent and hold a plate on your chest, then curl your shoulders off the floor. Lift by tightening your abs, not by pulling with your neck."),
        .init(id: "weighted-russian-twist", name: "Weighted Russian twist", kind: .gym, focus: .core, muscles: "Obliques, abs", equipment: "Dumbbell", level: .intermediate, prescription: "3 × 10 each side", howTo: "Sit leaning back with your chest up and rotate the dumbbell from one hip to the other. Turn from your ribs, not just your arms, and keep your back straight."),
        .init(id: "dumbbell-side-bend", name: "Dumbbell side bend", kind: .gym, focus: .core, muscles: "Obliques", equipment: "Dumbbell", level: .beginner, prescription: "3 × 12 each side", howTo: "Stand tall with a dumbbell in one hand and bend sideways toward it, then pull yourself back upright with the opposite side. Move only sideways; don't lean forward or back."),
        .init(id: "prone-t-raise", name: "Prone T raise", kind: .gym, focus: .upper, muscles: "Upper back, rear delts", equipment: "Bench, light dumbbells", level: .beginner, prescription: "3 × 12", howTo: "Lie face down on an incline bench and raise light weights out to your sides into a T, thumbs up. Squeeze your shoulder blades together and lower slowly without shrugging."),
        .init(id: "banded-hip-thrust", name: "Banded hip thrust", kind: .gym, focus: .lower, muscles: "Glutes, hamstrings, core", equipment: "Resistance band, bench", level: .intermediate, prescription: "3 × 12", howTo: "Rest your upper back on a bench with a band across your hips and drive your hips up until your thighs are level. Tuck your chin and keep your ribs down so the glutes, not your lower back, do the work."),
        .init(id: "weighted-push-up", name: "Weighted push-up", kind: .home, focus: .upper, muscles: "Chest, triceps, core", equipment: "Weight plate", level: .intermediate, prescription: "3 × 10", howTo: "With a plate resting on your upper back, lower your chest to just above the floor and push back up. Brace your core so your hips don't sag under the extra load."),
        .init(id: "dip", name: "Bar dip", kind: .home, focus: .upper, muscles: "Triceps, chest, shoulders", equipment: "Dip bars", level: .intermediate, prescription: "3 × 8", howTo: "Support yourself on straight arms, then bend your elbows to lower until your upper arms are about parallel to the floor. Press back up, keeping your shoulders down away from your ears."),
        .init(id: "hanging-leg-raise", name: "Hanging leg raise", kind: .home, focus: .core, muscles: "Abs, hip flexors", equipment: "Pull-up bar", level: .advanced, prescription: "3 × 10", howTo: "Hang from the bar and raise your straight legs to hip height or higher by curling your pelvis up. Lower them slowly and avoid swinging."),
        .init(id: "ab-wheel", name: "Ab wheel rollout", kind: .home, focus: .core, muscles: "Abs, shoulders", equipment: "Ab wheel", level: .intermediate, prescription: "3 × 8", howTo: "Kneel holding the wheel under your shoulders and roll it forward as far as you can without your lower back sagging. Brace your abs and pull back to the start."),
        .init(id: "chest-dip", name: "Chest dip", kind: .home, focus: .upper, muscles: "Lower chest, triceps, shoulders", equipment: "Dip bars", level: .intermediate, prescription: "3 × 8", howTo: "Support yourself on the bars, lean your torso forward and lower until your upper arms are about parallel to the floor. Press back up; stop higher if your shoulders ache."),
        .init(id: "neutral-grip-pull-up", name: "Neutral-grip pull-up", kind: .home, focus: .upper, muscles: "Lats, biceps, core", equipment: "Pull-up bar", level: .intermediate, prescription: "3 × 6", howTo: "Hang from parallel handles with palms facing each other and pull until your chin clears the bar. Lower all the way down under control without swinging."),
        .init(id: "nordic-hamstring-curl", name: "Nordic hamstring curl", kind: .home, focus: .lower, muscles: "Hamstrings, glutes", equipment: "Mat, ankle anchor", level: .advanced, prescription: "3 × 5", howTo: "Kneel with your ankles anchored and lower your body forward as slowly as you can, keeping hips straight. Catch yourself with your hands and push back up to start."),
        .init(id: "single-leg-glute-bridge", name: "Single-leg glute bridge", kind: .home, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Mat", level: .intermediate, prescription: "3 × 10 each side", howTo: "Lie on your back with one foot planted and the other leg raised, then drive through the heel to lift your hips into a straight line. Keep your hips level and lower slowly."),
        .init(id: "bench-dip", name: "Bench dip", kind: .home, focus: .upper, muscles: "Triceps, chest, shoulders", equipment: "Bench or chair", level: .beginner, prescription: "3 × 12", howTo: "With your hands on the bench edge behind you, bend your elbows to lower your hips until your upper arms are about level. Keep your back close to the bench and press back up without shrugging."),
        .init(id: "reverse-crunch", name: "Reverse crunch", kind: .home, focus: .core, muscles: "Abs", equipment: "Mat", level: .beginner, prescription: "3 × 12", howTo: "Lie on your back with knees bent and curl your hips off the floor, bringing your knees toward your chest. Lower slowly without swinging your legs."),
        .init(id: "knee-push-up", name: "Knee push-up", kind: .home, focus: .upper, muscles: "Chest, triceps, shoulders", equipment: "Mat", level: .beginner, prescription: "3 × 12", howTo: "From your knees, keep a straight line from head to knees and lower your chest between your hands. Press back up without letting your hips sag."),
        .init(id: "wide-push-up", name: "Wide push-up", kind: .home, focus: .upper, muscles: "Chest, shoulders", equipment: "None", level: .beginner, prescription: "3 × 10", howTo: "Set your hands well outside shoulder width and lower your chest toward the floor with a straight body. Stop if you feel it pinch in the front of your shoulders."),
        .init(id: "decline-push-up", name: "Decline push-up", kind: .home, focus: .upper, muscles: "Upper chest, shoulders, triceps", equipment: "Chair or bench", level: .intermediate, prescription: "3 × 10", howTo: "Rest your feet on a bench and your hands on the floor, then lower your chest with your body in one straight line. Keep your core tight so your lower back does not dip."),
        .init(id: "feet-elevated-pike-push-up", name: "Feet-elevated pike push-up", kind: .home, focus: .upper, muscles: "Shoulders, triceps", equipment: "Box or chair", level: .advanced, prescription: "3 × 6", howTo: "With your feet on a box and hips stacked high over your hands, bend your elbows to lower the top of your head toward the floor. Press back up and keep your elbows tucked, not flared."),
        .init(id: "archer-push-up", name: "Archer push-up", kind: .home, focus: .upper, muscles: "Chest, triceps, shoulders", equipment: "None", level: .advanced, prescription: "3 × 6 each side", howTo: "With hands wide, lower toward one hand while the other arm straightens out to the side. Push back up and switch sides, keeping your hips level."),
        .init(id: "typewriter-push-up", name: "Typewriter push-up", kind: .home, focus: .upper, muscles: "Chest, shoulders, triceps", equipment: "None", level: .advanced, prescription: "3 × 6 each side", howTo: "Lower into a wide push-up, then shift your chest across to one hand and back to the other before pressing up. Stay low and keep your body straight as you slide."),
        .init(id: "explosive-push-up", name: "Explosive push-up", kind: .home, focus: .upper, muscles: "Chest, triceps, shoulders", equipment: "None", level: .advanced, prescription: "4 × 6", howTo: "Lower under control, then push up hard enough for your hands to leave the floor. Land with soft elbows and go straight into the next rep."),
        .init(id: "hindu-push-up", name: "Hindu push-up", kind: .home, focus: .upper, muscles: "Chest, shoulders, triceps", equipment: "None", level: .intermediate, prescription: "3 × 10", howTo: "From a hips-high downward dog, swoop your chest low between your hands and up into an upward dog. Reverse the path back to the start with control."),
        .init(id: "scapular-push-up", name: "Scapular push-up", kind: .home, focus: .upper, muscles: "Upper back, chest, shoulders", equipment: "None", level: .beginner, prescription: "3 × 12", howTo: "In a high plank with straight arms, let your chest sink so your shoulder blades pinch together, then push the floor away to spread them. Keep your elbows locked; only the shoulder blades move."),
        .init(id: "push-up-shoulder-tap", name: "Push-up shoulder tap", kind: .home, focus: .core, muscles: "Core, chest, shoulders", equipment: "None", level: .intermediate, prescription: "3 × 10 each side", howTo: "Do a push-up, then tap each hand to the opposite shoulder from a high plank. Widen your feet and keep your hips still as you tap."),
        .init(id: "wall-push-up", name: "Wall push-up", kind: .home, focus: .upper, muscles: "Chest, triceps, shoulders", equipment: "Wall", level: .beginner, prescription: "3 × 15", howTo: "Stand an arm's length from a wall with hands at chest height and lower your chest towards it, then press back. Keep your body in one straight line from head to heels."),
        .init(id: "wall-walk", name: "Wall walk", kind: .home, focus: .upper, muscles: "Shoulders, core, triceps", equipment: "Wall", level: .advanced, prescription: "3 × 5", howTo: "From a push-up position with your feet at the wall, walk your feet up and your hands in until your chest nears the wall, then walk back down. Keep your core tight and only go as high as you can control."),
        .init(id: "wall-handstand-push-up", name: "Wall handstand push-up", kind: .home, focus: .upper, muscles: "Shoulders, triceps", equipment: "Wall", level: .advanced, prescription: "3 × 5", howTo: "Kick up into a handstand against the wall, lower your head under control to just above the floor, then press back up. Keep your elbows tracking forward and stop before your head touches down."),
        .init(id: "handstand-push-up", name: "Handstand push-up", kind: .home, focus: .upper, muscles: "Shoulders, triceps, core", equipment: "Parallettes", level: .advanced, prescription: "3 × 3", howTo: "Balance in a freestanding handstand, bend your elbows to lower your head between your hands, then press back to straight arms. Squeeze your glutes and abs to stay stacked; master the wall version first."),
        .init(id: "doorway-row", name: "Doorway row", kind: .home, focus: .upper, muscles: "Back, biceps", equipment: "Doorway", level: .beginner, prescription: "3 × 12", howTo: "Grip a sturdy door frame, lean back with straight arms, then pull your chest towards the frame. Keep your body straight and squeeze your shoulder blades together at the top."),
        .init(id: "towel-row", name: "Towel row", kind: .home, focus: .upper, muscles: "Back, biceps", equipment: "Towel", level: .beginner, prescription: "3 × 12", howTo: "Hold a towel taut in both hands and pull it towards your body by driving your elbows back. Keep your chest up and squeeze your shoulder blades at the end of each pull."),
        .init(id: "prone-y-raise", name: "Prone Y raise", kind: .home, focus: .upper, muscles: "Upper back, rear delts", equipment: "Mat", level: .beginner, prescription: "3 × 12", howTo: "Lie face down with your arms overhead in a Y, thumbs up, and lift your arms off the floor by drawing your shoulder blades down and back. Keep your neck long and your lower back relaxed."),
        .init(id: "superman-hold", name: "Superman back hold", kind: .home, focus: .core, muscles: "Lower back, glutes", equipment: "Mat", level: .beginner, prescription: "3 × 30 sec", howTo: "Lie face down and lift your arms, chest and legs a few centimetres off the floor and hold. Squeeze your glutes and keep your gaze down so your neck stays neutral."),
        .init(id: "reverse-snow-angel", name: "Reverse snow angel", kind: .home, focus: .upper, muscles: "Upper back, rear delts", equipment: "Mat", level: .beginner, prescription: "3 × 10", howTo: "Lie face down with your chest and arms lifted, then sweep your arms in a wide arc from your hips to overhead and back. Keep your arms off the floor and move slowly."),
        .init(id: "dead-hang", name: "Dead hang", kind: .home, focus: .upper, muscles: "Forearms, lats, shoulders", equipment: "Pull-up bar", level: .beginner, prescription: "3 × 30 sec", howTo: "Grip the bar shoulder-width apart and hang with straight arms and relaxed legs. Breathe steadily and step down before your grip gives out."),
        .init(id: "active-hang", name: "Active hang", kind: .home, focus: .upper, muscles: "Lats, upper back, forearms", equipment: "Pull-up bar", level: .beginner, prescription: "3 × 20 sec", howTo: "Hang from the bar, then pull your shoulders down away from your ears without bending your elbows and hold. Keep your ribs down and your legs still."),
        .init(id: "scapular-pull-up", name: "Scapular pull-up", kind: .home, focus: .upper, muscles: "Lats, upper back", equipment: "Pull-up bar", level: .beginner, prescription: "3 × 10", howTo: "From a dead hang, pull your shoulder blades down and together to lift your body a few centimetres, then lower slowly. Keep your arms straight throughout."),
        .init(id: "negative-pull-up", name: "Negative pull-up", kind: .home, focus: .upper, muscles: "Lats, biceps, forearms", equipment: "Pull-up bar", level: .intermediate, prescription: "3 × 5", howTo: "Jump or step up so your chin is over the bar, then lower yourself as slowly as you can to a full hang. Aim for 3 to 5 seconds down and keep your shoulders pulled away from your ears."),
        .init(id: "commando-pull-up", name: "Commando pull-up", kind: .home, focus: .upper, muscles: "Lats, biceps, core", equipment: "Pull-up bar", level: .advanced, prescription: "3 × 6 each side", howTo: "Stand side-on under the bar, grip it with hands close together, and pull your head up to one side of the bar. Lower all the way down, then alternate the side your head passes on each rep."),
        .init(id: "l-sit-pull-up", name: "L-sit pull-up", kind: .home, focus: .upper, muscles: "Lats, biceps, abs", equipment: "Pull-up bar", level: .advanced, prescription: "3 × 6", howTo: "Hang from the bar and lift your straight legs to hip height, then pull your chin over the bar. Keep the legs up the whole set and lower slowly without swinging."),
        .init(id: "towel-pull-up", name: "Towel pull-up", kind: .home, focus: .upper, muscles: "Lats, biceps, forearms", equipment: "Pull-up bar, towels", level: .advanced, prescription: "3 × 5", howTo: "Loop two towels over the bar, grip one in each hand, and pull your chest up between them. Squeeze the towels hard and lower under control; use strong towels that cannot slip."),
        .init(id: "pistol-squat", name: "Pistol squat", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "None", level: .advanced, prescription: "3 × 5 each side", howTo: "Stand on one leg with the other held straight out in front, and sit down until your hip is below the knee. Keep the standing heel down and the knee over your toes, then drive back up."),
        .init(id: "assisted-pistol-squat", name: "Assisted pistol squat", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "Sturdy support", level: .intermediate, prescription: "3 × 6 each side", howTo: "Hold a sturdy rail, lift one leg out in front, and squat down on the other as low as you can control. Use your hands only as much as you need to stand back up."),
        .init(id: "shrimp-squat", name: "Shrimp squat", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "None", level: .advanced, prescription: "3 × 5 each side", howTo: "Stand on one leg, bend the other behind you, and lower until that knee lightly touches the floor. Keep your chest up and push through the standing heel to rise; hold a pole for balance if you need it."),
        .init(id: "cossack-squat", name: "Cossack squat", kind: .home, focus: .lower, muscles: "Quads, glutes, adductors", equipment: "None", level: .intermediate, prescription: "3 × 8 each side", howTo: "Take a wide stance and shift your weight to one side, bending that knee while the other leg stays straight with toes up. Keep the bent heel flat and your chest tall, then push back through the middle to the other side."),
        .init(id: "sissy-squat", name: "Sissy squat", kind: .home, focus: .lower, muscles: "Quads", equipment: "None", level: .advanced, prescription: "3 × 8", howTo: "Anchor your feet, rise onto your toes, and lean back as your knees travel forward and down. Keep a straight line from knees to shoulders and go only as deep as your knees allow."),
        .init(id: "forward-lunge", name: "Forward lunge", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "None", level: .beginner, prescription: "3 × 10 each side", howTo: "Step forward and lower until both knees are bent to about 90 degrees, back knee just above the floor. Push through the front heel to return to standing."),
        .init(id: "curtsy-lunge", name: "Curtsy lunge", kind: .home, focus: .lower, muscles: "Glutes, quads", equipment: "None", level: .beginner, prescription: "3 × 10 each side", howTo: "Step one foot behind and across the other, then bend both knees to lower your hips. Keep your hips square to the front and push through the front heel to stand."),
        .init(id: "skater-squat", name: "Skater squat", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "None", level: .advanced, prescription: "3 × 6 each side", howTo: "Stand on one leg, bend the other behind you, and squat until the back knee nearly touches the floor. Lean your chest forward slightly for balance and keep the front knee in line with your toes."),
        .init(id: "single-leg-box-squat", name: "Single-leg box squat", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "Box or chair", level: .intermediate, prescription: "3 × 8 each side", howTo: "Stand in front of a box on one leg with the other held out in front, and sit back until you touch the box. Stand up without rocking, keeping the knee over your toes."),
        .init(id: "step-down", name: "Step-down", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "Step or box", level: .beginner, prescription: "3 × 10 each side", howTo: "Stand on a box on one leg and slowly lower the other heel to tap the floor beside it. Keep the standing knee tracking over your toes and press back up through that heel."),
        .init(id: "calf-raise", name: "Calf raise", kind: .home, focus: .lower, muscles: "Calves", equipment: "None", level: .beginner, prescription: "3 × 15", howTo: "Stand tall with feet hip-width apart and rise as high as you can onto the balls of your feet. Pause at the top, then lower your heels slowly; hold a support lightly for balance."),
        .init(id: "single-leg-calf-raise", name: "Single-leg calf raise", kind: .home, focus: .lower, muscles: "Calves", equipment: "None", level: .beginner, prescription: "3 × 12 each side", howTo: "Stand on one foot holding a support for balance and rise as high as you can onto the ball of the foot. Lower slowly until the heel is just below or level with the toes."),
        .init(id: "glute-bridge-march", name: "Glute bridge march", kind: .home, focus: .lower, muscles: "Glutes, hamstrings, core", equipment: "Mat", level: .intermediate, prescription: "3 × 10 each side", howTo: "Lift your hips into a bridge, then raise one knee toward your chest and set it down before switching legs. Keep your hips level and squeezed up the whole time."),
        .init(id: "frog-pump", name: "Frog pump", kind: .home, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Mat", level: .beginner, prescription: "3 × 20", howTo: "Lie on your back with the soles of your feet together and knees falling out, then drive your hips up and squeeze your glutes. Lower under control without arching your lower back."),
        .init(id: "fire-hydrant", name: "Fire hydrant", kind: .home, focus: .lower, muscles: "Glutes, core", equipment: "Mat", level: .beginner, prescription: "3 × 12 each side", howTo: "On hands and knees, lift one bent leg out to the side to hip height, then lower it slowly. Keep your back flat and your hips square to the floor."),
        .init(id: "clamshell", name: "Clamshell", kind: .home, focus: .lower, muscles: "Glutes", equipment: "Mat (band optional)", level: .beginner, prescription: "3 × 15 each side", howTo: "Lie on your side with knees bent and a band above them, then open the top knee while your feet stay together. Don't let your hips roll back as the knee rises."),
        .init(id: "hip-airplane", name: "Hip airplane", kind: .home, focus: .lower, muscles: "Glutes, hamstrings, core", equipment: "Wall or pole", level: .advanced, prescription: "3 × 6 each side", howTo: "Hinge forward on one leg holding a support, then slowly rotate your pelvis open toward the ceiling and back to level. Keep the standing knee soft and move only as far as you can control."),
        .init(id: "side-lying-hip-abduction", name: "Side-lying hip abduction", kind: .home, focus: .lower, muscles: "Glutes, core", equipment: "Mat", level: .beginner, prescription: "3 × 15 each side", howTo: "Lie on your side with legs straight and lift the top leg up and slightly back, leading with the heel. Lower slowly and keep your hips stacked."),
        .init(id: "side-lying-leg-raise", name: "Side-lying leg raise", kind: .home, focus: .lower, muscles: "Glutes, core", equipment: "Mat", level: .beginner, prescription: "3 × 12 each side", howTo: "Lie on your side propped on an elbow and raise the top leg as high as you can without rolling your hips. Pause at the top, then lower it slowly."),
        .init(id: "lying-hamstring-walkout", name: "Suspension hamstring curl", kind: .home, focus: .lower, muscles: "Hamstrings, glutes, core", equipment: "Suspension trainer", level: .intermediate, prescription: "3 × 10", howTo: "Lie on your back with your heels in the straps, lift your hips and pull your heels toward you. Keep your hips up as you straighten the legs back out slowly."),
        .init(id: "towel-hamstring-curl", name: "Towel hamstring curl", kind: .home, focus: .lower, muscles: "Hamstrings, glutes", equipment: "Towel", level: .beginner, prescription: "3 × 10 each side", howTo: "Lie on your back with a towel around one foot and bend and straighten that knee against the towel's pull. Keep your lower back flat on the floor."),
        .init(id: "stability-ball-hamstring-curl", name: "Stability ball hamstring curl", kind: .home, focus: .lower, muscles: "Hamstrings, glutes, core", equipment: "Stability ball", level: .intermediate, prescription: "3 × 10", howTo: "With your heels on the ball and hips lifted, roll the ball toward you by bending your knees, then roll it back out. Keep your hips high and your body in a straight line."),
        .init(id: "banded-glute-bridge", name: "Banded glute bridge pulse", kind: .home, focus: .lower, muscles: "Glutes, hamstrings, core", equipment: "Resistance band", level: .beginner, prescription: "3 × 15", howTo: "With a band above your knees, press your knees out and drive your hips up until your body is straight from knees to shoulders. Squeeze your glutes at the top and lower slowly."),
        .init(id: "banded-frog-pump", name: "Banded frog pump", kind: .home, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Resistance band", level: .beginner, prescription: "3 × 20", howTo: "With a band around your thighs and the soles of your feet together, push your knees out and drive your hips up. Squeeze your glutes at the top and lower under control."),
        .init(id: "banded-clamshell", name: "Banded clamshell", kind: .home, focus: .lower, muscles: "Glutes", equipment: "Resistance band", level: .beginner, prescription: "3 × 15 each side", howTo: "Lie on your side with knees bent and the band above them, then open the top knee while your feet stay together. Keep your hips stacked; don't roll back."),
        .init(id: "banded-lateral-walk", name: "Banded lateral walk", kind: .home, focus: .lower, muscles: "Glutes, quads", equipment: "Resistance band", level: .beginner, prescription: "3 × 12 each side", howTo: "Sit into a quarter squat with the band around your legs and step sideways, keeping tension on the band. Keep your toes forward and don't let your knees cave in."),
        .init(id: "banded-monster-walk", name: "Banded monster walk", kind: .home, focus: .lower, muscles: "Glutes, quads", equipment: "Resistance band", level: .beginner, prescription: "3 × 12 each side", howTo: "In a half squat with the band above your knees, walk forward and out on a diagonal in small steps. Keep your knees pushed out against the band and your chest up."),
        .init(id: "banded-squat", name: "Banded squat", kind: .home, focus: .lower, muscles: "Quads, glutes", equipment: "Resistance band", level: .beginner, prescription: "3 × 12", howTo: "Stand on the band holding it at your shoulders, then sit your hips back and down and drive up through your heels. Keep your chest up and your knees in line with your toes."),
        .init(id: "banded-donkey-kick", name: "Banded donkey kick", kind: .home, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Resistance band", level: .beginner, prescription: "3 × 15 each side", howTo: "On hands and knees with the band around your thighs, press one bent leg up until the thigh is level with your back. Brace your core so your lower back doesn't arch."),
        .init(id: "banded-fire-hydrant", name: "Banded fire hydrant", kind: .home, focus: .lower, muscles: "Glutes", equipment: "Resistance band", level: .beginner, prescription: "3 × 15 each side", howTo: "On hands and knees with the band above your knees, lift one bent leg out to the side, then lower with control. Keep your hips level and your back flat."),
        .init(id: "banded-kickback", name: "Banded glute kickback", kind: .home, focus: .lower, muscles: "Glutes, hamstrings", equipment: "Resistance band", level: .beginner, prescription: "3 × 12 each side", howTo: "Hold a support, lean forward slightly and push one leg straight back against the band, squeezing your glute at the top. Move from the hip, not the lower back."),
        .init(id: "banded-standing-hip-abduction", name: "Banded standing hip abduction", kind: .home, focus: .lower, muscles: "Glutes", equipment: "Resistance band", level: .beginner, prescription: "3 × 15 each side", howTo: "Stand tall with the band around your ankles and lift one straight leg out to the side, then lower slowly. Keep your torso upright; don't lean away from the working leg."),
        .init(id: "banded-seated-hip-abduction", name: "Banded seated hip abduction", kind: .home, focus: .lower, muscles: "Glutes", equipment: "Resistance band, chair", level: .beginner, prescription: "3 × 20", howTo: "Sit on the edge of a chair with the band above your knees and push your knees apart, then return slowly. Keep your feet planted and sit tall."),
        .init(id: "band-pull-apart", name: "Band pull-apart", kind: .home, focus: .upper, muscles: "Upper back, rear delts", equipment: "Resistance band", level: .beginner, prescription: "3 × 15", howTo: "Hold the band at shoulder height with straight arms and pull it apart until it touches your chest. Squeeze your shoulder blades together and keep your shoulders down."),
        .init(id: "banded-face-pull", name: "Banded face pull", kind: .home, focus: .upper, muscles: "Rear delts, upper back", equipment: "Resistance band", level: .beginner, prescription: "3 × 15", howTo: "Anchor the band at face height and pull the ends toward your forehead, elbows high and wide. Finish with your hands beside your ears and control the return."),
        .init(id: "banded-row", name: "Banded row", kind: .home, focus: .upper, muscles: "Back, biceps", equipment: "Resistance band", level: .beginner, prescription: "3 × 12", howTo: "With the band anchored in front of you, pull the handles to your lower ribs and squeeze your shoulder blades together. Keep your chest up and don't jerk with your back."),
        .init(id: "banded-lat-pulldown", name: "Banded lat pulldown", kind: .home, focus: .upper, muscles: "Lats, biceps", equipment: "Resistance band", level: .beginner, prescription: "3 × 12", howTo: "Sit under a high anchor and pull the band down until your hands reach shoulder level, driving your elbows toward your hips. Keep your chest up and return slowly."),
        .init(id: "banded-pallof-press", name: "Banded Pallof press", kind: .home, focus: .core, muscles: "Core, obliques", equipment: "Resistance band", level: .beginner, prescription: "3 × 10 each side", howTo: "Stand side-on to the anchor, hold the band at your chest and press it straight out, then bring it back. Brace your core so your body doesn't twist toward the band."),
        .init(id: "banded-woodchop", name: "Banded woodchop", kind: .home, focus: .core, muscles: "Obliques, abs, shoulders", equipment: "Resistance band", level: .beginner, prescription: "3 × 10 each side", howTo: "With the band anchored high, pull it diagonally down across your body to the opposite hip, turning through your trunk and pivoting the back foot. Keep your arms long and control the band back up."),
        .init(id: "banded-dead-bug", name: "Banded dead bug", kind: .home, focus: .core, muscles: "Abs", equipment: "Resistance band", level: .beginner, prescription: "3 × 8 each side", howTo: "Lie on your back holding a band looped around one foot, arms and knees up, and press your lower back into the floor. Straighten the opposite arm and leg slowly without letting your back arch."),
        .init(id: "hollow-body-hold", name: "Hollow body hold", kind: .home, focus: .core, muscles: "Abs, quads", equipment: "Mat", level: .intermediate, prescription: "3 × 30 sec", howTo: "Lie on your back, lift your shoulders and straight legs off the floor and reach your arms overhead. Keep your lower back pressed down; bend your knees if it starts to lift."),
        .init(id: "hollow-rock", name: "Hollow rock", kind: .home, focus: .core, muscles: "Abs, quads", equipment: "Mat", level: .intermediate, prescription: "3 × 15", howTo: "Hold the hollow position, arms overhead and legs straight, and rock from shoulders to hips as one rigid piece. Keep your lower back rounded into the floor and don't bend at the hips."),
        .init(id: "flutter-kick", name: "Flutter kicks", kind: .home, focus: .core, muscles: "Abs, quads", equipment: "Mat", level: .beginner, prescription: "3 × 30 sec", howTo: "Lean back on your elbows, lift both straight legs a little off the floor and kick them up and down in small, quick strokes. Keep your lower back flat; raise the legs higher if it arches."),
        .init(id: "heel-tap", name: "Heel taps", kind: .home, focus: .core, muscles: "Obliques, abs", equipment: "Mat", level: .beginner, prescription: "3 × 12 each side", howTo: "Lie with knees bent and shoulders slightly lifted, then crunch sideways to touch one heel, then the other. Keep your shoulders off the floor and your neck relaxed."),
        .init(id: "plank-shoulder-tap", name: "Plank shoulder tap", kind: .home, focus: .core, muscles: "Core, shoulders", equipment: "None", level: .intermediate, prescription: "3 × 10 each side", howTo: "In a high plank with feet wide, lift one hand to tap the opposite shoulder, then switch. Keep your hips square and still; don't rock side to side."),
        .init(id: "bear-plank", name: "Bear plank", kind: .home, focus: .core, muscles: "Core, quads, shoulders", equipment: "None", level: .beginner, prescription: "3 × 30 sec", howTo: "On hands and knees, hands under shoulders and knees under hips, lift your knees an inch off the floor and hold. Keep your back flat and breathe steadily."),
        .init(id: "crab-walk", name: "Crab walk", kind: .home, focus: .fullBody, muscles: "Triceps, glutes, core", equipment: "None", level: .beginner, prescription: "3 × 30 sec", howTo: "Sit with hands behind you and feet flat, lift your hips and walk on hands and feet. Keep your hips up and your fingers pointing toward your feet to protect your shoulders."),
        .init(id: "l-sit-hold", name: "L-sit hold", kind: .home, focus: .core, muscles: "Abs, quads, triceps", equipment: "Parallettes", level: .advanced, prescription: "4 × 15 sec", howTo: "Press down through straight arms on parallettes, lift your hips and hold your legs straight out in front. Push your shoulders down away from your ears; tuck the knees if you can't keep the legs straight."),
        .init(id: "side-plank-hip-dip", name: "Side plank hip dip", kind: .home, focus: .core, muscles: "Obliques, glutes, shoulders", equipment: "Mat", level: .intermediate, prescription: "3 × 10 each side", howTo: "From a side plank on your forearm, lower your hip toward the floor and lift it back above the line of your body. Keep your elbow under your shoulder and move slowly."),
        .init(id: "copenhagen-plank", name: "Copenhagen plank", kind: .home, focus: .core, muscles: "Inner thighs, obliques", equipment: "Bench", level: .advanced, prescription: "3 × 20 sec each side", howTo: "Lie on your side on your forearm with your top leg resting on a bench, then lift your hips and bottom leg off the floor. Keep your body in a straight line; rest the knee on the bench instead of the foot to make it easier."),
        .init(id: "dragon-flag", name: "Dragon flag", kind: .home, focus: .core, muscles: "Abs, lats", equipment: "Bench or sturdy post", level: .advanced, prescription: "3 × 5", howTo: "Lie back and grip a bench or sturdy post behind your head, lift your body onto your upper back and lower it as one straight line. Lower slowly and stop before your hips sag or your lower back arches."),
        .init(id: "assault-bike", name: "Assault bike", kind: .cardio, focus: nil, muscles: "Heart, quads, shoulders", equipment: "Assault bike", level: .intermediate, prescription: "10 × 20 sec", howTo: "Push and pull the handles while you drive the pedals, keeping your chest tall. Go hard for the interval, then pedal easy until the next one."),
        .init(id: "skierg", name: "SkiErg", kind: .cardio, focus: nil, muscles: "Heart, lats, triceps", equipment: "SkiErg", level: .intermediate, prescription: "10 min", howTo: "Reach the handles high, then pull them down past your hips as you hinge and bend your knees slightly. Drive with your lats and core, not just your arms."),
        .init(id: "hiking", name: "Hiking", kind: .cardio, focus: nil, muscles: "Heart, legs, glutes", equipment: "None", level: .beginner, prescription: "30 min", howTo: "Walk at a steady pace you can hold while still talking, pushing through your whole foot on each climb. Keep your posture tall and shorten your stride on steep ground."),
        .init(id: "treadmill-incline-walk", name: "Treadmill incline walk", kind: .cardio, focus: nil, muscles: "Heart, legs, glutes", equipment: "Treadmill", level: .beginner, prescription: "20 min", howTo: "Set a steep incline and walk at a brisk pace, pushing through your heels. Hold the rails only lightly for balance, not to take your weight."),
        .init(id: "half-burpee", name: "Half burpee", kind: .cardio, focus: nil, muscles: "Heart, legs, core", equipment: "None", level: .beginner, prescription: "4 × 30 sec", howTo: "Squat down, place your hands on the floor and jump your feet back to a plank, then jump them back in and stand. Keep your core tight in the plank so your hips don't sag."),
        .init(id: "squat-thrust", name: "Squat thrust", kind: .cardio, focus: nil, muscles: "Heart, core, legs", equipment: "None", level: .beginner, prescription: "4 × 30 sec", howTo: "From a crouch with hands on the floor, jump your feet back to a plank, then jump them back in under your hips. Keep your hips level in the plank so your lower back does not sag."),
        .init(id: "fast-feet", name: "Ladder fast feet", kind: .cardio, focus: nil, muscles: "Heart, calves, quads", equipment: "Agility ladder", level: .beginner, prescription: "4 × 30 sec", howTo: "Run through the ladder on the balls of your feet, landing one or both feet in each box. Keep your steps short and quick and your knees soft."),
        .init(id: "sprawl", name: "Sprawl", kind: .cardio, focus: nil, muscles: "Heart, legs, core", equipment: "None", level: .intermediate, prescription: "4 × 30 sec", howTo: "Drop your hands to the floor and shoot your legs back, letting your hips sink toward the floor, then snap your feet back in and stand up. Land softly and keep your arms straight to protect your shoulders."),
        .init(id: "seal-jack", name: "Seal jack", kind: .cardio, focus: nil, muscles: "Heart, chest, shoulders", equipment: "None", level: .beginner, prescription: "4 × 30 sec", howTo: "Jump your feet out while opening your straight arms wide to the sides, then jump them in as you clap your hands in front of your chest. Keep a steady rhythm and land softly on the balls of your feet."),
        .init(id: "leg-swings-stretch", name: "Leg swings", kind: .mobility, focus: nil, muscles: "Hip flexors, hamstrings", equipment: "Wall or rail", level: .beginner, prescription: "2 × 10 each side", howTo: "Hold a rail for balance and swing one straight leg forward and back, letting the swing grow a little each time. Keep your torso tall and the movement controlled rather than kicking."),
        .init(id: "seated-forward-fold-stretch", name: "Seated forward fold", kind: .mobility, focus: nil, muscles: "Hamstrings, lower back, calves", equipment: "Mat", level: .beginner, prescription: "3 × 30 sec", howTo: "Sit with your legs straight and hinge forward from the hips, reaching toward your feet. Keep your back long and stop at a gentle stretch; bend your knees slightly if you need to."),
        .init(id: "wall-calf-stretch", name: "Wall calf stretch", kind: .mobility, focus: nil, muscles: "Calves", equipment: "Wall", level: .beginner, prescription: "30 sec each side", howTo: "Lean your hands on a wall with one foot stepped back, back leg straight and heel pressed into the floor. Bend the front knee until you feel the stretch in the back calf, and keep the back toes pointing forward."),
    ]
}

// MARK: - Lookups, kit and movement families

extension Exercise {
    /// The catalogue by lowercased name, for matching a workout step (written by AI or saved earlier) to its entry.
    static let byLowercasedName: [String: Exercise] = Dictionary(catalog.map { ($0.name.lowercased(), $0) },
                                                                 uniquingKeysWith: { first, _ in first })

    /// The catalogue entry with this name, ignoring case and surrounding spaces.
    static func named(_ name: String) -> Exercise? {
        byLowercasedName[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    /// Things found in any home. Anything else (a bar, dip bars, parallettes, a bench,
    /// a box, a band, a ball, weights) counts as kit.
    static let householdKit: Set<String> = [
        "none", "mat", "wall", "a wall", "floor", "chair", "sturdy chair", "towel", "optional weight",
        "doorway", "a doorway", "door frame", "sturdy support", "sturdy table", "step", "sturdy step", "stairs",
    ]

    /// True when the exercise can be done with household things only, so it suits a
    /// "little or no kit" home session. `equipment` reads as alternatives joined by
    /// " or ", each a comma-separated list of things needed together; "(… optional)"
    /// notes are ignored. One alternative made only of household things is enough.
    var needsNoKit: Bool {
        var text = equipment.lowercased()
        if let open = text.firstIndex(of: "("), text.contains("optional)") { text = String(text[..<open]) }
        return text.components(separatedBy: " or ").contains { alternative in
            let items = alternative.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return !items.isEmpty && items.allSatisfy { Self.householdKit.contains($0) }
        }
    }

    /// The movement this is a version of ("hinge", "row", "push-up" …), so a session
    /// doesn't fill up with variants of one lift. Exercises that fit no family are their own.
    var family: String {
        let words = ExerciseText.words(name)
        func has(_ phrase: String) -> Bool { ExerciseText.contains(words, phrase) }
        let table: [(String, [String])] = [
            ("calf raise", ["calf raise"]),
            ("triceps", ["triceps", "tricep", "skull crusher", "skullcrusher", "pushdown", "overhead extension",
                         "overhead dumbbell extension"]),
            ("chest press", ["bench press", "chest press", "incline dumbbell press", "decline dumbbell press"]),
            ("lunge", ["lunge", "split squat", "step up", "step down"]),
            ("hinge", ["deadlift", "good morning", "pull through", "swing", "rack pull"]),
            ("back extension", ["back extension", "hyperextension", "superman"]),
            ("bridge", ["hip thrust", "bridge", "frog pump"]),
            ("leg curl", ["leg curl", "hamstring curl", "nordic"]),
            ("hip abduction", ["abduction", "clamshell", "fire hydrant", "lateral walk", "monster walk"]),
            ("glute kickback", ["kickback", "donkey kick"]),
            ("vertical push", ["overhead press", "shoulder press", "dumbbell press", "arnold press", "push press",
                               "landmine press", "pike", "handstand", "wall walk"]),
            ("push-up", ["push up", "pushup"]),
            ("rear delt", ["reverse fly", "rear delt", "reverse pec deck", "face pull", "pull apart",
                           "t raise", "y raise", "snow angel"]),
            ("fly", ["fly", "pec deck"]),
            ("vertical pull", ["pulldown", "pull up", "chin up"]),
            ("hang", ["hang"]),
            ("row", ["row"]),
            ("dip", ["dip"]),
            ("lateral raise", ["lateral raise"]),
            ("front raise", ["front raise"]),
            ("curl", ["curl"]),
            ("squat", ["squat"]),
            ("plank", ["plank"]),
            ("crunch", ["crunch", "sit up"]),
            ("rotation", ["twist", "woodchop", "side bend", "windmill"]),
            ("anti-rotation", ["pallof"]),
            ("leg raise", ["leg raise", "knee raise", "knee tuck", "v up", "flutter", "hollow", "dragon flag", "l sit"]),
            ("dead bug", ["dead bug", "bird dog"]),
        ]
        for (family, phrases) in table where phrases.contains(where: has) { return family }
        return words.joined(separator: " ")
    }
}

/// Word-level text matching for exercise names, so "row" doesn't match "narrow".
enum ExerciseText {
    /// Lowercased words, split on anything that isn't a letter, digit or apostrophe
    /// ("Push-up" → ["push", "up"]).
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init)
    }

    /// True when the words of `phrase` appear one after another in `words`.
    static func contains(_ words: [String], _ phrase: String) -> Bool {
        let needle = Self.words(phrase)
        guard !needle.isEmpty, needle.count <= words.count else { return false }
        for start in 0...(words.count - needle.count) where Array(words[start..<start + needle.count]) == needle {
            return true
        }
        return false
    }
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

    /// What the session is, independent of its `id` (a new one each time a session is
    /// built): kind, level, length, title and the exercises in order. Two separately
    /// built but identical sessions share it, so marking either as done logs it once a day.
    var contentKey: String {
        ([kind.rawValue, level.rawValue, String(durationMinutes), title.lowercased()]
            + exercises.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            .joined(separator: "|")
    }

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
    /// The workout this logs. `nil` in older entries.
    var workoutID: UUID? = nil
    /// The logged session's `Workout.contentKey`, so marking the same session twice in a day
    /// adds nothing, even when it was built twice. `nil` in older entries.
    var contentKey: String? = nil
    let title: String
    let kind: ExerciseKind
    let minutes: Int
    let calories: Int
    var date = Date()
}
