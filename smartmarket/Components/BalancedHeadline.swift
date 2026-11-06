import SwiftUI

/// Public UIKit line breaking avoids a lone word on the last headline line.
/// Dynamic Type and VoiceOver remain native; no manual device-specific breaks.
struct BalancedHeadline: UIViewRepresentable {
    let text: String
    var color: Color = .labelPrimary

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.lineBreakStrategy = .pushOut
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: label.traitCollection)
        label.textColor = UIColor(color)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
