import SwiftUI
import UIKit

enum MascotMood: String {
    case idle, thinking, celebrate, help

    var assetName: String {
        switch self {
        case .idle: return "BowlMascot"
        case .thinking: return "BowlMascotThinking"
        case .celebrate: return "BowlMascotCelebrate"
        case .help: return "BowlMascotHelp"
        }
    }

    var description: String {
        switch self {
        case .idle: return "Ready to help"
        case .thinking: return "Working on your request"
        case .celebrate: return "Ready"
        case .help: return "Help is available"
        }
    }
}

/// A local guide button, never an AI request. Pose changes play one short,
/// cancellable spring gesture; there are no timers or endlessly looping motions.
struct MascotGuideView: View {
    var mood: MascotMood = .idle
    var size: CGFloat = 72
    var onTap: (() -> Void)? = nil
    var trigger: Int = 0
    var hint: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var interaction = 0
    @State private var lift: CGFloat = 0
    @State private var tilt: Double = 0
    @State private var scale: CGFloat = 1

    private var motionID: String {
        "\(mood.rawValue)-\(visible)-\(scenePhase == .active)-\(reduceMotion)-\(interaction)-\(trigger)"
    }

    var body: some View {
        Button {
            interaction += 1
            onTap?()
        } label: {
            // Fit, never fill/crop: the food, arms and feet all stay visible.
            Image(UIImage(named: mood.assetName) == nil ? "BowlMascot" : mood.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(scale)
                .rotationEffect(.degrees(tilt))
                .offset(y: lift)
                .padding(12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(MascotPressStyle())
        .accessibilityLabel("Nourlo bowl guide")
        .accessibilityValue(mood.description)
        .accessibilityHint(hint ?? (onTap == nil ? "Plays a short greeting. No AI request is sent." : "Opens local next steps and a short tour. No AI request is sent."))
        .accessibilityIdentifier("mascot.guide")
        .onAppear { visible = true }
        .onDisappear {
            visible = false
            resetPose()
        }
        .task(id: motionID) {
            guard visible, scenePhase == .active, !reduceMotion else {
                resetPose()
                return
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                switch mood {
                case .idle: lift = -2; tilt = 2; scale = 1
                case .thinking: lift = -3; tilt = -6; scale = 1
                case .celebrate: lift = -8; tilt = 5; scale = 1.04
                case .help: lift = -2; tilt = -4; scale = 1
                }
            }
            do { try await Task.sleep(for: .milliseconds(320)) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                lift = 0; tilt = 0; scale = 1
            }
        }
    }

    private func resetPose() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { lift = 0; tilt = 0; scale = 1 }
    }
}

private struct MascotPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}
