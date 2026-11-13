import SwiftUI
import UIKit

// MARK: - Copy Button
//
// Port of designbookmark.com/motion "Copy Button" (copy-button/copy.js).
// Tap: the copy icon shrinks and turns away while a check pops in, the word
// rolls up from the title to the done title and the button's width springs to
// fit it. After a moment it rolls back. No autoplay: it only moves on a tap.

struct CopyButton: View {
    var title: String = "Copy"
    var doneTitle: String = "Copied"
    /// Spoken after a copy.
    var announcement: String = "Copied"
    /// The text to put on the pasteboard, built at tap time.
    let text: () -> String

    @State private var model = CopyButtonModel()
    @State private var copies = 0
    /// When VoiceOver last heard the announcement; repeated taps within 2 s stay quiet.
    @State private var lastAnnounced: Date?
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 36
    @ScaledMetric(relativeTo: .subheadline) private var icon: CGFloat = 18
    @ScaledMetric(relativeTo: .subheadline) private var row: CGFloat = 18
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            UIPasteboard.general.string = text()
            copies += 1
            model.copy()
            let now = Date()
            if lastAnnounced.map({ now.timeIntervalSince($0) >= 2 }) ?? true {
                lastAnnounced = now
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
        } label: {
            HStack(spacing: 6) {
                icons
                roll
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.labelPrimary)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(height: height)
            .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .sensoryFeedback(.success, trigger: copies)
        .accessibilityLabel(title)
        .accessibilityValue(model.isOn ? doneTitle : "")
        .onDisappear { model.stop() }
    }

    private var icons: some View {
        let i = model.icon
        let ic = motionClamp(i, 0, 1)
        return ZStack {
            Image(systemName: "doc.on.doc")
                .opacity(motionClamp(1 - i * 1.6, 0, 1))
                .scaleEffect(1 - 0.5 * ic)
                .rotationEffect(.degrees(MotionSettings.reduceMotion ? 0 : -40 * ic))
            Image(systemName: "checkmark")
                .fontWeight(.bold)
                .foregroundStyle(Color.dullPink)
                .opacity(motionClamp(i * 1.6 - 0.4, 0, 1))
                .scaleEffect(max(0, 0.4 + 0.6 * i))
        }
        .font(.system(size: icon * 0.86, weight: .medium))
        .frame(width: icon, height: icon)
        .accessibilityHidden(true)
    }

    /// Both words stacked; the clip shows one row and springs to its width.
    /// Reduce Motion: the words crossfade in place instead of rolling.
    @ViewBuilder private var roll: some View {
        if reduceMotion { fade } else { rolling }
    }

    private var fade: some View {
        let on = motionClamp(model.roll, 0, 1)
        return ZStack(alignment: .leading) {
            Text(title)
                .frame(height: row)
                .fixedSize()
                .opacity(1 - on)
                .background(widthReader { model.setWidths(idle: $0, done: nil) })
            Text(doneTitle)
                .foregroundStyle(Color.brandPrimary)
                .frame(height: row)
                .fixedSize()
                .opacity(on)
                .background(widthReader { model.setWidths(idle: nil, done: $0) })
        }
        .lineLimit(1)
        .frame(width: model.width > 0 ? model.width : nil, height: row, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }

    private var rolling: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .frame(height: row)
                .fixedSize()
                .background(widthReader { model.setWidths(idle: $0, done: nil) })
            Text(doneTitle)
                .foregroundStyle(Color.brandPrimary)
                .frame(height: row)
                .fixedSize()
                .background(widthReader { model.setWidths(idle: nil, done: $0) })
        }
        .lineLimit(1)
        .offset(y: -row * model.roll)
        .frame(width: model.width > 0 ? model.width : nil, height: row, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
    }

    private func widthReader(_ set: @escaping (Double) -> Void) -> some View {
        GeometryReader { g in
            Color.clear
                .onAppear { set(g.size.width) }
                .onChange(of: g.size.width) { _, w in set(w) }
        }
    }
}

@Observable
final class CopyButtonModel {
    private(set) var roll: Double = 0
    private(set) var icon: Double = 0
    private(set) var width: Double = 0
    private(set) var isOn = false

    @ObservationIgnored private var r = MotionSpring(0, 260, 20)    // word roll
    @ObservationIgnored private var i = MotionSpring(0, 420, 18)    // icon swap
    @ObservationIgnored private var rw = MotionSpring(0, 300, 24)   // clip width
    @ObservationIgnored private var idleWidth: Double = 0
    @ObservationIgnored private var doneWidth: Double = 0
    @ObservationIgnored private var timer: Int?
    @ObservationIgnored private let clock = MotionClock()

    /// How long "Copied" holds before rolling back.
    private static let hold: Double = 1.8

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func setWidths(idle: Double?, done: Double?) {
        if let idle { idleWidth = idle }
        if let done { doneWidth = done }
        let target = isOn ? doneWidth : idleWidth
        guard target > 0 else { return }
        if width == 0 { rw.snap(target); width = target; return }
        if rw.t != target { rw.t = target; clock.start() }
    }

    func copy() {
        isOn = true
        r.t = 1; i.t = 1; rw.t = doneWidth
        if let timer { clock.cancel(timer) }
        timer = clock.after(Self.hold) { [weak self] in
            guard let self else { return }
            self.timer = nil
            self.isOn = false
            self.r.t = 0; self.i.t = 0; self.rw.t = self.idleWidth
        }
        clock.start()
    }

    func stop() {
        clock.cancelAllTimers(); timer = nil
        isOn = false
        r.snap(0); i.snap(0); rw.snap(idleWidth)
        roll = 0; icon = 0; if idleWidth > 0 { width = idleWidth }
        clock.stop()
    }

    private func frame(_ dt: Double) {
        r.step(dt); i.step(dt); rw.step(dt)
    }

    private func render() {
        let nextIcon = motionClamp(i.x, -0.2, 1.2), nextWidth = max(0, rw.x)
        if roll != r.x { roll = r.x }
        if icon != nextIcon { icon = nextIcon }
        if width != nextWidth { width = nextWidth }
        if clock.isRunning, timer == nil, r.isSettled, i.isSettled, rw.isSettled(within: MotionSpring.points) {
            r.snap(r.t); i.snap(i.t); rw.snap(rw.t)
            roll = r.x; icon = i.x; width = rw.x
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Copy Button") {
    VStack(spacing: Spacing.xl) {
        HStack {
            Text("3 of 8 bought").font(.footnote).foregroundStyle(Color.labelSecondary)
            Spacer()
            CopyButton(title: "Copy list", doneTitle: "Copied", announcement: "List copied") {
                "• Milk × 2 — Rimi\n• Rye bread — Maxima"
            }
        }
        CopyButton(title: "Copy list") { "" }.disabled(true)
    }
    .padding(Spacing.lg)
    .background(Color.surface)
}
