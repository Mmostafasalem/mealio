import SwiftUI
import UIKit

// MARK: - Springy text field
//
// Port of designbookmark.com/motion "Springy Input" (springy-input/input.js).
// The real UITextField stays in place and does everything a field does (typing,
// paste, selection, autocorrection settings, VoiceOver, UI tests), but its text is
// transparent. A mirror layer draws one glyph per character on top: new characters
// land with a small bounce (a paste becomes a wave), deleted ones float away from
// where they were, and a custom caret springs between positions and stretches with
// its speed (--input-caret 700 32).
//
// Positions come from the field's own layout (`firstRect(for:)` per character and
// the real caret rect), so kerning, scrolling and Dynamic Type stay exact. Whenever
// the mirror can't be exact it steps aside and the plain field shows: while marked
// text is being composed (IME, dictation), while the field isn't editing, or if a
// measurement fails. Typing never depends on the mirror.
//
// Optional ghost text (see `GhostSuggestionField`) is drawn right after the text in
// labelTertiary; when it is accepted the inserted letters turn ink with a small hop,
// left to right, instead of dropping in.
//
// Reduce Motion: letters appear and disappear in place (no bounce, no float), the
// caret moves without overshoot (the engine damps it critically).

enum SpringyFieldMotion {
    /// Caret travel, from tokens.css --input-caret.
    static let caret = MotionTokens.Preset(k: 700, c: 32)
    /// A typed letter landing. The original is a 0.5 s keyframe with one overshoot;
    /// this spring lands the same way with a calmer bounce, since search is typed often.
    static let land = MotionTokens.Preset(k: 420, c: 25)
    /// Seconds between letters of a paste (the original: 18 ms, at most 30 steps).
    static let wave: Double = 0.018
    /// A deleted letter floating away.
    static let leaveDuration: Double = 0.34
    /// Accepted ghost letters: colour, hop and the stagger between them (ghost.js).
    static let ink = MotionTokens.fade
    static let hop = MotionTokens.Preset(k: 520, c: 16)
    static let hopKick: Double = -70
    static let acceptStagger: Double = 0.016
    /// Ghost letters fading in (ghost.js: 300 30, 8 ms apart).
    static let ghostIn = MotionTokens.Preset(k: 300, c: 30)
    static let ghostStagger: Double = 0.008
    /// Caret stays solid this long after a move before it blinks.
    static let idleAfter: Double = 0.55
}

struct SpringyTextField: View {
    let placeholder: String
    @Binding var text: String
    /// Text to draw dimmed after the typed text (the rest of a suggestion), or nil.
    var ghost: String? = nil
    var accessibilityIdentifier: String? = nil
    var returnKey: UIReturnKeyType = .default
    var autocorrection: UITextAutocorrectionType = .no
    var autocapitalization: UITextAutocapitalizationType = .sentences
    var keyboardType: UIKeyboardType = .default
    /// Shared state when a wrapper needs to read it (ghost visibility) or drive an accept.
    var model: SpringyFieldModel? = nil
    /// Called by the Return key. Return true to end editing (hide the keyboard).
    var onReturn: () -> Bool = { true }

    @State private var ownModel = SpringyFieldModel()
    @State private var caretOn = true
    private var m: SpringyFieldModel { model ?? ownModel }

    var body: some View {
        let m = m
        SpringyFieldRepresentable(
            placeholder: placeholder,
            text: $text,
            model: m,
            accessibilityIdentifier: accessibilityIdentifier,
            returnKey: returnKey,
            autocorrection: autocorrection,
            autocapitalization: autocapitalization,
            keyboardType: keyboardType,
            onReturn: onReturn
        )
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                SpringyMirror(model: m, frame: m.frame)
                if m.caretVisible {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.labelPrimary)
                        .frame(width: m.caretWidth, height: m.caretRect.height)
                        .offset(x: m.caretX, y: m.caretRect.minY)
                        .opacity(m.caretIdle && !caretOn ? 0 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Clip sideways like the original's overflow box, but leave room above and
            // below for letters landing and floating off.
            .mask(Rectangle().padding(.vertical, -28))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: ghost, initial: true) { _, rest in m.setGhost(rest) }
        .task(id: m.caretIdle && m.caretVisible) {
            // A plain timer blink, only while the caret rests. Nothing runs otherwise.
            caretOn = true
            guard m.caretIdle && m.caretVisible else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                caretOn.toggle()
            }
        }
        .onDisappear { m.stop() }
    }
}

// MARK: - Mirror

private struct SpringyMirror: View {
    let model: SpringyFieldModel
    /// Changes every rendered frame so the canvas redraws.
    let frame: Int

    var body: some View {
        Canvas { ctx, _ in
            guard model.mirrorActive else { return }
            let font = Font(model.font as CTFont)
            let uiFont = model.font
            let ink = Color.labelPrimary
            let dim = Color.labelTertiary
            let reduce = MotionSettings.reduceMotion

            func draw(_ ch: String, in rect: CGRect, dy: Double, rot: Double, scale: Double,
                      opacity: Double, blur: Double, colorMix: Double) {
                guard opacity > 0.004, rect.width.isFinite else { return }
                var c = ctx
                // Pivot at 50% / 80% like the original's transform-origin.
                let pivot = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.8)
                // Centre the font's line box in the rect so baselines match the field.
                let baseline = rect.midY + (uiFont.ascender + uiFont.descender) / 2
                c.translateBy(x: pivot.x, y: pivot.y + dy)
                if rot != 0 { c.rotate(by: .degrees(rot)) }
                if scale != 1 { c.scaleBy(x: scale, y: scale) }
                if blur > 0.05 { c.addFilter(.blur(radius: blur)) }
                func place(_ color: Color, _ alpha: Double) {
                    guard alpha > 0.004 else { return }
                    let r = c.resolve(Text(ch).font(font).foregroundStyle(color))
                    let size = r.measure(in: CGSize(width: 400, height: 200))
                    let tb = r.firstBaseline(in: size)
                    var cc = c
                    cc.opacity = opacity * alpha
                    cc.draw(r, in: CGRect(x: -size.width / 2, y: baseline - tb - pivot.y,
                                          width: size.width, height: size.height))
                }
                place(dim, 1 - colorMix)
                place(ink, colorMix)
            }

            for g in model.glyphs {
                let p = g.enter.x
                let q = reduce ? 0 : 1 - p
                draw(g.ch, in: g.rect,
                     dy: 14 * q + g.hop.x,
                     rot: -16 * q,
                     scale: reduce ? 1 : 0.5 + 0.5 * p,
                     opacity: motionClamp(p * 1.6, 0, 1),
                     blur: max(0, 3 * q),
                     colorMix: motionClamp(g.ink.x, 0, 1))
            }
            for g in model.leaving {
                // cubic-bezier(.5, 0, .75, 0): an ease-in, close to t^2.4.
                let e = pow(motionClamp(g.out / SpringyFieldMotion.leaveDuration, 0, 1), 2.4)
                draw(g.ch, in: g.rect, dy: -18 * e, rot: 20 * e, scale: 1 - 0.5 * e,
                     opacity: 1 - e, blur: 3 * e, colorMix: 1)
            }
            if model.ghostShown, let anchor = model.ghostAnchor {
                for l in model.ghostLetters {
                    let rect = CGRect(x: anchor.maxX + l.x, y: anchor.minY, width: l.width, height: anchor.height)
                    draw(l.ch, in: rect, dy: 0, rot: 0, scale: 1,
                         opacity: motionClamp(l.o.x, 0, 1), blur: 0, colorMix: 0)
                }
            }
        }
    }
}

// MARK: - Model

@MainActor @Observable
final class SpringyFieldModel {

    struct Glyph {
        var ch: String
        var rect: CGRect = .zero
        /// 0 → 1 as the letter lands.
        var enter = MotionSpring(1, SpringyFieldMotion.land)
        /// 0 dim (ghost) → 1 ink.
        var ink = MotionSpring(1, SpringyFieldMotion.ink)
        /// Vertical hop of an accepted ghost letter, in points.
        var hop = MotionSpring(0, SpringyFieldMotion.hop)
        /// Seconds until it starts moving.
        var wait: Double = 0
        var accepting = false
        /// Seconds since it started leaving.
        var out: Double = 0
    }

    struct GhostLetter {
        let ch: String
        let x: CGFloat
        let width: CGFloat
        var o = MotionSpring(0, SpringyFieldMotion.ghostIn)
        var wait: Double
    }

    /// Bumped once per rendered frame.
    private(set) var frame = 0
    /// The mirror draws the text (and the field's own text is transparent).
    private(set) var mirrorActive = false
    private(set) var caretVisible = false
    private(set) var caretX: CGFloat = 0
    private(set) var caretWidth: CGFloat = 2
    private(set) var caretRect: CGRect = .zero
    private(set) var caretIdle = true
    /// The ghost is on screen: editing, caret at the end, nothing selected.
    private(set) var ghostShown = false

    @ObservationIgnored private(set) var glyphs: [Glyph] = []
    @ObservationIgnored private(set) var leaving: [Glyph] = []
    @ObservationIgnored private(set) var ghostLetters: [GhostLetter] = []
    @ObservationIgnored private(set) var font: UIFont = .preferredFont(forTextStyle: .body)

    @ObservationIgnored private var text = ""
    @ObservationIgnored private var ghost: String?
    @ObservationIgnored private var acceptedGhost: String?
    @ObservationIgnored private var caret = MotionSpring(0, SpringyFieldMotion.caret)
    @ObservationIgnored private var caretAtEnd = true
    @ObservationIgnored private var hasSelection = false
    @ObservationIgnored private var editing = false
    @ObservationIgnored private var idleToken: Int?
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.step(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    /// Where the ghost starts: the last letter's rect.
    var ghostAnchor: CGRect? { glyphs.last?.rect }

    /// The next insertion of exactly `rest` at the end is an accepted suggestion:
    /// its letters hop and ink in instead of dropping.
    func prepareAccept(_ rest: String) { acceptedGhost = rest }

    func setGhost(_ rest: String?) {
        let rest = (rest?.isEmpty ?? true) ? nil : rest
        guard rest != ghost else { return }
        ghost = rest
        rebuildGhost(animated: true)
        refreshGhostShown()
        clock.start()
    }

    /// Called by the field after every change of text, selection, focus or layout.
    func update(text newText: String, rects: [CGRect]?, caret caretRect: CGRect?,
                caretAtEnd: Bool, hasSelection: Bool, editing: Bool, font: UIFont) {
        let wasActive = mirrorActive
        let active = rects != nil && caretRect != nil && editing
        let fontChanged = font != self.font
        self.font = font
        self.editing = editing
        self.hasSelection = hasSelection
        self.caretAtEnd = caretAtEnd
        if fontChanged { rebuildGhost(animated: false) }

        let animate = active && wasActive && !MotionSettings.reduceMotion
        var moved = false
        if newText != text {
            diff(to: newText, animate: animate)
            text = newText
            moved = true
            acceptedGhost = nil
        }
        if let rects, rects.count == glyphs.count {
            for i in glyphs.indices { glyphs[i].rect = rects[i] }
        }
        if mirrorActive != active { mirrorActive = active }

        if let caretRect, active {
            self.caretRect = caretRect
            if !wasActive || caret.t == 0 && caret.x == 0 { caret.snap(caretRect.minX) }
            if abs(caret.t - caretRect.minX) > 0.01 { caret.t = caretRect.minX; moved = true }
        }
        let showCaret = active && !hasSelection
        if caretVisible != showCaret { caretVisible = showCaret }
        if moved || !wasActive { markMoved() }
        refreshGhostShown()
        render()
        clock.start()
    }

    func stop() {
        clock.stop()
        clock.cancelAllTimers()
        leaving.removeAll()
        for i in glyphs.indices {
            glyphs[i].enter.snap(1); glyphs[i].ink.snap(1); glyphs[i].hop.snap(0)
            glyphs[i].wait = 0; glyphs[i].accepting = false
        }
        for i in ghostLetters.indices { ghostLetters[i].o.snap(1); ghostLetters[i].wait = 0 }
        caret.snap(caret.t)
        caretIdle = true
        render()
    }

    // MARK: Diff (input.js sync)

    private func diff(to next: String, animate: Bool) {
        let old = glyphs.map(\.ch)
        let new = next.map(String.init)
        var a = 0
        while a < old.count && a < new.count && old[a] == new[a] { a += 1 }
        var b = 0
        while b < old.count - a && b < new.count - a && old[old.count - 1 - b] == new[new.count - 1 - b] { b += 1 }

        // Removed letters float away from where they were.
        let gone = glyphs[a..<(old.count - b)]
        if animate {
            for var g in gone {
                g.out = 0; g.wait = 0
                leaving.append(g)
            }
        }
        glyphs.removeSubrange(a..<(old.count - b))

        // Inserted letters land one after another, or ink in if they were the ghost.
        let inserted = Array(new[a..<(new.count - b)])
        let isAccept = animate && b == 0 && !inserted.isEmpty && inserted.joined() == acceptedGhost
        let fresh: [Glyph] = inserted.enumerated().map { i, ch in
            var g = Glyph(ch: ch)
            if isAccept {
                g.accepting = true
                g.ink.snap(0)
                g.wait = Double(i) * SpringyFieldMotion.acceptStagger
            } else if animate {
                g.enter.snap(0)
                g.wait = Double(min(i, 30)) * SpringyFieldMotion.wave
            }
            // A new letter takes its neighbour's rect until the field reports its own.
            if a > 0, a - 1 < glyphs.count { g.rect = glyphs[a - 1].rect }
            return g
        }
        glyphs.insert(contentsOf: fresh, at: a)
        if isAccept {
            ghostLetters.removeAll()
        }
    }

    // MARK: Ghost

    private func rebuildGhost(animated: Bool) {
        guard let ghost else { ghostLetters.removeAll(); return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var letters: [GhostLetter] = []
        var prefix = ""
        for (i, ch) in ghost.enumerated() {
            let x = (prefix as NSString).size(withAttributes: attrs).width
            prefix.append(ch)
            let w = (prefix as NSString).size(withAttributes: attrs).width - x
            var l = GhostLetter(ch: String(ch), x: x, width: w,
                                wait: animated ? Double(i) * SpringyFieldMotion.ghostStagger : 0)
            if !animated || MotionSettings.reduceMotion { l.o.snap(1); l.wait = 0 }
            letters.append(l)
        }
        ghostLetters = letters
    }

    private func refreshGhostShown() {
        let shown = ghost != nil && mirrorActive && editing && caretAtEnd && !hasSelection && !glyphs.isEmpty
        if ghostShown != shown { ghostShown = shown }
    }

    // MARK: Clock

    private func markMoved() {
        if caretIdle { caretIdle = false }
        if let idleToken { clock.cancel(idleToken) }
        idleToken = clock.after(SpringyFieldMotion.idleAfter) { [weak self] in
            guard let self else { return }
            idleToken = nil
            caretIdle = true
        }
    }

    private func step(_ dt: Double) {
        caret.step(dt)
        for i in glyphs.indices {
            if glyphs[i].wait > 0 {
                glyphs[i].wait -= dt
                if glyphs[i].wait <= 0 { start(&glyphs[i]) }
                continue
            }
            glyphs[i].enter.step(dt)
            glyphs[i].ink.step(dt)
            glyphs[i].hop.step(dt)
        }
        for i in leaving.indices { leaving[i].out += dt }
        leaving.removeAll { $0.out >= SpringyFieldMotion.leaveDuration + 0.02 }
        for i in ghostLetters.indices {
            if ghostLetters[i].wait > 0 {
                ghostLetters[i].wait -= dt
                if ghostLetters[i].wait <= 0 { ghostLetters[i].o.t = 1 }
                continue
            }
            ghostLetters[i].o.step(dt)
        }
    }

    private func start(_ g: inout Glyph) {
        g.wait = 0
        if g.accepting {
            g.ink.t = 1
            if !MotionSettings.reduceMotion { g.hop.v = SpringyFieldMotion.hopKick }
        } else {
            g.enter.t = 1
        }
    }

    private func render() {
        caretX = CGFloat(caret.x)
        // Stretch with speed, trailing behind the direction of travel (input.js).
        let stretch = MotionSettings.reduceMotion ? 0 : min(abs(caret.v) / 80, 7)
        caretWidth = 2 + CGFloat(stretch)
        if caret.v > 0 { caretX -= CGFloat(stretch) }
        frame &+= 1

        let settled = caret.isSettled(within: MotionSpring.points)
            && leaving.isEmpty
            && glyphs.allSatisfy { $0.wait <= 0 && $0.enter.isSettled && $0.ink.isSettled && $0.hop.isSettled(within: MotionSpring.points) }
            && ghostLetters.allSatisfy { $0.wait <= 0 && $0.o.isSettled }
        if settled && idleToken == nil && clock.isRunning {
            caret.snap(caret.t)
            for i in glyphs.indices {
                glyphs[i].enter.snap(1); glyphs[i].ink.snap(1); glyphs[i].hop.snap(0)
                glyphs[i].accepting = false
            }
            for i in ghostLetters.indices { ghostLetters[i].o.snap(1) }
            caretX = CGFloat(caret.x)
            caretWidth = 2
            clock.stop()
        }
    }
}

// MARK: - UIKit field

/// The real text field. Its caret is drawn by the mirror while the mirror is active,
/// so the native one is hidden then; selection handles and highlight stay native.
final class SpringyUITextField: UITextField {
    var mirrorActive = false {
        didSet {
            guard mirrorActive != oldValue else { return }
            textColor = mirrorActive ? .clear : UIColor(Color.labelPrimary)
            setNeedsLayout()
        }
    }
    var onLayout: (() -> Void)?

    override func caretRect(for position: UITextPosition) -> CGRect {
        mirrorActive ? .zero : super.caretRect(for: position)
    }

    func realCaretRect(for position: UITextPosition) -> CGRect { super.caretRect(for: position) }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private struct SpringyFieldRepresentable: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let model: SpringyFieldModel
    let accessibilityIdentifier: String?
    let returnKey: UIReturnKeyType
    let autocorrection: UITextAutocorrectionType
    let autocapitalization: UITextAutocapitalizationType
    let keyboardType: UIKeyboardType
    let onReturn: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SpringyUITextField {
        let tf = SpringyUITextField()
        tf.delegate = context.coordinator
        tf.font = .preferredFont(forTextStyle: .body)
        tf.adjustsFontForContentSizeCategory = true
        tf.textColor = UIColor(Color.labelPrimary)
        tf.tintColor = UIColor(Color.brandPrimary)
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.clearButtonMode = .never
        tf.inlinePredictionType = .no
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        tf.onLayout = { [weak tf, weak coordinator = context.coordinator] in
            guard let tf else { return }
            coordinator?.scheduleMeasure(tf)
        }
        context.coordinator.field = tf
        apply(to: tf)
        tf.text = text
        return tf
    }

    func updateUIView(_ tf: SpringyUITextField, context: Context) {
        context.coordinator.parent = self
        apply(to: tf)
        // Never overwrite text that is being composed.
        if tf.text != text && tf.markedTextRange == nil {
            tf.text = text
            // Measure after this update pass, not during it.
            context.coordinator.scheduleMeasure(tf)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SpringyUITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: uiView.intrinsicContentSize.height)
    }

    private func apply(to tf: SpringyUITextField) {
        if tf.placeholder != placeholder {
            tf.attributedPlaceholder = NSAttributedString(
                string: placeholder, attributes: [.foregroundColor: UIColor(Color.labelTertiary)])
        }
        tf.accessibilityIdentifier = accessibilityIdentifier
        tf.returnKeyType = returnKey
        tf.autocorrectionType = autocorrection
        tf.autocapitalizationType = autocapitalization
        tf.keyboardType = keyboardType
        tf.spellCheckingType = autocorrection == .no ? .no : .default
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SpringyFieldRepresentable
        weak var field: SpringyUITextField?
        private var pending = false

        init(_ parent: SpringyFieldRepresentable) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            let value = tf.text ?? ""
            if parent.text != value { parent.text = value }
            if let tf = tf as? SpringyUITextField { measure(tf); scheduleMeasure(tf) }
        }

        func textFieldDidChangeSelection(_ tf: UITextField) {
            if let tf = tf as? SpringyUITextField { measure(tf) }
        }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            if let tf = tf as? SpringyUITextField { scheduleMeasure(tf) }
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            if let tf = tf as? SpringyUITextField { measure(tf) }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            if parent.onReturn() { tf.resignFirstResponder() }
            return false
        }

        /// Measure again after UIKit has laid the new text out.
        func scheduleMeasure(_ tf: SpringyUITextField) {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self, weak tf] in
                MainActor.assumeIsolated {
                    self?.pending = false
                    if let tf { self?.measure(tf) }
                }
            }
        }

        func measure(_ tf: SpringyUITextField) {
            let text = tf.text ?? ""
            let editing = tf.isFirstResponder
            let font = tf.font ?? .preferredFont(forTextStyle: .body)
            var rects: [CGRect]? = nil
            var caret: CGRect? = nil
            var atEnd = true
            var selection = false
            if editing, tf.markedTextRange == nil, let sel = tf.selectedTextRange {
                selection = !sel.isEmpty
                atEnd = tf.compare(sel.end, to: tf.endOfDocument) == .orderedSame
                let c = tf.realCaretRect(for: sel.end)
                if c.minX.isFinite, c.height > 0 { caret = c }
                rects = Self.rects(of: text, in: tf, lineHeight: c.height)
            }
            parent.model.update(text: text, rects: rects, caret: caret, caretAtEnd: atEnd,
                                hasSelection: selection, editing: editing, font: font)
            tf.mirrorActive = parent.model.mirrorActive
        }

        /// One rect per character from the field's own layout, or nil if any is unusable.
        private static func rects(of text: String, in tf: UITextField, lineHeight: CGFloat) -> [CGRect]? {
            var out: [CGRect] = []
            out.reserveCapacity(text.count)
            var offset = 0
            let bounds = tf.bounds
            for ch in text {
                let n = ch.utf16.count
                guard let s = tf.position(from: tf.beginningOfDocument, offset: offset),
                      let e = tf.position(from: s, offset: n),
                      let range = tf.textRange(from: s, to: e) else { return nil }
                let r = tf.firstRect(for: range)
                guard !r.isNull, !r.isInfinite, r.minX.isFinite, r.height > 0 else { return nil }
                out.append(r)
                offset += n
            }
            // Sanity: the line must sit inside the field, or the mirror steps aside.
            if let first = out.first, abs(first.midY - bounds.midY) > max(lineHeight, bounds.height) { return nil }
            return out
        }
    }
}

// MARK: - Preview

#Preview("Springy text field") {
    @Previewable @State var query = "Oats"
    VStack(spacing: Spacing.lg) {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
            SpringyTextField(placeholder: "Search foods", text: $query, returnKey: .search)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        Text("Tap the field and type: letters land, the caret stretches.")
            .font(.footnote).foregroundStyle(Color.labelSecondary)
    }
    .padding(Spacing.lg)
    .frame(maxHeight: .infinity)
    .background(Color.surfaceGrouped)
}
