import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var actions: [CustomAction]
    @Published var input = ""
    @Published var output = ""
    @Published var isRunning = false
    @Published var errorMessage = ""
    @Published var APIKeyDraft = ""
    @Published var APIKeyStatus = ""
    @Published var availableModels: [String] = []
    @Published var isLoadingModels = false

    private let store = SharedStore()
    private let client = AIClient()
    private var requestTask: Task<Void, Never>?

    private static let exampleActionsSeedKey = "plyph.exampleActions.seeded.v1"

    private static var exampleActions: [CustomAction] {
        [
            CustomAction(
                name: "Professional tone",
                prompt: "Rewrite this naturally and professionally while preserving the original meaning. Return only the rewritten text."
            ),
            CustomAction(
                name: "Make shorter",
                prompt: "Make this significantly shorter while keeping the important information and original meaning. Return only the shortened text."
            ),
            CustomAction(
                name: "Turn into checklist",
                prompt: "Convert this text into a concise, actionable checklist. Return only the checklist."
            )
        ]
    }

    init() {
        settings = store.loadSettings()

        let storedActions = store.loadActions()
        actions = Self.seedExampleActionsIfNeeded(storedActions, using: store)

        APIKeyDraft = KeychainStore.value(for: settings.provider)
    }

    private static func seedExampleActionsIfNeeded(
        _ storedActions: [CustomAction],
        using store: SharedStore
    ) -> [CustomAction] {
        let defaults = UserDefaults.standard

        guard !defaults.bool(forKey: exampleActionsSeedKey) else {
            return storedActions
        }

        // Existing users with custom actions keep exactly what they already have.
        // We still mark seeding complete so examples are never inserted later if
        // they eventually delete all of their actions.
        guard storedActions.isEmpty else {
            defaults.set(true, forKey: exampleActionsSeedKey)
            return storedActions
        }

        let examples = exampleActions
        store.save(actions: examples)
        defaults.set(true, forKey: exampleActionsSeedKey)
        return examples
    }

    func reload() {
        settings = store.loadSettings()
        actions = store.loadActions()
        APIKeyDraft = KeychainStore.value(for: settings.provider)
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        store.save(settings: settings)
    }

    func selectProvider(_ provider: Provider) {
        updateSettings { $0.provider = provider }
        APIKeyDraft = KeychainStore.value(for: provider)
        APIKeyStatus = ""
        availableModels = []
    }

    func saveAPIKey() {
        do {
            try KeychainStore.set(APIKeyDraft, for: settings.provider)
            APIKeyDraft = APIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let credential = settings.provider == .cloudflare ?
                "API token" : "API key"
            APIKeyStatus = APIKeyDraft.isEmpty ?
                "\(credential) removed" : "\(credential) stored securely"
        } catch {
            APIKeyStatus = error.localizedDescription
        }
    }

    func setModel(_ model: String) {
        let providerID = settings.provider.id
        updateSettings { $0.models[providerID] = model }
    }

    func run(_ action: BuiltInAction) { run(action.request(settings: settings)) }
    func run(_ action: CustomAction) { run(action.request) }

    func run(_ request: ActionRequest) {
        let sourceText: String

        if request.readsClipboard {
            sourceText = UIPasteboard.general.string ?? ""
            input = sourceText
        } else {
            sourceText = input
        }

        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = request.readsClipboard ?
                "Copy some text before running this action." :
                "Add or paste some text first."
            return
        }
        requestTask?.cancel()
        output = ""
        errorMessage = ""
        isRunning = true
        let snapshot = settings
        requestTask = Task {
            do {
                let value = try await client.transform(text: text, request: request, settings: snapshot)
                try Task.checkCancellation()
                output = value
                isRunning = false
            } catch is CancellationError {
                isRunning = false
            } catch {
                errorMessage = error.localizedDescription
                isRunning = false
            }
        }
    }

    func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        isRunning = false
    }

    func saveAction(_ action: CustomAction) {
        var value = action
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.prompt = value.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty, value.inputMode == .prompt || !value.prompt.isEmpty else {
            errorMessage = "An action needs a name and transformation prompt."
            return
        }
        if let index = actions.firstIndex(where: { $0.id == value.id }) {
            actions[index] = value
        } else {
            actions.append(value)
        }
        store.save(actions: actions)
    }

    func deleteActions(at offsets: IndexSet) {
        actions.remove(atOffsets: offsets)
        store.save(actions: actions)
    }

    func moveActions(from offsets: IndexSet, to destination: Int) {
        actions.move(fromOffsets: offsets, toOffset: destination)
        store.save(actions: actions)
    }

    func setAction(_ action: CustomAction, enabled: Bool) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[index].enabled = enabled
        store.save(actions: actions)
    }

    func refreshModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        availableModels = []
        let provider = settings.provider
        let snapshot = settings
        Task {
            defer { isLoadingModels = false }
            do {
                let models = try await client.fetchModels(settings: snapshot, provider: provider)
                guard settings.provider == provider else { return }
                availableModels = models
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
