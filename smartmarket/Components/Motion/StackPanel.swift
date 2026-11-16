import SwiftUI

// MARK: - Stack Panel
//
// Port of Kokonut UI "Stack Panel" (stack-panel.tsx, MIT), as shown at
// designbookmark.com/motion "Stack panel". A card that drills into pages in
// place, like settings on a phone: a row opens its page from the right while
// its label flies up to become the title, and the page underneath moves a
// third as far (parallax). Swipe the page right, or tap Back, to return: let
// go past 35 % of the width, or flick faster than 500 pt/s, and it pops. The
// card's height follows the page. Push 0.42 s and height 0.38 s, no bounce.
// Reduce Motion: pages cross-fade and the title doesn't fly.

struct StackPanelRow: Identifiable {
    let id: String
    let label: String
    var symbol: String? = nil
    var detail: String? = nil
    /// The page this row opens.
    var to: String? = nil
    /// Runs on tap when the row doesn't open a page.
    var action: (() -> Void)? = nil
}

struct StackPanelSection: Identifiable {
    var id: String { title ?? rows.first?.id ?? "section" }
    var title: String? = nil
    let rows: [StackPanelRow]
}

struct StackPanelPage {
    let title: String
    let sections: [StackPanelSection]
}

struct StackPanel: View {
    let pages: [String: StackPanelPage]
    let root: String

    /// Page ids from the root to the one on top.
    @State private var stack: [String] = []
    /// How far the top page is in: 0 off to the right, 1 fully shown.
    @State private var progress: CGFloat = 1
    @State private var heights: [String: CGFloat] = [:]
    /// Where each row's label sits, so a title can fly from it.
    @State private var labelFrames: [String: CGRect] = [:]
    /// The row that opened each page.
    @State private var openedBy: [String: String] = [:]
    @State private var isPopping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let push = Animation.spring(duration: 0.42, bounce: 0)
    private static let parallax: CGFloat = 0.3
    private static let popDistance: CGFloat = 0.35
    private static let popVelocity: CGFloat = 500
    private static let headerHeight: CGFloat = 48
    private static let space = "stackPanel"

    private var path: [String] { stack.isEmpty ? [root] : stack }
    private var topID: String { path[path.count - 1] }
    private var underID: String? { path.count > 1 ? path[path.count - 2] : nil }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                if let underID, let under = pages[underID] {
                    pageView(under, id: underID)
                        .offset(x: reduceMotion ? 0 : -Self.parallax * width * progress)
                        .opacity(reduceMotion ? 1 - progress : 1 - 0.35 * progress)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let top = pages[topID] {
                    pageView(top, id: topID)
                        .background(Color.surfaceElevated)
                        .offset(x: reduceMotion ? 0 : width * (1 - progress))
                        .opacity(reduceMotion ? progress : 1)
                        .gesture(swipeBack(width: width))
                }
                header(width: width)
            }
            .coordinateSpace(name: Self.space)
        }
        .frame(height: currentHeight)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline.opacity(0.6), lineWidth: 0.5))
        .elevation(Elevation.card)
    }

    /// The card's height follows the page on top as it comes in or leaves.
    private var currentHeight: CGFloat {
        let top = heights[topID] ?? 200
        guard let underID, let under = heights[underID] else { return top }
        return under + (top - under) * progress
    }

    // MARK: Header

    private func header(width: CGFloat) -> some View {
        let topTitle = pages[topID]?.title ?? ""
        let rest = CGPoint(x: width / 2, y: Self.headerHeight / 2)
        // Pushed in from a row, the title flies from that row's label.
        let origin: CGPoint = {
            guard !reduceMotion, let row = openedBy[topID], let frame = labelFrames[row] else {
                return CGPoint(x: rest.x + 24, y: rest.y)
            }
            return CGPoint(x: frame.midX, y: frame.midY)
        }()
        let flown = CGPoint(x: origin.x + (rest.x - origin.x) * progress, y: origin.y + (rest.y - origin.y) * progress)

        return ZStack(alignment: .topLeading) {
            if let underID, let under = pages[underID] {
                // The outgoing title slides a little and fades.
                Text(under.title)
                    .font(.headline)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                    .position(x: rest.x - 24 * progress, y: rest.y)
                    .opacity(1 - progress)
                    .accessibilityHidden(true)

                Button { pop() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                        Text("Back").font(.subheadline)
                    }
                    .foregroundStyle(Color.labelPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.md)
                .frame(height: Self.headerHeight)
                .opacity(progress)
                .accessibilityLabel("Back to \(under.title)")
                .accessibilityIdentifier("stackPanel.back")
            }
            Text(topTitle)
                .font(.headline)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .frame(maxWidth: width - 140)
                .position(underID == nil ? rest : flown)
                .opacity(underID == nil ? 1 : progress)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(width: width, height: Self.headerHeight, alignment: .topLeading)
    }

    // MARK: Page

    private func pageView(_ page: StackPanelPage, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Self.headerHeight)
            ForEach(page.sections) { section in
                if let title = section.title {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xs)
                }
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row, on: id)
                    if index < section.rows.count - 1 {
                        Divider().padding(.leading, row.symbol == nil ? Spacing.lg : Spacing.lg + 28 + Spacing.md)
                    }
                }
            }
            Color.clear.frame(height: Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[id] = $0 }
    }

    private func rowView(_ row: StackPanelRow, on pageID: String) -> some View {
        let isPlain = row.to == nil && row.action == nil
        return Button {
            if let to = row.to { open(to, from: row) } else { row.action?() }
        } label: {
            HStack(spacing: Spacing.md) {
                if let symbol = row.symbol {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                Text(row.label)
                    .font(.body)
                    .foregroundStyle(Color.labelPrimary)
                    .multilineTextAlignment(.leading)
                    // While its page is open, this label has flown up to be the title.
                    .opacity(openedBy[topID] == row.id && pageID != topID && !reduceMotion ? 1 - progress : 1)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                        // Only the resting page reports positions worth flying from.
                        if pageID == topID && progress == 1 { labelFrames[row.id] = frame }
                    }
                Spacer(minLength: Spacing.sm)
                if let detail = row.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.trailing)
                }
                if row.to != nil {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.labelTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // An information row isn't a control, but it shouldn't look switched off.
        .allowsHitTesting(!isPlain)
        .accessibilityRemoveTraits(isPlain ? .isButton : [])
        .accessibilityIdentifier("stackPanel.row." + row.id)
    }

    // MARK: Moves

    private func open(_ pageID: String, from row: StackPanelRow) {
        guard pages[pageID] != nil, !isPopping else { return }
        openedBy[pageID] = row.id
        stack = path + [pageID]
        progress = 0
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.push) { progress = 1 }
    }

    private func pop() {
        guard path.count > 1, !isPopping else { return }
        isPopping = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.push) { progress = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.42))
            stack = Array(path.dropLast())
            progress = 1
            isPopping = false
        }
    }

    private func swipeBack(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard path.count > 1, !isPopping, value.translation.width > 0,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                progress = 1 - min(value.translation.width / max(width, 1), 1)
            }
            .onEnded { value in
                guard path.count > 1, !isPopping, progress < 1 else { return }
                if 1 - progress > Self.popDistance || value.velocity.width > Self.popVelocity {
                    pop()
                } else {
                    withAnimation(Self.push) { progress = 1 }
                }
            }
    }
}

#Preview {
    ScrollView {
        StackPanel(pages: [
            "root": StackPanelPage(title: "Exercises", sections: [StackPanelSection(rows: [
                StackPanelRow(id: "gym", label: "Gym", symbol: "dumbbell.fill", detail: "13", to: "gym"),
                StackPanelRow(id: "home", label: "Home", symbol: "house.fill", detail: "12", to: "gym"),
            ])]),
            "gym": StackPanelPage(title: "Gym", sections: [StackPanelSection(title: "Lower body", rows: [
                StackPanelRow(id: "squat", label: "Back squat", detail: "Intermediate", to: "squat"),
                StackPanelRow(id: "press", label: "Leg press", detail: "Beginner"),
            ])]),
            "squat": StackPanelPage(title: "Back squat", sections: [StackPanelSection(rows: [
                StackPanelRow(id: "works", label: "Works", detail: "Quads, glutes"),
            ])]),
        ], root: "root")
        .padding()
    }
}
