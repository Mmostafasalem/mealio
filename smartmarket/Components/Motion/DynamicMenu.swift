import SwiftUI

// MARK: - Dynamic Menu
//
// Port of designbookmark.com/motion "Dynamic Menu" (dynamic-menu/menu.js).
// Width (320, 26) and height (240, 22) have their own springs, the height a
// little softer, so the panel widens first and lands after. The toggle's two
// lines (8 apart) meet in the middle and turn ±45° into a cross on a third
// spring (380, 24). Items rise 18 pt and fade in on (260, 22) with a short
// stagger (0.08 + 0.05·i) and drop away in reverse (0.03 apart) on close.
//
// The toggle lives where the actions used to be (a toolbar slot) and the panel
// is drawn over the content under it, sharing one `DynamicMenuModel`:
//
//     @State private var menu = DynamicMenuModel()
//     .toolbar { ToolbarItem { DynamicMenuToggle(model: menu, items: items) } }
//     .overlay(alignment: .topTrailing) { DynamicMenuPanel(model: menu, items: items) }
//
// VoiceOver: the toggle is a native `Menu` (accessibilityRepresentation), and
// while VoiceOver runs it simply *is* a native Menu. Reduce Motion: the panel
// appears at full size and fades; items fade without rising.

/// One action in the menu.
struct DynamicMenuItem: Identifiable {
    enum Kind {
        case action(() -> Void)
        /// Opens the share sheet with this text.
        case share(String)
    }

    let id: String
    let title: String
    let systemImage: String
    var isDisabled = false
    var role: ButtonRole?
    let kind: Kind

    init(_ title: String, systemImage: String, id: String, isDisabled: Bool = false,
         role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.id = id
        self.isDisabled = isDisabled; self.role = role; self.kind = .action(action)
    }

    init(_ title: String, systemImage: String, id: String, isDisabled: Bool = false, share text: String) {
        self.title = title; self.systemImage = systemImage; self.id = id
        self.isDisabled = isDisabled; self.role = nil; self.kind = .share(text)
    }
}

// MARK: - Toggle (two lines that turn into a cross)

struct DynamicMenuToggle: View {
    let model: DynamicMenuModel
    let items: [DynamicMenuItem]
    var label: String = "More actions"
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        if voiceOver {
            nativeMenu
        } else {
            Button { model.set(!model.isOpen, count: items.count) } label: {
                lines
            }
            .buttonStyle(.plain)
            .accessibilityRepresentation { nativeMenu }
        }
    }

    private var lines: some View {
        let x = model.snap.cross
        return ZStack {
            Capsule().frame(width: 18, height: 2)
                .offset(y: -4 * (1 - x))
                .rotationEffect(.degrees(45 * x))
            Capsule().frame(width: 18, height: 2)
                .offset(y: 4 * (1 - x))
                .rotationEffect(.degrees(-45 * x))
        }
        .foregroundStyle(Color.labelPrimary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .transaction { $0.animation = nil }
    }

    private var nativeMenu: some View {
        Menu {
            ForEach(items) { item in
                DynamicMenuItemControl(item: item) {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        } label: {
            Label(label, systemImage: "ellipsis.circle")
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Panel

struct DynamicMenuPanel: View {
    let model: DynamicMenuModel
    let items: [DynamicMenuItem]
    /// Widest the open panel gets (300 in the original, here sized for list actions).
    var maxWidth: CGFloat = 260

    var body: some View {
        let s = model.snap
        ZStack(alignment: .topTrailing) {
            if model.isOpen {
                // tap outside closes
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.set(false, count: items.count) }
                    .accessibilityHidden(true)
            }
            // Always mounted (just transparent when closed), so a share sheet opened
            // from an item keeps its presenting view while the panel closes.
            panel(s)
                .allowsHitTesting(model.isOpen)
                .accessibilityHidden(!model.isOpen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            model.setRoom(min(maxWidth, $0 - 32))
        }
        .transaction { $0.animation = nil }
    }

    private func panel(_ s: DynamicMenuModel.Snapshot) -> some View {
        let radius = 22 - 4 * motionClamp(s.cross, 0, 1)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let p = s.items.indices.contains(i) ? s.items[i] : 0
                DynamicMenuItemControl(item: item, onDone: { model.set(false, count: items.count) }) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: item.systemImage)
                            .font(.body.weight(.medium))
                            .frame(width: 24)
                        Text(item.title)
                            .font(.body.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(item.role == .destructive ? Color.brandDanger : Color.labelPrimary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(item.isDisabled ? 0.4 : 1)
                .opacity(motionClamp(p, 0, 1))
                .offset(y: s.reduced ? 0 : (1 - p) * 18)
                .accessibilityHidden(p < 0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: model.room, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.setContentHeight($0) }
        // the panel is a window onto the content: its springs set the size
        .frame(width: max(0, s.width), height: max(0, s.height), alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
        .elevation(Elevation.high)
        .opacity(s.opacity)
        .padding(.trailing, Spacing.lg)
        .padding(.top, Spacing.xs)
    }
}

/// A menu entry as a real control: a Button, or a ShareLink for `.share`.
private struct DynamicMenuItemControl<Label: View>: View {
    let item: DynamicMenuItem
    var onDone: () -> Void = {}
    @ViewBuilder let label: () -> Label

    var body: some View {
        Group {
            switch item.kind {
            case .action(let action):
                Button(role: item.role) { action(); onDone() } label: { label() }
            case .share(let text):
                ShareLink(item: text) { label() }
                    .simultaneousGesture(TapGesture().onEnded { onDone() })
            }
        }
        .disabled(item.isDisabled)
        .accessibilityIdentifier(item.id)
    }
}

// MARK: - Engine

@MainActor
@Observable
final class DynamicMenuModel {
    struct Snapshot: Equatable {
        var width: Double = 44
        var height: Double = 0
        var cross: Double = 0
        var opacity: Double = 0
        var items: [Double] = []
        var reduced = false
    }

    /// From menu.js.
    static let widthSpring = MotionTokens.Preset(k: 320, c: 26)
    static let heightSpring = MotionTokens.Preset(k: 240, c: 22)
    static let crossSpring = MotionTokens.Preset(k: 380, c: 24)
    static let itemSpring = MotionTokens.Preset(k: 260, c: 22)
    /// Closed panel: the width of the toggle, no height.
    static let closedWidth: Double = 44

    private(set) var isOpen = false
    private(set) var snap = Snapshot()
    private(set) var room: CGFloat = 260

    @ObservationIgnored private var contentHeight: Double = 120
    @ObservationIgnored private var W = MotionSpring(DynamicMenuModel.closedWidth, DynamicMenuModel.widthSpring)
    @ObservationIgnored private var H = MotionSpring(0, DynamicMenuModel.heightSpring)
    @ObservationIgnored private var X = MotionSpring(0, DynamicMenuModel.crossSpring)
    @ObservationIgnored private var O = MotionSpring(0, MotionTokens.fade)
    @ObservationIgnored private var lis: [MotionSpring] = []
    @ObservationIgnored private var timers: [Int] = []
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func setRoom(_ w: CGFloat) {
        let w = max(160, w)
        guard abs(w - room) > 0.5 else { return }
        room = w
        if isOpen { W.t = Double(w); clock.start() }
    }

    func setContentHeight(_ h: Double) {
        guard h > 0, abs(h - contentHeight) > 0.5 else { return }
        contentHeight = h
        if isOpen { H.t = h; clock.start() }
    }

    func set(_ open: Bool, count: Int) {
        if lis.count != count { lis = (0..<count).map { _ in MotionSpring(0, DynamicMenuModel.itemSpring) } }
        isOpen = open
        timers.forEach(clock.cancel)
        timers.removeAll()
        W.t = open ? Double(room) : Self.closedWidth
        H.t = open ? contentHeight : 0
        X.t = open ? 1 : 0
        O.t = open ? 1 : 0
        if MotionSettings.reduceMotion {
            // no growing panel, no rising items: the panel fades at its full size
            W.snap(Double(room)); H.snap(contentHeight)
            for i in lis.indices { lis[i].t = open ? 1 : 0 }
        } else {
            let n = lis.count
            for i in lis.indices {
                let delay = open ? 0.08 + Double(i) * 0.05 : Double(n - 1 - i) * 0.03
                var token = 0
                token = clock.after(delay) { [weak self] in
                    guard let self else { return }
                    self.lis[i].t = self.isOpen ? 1 : 0
                    self.timers.removeAll { $0 == token }
                }
                timers.append(token)
            }
        }
        clock.start()
        render()
    }

    private func frame(_ dt: Double) {
        W.step(dt); H.step(dt); X.step(dt); O.step(dt)
        for i in lis.indices { lis[i].step(dt) }
    }

    private func render() {
        let settled = W.isSettled(within: MotionSpring.points) && H.isSettled(within: MotionSpring.points)
            && X.isSettled && O.isSettled && lis.allSatisfy(\.isSettled)
        if clock.isRunning, timers.isEmpty, settled {
            clock.stop()
            W.snap(W.t); H.snap(H.t); X.snap(X.t); O.snap(O.t)
            for i in lis.indices { lis[i].snap(lis[i].t) }
        }
        let reduce = MotionSettings.reduceMotion
        var s = Snapshot()
        s.reduced = reduce
        s.width = W.x
        s.height = H.x
        s.cross = motionClamp(X.x, -0.1, 1.1)
        s.items = lis.map(\.x)
        // closed: the panel is gone once it has shrunk away (or faded, with Reduce Motion)
        s.opacity = reduce ? motionClamp(O.x, 0, 1) : motionClamp(H.x / 24, 0, 1)
        if s != snap { snap = s }
    }
}

// MARK: - Preview

#Preview("Dynamic Menu") {
    @Previewable @State var menu = DynamicMenuModel()
    let items = [
        DynamicMenuItem("Share list", systemImage: "square.and.arrow.up", id: "groceries.share", share: "• Milk — Rimi"),
        DynamicMenuItem("Clear bought", systemImage: "checkmark.circle", id: "groceries.clearBought") {},
    ]
    NavigationStack {
        List { Text("Kefyras 3.5%"); Text("Grikiai") }
            .navigationTitle("Groceries")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { DynamicMenuToggle(model: menu, items: items) }
            }
            .overlay(alignment: .topTrailing) { DynamicMenuPanel(model: menu, items: items) }
    }
}
