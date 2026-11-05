import SwiftUI

/// Teal-tinted chat bubble from the SmartMarket agent.
struct AgentMessageCardView: View {

    let message: String?
    let isLoading: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showTyping: Bool { isLoading || (message?.isEmpty ?? true) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("SM")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.onAccent)
                .frame(width: 36, height: 36)
                .background(Color.dullPink)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mealio Agent")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.brandDark)

                if showTyping {
                    TypingDotsView(reduceMotion: reduceMotion)
                } else {
                    Text(message ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Color.labelPrimary)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.brandPrimary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.brandPrimary.opacity(0.18), lineWidth: 0.5)
        )
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: showTyping)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showTyping ? "Agent is generating your plan" : (message ?? ""))
    }
}

private struct TypingDotsView: View {
    let reduceMotion: Bool
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.brandPrimary.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == index ? 1.3 : 0.7)
                    .opacity(phase == index ? 1.0 : 0.5)
            }
        }
        .frame(height: 14)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AgentMessageCardView(message: "I built your plan around salmon and chicken to hit your protein target while staying within your budget.", isLoading: false)
        AgentMessageCardView(message: nil, isLoading: true)
    }
    .padding()
}
