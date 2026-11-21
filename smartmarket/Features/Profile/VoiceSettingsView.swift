import SwiftUI

/// Profile › Voice: which language voice commands listen in, the optional
/// offline speech model, and what helps when the built-in rules can't place a phrase.
struct VoiceSettingsView: View {

    @AppStorage(VoiceLanguage.storageKey) private var languageCode = VoiceLanguage.deviceDefault.rawValue
    @State private var offline = OfflineSpeechModel.shared
    @State private var keys = VoiceAIKeyStore.shared
    @State private var route: SpeechCapture.Route?
    @State private var confirmDelete = false

    @State private var provider = VoiceAIKeyStore.Provider.anthropic
    @State private var model = ""
    @State private var address = ""
    @State private var key = ""
    @State private var keyMessage: String?
    @State private var keyFailed = false

    private var language: VoiceLanguage { VoiceLanguage(rawValue: languageCode) ?? .english }

    var body: some View {
        List {
            languageSection
            offlineSection
            understandingSection
            ownKeySection
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: languageCode + String(describing: offline.state)) {
            route = await SpeechCapture.route(for: language)
        }
        .onAppear {
            offline.refresh()
            provider = keys.provider
            model = keys.model
            address = keys.baseURL
        }
        .confirmationDialog("Delete the offline speech model?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { offline.remove() }
        } message: {
            Text("You can download it again at any time.")
        }
    }

    // MARK: Language

    private var languageSection: some View {
        Section {
            Picker("Language", selection: $languageCode) {
                ForEach(VoiceLanguage.allCases) { Text($0.name).tag($0.rawValue) }
            }
            .accessibilityIdentifier("voice.language")
            if let route {
                HStack(alignment: .firstTextBaseline) {
                    Text("Listens with")
                    Spacer(minLength: Spacing.sm)
                    Text(route.name)
                        .foregroundStyle(routeIsMissing ? Color.brandDanger : Color.labelSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Language")
        } footer: {
            Text("Speech is turned into text on this iPhone. The sound is never recorded, stored or sent anywhere. Tap + and choose Speak a command to use it.")
        }
    }

    private var routeIsMissing: Bool {
        if case .some(.none) = route { return true }
        return false
    }

    // MARK: Offline model

    @ViewBuilder private var offlineSection: some View {
        Section {
            switch offline.state {
            case .unsupported:
                Text("The offline model isn't included in this build.")
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
            case .notDownloaded:
                Button { offline.startDownload() } label: {
                    Label("Download offline model (about 470 MB)", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("voice.offline.download")
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ProgressView(value: progress) {
                        Text("Downloading… \(Int((progress * 100).rounded()))%" as String).font(.subheadline)
                    }
                    .tint(Color.progress)
                    Button("Cancel", role: .cancel) { offline.cancelDownload() }
                        .font(.subheadline)
                }
            case .ready:
                HStack {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                    Spacer(minLength: Spacing.sm)
                    Text(ByteCountFormatter.string(fromByteCount: offline.sizeOnDisk, countStyle: .file))
                        .foregroundStyle(Color.labelSecondary)
                }
                .font(.subheadline)
                Button("Delete from this iPhone", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("voice.offline.delete")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(Color.brandDanger)
                Button("Try again") { offline.startDownload() }
            }
            Link(destination: OfflineSpeechModel.creditURL) {
                Text(OfflineSpeechModel.credit)
                    .font(.caption)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.leading)
            }
        } header: {
            Text("Offline speech model")
        } footer: {
            Text("Optional. Adds Lithuanian, and works for English and German where Apple's own model isn't available. A large download (about 470 MB) from Hugging Face over your connection; after that it runs entirely on this iPhone. With it, your words appear when you stop speaking instead of as you speak.")
        }
    }

    // MARK: Understanding

    private var understandingSection: some View {
        Section {
            row("Built-in rules", detail: "Always on, on this iPhone", symbol: "list.bullet.rectangle")
            row("Apple Intelligence", detail: AppleIntelligence.status(for: language).explanation, symbol: "sparkles")
        } header: {
            Text("Understanding what you said")
        } footer: {
            Text("Common phrases are understood by rules built into the app, instantly and offline. A phrase the rules don't know goes to Apple Intelligence on this iPhone when it is available, and only then to your own AI key if you have added one.")
        }
    }

    private func row(_ title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.labelPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Own AI key

    @ViewBuilder private var ownKeySection: some View {
        Section {
            if !keys.signedIn {
                Label("Sign in to your Nourlo account first (Profile › AI account). Your own key can be added after that.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .accessibilityIdentifier("voice.key.signInFirst")
            } else {
                Picker("Provider", selection: $provider) {
                    ForEach(VoiceAIKeyStore.Provider.allCases) { Text($0.name).tag($0) }
                }
                .onChange(of: provider) { _, new in
                    model = new.defaultModel
                    address = new.defaultBaseURL
                }
                TextField("Model name", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("voice.key.model")
                if provider == .custom {
                    TextField("Address (https://…)", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                SecureField(keys.hasKey ? "Key saved. Type to replace it" : "API key", text: $key)
                    .textContentType(.password)
                    .accessibilityIdentifier("voice.key.field")
                Button("Save") { saveKey() }
                    .disabled(model.trimmingCharacters(in: .whitespaces).isEmpty || (key.isEmpty && !keys.hasKey))
                    .accessibilityIdentifier("voice.key.save")
                if keys.hasKey {
                    Button("Remove key", role: .destructive) {
                        keys.remove()
                        provider = keys.provider
                        model = keys.model
                        address = keys.baseURL
                        key = ""
                        keyFailed = false
                        keyMessage = "Key removed."
                    }
                }
                if let keyMessage {
                    Text(keyMessage)
                        .font(.footnote)
                        .foregroundStyle(keyFailed ? Color.brandDanger : Color.labelSecondary)
                }
            }
        } header: {
            Text("Your own AI key (optional)")
        } footer: {
            Text("Used only for phrases neither the rules nor Apple Intelligence could place. The text of that phrase, and nothing else, is sent to the provider you choose and billed to your key. The key is kept in this iPhone's keychain and never sent to Nourlo. Claude models hand a declined request to a fallback model automatically.")
        }
    }

    private func saveKey() {
        do {
            try keys.save(provider: provider, model: model, baseURL: provider == .custom ? address : provider.defaultBaseURL, key: key)
            key = ""
            keyFailed = false
            keyMessage = "Saved."
        } catch {
            keyFailed = true
            keyMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't save the key."
        }
    }
}

#Preview {
    NavigationStack { VoiceSettingsView() }
}
