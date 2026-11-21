import SwiftUI
import UIKit

// MARK: - Log a meal from a photo
//
// Online AI only names the foods it sees and guesses their grams
// (`POST /api/food-photo`); the names then go through the voice feature's
// review card, so nutrition always comes from the on-device food data and
// nothing is logged until the person taps.

/// Whether "Snap a meal" is shown: online AI is offered, the person allowed AI
/// sharing, and an AI account (or the owner's test build) can send the request.
@MainActor
enum MealPhotoAccess {
    static var isUsable: Bool {
        let account = AIAccountService.shared
        guard account.offersOnlineAI, APIService.shared.hasAIConsent else { return false }
        return OwnerAITestConfiguration.current != nil || account.isSignedIn
    }

    /// What one photo costs, as the server says (2 when it doesn't say).
    static var costText: String {
        let cost = AIAccountService.shared.allowance?.photoCost ?? 2
        return cost == 1 ? "1 credit" : "\(cost) credits"
    }
}

/// Shrinks a photo for the server: longest side 768 px, JPEG, small enough
/// that its base64 text fits the server's 180,000-character limit.
nonisolated enum MealPhotoEncoder {
    static let longestSide: CGFloat = 768
    static let maxBase64Length = 180_000

    /// Base64 JPEG (no `data:` prefix), or nil when the image can't be encoded.
    static func base64JPEG(from image: UIImage, longestSide: CGFloat = longestSide,
                           limit: Int = maxBase64Length) -> String? {
        var side = longestSide
        var quality: CGFloat = 0.6
        for _ in 0..<10 {
            guard let data = jpeg(image, longestSide: side, quality: quality) else { return nil }
            let text = data.base64EncodedString()
            if text.count <= limit { return text }
            // Lower the quality first, then the size.
            if quality > 0.31 { quality -= 0.15 } else { side = (side * 0.8).rounded() }
        }
        return nil
    }

    static func jpeg(_ image: UIImage, longestSide: CGFloat, quality: CGFloat) -> Data? {
        resized(image, longestSide: longestSide).jpegData(compressionQuality: quality)
    }

    /// Drawn at scale 1, so pixels equal points; never enlarged.
    static func resized(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return image }
        let factor = min(1, longestSide / longest)
        let target = CGSize(width: max(1, (size.width * factor).rounded(.down)),
                            height: max(1, (size.height * factor).rounded(.down)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// The body sent to `/api/food-photo`.
nonisolated struct FoodPhotoRequest: Encodable, Sendable {
    let image: String
}

/// What `/api/food-photo` answers: plain English food names with grams.
nonisolated struct FoodPhotoResponse: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let name: String
        let grams: Double
    }
    let foods: [Item]

    /// The foods as the voice feature's phrases (grams kept within 1–1500, at most 8).
    @MainActor var phrases: [VoiceFoodPhrase] {
        foods.compactMap { item -> VoiceFoodPhrase? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.grams.isFinite else { return nil }
            let grams = min(max(item.grams.rounded(), 1), 1500)
            return VoiceFoodPhrase(name: name, quantity: grams, unit: .gram)
        }
        .prefix(8)
        .map { $0 }
    }
}

/// The system camera, for one photo. Shown only when the device has a camera.
struct MealCameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
    }
}
