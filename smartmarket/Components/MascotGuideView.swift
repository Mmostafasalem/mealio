import SwiftUI
import UIKit

enum MascotMood: String, CaseIterable {
    case idle, thinking, celebrate, help, happy, sleepy

    var description: String {
        switch self {
        case .idle: return "Ready to help"
        case .thinking: return "Working on your request"
        case .celebrate: return "Ready"
        case .help: return "Help is available"
        case .happy: return "Happy"
        case .sleepy: return "Resting"
        }
    }
}

/// A local guide button, never an AI request. The bowl is drawn in code and
/// rigged (`MascotRig`): idle life runs only while visible and the app is active,
/// at 30 fps, and stops entirely under Reduce Motion. Pass `rig` to drive it from
/// a host (drag, throw, look-at); without one the view owns its own rig.
struct MascotGuideView: View {
    typealias Mood = MascotMood

    var mood: MascotMood = .idle
    var size: CGFloat = 72
    var onTap: (() -> Void)? = nil
    var trigger: Int = 0
    var hint: String? = nil
    var rig: MascotRig? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var ownRig = MascotRig()
    @State private var visible = false

    private var model: MascotRig { rig ?? ownRig }

    var body: some View {
        let model = self.model
        Button {
            // A host that passes its own rig owns the tap reaction (it may need
            // to ignore the tap that ends a drag).
            if rig == nil { model.react(.tap) }
            onTap?()
        } label: {
            MascotFigure(pose: model.pose, size: size)
                .padding(12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(MascotPressStyle())
        .accessibilityLabel("Nourlo bowl guide")
        .accessibilityValue(mood.description)
        .accessibilityHint(hint ?? (onTap == nil ? "Plays a short greeting. No AI request is sent." : "Opens local next steps and a short tour. No AI request is sent."))
        .accessibilityIdentifier("mascot.guide")
        .onAppear {
            visible = true
            model.reduceMotion = reduceMotion
            model.set(mood: mood)
            syncActive()
        }
        .onDisappear {
            visible = false
            syncActive()
        }
        .onChange(of: scenePhase) { _, _ in syncActive() }
        .onChange(of: reduceMotion) { _, on in model.reduceMotion = on }
        .onChange(of: mood) { _, m in model.set(mood: m) }
        .onChange(of: trigger) { _, _ in model.react(.tap) }
    }

    private func syncActive() {
        model.setActive(visible && scenePhase == .active)
    }
}

private struct MascotPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

#Preview("Mascot moods") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(MascotMood.allCases, id: \.self) { mood in
                HStack(spacing: 24) {
                    MascotGuideView(mood: mood, size: 36)
                    MascotGuideView(mood: mood, size: 132)
                }
            }
        }
        .padding(40)
    }
}
