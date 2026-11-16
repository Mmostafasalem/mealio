import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The workout in progress on the lock screen and in the Dynamic Island, with
/// Next and Finish buttons (`LiveActivityIntent`s that run in the app).
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(title: context.attributes.title, sessionID: context.attributes.sessionID,
                                  state: context.state)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(Color.nourloPink)
                .widgetURL(NourloLink.train.url)
        } dynamicIsland: { context in
            let state = context.state
            let sessionID = context.attributes.sessionID
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(NourloWidgetFormat.stepShort(index: state.index, total: state.total),
                          systemImage: "figure.strengthtraining.traditional")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.nourloPink)
                        .accessibilityLabel(NourloWidgetFormat.stepPosition(index: state.index, total: state.total))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: state)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: 72, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.isFinished ? "Workout done" : state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if !state.isFinished, !state.detail.isEmpty {
                            Text(state.detail)
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        WorkoutActivityButtons(sessionID: sessionID, state: state)
                    }
                }
            } compactLeading: {
                Image(systemName: state.isFinished ? "checkmark.circle.fill" : "figure.strengthtraining.traditional")
                    .foregroundStyle(Color.nourloPink)
                    .accessibilityLabel(state.isFinished ? "Workout done" : context.attributes.title)
            } compactTrailing: {
                if state.isFinished {
                    Text("Done").font(.caption.weight(.semibold))
                } else {
                    Text(NourloWidgetFormat.stepShort(index: state.index, total: state.total))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel(NourloWidgetFormat.stepPosition(index: state.index, total: state.total))
                }
            } minimal: {
                Image(systemName: state.isFinished ? "checkmark" : "figure.strengthtraining.traditional")
                    .foregroundStyle(Color.nourloPink)
                    .accessibilityLabel(state.isFinished ? "Workout done" : "Workout in progress")
            }
            .widgetURL(NourloLink.train.url)
            .keylineTint(Color.nourloPink)
        }
    }
}

/// Elapsed time: ticking while running, fixed once finished.
private struct ElapsedText: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isFinished, let end = state.endDate {
            Text(NourloWidgetFormat.duration(end.timeIntervalSince(state.startDate)))
                .monospacedDigit()
        } else {
            Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Elapsed time")
        }
    }
}

private struct WorkoutActivityButtons: View {
    let sessionID: String
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if !state.isFinished {
            HStack(spacing: 10) {
                if !state.isLastStep {
                    Button(intent: NextExerciseIntent(sessionID: sessionID)) {
                        Label("Next", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.secondary)
                    .accessibilityHint("Moves on to the next exercise")
                }
                Button(intent: FinishWorkoutIntent(sessionID: sessionID)) {
                    Label("Finish", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color.nourloOnPink)
                }
                .tint(Color.nourloPink)
                .accessibilityHint("Logs this workout as done")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }
}

private struct WorkoutLockScreenView: View {
    let title: String
    let sessionID: String
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: "figure.strengthtraining.traditional")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.nourloPink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ElapsedText(state: state)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: 80, alignment: .trailing)
            }
            if state.isFinished {
                Text("Workout done")
                    .font(.title3.weight(.bold))
                Text("Logged for today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NourloWidgetFormat.stepPosition(index: state.index, total: state.total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(state.exerciseName)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    if !state.detail.isEmpty {
                        Text(state.detail)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                WorkoutActivityButtons(sessionID: sessionID, state: state)
            }
        }
        .padding(16)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

#Preview("Lock screen", as: .content, using: WorkoutActivityAttributes(title: "Full body strength", sessionID: "preview")) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(exerciseName: "Goblet squat", detail: "3 × 10", index: 1, total: 6,
                                           startDate: .now.addingTimeInterval(-420), isFinished: false)
    WorkoutActivityAttributes.ContentState(exerciseName: "Plank", detail: "", index: 5, total: 6,
                                           startDate: .now.addingTimeInterval(-1500), isFinished: true, endDate: .now)
}
