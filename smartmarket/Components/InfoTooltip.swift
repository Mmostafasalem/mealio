import SwiftUI

/// Small ⓘ button that explains a metric. Inside a `.morphTooltipHost()` it shares
/// the host's one travelling bubble (see MorphTooltip.swift); elsewhere it shows
/// its own popover. VoiceOver reads the text as the hint and speaks it on activation.
struct InfoTooltip: View {
    let text: String
    @Environment(\.morphTooltip) private var morph
    @State private var isPresented = false
    @State private var key = UUID().uuidString

    var body: some View {
        Button {
            if let morph {
                if UIAccessibility.isVoiceOverRunning {
                    AccessibilityNotification.Announcement(text).post()
                } else {
                    morph.point(key)
                }
            } else {
                isPresented.toggle()
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary.opacity(0.65))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.labelPrimary)
                .multilineTextAlignment(.leading)
                .padding(14)
                .frame(maxWidth: 230)
                .presentationCompactAdaptation(.popover)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MorphTooltipModel.space)) } action: { frame in
            morph?.setAnchor(frame, for: key)
        }
        .onAppear { morph?.register(key, text: text) }
        .onChange(of: text) { _, new in morph?.register(key, text: new) }
        .onDisappear { morph?.unregister(key) }
        .accessibilityLabel("More info")
        .accessibilityHint(text)
    }
}
