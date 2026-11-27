import SwiftUI
import PhotosUI

/// Profile card › Edit profile: first name, surname and a photo (from Photos,
/// taken with the camera, or removed). The photo stays on this iPhone
/// (`ProfilePhotoStore`); the avatar on Home and Profile shows it.
struct EditProfileView: View {
    @Bindable var vm: ProfileViewModel
    @State private var photos = ProfilePhotoStore.shared
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var photoError: String?
    @State private var isReady = false
    @FocusState private var focused: Field?

    private enum Field { case first, last }

    var body: some View {
        List {
            Section {
                VStack(spacing: Spacing.md) {
                    ProfileAvatar(size: 112, name: fullName)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    photoButtons
                    if let photoError {
                        Text(photoError).font(.footnote).foregroundStyle(Color.brandDanger)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Your photo stays on this iPhone. It isn't synced to iCloud or sent anywhere.")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }

            Section("Name") {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .first)
                    .submitLabel(.next)
                    .onSubmit { focused = .last }
                    // An AutoFill name arrives whole: go on to the surname.
                    .onChange(of: firstName) { old, new in
                        if focused == .first, new.count - old.count >= 2, lastName.isEmpty { focused = .last }
                    }
                    .accessibilityIdentifier("editProfile.firstName")
                TextField("Surname", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .last)
                    .submitLabel(.done)
                    .onSubmit { focused = nil; commitName(save: true) }
                    .accessibilityIdentifier("editProfile.surname")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !isReady else { return }
            let parts = vm.profile.name.split(separator: " ", maxSplits: 1)
            firstName = parts.first.map(String.init) ?? ""
            lastName = parts.count > 1 ? String(parts[1]) : ""
            isReady = true
        }
        .onChange(of: fullName) { _, _ in commitName() }
        .onDisappear { commitName(save: true) }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPhotoPicker { image in
                showCamera = false
                if let image { store(image) }
            }
            .ignoresSafeArea()
        }
    }

    private var fullName: String {
        [firstName, lastName].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var photoButtons: some View {
        HStack(spacing: Spacing.sm) {
            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                photoButtonLabel("Choose photo", symbol: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editProfile.choosePhoto")
            if CameraPhotoPicker.isAvailable {
                Button { showCamera = true } label: { photoButtonLabel("Take photo", symbol: "camera") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editProfile.takePhoto")
            }
            if photos.hasPhoto {
                Button(role: .destructive) {
                    photos.remove()
                    pickedItem = nil
                } label: { photoButtonLabel("Remove", symbol: "trash", destructive: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editProfile.removePhoto")
            }
        }
    }

    private func photoButtonLabel(_ title: String, symbol: String, destructive: Bool = false) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(destructive ? Color.brandDanger : Color.brandPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
            .contentShape(Capsule())
    }

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            photoError = "That photo couldn't be opened. Try another one."
            return
        }
        store(image)
    }

    private func store(_ image: UIImage) {
        photoError = photos.save(image) ? nil : "The photo couldn't be saved. Check your iPhone's free space and try again."
    }

    /// The card updates as you type; the save (which tells the rest of the app) waits
    /// for Return or leaving the screen. `save()` skips when nothing changed.
    private func commitName(save: Bool = false) {
        guard isReady else { return }
        if vm.profile.name != fullName { vm.profile.name = fullName }
        if save { vm.save() }
    }
}

/// The system camera, for taking a profile photo.
struct CameraPhotoPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish((info[.editedImage] ?? info[.originalImage]) as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
