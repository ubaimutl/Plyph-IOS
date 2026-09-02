import Combine
import Foundation

@MainActor
final class KeyboardState: ObservableObject {
    enum Phase: Equatable { case idle, running, review, error, done }

    struct ConversationMessage: Identifiable, Equatable {
        enum Role: Equatable {
            case user
            case assistant
        }

        let id = UUID()
        var role: Role
        var text: String
    }

    enum Page: Equatable {
        case letters
        case numbers
        case symbols
    }

    enum ShiftState: Equatable {
        case lowercase
        case shifted
        case capsLocked
    }

    @Published var phase: Phase = .idle
    @Published var status = "Select text, then choose an action"
    @Published var errorMessage = ""
    @Published var result = ""
    @Published var actions: [ActionRequest] = []
    @Published var fullAccessEnabled = false
    @Published var secureField = false
    @Published var page: Page = .letters
    @Published var shiftState: ShiftState = .lowercase
    @Published var needsInputModeSwitchKey = false
    @Published var language: KeyboardLanguage
    @Published var enabledLanguages: [KeyboardLanguage] = [.english]
    @Published var wholeTextMode = false

    @Published var aiComposerMode = false
    @Published var aiInstruction = ""
    @Published var aiContext = ""
    @Published var aiInsertResultMode = false

    @Published var conversationMessages: [ConversationMessage] = []
    @Published var activeResponseID: UUID?
    @Published var conversationTitle = ""
    @Published var plainTextPreviewEnabled = false
    @Published var conversationError = ""

    var originalSelection = ""
    var settings = AppSettings()
    var conversationRequest: ActionRequest?
    var conversationSourceText = ""

    private static let languageStorageKey = "plyph.keyboard.language"
    private var lastShiftTap = Date.distantPast

    init() {
        if let value = UserDefaults.standard.string(forKey: Self.languageStorageKey),
           let saved = KeyboardLanguage(rawValue: value) {
            language = saved
        } else {
            language = .english
        }
    }

    var usesUppercaseLetters: Bool {
        guard language.supportsShift else { return false }
        return shiftState != .lowercase
    }

    var isConversationActive: Bool {
        !conversationMessages.isEmpty &&
            (phase == .review || phase == .running)
    }

    var activeConversationResult: String {
        guard let activeResponseID,
              let message = conversationMessages.first(where: {
                  $0.id == activeResponseID && $0.role == .assistant
              }) else {
            return result
        }

        return plainTextPreviewEnabled ?
            MarkdownPlainTextConverter.convert(message.text) : message.text
    }

    func configureLanguages(_ languages: [KeyboardLanguage]) {
        let configured = languages.isEmpty ? [.english] : languages
        enabledLanguages = configured

        guard configured.contains(language) else {
            language = configured[0]
            persistLanguage()
            page = .letters
            shiftState = .lowercase
            return
        }
    }

    func switchLanguage() {
        guard enabledLanguages.count > 1 else { return }

        let currentIndex = enabledLanguages.firstIndex(of: language) ?? 0
        let nextIndex = (currentIndex + 1) % enabledLanguages.count
        language = enabledLanguages[nextIndex]
        persistLanguage()
        page = .letters
        shiftState = .lowercase
    }

    private func persistLanguage() {
        UserDefaults.standard.set(language.rawValue, forKey: Self.languageStorageKey)
    }

    func toggleWholeTextMode() {
        wholeTextMode.toggle()
    }

    func beginAIComposer(context: String) {
        wholeTextMode = false
        aiContext = context
        aiInstruction = ""
        aiInsertResultMode = false
        aiComposerMode = true
        phase = .idle
    }

    func cancelAIComposer() {
        aiComposerMode = false
        aiInstruction = ""
        aiContext = ""
        aiInsertResultMode = false
    }

    func beginConversation(
        title: String,
        sourceText: String,
        request: ActionRequest,
        initialResult: String,
        insertsResult: Bool
    ) {
        let response = ConversationMessage(
            role: .assistant,
            text: initialResult
        )

        conversationTitle = title
        conversationSourceText = sourceText
        conversationRequest = request
        conversationMessages = [response]
        activeResponseID = response.id
        plainTextPreviewEnabled = false
        conversationError = ""
        aiInsertResultMode = insertsResult
        aiComposerMode = false
        aiInstruction = ""
        result = initialResult
        phase = .review
    }

    func beginFollowUpComposer() {
        guard isConversationActive, !aiComposerMode else { return }
        conversationError = ""
        aiComposerMode = true
        page = .letters
        if aiInstruction.isEmpty {
            shiftState = language.supportsShift ? .shifted : .lowercase
        }
    }

    func collapseFollowUpComposer(clearDraft: Bool = false) {
        aiComposerMode = false

        if clearDraft {
            aiInstruction = ""
        }
    }

    func appendFollowUp() -> String? {
        let instruction = aiInstruction
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !instruction.isEmpty else { return nil }

        conversationMessages.append(
            ConversationMessage(role: .user, text: instruction)
        )
        aiInstruction = ""
        aiComposerMode = false
        conversationError = ""
        return instruction
    }

    func appendConversationResponse(_ text: String) {
        let response = ConversationMessage(
            role: .assistant,
            text: text
        )

        conversationMessages.append(response)
        activeResponseID = response.id
        result = text
        conversationError = ""
        phase = .review
    }

    func selectConversationResponse(_ id: UUID) {
        guard let response = conversationMessages.first(where: {
            $0.id == id && $0.role == .assistant
        }) else {
            return
        }

        activeResponseID = id
        result = response.text
    }

    var providerConversationHistory: [AIConversationMessage] {
        conversationMessages.map { message in
            AIConversationMessage(
                role: message.role == .assistant ? .assistant : .user,
                content: message.text
            )
        }
    }

    func appendAIInstruction(_ text: String) {
        aiInstruction.append(text)
    }

    func deleteAIInstructionCharacter() {
        guard !aiInstruction.isEmpty else { return }
        aiInstruction.removeLast()
    }

    func toggleShift() {
        guard language.supportsShift else { return }

        let now = Date()

        if shiftState == .shifted,
           now.timeIntervalSince(lastShiftTap) < 0.4 {
            shiftState = .capsLocked
        } else {
            switch shiftState {
            case .lowercase:
                shiftState = .shifted
            case .shifted, .capsLocked:
                shiftState = .lowercase
            }
        }

        lastShiftTap = now
    }

    func consumeOneShotShift() {
        guard language.supportsShift else { return }

        if shiftState == .shifted {
            shiftState = .lowercase
        }
    }

    func showLetters() {
        page = .letters
    }

    func showNumbers() {
        page = .numbers
    }

    func showSymbols() {
        page = .symbols
    }

    func suggestShift(for context: String?) {
        guard language.supportsShift,
              page == .letters,
              shiftState != .capsLocked else {
            return
        }

        let trimmed = context?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let shouldShift = trimmed.isEmpty ||
            trimmed.hasSuffix(".") ||
            trimmed.hasSuffix("!") ||
            trimmed.hasSuffix("?")

        if shouldShift {
            shiftState = .shifted
        } else if shiftState == .shifted {
            shiftState = .lowercase
        }
    }

    func show(error: String) {
        errorMessage = error
        status = "The request failed"
        phase = .error
    }

    func reset(status: String) {
        phase = .idle
        self.status = status
        errorMessage = ""
        result = ""
        originalSelection = ""
        wholeTextMode = false
        aiComposerMode = false
        aiInstruction = ""
        aiContext = ""
        aiInsertResultMode = false
        conversationMessages = []
        activeResponseID = nil
        conversationTitle = ""
        plainTextPreviewEnabled = false
        conversationError = ""
        conversationRequest = nil
        conversationSourceText = ""
    }
}
