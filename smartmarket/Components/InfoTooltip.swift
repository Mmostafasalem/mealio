import SwiftUI

/// Small ⓘ button that shows a popover explaining a metric.
struct InfoTooltip: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
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
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .padding(14)
                .frame(maxWidth: 230)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("More info")
        .accessibilityHint(text)
    }
}
