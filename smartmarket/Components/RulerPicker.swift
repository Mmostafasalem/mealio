import SwiftUI

// MARK: - Ruler Picker
//
// A tick ruler you drag under a fixed marker, used wherever the app asks for a
// number (weight, height, age, portion, budget). The ruler moves with the
// finger, keeps going with the flick, and always comes to rest on a tick.
// Values live on whole ticks (`step`), so there's no floating-point drift.

struct RulerPicker: View {

    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var axis: Axis = .horizontal
    /// A labelled tick every this many ticks.
    var majorEvery: Int = 10
    /// A medium tick every this many ticks.
    var midEvery: Int = 5
    /// Points between two ticks.
    var spacing: CGFloat = 10
    /// Where the marker sits along the ruler, 0…1 (0.5 is the centre).
    var anchor: CGFloat = 0.5
    var tint: Color = .progress
    var showsMarker: Bool = true
    /// Text under a labelled tick.
    var tickLabel: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
    /// VoiceOver name and spoken value.
    var accessibilityName: String = "Value"
    var spokenValue: ((Double) -> String)? = nil

    @State private var position: Double = 0
    @State private var dragStart: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lowTick: Int { Int((range.lowerBound / step).rounded(.up)) }
    private var highTick: Int { Int((range.upperBound / step).rounded(.down)) }
    private var valueTick: Int { clampTick(Int((value / step).rounded())) }

    private func clampTick(_ tick: Int) -> Int { min(max(tick, lowTick), highTick) }
    private func clampPosition(_ p: Double) -> Double { min(max(p, Double(lowTick)), Double(highTick)) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RulerTicks(position: position, lowTick: lowTick, highTick: highTick, step: step,
                           axis: axis, majorEvery: majorEvery, midEvery: midEvery, spacing: spacing,
                           anchor: anchor, tint: tint, tickLabel: tickLabel)
                if showsMarker { marker(in: geo.size) }
            }
            .overlay {
                AxisPan(axis: axis, onChanged: dragChanged, onEnded: dragEnded)
            }
        }
        .frame(minWidth: axis == .vertical ? 96 : nil, minHeight: axis == .horizontal ? 96 : nil)
        .onAppear { position = Double(valueTick) }
        .onChange(of: valueTick) { _, tick in
            // An outside change (unit switch, stepper, preset) glides the ruler there.
            guard dragStart == nil, Int(position.rounded()) != tick else { return }
            withAnimation(reduceMotion ? .reducedFade : .smoothCard) { position = Double(tick) }
        }
        .sensoryFeedback(.selection, trigger: valueTick)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(spokenValue?(value) ?? tickLabel(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = Double(clampTick(valueTick + 1)) * step
            case .decrement: value = Double(clampTick(valueTick - 1)) * step
            @unknown default: break
            }
        }
    }

    // The ruler follows the finger. Horizontal rulers grow to the right,
    // vertical ones grow upward. `distance` is points along the ruler's axis.
    private func dragChanged(_ distance: CGFloat) {
        let start = dragStart ?? position
        if dragStart == nil { dragStart = start }
        position = clampPosition(start + ticks(for: distance))
        let tick = clampTick(Int(position.rounded()))
        if tick != valueTick { value = Double(tick) * step }
    }

    private func dragEnded(_ projectedDistance: CGFloat) {
        let start = dragStart ?? position
        dragStart = nil
        let target = clampTick(Int((start + ticks(for: projectedDistance)).rounded()))
        withAnimation(reduceMotion ? .reducedFade : .spring(response: 0.45, dampingFraction: 0.9)) {
            position = Double(target)
        }
        value = Double(target) * step
    }

    private func ticks(for distance: CGFloat) -> Double {
        axis == .horizontal ? Double(-distance / spacing) : Double(distance / spacing)
    }

    @ViewBuilder
    private func marker(in size: CGSize) -> some View {
        if axis == .horizontal {
            VStack(spacing: 0) {
                Circle().frame(width: 9, height: 9)
                Rectangle().frame(width: 2, height: max(0, size.height - 30))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.labelPrimary)
            .position(x: size.width * anchor, y: size.height / 2)
            .allowsHitTesting(false)
        } else {
            Rectangle()
                .fill(Color.labelPrimary)
                .frame(width: size.width, height: 2)
                .position(x: size.width / 2, y: size.height * anchor)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Direction-locked pan
//
// A SwiftUI DragGesture would also claim vertical drags, which stops a sheet or
// list from scrolling when the finger starts on a horizontal ruler. This pan
// only begins when the drag runs along the ruler; anything else falls through
// to whatever scrolls behind it.

private struct AxisPan: UIViewRepresentable {
    let axis: Axis
    let onChanged: (CGFloat) -> Void
    /// Receives where the drag would coast to, given its release speed.
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: AxisPan
        init(_ parent: AxisPan) { self.parent = parent }

        private func along(_ point: CGPoint) -> CGFloat { parent.axis == .horizontal ? point.x : point.y }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return parent.axis == .horizontal ? abs(v.x) > abs(v.y) : abs(v.y) > abs(v.x)
        }

        @objc func handle(_ pan: UIPanGestureRecognizer) {
            let distance = along(pan.translation(in: pan.view))
            switch pan.state {
            case .began, .changed:
                parent.onChanged(distance)
            case .ended:
                // Roughly a quarter second of coasting at the release speed.
                parent.onEnded(distance + along(pan.velocity(in: pan.view)) * 0.25)
            case .cancelled, .failed:
                parent.onEnded(distance)
            default:
                break
            }
        }
    }
}

// MARK: - Ticks

/// Draws only the ticks on screen. `position` is animatable, so a flick's
/// spring redraws the ruler every frame without touching the bound value.
private struct RulerTicks: View, Animatable {
    var position: Double
    let lowTick: Int
    let highTick: Int
    let step: Double
    let axis: Axis
    let majorEvery: Int
    let midEvery: Int
    let spacing: CGFloat
    let anchor: CGFloat
    let tint: Color
    let tickLabel: (Double) -> String

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { context, size in
            if axis == .horizontal { drawHorizontal(&context, size) } else { drawVertical(&context, size) }
        }
        .accessibilityHidden(true)
    }

    private func drawHorizontal(_ context: inout GraphicsContext, _ size: CGSize) {
        let origin = size.width * anchor
        let base = size.height - 24                 // ticks stand on this line; labels sit below
        let tall = min(base - 6, 64)
        // Soft tint over everything above the current value, as on a tape measure.
        let band = CGRect(x: origin, y: base - tall * 0.7, width: max(0, size.width - origin), height: tall * 0.7)
        context.fill(Path(band), with: .linearGradient(
            Gradient(colors: [tint.opacity(0.05), tint.opacity(0.28)]),
            startPoint: CGPoint(x: band.minX, y: 0), endPoint: CGPoint(x: band.maxX, y: 0)))

        let first = max(lowTick, Int((position - Double(origin / spacing)).rounded(.down)) - 1)
        let last = min(highTick, Int((position + Double((size.width - origin) / spacing)).rounded(.up)) + 1)
        guard first <= last else { return }
        for tick in first...last {
            let x = origin + CGFloat(Double(tick) - position) * spacing
            let major = tick % majorEvery == 0
            let mid = tick % midEvery == 0
            let height = major ? tall : (mid ? tall * 0.72 : tall * 0.55)
            var line = Path()
            line.move(to: CGPoint(x: x, y: base))
            line.addLine(to: CGPoint(x: x, y: base - height))
            context.stroke(line, with: .color(major ? tint : Color.labelTertiary.opacity(mid ? 0.6 : 0.35)),
                           lineWidth: major ? 1.5 : 1)
            if major {
                context.draw(Text(tickLabel(Double(tick) * step)).font(.footnote).foregroundStyle(Color.labelSecondary),
                             at: CGPoint(x: x, y: base + 14))
            }
        }
    }

    private func drawVertical(_ context: inout GraphicsContext, _ size: CGSize) {
        let origin = size.height * anchor
        let long = min(size.width - 44, 72)
        // Tint below the marker: the height already "filled in".
        let band = CGRect(x: size.width - long * 0.7, y: origin, width: long * 0.7, height: max(0, size.height - origin))
        context.fill(Path(band), with: .linearGradient(
            Gradient(colors: [tint.opacity(0.28), tint.opacity(0.05)]),
            startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))

        // Larger values are drawn higher up.
        let first = max(lowTick, Int((position - Double((size.height - origin) / spacing)).rounded(.down)) - 1)
        let last = min(highTick, Int((position + Double(origin / spacing)).rounded(.up)) + 1)
        guard first <= last else { return }
        for tick in first...last {
            let y = origin - CGFloat(Double(tick) - position) * spacing
            let major = tick % majorEvery == 0
            let mid = tick % midEvery == 0
            let length = major ? long : (mid ? long * 0.72 : long * 0.55)
            var line = Path()
            line.move(to: CGPoint(x: size.width, y: y))
            line.addLine(to: CGPoint(x: size.width - length, y: y))
            context.stroke(line, with: .color(major ? tint : Color.labelTertiary.opacity(mid ? 0.6 : 0.35)),
                           lineWidth: major ? 1.5 : 1)
            // A label passing under the marker line would be struck through; fade it there.
            if major {
                context.opacity = min(1, max(0, (abs(y - origin) - 6) / 10))
                defer { context.opacity = 1 }
                context.draw(Text(tickLabel(Double(tick) * step)).font(.footnote).foregroundStyle(Color.labelSecondary),
                             at: CGPoint(x: size.width - long - 8, y: y), anchor: .trailing)
            }
        }
    }
}

// MARK: - Measurement units
//
// Body stats are always stored in kg and cm. These only change how they are
// shown and picked; the choice is remembered across the app.

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    var label: String { self == .kg ? "Kg" : "Lbs" }
    var suffix: String { self == .kg ? "kg" : "lbs" }
    static let kgPerPound = 0.45359237
}

enum HeightUnit: String, CaseIterable, Identifiable {
    case cm, ft
    var id: String { rawValue }
    var label: String { self == .cm ? "Cm" : "Ft" }
    static let cmPerInch = 2.54

    /// "5′ 11″" from a whole number of inches.
    static func feetAndInches(_ inches: Double) -> String {
        let total = Int(inches.rounded())
        return "\(total / 12)′ \(total % 12)″"
    }
}

/// Weight ruler bound to kilograms, shown in the chosen unit.
struct WeightRuler: View {
    @Binding var kilograms: Double
    let unit: WeightUnit
    var range: ClosedRange<Double> = 40...150

    private var pounds: Binding<Double> {
        Binding(
            get: { (kilograms / WeightUnit.kgPerPound).rounded() },
            set: { kilograms = min(max($0 * WeightUnit.kgPerPound, range.lowerBound), range.upperBound) }
        )
    }

    var body: some View {
        Group {
            if unit == .kg {
                RulerPicker(value: $kilograms, range: range, step: 0.5, majorEvery: 10, midEvery: 2,
                            accessibilityName: "Weight", spokenValue: { _ in Self.text(kilograms, unit) })
            } else {
                RulerPicker(value: pounds,
                            range: (range.lowerBound / WeightUnit.kgPerPound)...(range.upperBound / WeightUnit.kgPerPound),
                            step: 1, majorEvery: 10, midEvery: 5,
                            accessibilityName: "Weight", spokenValue: { _ in Self.text(kilograms, unit) })
            }
        }
        .id(unit)
    }

    static func number(_ kilograms: Double, _ unit: WeightUnit) -> String {
        unit == .kg ? String(format: "%.1f", kilograms)
                    : String(format: "%.0f", (kilograms / WeightUnit.kgPerPound).rounded())
    }

    static func text(_ kilograms: Double, _ unit: WeightUnit) -> String {
        "\(number(kilograms, unit)) \(unit.suffix)"
    }
}

/// Height ruler bound to centimetres, shown in the chosen unit.
struct HeightRuler: View {
    @Binding var centimetres: Double
    let unit: HeightUnit
    var axis: Axis = .horizontal
    var anchor: CGFloat = 0.5
    var showsMarker: Bool = true
    var range: ClosedRange<Double> = 140...220

    private var inches: Binding<Double> {
        Binding(
            get: { (centimetres / HeightUnit.cmPerInch).rounded() },
            set: { centimetres = min(max(($0 * HeightUnit.cmPerInch).rounded(), range.lowerBound), range.upperBound) }
        )
    }

    var body: some View {
        Group {
            if unit == .cm {
                RulerPicker(value: $centimetres, range: range, step: 1, axis: axis, majorEvery: 10, midEvery: 5,
                            anchor: anchor, showsMarker: showsMarker,
                            accessibilityName: "Height", spokenValue: { _ in Self.text(centimetres, unit) })
            } else {
                RulerPicker(value: inches,
                            range: (range.lowerBound / HeightUnit.cmPerInch)...(range.upperBound / HeightUnit.cmPerInch),
                            step: 1, axis: axis, majorEvery: 12, midEvery: 6, spacing: 22,
                            anchor: anchor, showsMarker: showsMarker,
                            tickLabel: { "\(Int($0) / 12)′" },
                            accessibilityName: "Height", spokenValue: { _ in Self.text(centimetres, unit) })
            }
        }
        .id(unit)
    }

    static func text(_ centimetres: Double, _ unit: HeightUnit) -> String {
        unit == .cm ? String(format: "%.0f cm", centimetres)
                    : HeightUnit.feetAndInches(centimetres / HeightUnit.cmPerInch)
    }
}

/// Small two-option pill used to switch units.
struct UnitToggle<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String
    var accessibilityName: String = "Unit"

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? Color.onAccent : Color.labelSecondary)
                        .frame(minWidth: 64, minHeight: 40)
                        .background(on ? Color.dullPink : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
        .animation(.snappyValue, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

#Preview {
    struct Demo: View {
        @State private var kg = 70.0
        @State private var cm = 175.0
        @State private var unit = WeightUnit.kg
        var body: some View {
            VStack(spacing: 24) {
                UnitToggle(selection: $unit, options: WeightUnit.allCases, label: \.label)
                Text(WeightRuler.text(kg, unit)).font(.largeTitle.bold()).monospacedDigit()
                WeightRuler(kilograms: $kg, unit: unit).frame(height: 110)
                HeightRuler(centimetres: $cm, unit: .cm, axis: .vertical).frame(width: 130, height: 300)
            }
            .padding()
        }
    }
    return Demo()
}
