import XCTest
import SwiftUI
@testable import smartmarket

/// Renders the Home quest card for visual review (no pixel asserts).
@MainActor
final class QuestCardSnapshotTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/mealio-run/loop", isDirectory: true)

    func testRenderQuestCard() throws {
        let quests = [
            Quest(id: .breakfast, title: "Log breakfast", symbol: "sunrise.fill", current: 1, goal: 1, unit: "", isDone: true, destination: .logFood),
            Quest(id: .protein, title: "Hit your protein", symbol: "bolt.fill", current: 62, goal: 90, unit: "g", isDone: false, destination: .logFood),
            Quest(id: .workout, title: "Move for 20 minutes", symbol: "figure.walk", current: 0, goal: 20, unit: "min", isDone: false, destination: .train),
        ]
        let state = LoopState(streak: 12, longest: 20, quests: quests,
                              week: [.kept, .saved, .today(kept: true), .future, .future, .future, .future],
                              saversHeld: 1, todayKept: true, perfectToday: false)
        let fresh = LoopState(streak: 0, quests: quests.map { Quest(id: $0.id, title: $0.title, symbol: $0.symbol, current: 0, goal: $0.goal, unit: $0.unit, isDone: false, destination: $0.destination) },
                              week: [.open, .open, .today(kept: false), .future, .future, .future, .future])
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for (name, s) in [("streak", state), ("fresh", fresh)] {
            for scheme in [ColorScheme.light, .dark] {
                let view = DailyQuestCard(state: s)
                    .padding(16)
                    .frame(width: 393)
                    .background(scheme == .dark ? Color.black : Color(white: 0.96))
                    .environment(\.colorScheme, scheme)
                let r = ImageRenderer(content: view)
                r.scale = 2
                if let data = r.uiImage?.pngData() {
                    try data.write(to: outDir.appendingPathComponent("quests-\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
