import UIKit
import Observation

/// The person's profile photo: one small JPEG in Application Support on this
/// iPhone. It is left out of iCloud backups and never synced or uploaded.
@Observable
final class ProfilePhotoStore {
    static let shared = ProfilePhotoStore()

    /// What the avatar shows; nil shows initials.
    private(set) var image: UIImage?

    /// Longest side of the saved photo, in pixels: sharp in a 96 pt circle at 3×.
    static let maxPixels: CGFloat = 512

    @ObservationIgnored let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("ProfilePhoto.jpg")
        if let data = try? Data(contentsOf: fileURL) { image = UIImage(data: data) }
    }

    var hasPhoto: Bool { image != nil }

    /// Scales the photo down, crops it square and saves it. Returns false if it couldn't be written.
    @discardableResult
    func save(_ picked: UIImage) -> Bool {
        let square = Self.squared(picked, side: Self.maxPixels)
        guard let data = square.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            return false
        }
        image = UIImage(data: data)
        return true
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        image = nil
    }

    /// A centred square crop, at most `side` pixels wide.
    static func squared(_ image: UIImage, side: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let edge = min(size.width, size.height)
        let target = min(side, edge * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / edge
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
    }
}
