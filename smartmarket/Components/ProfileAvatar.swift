import SwiftUI

/// The person's avatar: their photo when they chose one, else their initials
/// on the accent colour, else a person symbol. Used on Home's header and on
/// Profile, so the photo shows wherever the initials used to.
struct ProfileAvatar: View {
    var size: CGFloat = 44
    /// Defaults to the saved profile's name.
    var name: String? = nil
    @State private var photos = ProfilePhotoStore.shared

    static func initials(for name: String, max: Int = 2) -> String {
        let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ")
        return String(parts.prefix(max).compactMap(\.first)).uppercased()
    }

    var body: some View {
        let shownName = name ?? AppState.shared.userProfile.name
        let letters = Self.initials(for: shownName, max: size < 50 ? 1 : 2)
        ZStack {
            if let image = photos.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.dullPink
                if letters.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(Color.onAccent)
                } else {
                    Text(letters)
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.25)
                        .padding(size * 0.12)
                        .foregroundStyle(Color.onAccent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.hairline, lineWidth: photos.image == nil ? 0 : 1))
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack { ProfileAvatar(size: 44, name: "Urte K"); ProfileAvatar(size: 96, name: "Urte K"); ProfileAvatar(size: 44, name: "") }
}
