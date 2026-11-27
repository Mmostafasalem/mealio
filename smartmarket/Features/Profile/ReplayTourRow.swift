import SwiftUI

/// "Replay the tour" for Profile › Help: closes Profile, goes to Home and runs the
/// guided tour again (`GuidedTour`). A plain list row, for a `List` section.
struct ReplayTourRow: View {
    var body: some View {
        Button { GuidedTour.shared.replay() } label: {
            Label("Replay the tour", systemImage: "sparkles")
        }
        .accessibilityHint("Goes back to Home and shows you around again")
        .accessibilityIdentifier("profile.replayTour")
    }
}
