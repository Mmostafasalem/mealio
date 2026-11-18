import SwiftUI

/// Tap once, speak, done: the sheet that listens, shows what it understood and
/// saves it. Opened from the "+" quick actions.
struct VoiceCommandSheet: View {
    let close: () -> Void
    let navigate: (VoiceNavigation) -> Void

    @State private var model = VoiceCommandModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(reduceMotion ? .reducedFade : .snappyValue, value: model.phase)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }.accessibilityIdentifier("voice.done")
                }
            }
        }
        // On iPad a medium detent makes a short card that hides the review list; use the full form sheet there.
        .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        // Solid, so the screen behind doesn't show through the review card.
        .presentationBackground(Color.surfaceGrouped)
        .onAppear {
            model.onNavigate = navigate
            model.onFinished = close
            model.start()
        }
        .onDisappear { model.cancel() }
        .sensoryFeedback(.success, trigger: model.phase == .done)
        .sensoryFeedback(.selection, trigger: model.phase == .listening)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .starting, .preparing, .listening, .thinking:
            listening
        case .review:
            review
        case .done:
            done
        case .failed(let message):
            failed(message)
        }
    }

    // MARK: Listening

    private var statusText: String {
        switch model.phase {
        case .starting: return "Starting…"
        case .preparing: return "Getting dictation ready…"
        case .listening: return model.transcript.isEmpty && !model.hasSpoken ? "Listening…" : "Listening… tap when you're done"
        case .thinking: return "Working it out…"
        default: return ""
        }
    }

    private var listening: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)
            Button { model.stopListening() } label: {
                ZStack {
                    // The halo breathes with the voice.
                    Circle()
                        .fill(Color.progress.opacity(0.18))
                        .frame(width: 132, height: 132)
                        .scaleEffect(reduceMotion ? 1 : 0.8 + 0.45 * model.level)
                    Circle()
                        .fill(Color.progress)
                        .frame(width: 84, height: 84)
                    if model.phase == .thinking || model.phase == .starting || model.phase == .preparing {
                        ProgressView().tint(Color.onAccent)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Color.onAccent)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.level)
                .frame(width: 150, height: 150)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.phase != .listening)
            .accessibilityLabel(model.phase == .listening ? "Stop listening" : statusText)
            .accessibilityIdentifier("voice.microphone")

            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.labelSecondary)

            if model.transcript.isEmpty {
                VStack(spacing: Spacing.xs) {
                    Text("Try saying")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.labelSecondary)
                    ForEach(["\u{201C}Two eggs and toast for breakfast\u{201D}", "\u{201C}Add milk to my cart\u{201D}", "\u{201C}Start a 30 minute cardio workout\u{201D}"], id: \.self) { example in
                        Text(example)
                            .font(.subheadline)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                .multilineTextAlignment(.center)
            } else {
                Text(model.transcript)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice.transcript")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Review

    private var review: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            heard
            helperNote
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    switch model.plan {
                    case .food(let matches, let missing, let slot):
                        foodReview(matches, missing: missing, slot: slot)
                    case .cart(let items, let missing):
                        listReview(title: "Add to your cart", symbol: "cart", names: items.map(\.name), missing: missing)
                    case .checklist(let names):
                        listReview(title: "Add to your checklist", symbol: "checklist", names: names, missing: [])
                    default:
                        EmptyView()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Touching the card means the person is deciding: stop the countdown.
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in model.holdCountdown() })

            VStack(spacing: Spacing.sm) {
                PrimaryButton(title: confirmTitle, systemImage: "checkmark") { model.confirm() }
                    .disabled(!model.canConfirm)
                    .opacity(model.canConfirm ? 1 : 0.5)
                    .accessibilityIdentifier("voice.confirm")
                Button("Try again") { model.start() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("voice.retry")
            }
        }
        .padding(.top, Spacing.sm)
    }

    /// What was heard, small, above what it was taken to mean.
    private var heard: some View {
        Label {
            Text("\u{201C}\(model.transcript)\u{201D}")
                .font(.footnote)
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "waveform").foregroundStyle(Color.labelSecondary)
        }
        .accessibilityLabel("You said: \(model.transcript)")
    }

    /// Says so when a model, not the rules, worked the phrase out.
    @ViewBuilder private var helperNote: some View {
        if let helper = model.helper {
            Label(helper == .appleIntelligence ? "Understood with Apple Intelligence, on this iPhone" : "Understood with your AI key",
                  systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.labelSecondary)
                .accessibilityIdentifier("voice.helper")
        }
    }

    private var confirmTitle: String {
        let action: String
        switch model.plan {
        case .food(let matches, _, _):
            let kcal = matches.reduce(0) { $0 + $1.kcal }
            action = matches.count == 1 ? "Log · \(kcal) kcal" : "Log \(matches.count) foods · \(kcal) kcal"
        case .cart(let items, _): action = items.count == 1 ? "Add to cart" : "Add \(items.count) to cart"
        case .checklist(let names): action = names.count == 1 ? "Add to checklist" : "Add \(names.count) to checklist"
        default: action = "Confirm"
        }
        if let seconds = model.countdown { return "\(action) (\(seconds))" }
        return action
    }

    private func foodReview(_ matches: [VoiceFoodMatch], missing: [String], slot: MealSlot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Log to")
                    .font(.headline)
                Menu {
                    Picker("Meal", selection: Binding(get: { slot }, set: { model.setSlot($0) })) {
                        ForEach(MealSlot.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(slot.title.lowercased()).font(.headline)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Color.labelPrimary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Meal")
                .accessibilityValue(slot.title)
                .accessibilityIdentifier("voice.slot")
                Spacer(minLength: 0)
            }
            ForEach(matches) { match in
                foodRow(match)
            }
            missingNote(missing)
        }
    }

    private func foodRow(_ match: VoiceFoodMatch) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                // Tap the name to pick another food the words could mean.
                Menu {
                    Picker("Food", selection: Binding(get: { match.food.id }, set: { id in
                        if let food = match.alternatives.first(where: { $0.id == id }) { model.choose(food, for: match) }
                    })) {
                        ForEach(match.alternatives) { Text($0.name).tag($0.id) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(match.food.name)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if match.alternatives.count > 1 {
                            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                        }
                    }
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .disabled(match.alternatives.count <= 1)
                .accessibilityLabel(match.food.name)
                .accessibilityHint(match.alternatives.count > 1 ? "Choose a different food" : "")
                Button { model.remove(match) } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.labelSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(match.food.name)")
            }
            HStack(spacing: Spacing.sm) {
                stepButton("minus", name: "Less", disabled: match.amount <= match.food.minimumAmount) { model.nudge(match, up: false) }
                Text(LogFoodSheet.amountText(match.amount, basis: match.food.basis))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .frame(minWidth: 76)
                    .contentTransition(.numericText())
                stepButton("plus", name: "More", disabled: match.amount >= match.food.maximumAmount) { model.nudge(match, up: true) }
                if match.estimated {
                    // Short and on one line: the full word broke in two beside a long amount.
                    Text("est.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.surfaceSecondary, in: Capsule())
                        .accessibilityLabel("Estimated amount")
                }
                Spacer(minLength: 0)
                Text("\(match.kcal) kcal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.food")
    }

    private func stepButton(_ symbol: String, name: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 32, height: 32)
                .background(Color.surfaceSecondary, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(name)
    }

    private func listReview(title: String, symbol: String, names: [String], missing: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Color.labelPrimary)
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .background(Color.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            missingNote(missing)
        }
    }

    @ViewBuilder private func missingNote(_ missing: [String]) -> some View {
        if !missing.isEmpty {
            Label("Couldn't find: " + missing.joined(separator: ", "), systemImage: "questionmark.circle")
                .font(.footnote)
                .foregroundStyle(Color.brandDanger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voice.missing")
        }
    }

    // MARK: Done and failed

    private var done: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: model.canUndo ? "checkmark.circle.fill" : "text.bubble.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color.progress)
                .accessibilityHidden(true)
            Text(model.message)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voice.result")
            if model.canUndo {
                Button("Undo") { model.undoLast() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(minWidth: 88, minHeight: 44)
                    .accessibilityIdentifier("voice.undo")
            }
            Button { model.start() } label: {
                Label("Say another", systemImage: "mic.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("voice.again")
            Spacer(minLength: 0)
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .accessibilityHidden(true)
            if !model.transcript.isEmpty {
                Text("\u{201C}\(model.transcript)\u{201D}")
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.labelPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voice.error")
            if model.permissionDenied {
                PrimaryButton(title: "Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .frame(maxWidth: 260)
            } else {
                PrimaryButton(title: "Try again", systemImage: "mic.fill") { model.start() }
                    .frame(maxWidth: 260)
                    .accessibilityIdentifier("voice.retry")
            }
            Spacer(minLength: 0)
        }
    }
}
