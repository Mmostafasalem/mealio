import SwiftUI

// MARK: - Spring Segmented Control
//
// Port of designbookmark.com/motion "Segmented Control" (segmented-control/seg.js).
// The highlight rides one position spring (300, 20); its speed squashes it, wider
// and a touch shorter, so it reads as soft. The optional caption under it swaps
// with a quick blur out and rise in (300, 26). No autoplay: it only moves when
// the selection changes.

/// Equal-width segments with a springy highlight and an optional caption below.
struct SpringSegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String
    var caption: ((T) -> String)? = nil
    /// Spoken name of the whole control.
    var accessibilityName: String = "View"

    @State private var model = SpringSegmentedModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var pad: CGFloat { 4 }

    init(selection: Binding<T>, options: [T], label: @escaping (T) -> String,
         caption: ((T) -> String)? = nil, accessibilityName: String = "View") {
        _selection = selection
        self.options = options
        self.label = label
        self.caption = caption
        self.accessibilityName = accessibilityName
    }

    private var index: Int { options.firstIndex(of: selection) ?? 0 }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            segments
            if let caption, !options.isEmpty {
                captionView(caption(options[min(model.captionIndex, options.count - 1)]))
            }
        }
        .onAppear { model.set(index, animated: false) }
        .onChange(of: index) { _, i in model.set(i, animated: true) }
        .onDisappear { model.stop() }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                let on = i == index
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(on ? Color.surface : Color.labelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .contentShape(Rectangle())
                        .animation(.easeOut(duration: 0.25), value: on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityHint(on ? "" : "Shows \(label(option))")
            }
        }
        .padding(Self.pad)
        .background(alignment: .leading) {
            GeometryReader { geo in
                let n = max(options.count, 1)
                let w = (geo.size.width - Self.pad * 2) / CGFloat(n)
                let sp = reduceMotion ? 0 : motionClamp(abs(model.velocity) * w / 1400, 0, 0.22)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.brandPrimary)
                    .frame(width: max(0, w), height: max(0, geo.size.height - Self.pad * 2))
                    .scaleEffect(x: 1 + sp, y: 1 - sp * 0.5)
                    .offset(x: Self.pad + model.position * w, y: Self.pad)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .sensoryFeedback(.selection, trigger: index)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }

    private func captionView(_ text: String) -> some View {
        let c = model.caption
        let shown = motionClamp(c, 0, 1)
        return Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.labelSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .opacity(shown)
            .offset(y: c < 0 ? -c * 10 : (1 - shown) * -6)
            .blur(radius: (1 - shown) * 4)
    }
}

// MARK: - Engine

@MainActor
@Observable
final class SpringSegmentedModel {
    /// Highlight position in segments (0 = first).
    private(set) var position: Double = 0
    /// Highlight speed in segments per second; the view turns it into squash.
    private(set) var velocity: Double = 0
    /// Caption visibility: 1 shown, 0 gone, below 0 rising in from underneath.
    private(set) var caption: Double = 1
    /// Which option the caption shows right now (it swaps mid-transition).
    private(set) var captionIndex: Int = 0

    @ObservationIgnored private var x = MotionSpring(0, 300, 20)
    @ObservationIgnored private var c = MotionSpring(1, 300, 26)
    @ObservationIgnored private var current: Int?
    @ObservationIgnored private var swap: Int?
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func set(_ i: Int, animated: Bool) {
        guard i != current else { return }
        let first = current == nil
        current = i
        if first || !animated {
            x.snap(Double(i)); c.snap(1); captionIndex = i
            render()
            return
        }
        x.t = Double(i)
        if MotionSettings.reduceMotion {
            // The caption change is decorative: swap it in place.
            captionIndex = i
        } else {
            c.t = 0
            if let swap { clock.cancel(swap) }
            swap = clock.after(0.14) { [weak self] in
                guard let self, let cur = self.current else { return }
                self.swap = nil
                self.captionIndex = cur
                self.c.x = -0.4
                self.c.t = 1
            }
        }
        clock.start()
    }

    func stop() {
        clock.stop()
        if let swap { clock.cancel(swap); self.swap = nil }
        if let current { x.snap(Double(current)); c.snap(1); captionIndex = current }
        render()
    }

    private func frame(_ dt: Double) {
        x.step(dt); c.step(dt)
    }

    private func render() {
        position = x.x
        velocity = x.v
        caption = c.x
        if clock.isRunning, swap == nil, x.isSettled, c.isSettled {
            x.snap(x.t); c.snap(c.t)
            position = x.x; velocity = 0; caption = c.x
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Spring Segmented Control") {
    @Previewable @State var tab = MealPlanTab.today
    VStack {
        SpringSegmentedControl(
            selection: $tab,
            options: MealPlanTab.allCases,
            label: \.displayName,
            caption: { $0 == .today
                ? "Your meals for today, built from your goal and stock."
                : "Seven days of meals within your weekly budget." })
    }
    .padding(24)
    .background(Color.surface)
}
