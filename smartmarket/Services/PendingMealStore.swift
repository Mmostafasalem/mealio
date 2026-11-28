import UIKit
import Observation
import os

// MARK: - Meal photos to clarify later
//
// "Snap a meal" keeps the photo as soon as it's taken. If it isn't reviewed and logged
// right away (the sheet was closed, there's no connection, or online AI isn't offered),
// it waits here as "To clarify", with the time it was taken, until the person says what
// was in it. Photos stay on the phone: a small JPEG in Application Support, never synced.

struct PendingMeal: Codable, Identifiable, Hashable {
    let id: UUID
    let takenAt: Date
    var slot: MealSlot
    let fileName: String
}

@MainActor @Observable
final class PendingMealStore {
    static let shared = PendingMealStore()

    /// Longest side of a saved photo, and its JPEG quality.
    static let longestSide: CGFloat = 768
    static let quality: CGFloat = 0.6
    /// More than this and the oldest go (with their photos).
    static let limit = 30

    private let defaults: UserDefaults
    private let key = "pendingMealPhotos_v1"
    private let directory: URL
    private static let logger = Logger(subsystem: "com.mostafa.mealio", category: "PendingMealStore")

    /// Newest first.
    private(set) var meals: [PendingMeal] = []

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base.appendingPathComponent("PendingMeals", isDirectory: true)
        meals = ResilientStorage.loadArray(PendingMeal.self, key: key, defaults: defaults)
            .filter { FileManager.default.fileExists(atPath: self.directory.appendingPathComponent($0.fileName).path) }
            .sorted { $0.takenAt > $1.takenAt }
    }

    /// Saves the photo, shrunk to a small JPEG; nil when it can't be written.
    @discardableResult
    func add(_ image: UIImage, slot: MealSlot? = nil, at date: Date = Date()) -> PendingMeal? {
        guard let data = MealPhotoEncoder.jpeg(image, longestSide: Self.longestSide, quality: Self.quality) else { return nil }
        return add(jpeg: data, slot: slot ?? .suggested(at: date), at: date)
    }

    @discardableResult
    func add(jpeg data: Data, slot: MealSlot, at date: Date, id: UUID = UUID()) -> PendingMeal? {
        let meal = PendingMeal(id: id, takenAt: date, slot: slot, fileName: id.uuidString + ".jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory.appendingPathComponent(meal.fileName)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // Not in iCloud backups: a photo waiting to be described.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            Self.logger.error("Could not save a meal photo: \(error.localizedDescription)")
            return nil
        }
        meals.removeAll { $0.id == id }
        meals.insert(meal, at: 0)
        meals.sort { $0.takenAt > $1.takenAt }
        while meals.count > Self.limit, let oldest = meals.last { remove(oldest.id) }
        persist()
        return meal
    }

    func imageData(for meal: PendingMeal) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(meal.fileName))
    }

    func image(for meal: PendingMeal) -> UIImage? {
        imageData(for: meal).flatMap(UIImage.init(data:))
    }

    func contains(_ id: UUID) -> Bool { meals.contains { $0.id == id } }

    func setSlot(_ slot: MealSlot, for id: UUID) {
        guard let index = meals.firstIndex(where: { $0.id == id }) else { return }
        meals[index].slot = slot
        persist()
    }

    /// The meal was logged (or the photo deleted): it and its photo go.
    func remove(_ id: UUID) {
        guard let meal = meals.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(meal.fileName))
        meals.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        for meal in meals { try? FileManager.default.removeItem(at: directory.appendingPathComponent(meal.fileName)) }
        meals = []
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(meals) { defaults.set(data, forKey: key) }
    }
}
