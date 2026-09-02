import SwiftUI
import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController {
    private struct WholeTextSnapshot {
        let before: String
        let after: String

        var text: String {
            before + after
        }
    }

    private let state = KeyboardState()
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var requestTask: Task<Void, Never>?
    private var heightConstraint: NSLayoutConstraint?
    private var wholeTextSnapshot: WholeTextSnapshot?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = KeyboardMetrics.keyboardBackground

        let root = KeyboardRootView(
            state: state,
            onRun: { [weak self] request in
                self?.run(request)
            },
            onReplace: { [weak self] in
                self?.replaceSelection()
            },
            onCancel: { [weak self] in
                self?.cancelReview()
            },
            onToggleWholeText: { [weak self] in
                self?.state.toggleWholeTextMode()
            },
            onStartAsk: { [weak self] in
                self?.startAskComposer()
            },
            onGenerateAsk: { [weak self] in
                self?.generateAskResponse()
            },
            onCancelAsk: { [weak self] in
                self?.cancelAskComposer()
            },
            onCursorMove: { [weak self] movement in
                self?.moveCursor(movement)
            },
            onKey: { [weak self] action in
                self?.handle(action)
            }
        )

        let host = UIHostingController(rootView: root)
        hostingController = host

        addChild(host)
        view.addSubview(host.view)

        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let height = view.heightAnchor.constraint(
            equalToConstant: KeyboardMetrics.normalHeight
        )
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height

        host.didMove(toParent: self)

        reloadConfiguration()
        updateHeight()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadConfiguration()
        state.fullAccessEnabled = hasFullAccess
        state.secureField = textDocumentProxy.isSecureTextEntry ?? false
        state.needsInputModeSwitchKey = needsInputModeSwitchKey
        state.suggestShift(for: textDocumentProxy.documentContextBeforeInput)

        updateHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)

        state.secureField = textDocumentProxy.isSecureTextEntry ?? false
        state.needsInputModeSwitchKey = needsInputModeSwitchKey
        state.suggestShift(for: textDocumentProxy.documentContextBeforeInput)

        if state.phase == .idle {
            state.status = idleStatus
        }
    }

    private var idleStatus: String {
        if state.secureField {
            return "Actions are unavailable in password fields"
        }

        if !state.fullAccessEnabled {
            return "Enable Allow Full Access in iOS Settings"
        }

        return "Select text, then choose an action"
    }

    private func reloadConfiguration() {
        let store = SharedStore()

        state.settings = store.loadSettings()
        state.configureLanguages(state.settings.enabledKeyboardLanguages)

        state.actions =
            BuiltInAction.allCases.map {
                $0.request(settings: state.settings)
            }
            + store.loadActions()
                .filter(\.enabled)
                .map(\.request)

        state.status = idleStatus
    }

    private func updateHeight() {
        let targetHeight: CGFloat

        switch state.phase {
        case .idle, .done:
            targetHeight = KeyboardMetrics.normalHeight

        case .running:
            targetHeight = KeyboardMetrics.normalHeight

        case .review:
            targetHeight = KeyboardMetrics.reviewHeight

        case .error:
            targetHeight = KeyboardMetrics.errorHeight
        }

        guard heightConstraint?.constant != targetHeight else {
            return
        }

        heightConstraint?.constant = targetHeight

        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func moveCursor(_ movement: Int) {
        guard movement != 0,
              !state.aiComposerMode else {
            return
        }

        textDocumentProxy.adjustTextPosition(
            byCharacterOffset: movement
        )
    }

    private func handle(_ action: KeyboardKeyAction) {
        if state.aiComposerMode {
            handleAIComposerKey(action)
            return
        }

        switch action {
        case let .insert(text):
            textDocumentProxy.insertText(text)
            state.consumeOneShotShift()

        case .shift:
            state.toggleShift()

        case .delete:
            textDocumentProxy.deleteBackward()

        case .letters:
            state.showLetters()

        case .numbers:
            state.showNumbers()

        case .symbols:
            state.showSymbols()

        case .space:
            textDocumentProxy.insertText(" ")
            state.suggestShift(for: textDocumentProxy.documentContextBeforeInput)

        case .returnKey:
            textDocumentProxy.insertText("\n")
            state.showLetters()

            if state.language.supportsShift {
                state.shiftState = .shifted
            }

        case .switchLanguage:
            state.switchLanguage()
            state.suggestShift(for: textDocumentProxy.documentContextBeforeInput)

        case .nextKeyboard:
            advanceToNextInputMode()

        case .none:
            break
        }
    }

    private func handleAIComposerKey(_ action: KeyboardKeyAction) {
        switch action {
        case let .insert(text):
            state.appendAIInstruction(text)
            state.consumeOneShotShift()

        case .delete:
            state.deleteAIInstructionCharacter()

        case .space:
            state.appendAIInstruction(" ")
            state.suggestShift(for: state.aiInstruction)

        case .returnKey:
            generateAskResponse()

        case .shift:
            state.toggleShift()

        case .letters:
            state.showLetters()

        case .numbers:
            state.showNumbers()

        case .symbols:
            state.showSymbols()

        case .switchLanguage:
            state.switchLanguage()

        case .nextKeyboard:
            advanceToNextInputMode()

        case .none:
            break
        }
    }

    private func startAskComposer() {
        guard hasFullAccess else {
            state.show(error: "Allow Full Access is required for AI requests.")
            updateHeight()
            return
        }

        guard textDocumentProxy.isSecureTextEntry != true else {
            state.show(error: "Plyph is disabled in password fields.")
            updateHeight()
            return
        }

        let selected = textDocumentProxy.selectedText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let copied = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let availableFieldText =
            (textDocumentProxy.documentContextBeforeInput ?? "") +
            (textDocumentProxy.documentContextAfterInput ?? "")

        let context: String

        if !selected.isEmpty {
            context = selected
        } else if !copied.isEmpty {
            context = copied
        } else if !availableFieldText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            context = availableFieldText
        } else {
            state.show(
                error: "No context found. Select editable text or copy the message first, then tap Ask."
            )
            updateHeight()
            return
        }

        requestTask?.cancel()
        clearPendingWholeText()
        state.beginAIComposer(context: context)
        state.status = "Type what you want the AI to do"
        updateHeight()
    }

    private func cancelAskComposer() {
        state.cancelAIComposer()
        state.status = idleStatus
        updateHeight()
    }

    private func generateAskResponse() {
        guard state.aiComposerMode else { return }

        let instruction = state.aiInstruction
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let context = state.aiContext
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !instruction.isEmpty else { return }
        guard !context.isEmpty else {
            state.show(error: "The Ask context is empty.")
            updateHeight()
            return
        }

        guard hasFullAccess else {
            state.show(error: "Allow Full Access is required for AI requests.")
            updateHeight()
            return
        }

        requestTask?.cancel()
        clearPendingWholeText()

        let settings = state.settings
        let request = ActionRequest(
            label: "Ask",
            prompt: "Use the provided context and the user's instruction to produce the requested response. If the user is asking how to reply, write a natural reply in the appropriate language. Return only the text that should be inserted, unless the user explicitly asks for an explanation.",
            inputMode: .prompt,
            providerID: settings.runProviderID,
            model: settings.runModel,
            inputLimit: settings.runInputLimit,
            outputLimit: settings.runOutputLimit
        )
        let input = "Context:\n\(context)\n\nInstruction:\n\(instruction)"

        state.aiComposerMode = false
        state.aiInsertResultMode = true
        state.result = ""
        state.errorMessage = ""
        state.phase = .running
        state.status = "Generating answer…"
        updateHeight()

        requestTask = Task {
            do {
                let result = try await AIClient().transform(
                    text: input,
                    request: request,
                    settings: settings
                )

                try Task.checkCancellation()

                if settings.reviewBeforeKeyboardReplacement {
                    state.result = result
                    state.phase = .review
                    state.status = "Review generated answer"
                    updateHeight()
                } else {
                    insertGeneratedAnswer(result)
                }
            } catch is CancellationError {
                state.reset(status: idleStatus)
                updateHeight()
            } catch {
                state.aiInsertResultMode = false
                state.show(error: error.localizedDescription)
                updateHeight()
            }
        }
    }

    private func insertGeneratedAnswer(_ result: String) {
        textDocumentProxy.insertText(result)
        state.aiInsertResultMode = false
        state.phase = .done
        state.status = "Answer inserted"
        updateHeight()

        Task {
            try? await Task.sleep(for: .milliseconds(450))
            state.reset(status: idleStatus)
            updateHeight()
        }
    }

    private func run(_ request: ActionRequest) {
        guard hasFullAccess else {
            state.show(
                error: "Allow Full Access is required for provider requests and shared settings."
            )
            updateHeight()
            return
        }

        guard textDocumentProxy.isSecureTextEntry != true else {
            state.show(
                error: "Plyph is disabled in password fields."
            )
            updateHeight()
            return
        }

        state.aiInsertResultMode = false
        let inputText: String

        if state.wholeTextMode {
            if let selection = textDocumentProxy.selectedText,
               !selection.isEmpty {
                state.show(
                    error: "Whole text mode works when no text is selected. Tap once in the field, then retry."
                )
                updateHeight()
                return
            }

            let snapshot = WholeTextSnapshot(
                before: textDocumentProxy.documentContextBeforeInput ?? "",
                after: textDocumentProxy.documentContextAfterInput ?? ""
            )

            guard !snapshot.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty else {
                state.show(error: "No text is available around the cursor.")
                updateHeight()
                return
            }

            wholeTextSnapshot = snapshot
            inputText = snapshot.text
        } else {
            guard let selection = textDocumentProxy.selectedText,
                  !selection
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty else {
                state.show(
                    error: "Select text in the app first, or tap All to process the available text around the cursor."
                )
                updateHeight()
                return
            }

            wholeTextSnapshot = nil
            inputText = selection
        }

        requestTask?.cancel()

        state.originalSelection = inputText
        state.result = ""
        state.errorMessage = ""
        state.phase = .running
        state.status = state.wholeTextMode ?
            "Running \(request.label) on whole text…" :
            "Running \(request.label)…"

        updateHeight()

        let settings = state.settings

        requestTask = Task {
            do {
                let result = try await AIClient().transform(
                    text: inputText,
                    request: request,
                    settings: settings
                )

                try Task.checkCancellation()

                if settings.reviewBeforeKeyboardReplacement {
                    state.result = result
                    state.phase = .review
                    state.status = state.wholeTextMode ?
                        "Review whole text before replacing" :
                        "Review before replacing"

                    updateHeight()
                } else {
                    try commit(
                        result: result,
                        original: inputText
                    )
                }
            } catch is CancellationError {
                clearPendingWholeText()
                state.reset(status: idleStatus)
                updateHeight()
            } catch {
                clearPendingWholeText()
                state.show(error: error.localizedDescription)
                updateHeight()
            }
        }
    }

    private func replaceSelection() {
        let result = state.result

        guard !result.isEmpty else {
            return
        }

        if state.aiInsertResultMode {
            insertGeneratedAnswer(result)
            return
        }

        let original = state.originalSelection
        guard !original.isEmpty else { return }

        do {
            try commit(
                result: result,
                original: original
            )
        } catch {
            clearPendingWholeText()
            state.show(error: error.localizedDescription)
            updateHeight()
        }
    }

    private func commit(
        result: String,
        original: String
    ) throws {
        if let snapshot = wholeTextSnapshot {
            try replaceWholeText(
                result: result,
                snapshot: snapshot
            )
        } else {
            guard textDocumentProxy.selectedText == original else {
                throw KeyboardError.selectionChanged
            }

            textDocumentProxy.insertText(result)
        }

        clearPendingWholeText()
        state.phase = .done
        state.status = "Text replaced"

        updateHeight()

        Task {
            try? await Task.sleep(
                for: .milliseconds(450)
            )

            state.reset(status: idleStatus)
            updateHeight()
        }
    }

    private func replaceWholeText(
        result: String,
        snapshot: WholeTextSnapshot
    ) throws {
        guard textDocumentProxy.selectedText?.isEmpty ?? true else {
            throw KeyboardError.textChanged
        }

        let currentBefore = textDocumentProxy.documentContextBeforeInput ?? ""
        let currentAfter = textDocumentProxy.documentContextAfterInput ?? ""

        guard currentBefore == snapshot.before,
              currentAfter == snapshot.after else {
            throw KeyboardError.textChanged
        }

        if !snapshot.after.isEmpty {
            textDocumentProxy.adjustTextPosition(
                byCharacterOffset: snapshot.after.count
            )
        }

        for _ in snapshot.text {
            textDocumentProxy.deleteBackward()
        }

        textDocumentProxy.insertText(result)
    }

    private func clearPendingWholeText() {
        wholeTextSnapshot = nil
    }

    private func cancelReview() {
        requestTask?.cancel()
        clearPendingWholeText()
        state.reset(status: idleStatus)
        updateHeight()
    }
}

private enum KeyboardError: LocalizedError {
    case selectionChanged
    case textChanged

    var errorDescription: String? {
        switch self {
        case .selectionChanged:
            return "The selection changed. Select it again and retry."
        case .textChanged:
            return "The text or cursor changed. Tap All and retry."
        }
    }
}
