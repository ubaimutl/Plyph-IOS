import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAPIKey = false
    @State private var showModels = false
    @State private var modelSearch = ""

    var body: some View {
        Form {
            Section {
                Button("Open iOS Settings", systemImage: "gear") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }

                Toggle(
                    "Review before replacing",
                    isOn: settingsBinding(\.reviewBeforeKeyboardReplacement)
                )
                .toggleStyle(MonochromeToggleStyle())

                NavigationLink {
                    KeyboardLanguagesView()
                } label: {
                    HStack {
                        Text("Keyboard languages")
                        Spacer()
                        Text(keyboardLanguageSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Keyboard integration")
            } footer: {
                Text("In Settings, go to General › Keyboard › Keyboards › Add New Keyboard, choose Plyph, then enable Allow Full Access. Full Access is required only so an action can contact your chosen provider and read settings stored by this app.")
            }

            Section("AI provider") {
                Picker("Provider", selection: Binding(
                    get: { state.settings.provider },
                    set: { state.selectProvider($0) }
                )) {
                    ForEach(Provider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                if state.settings.provider == .ollama {
                    TextField("Ollama address", text: settingsBinding(\.ollamaURL))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } else {
                    if state.settings.provider == .customOpenAI {
                        TextField(
                            "Base URL",
                            text: settingsBinding(\.configuredCustomOpenAIBaseURL)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                        Text("Use the API base, such as https://api.example.com/v1. Plyph adds /chat/completions and /models.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if state.settings.provider == .cloudflare {
                        TextField(
                            "Account ID",
                            text: settingsBinding(\.configuredCloudflareAccountID)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }

                    HStack {
                        if showAPIKey {
                            TextField(apiCredentialLabel, text: $state.APIKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField(apiCredentialLabel, text: $state.APIKeyDraft)
                        }
                        Button(showAPIKey ? "Hide" : "Show") { showAPIKey.toggle() }
                    }
                    Button(saveCredentialLabel) { state.saveAPIKey() }
                    if !state.APIKeyStatus.isEmpty {
                        Text(state.APIKeyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if state.settings.provider == .cloudflare {
                        Toggle(
                            "Enable Qwen reasoning",
                            isOn: settingsBinding(\.isCloudflareReasoningEnabled)
                        )
                        .toggleStyle(MonochromeToggleStyle())

                        Text("Applies to Cloudflare Qwen 3 models. It is off by default because reasoning uses part of the response limit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Model ID", text: Binding(
                    get: { state.settings.model(for: state.settings.provider) },
                    set: { state.setModel($0) }
                ))
                HStack {
                    Button("Refresh models", systemImage: "arrow.clockwise") { state.refreshModels() }
                        .disabled(state.isLoadingModels)
                    if state.isLoadingModels { ProgressView() }
                    Spacer()
                    if !state.availableModels.isEmpty {
                        Button("Choose (\(state.availableModels.count))") { showModels = true }
                    }
                }
            }

            Section("Prompt variables") {
                TextField("Language", text: settingsBinding(\.language))
                TextField("Tone", text: settingsBinding(\.tone))
                TextField("Style", text: settingsBinding(\.style))
                Text("Use ${selection}, ${language}, ${tone}, and ${style} in prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Built-in prompts") {
                PromptField(title: "Correct", text: settingsBinding(\.promptCorrect))
                PromptField(title: "Rewrite", text: settingsBinding(\.promptRewrite))
                PromptField(title: "Run prompt", text: settingsBinding(\.promptRun))
            }

            Section {
                Picker("Provider", selection: settingsBinding(\.runProviderID)) {
                    Text("Use active provider").tag("")
                    ForEach(Provider.allCases) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }

                TextField("Model (optional)", text: settingsBinding(\.runModel))

                AutomaticTokenLimitField(
                    title: "Input token limit",
                    value: settingsBinding(\.runInputLimit)
                )

                AutomaticTokenLimitField(
                    title: "Output token limit",
                    value: settingsBinding(\.runOutputLimit)
                )
            } header: {
                Text("Run prompt overrides")
            } footer: {
                Text("Automatic uses Plyph's default token handling. Enter a number only when you want a custom cap; clear the field to return to Automatic.")
            }

            Section("Privacy") {
                Text("Plyph has no account, analytics, telemetry, or background clipboard monitoring. Text is sent only after you tap an action. API keys stay in the iOS Keychain.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showModels) {
            NavigationStack {
                List(filteredModels, id: \.self) { model in
                    Button(model) {
                        state.setModel(model)
                        showModels = false
                    }
                }
                .navigationTitle("Choose model")
                .searchable(text: $modelSearch)
                .toolbar { Button("Done") { showModels = false } }
            }
        }
    }

    private var keyboardLanguageSummary: String {
        state.settings.enabledKeyboardLanguages
            .map(\.shortCode)
            .joined(separator: ", ")
    }

    private var apiCredentialLabel: String {
        switch state.settings.provider {
        case .cloudflare:
            return "API token"
        case .customOpenAI:
            return "API key (optional)"
        default:
            return "API key"
        }
    }

    private var saveCredentialLabel: String {
        state.settings.provider == .cloudflare ?
            "Save API token" : "Save API key"
    }

    private var filteredModels: [String] {
        guard !modelSearch.isEmpty else { return state.availableModels }
        return state.availableModels.filter { $0.localizedCaseInsensitiveContains(modelSearch) }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { state.settings[keyPath: keyPath] },
            set: { value in state.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct KeyboardLanguagesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section {
                ForEach(KeyboardLanguage.allCases) { language in
                    Button {
                        toggle(language)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.displayName)
                                    .foregroundStyle(.primary)
                                Text(language.shortCode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isEnabled(language) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("English is the only default. Enable only the languages you want on the Plyph keyboard. The language key appears when two or more are enabled and cycles in the order you add them. At least one language must stay enabled.")
            }
        }
        .navigationTitle("Keyboard Languages")
    }

    private func isEnabled(_ language: KeyboardLanguage) -> Bool {
        state.settings.enabledKeyboardLanguages.contains(language)
    }

    private func toggle(_ language: KeyboardLanguage) {
        var enabled = state.settings.enabledKeyboardLanguages

        if let index = enabled.firstIndex(of: language) {
            guard enabled.count > 1 else { return }
            enabled.remove(at: index)
        } else {
            enabled.append(language)
        }

        state.updateSettings {
            $0.keyboardLanguageIDs = enabled.map(\.rawValue)
        }
    }
}

private struct PromptField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            TextEditor(text: $text)
                .frame(minHeight: 90)
        }
    }
}
