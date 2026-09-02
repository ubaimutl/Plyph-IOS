import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case ollama, groq, gemini, openrouter, cerebras, openai, vercel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: "Ollama (local)"
        case .groq: "Groq"
        case .gemini: "Gemini"
        case .openrouter: "OpenRouter"
        case .cerebras: "Cerebras"
        case .openai: "OpenAI"
        case .vercel: "Vercel AI Gateway"
        }
    }

    var requiresAPIKey: Bool { self != .ollama }

    var defaultModel: String {
        switch self {
        case .ollama: "qwen3:4b"
        case .groq: "openai/gpt-oss-20b"
        case .gemini: "gemini-3.5-flash-lite"
        case .openrouter: "openrouter/free"
        case .cerebras: "gpt-oss-120b"
        case .openai: "gpt-4.1-mini"
        case .vercel: "openai/gpt-5.4-mini"
        }
    }
}

enum InputMode: String, Codable, CaseIterable {
    case transform
    case prompt
}

enum KeyboardLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case german
    case arabic
    case french
    case spanish
    case italian
    case portuguese
    case dutch
    case turkish
    case russian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        case .arabic: "العربية"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .dutch: "Nederlands"
        case .turkish: "Türkçe"
        case .russian: "Русский"
        }
    }

    var shortCode: String {
        switch self {
        case .english: "EN"
        case .german: "DE"
        case .arabic: "AR"
        case .french: "FR"
        case .spanish: "ES"
        case .italian: "IT"
        case .portuguese: "PT"
        case .dutch: "NL"
        case .turkish: "TR"
        case .russian: "RU"
        }
    }

    var spaceLabel: String {
        switch self {
        case .english: "space"
        case .german: "Leerzeichen"
        case .arabic: "مسافة"
        case .french: "espace"
        case .spanish: "espacio"
        case .italian: "spazio"
        case .portuguese: "espaço"
        case .dutch: "spatie"
        case .turkish: "boşluk"
        case .russian: "пробел"
        }
    }

    var returnLabel: String {
        switch self {
        case .english: "return"
        case .german: "Eingabe"
        case .arabic: "رجوع"
        case .french: "retour"
        case .spanish: "intro"
        case .italian: "invio"
        case .portuguese: "retorno"
        case .dutch: "return"
        case .turkish: "dönüş"
        case .russian: "ввод"
        }
    }

    var lettersLabel: String {
        switch self {
        case .arabic: "أبج"
        case .russian: "АБВ"
        default: "ABC"
        }
    }

    var supportsShift: Bool {
        self != .arabic
    }
}

struct AppSettings: Codable, Equatable {
    var provider: Provider = .groq
    var models: [String: String] = Dictionary(
        uniqueKeysWithValues: Provider.allCases.map { ($0.id, $0.defaultModel) }
    )
    var ollamaURL = "http://127.0.0.1:11434"
    var promptCorrect = "Correct grammar, spelling, punctuation, clarity, and style. Preserve the language, meaning, and tone. Return only the corrected text, unchanged if already correct."
    var promptRewrite = "Rewrite for clarity and natural flow. Preserve the language, meaning, and tone. Add no ideas or commentary. Return only the improved text."
    var promptRun = "Follow the provided instruction precisely. Produce the requested result directly. Do not add introductory commentary unless requested."
    var runProviderID = ""
    var runModel = ""
    var runInputLimit = 0
    var runOutputLimit = 0
    var reviewBeforeKeyboardReplacement = true
    var language = "English"
    var tone = "professional"
    var style = "clear and concise"

    // Optional keeps older saved settings decodable. No saved value means
    // English only, so new and existing installs never get extra keyboard
    // languages unless the user explicitly enables them.
    var keyboardLanguageIDs: [String]?

    var enabledKeyboardLanguages: [KeyboardLanguage] {
        let ids = keyboardLanguageIDs ?? [KeyboardLanguage.english.rawValue]
        let languages = ids.compactMap(KeyboardLanguage.init(rawValue:))
        return languages.isEmpty ? [.english] : languages
    }

    func model(for provider: Provider) -> String {
        let value = models[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? provider.defaultModel : value
    }
}

struct CustomAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var prompt = ""
    var enabled = true
    var providerID = ""
    var model = ""
    var inputMode: InputMode = .transform
    var inputLimit = 0
    var outputLimit = 0
}

enum BuiltInAction: String, CaseIterable, Identifiable {
    case correct = "Correct"
    case rewrite = "Rewrite"
    case runPrompt = "Run prompt"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .correct: return "checkmark.circle"
        case .rewrite: return "pencil.and.outline"
        case .runPrompt: return "paperplane.fill"
        }
    }

    func request(settings: AppSettings) -> ActionRequest {
        switch self {
        case .correct:
            ActionRequest(
                label: rawValue,
                systemImage: systemImage,
                prompt: settings.promptCorrect,
                inputMode: .transform
            )
        case .rewrite:
            ActionRequest(
                label: rawValue,
                systemImage: systemImage,
                prompt: settings.promptRewrite,
                inputMode: .transform
            )
        case .runPrompt:
            ActionRequest(
                label: rawValue,
                systemImage: systemImage,
                prompt: settings.promptRun,
                inputMode: .prompt,
                providerID: settings.runProviderID,
                model: settings.runModel,
                inputLimit: settings.runInputLimit,
                outputLimit: settings.runOutputLimit
            )
        }
    }
}

struct ActionRequest: Identifiable, Equatable {
    let id = UUID()
    var label: String
    var systemImage: String? = nil
    var prompt: String
    var inputMode: InputMode
    var providerID = ""
    var model = ""
    var inputLimit = 0
    var outputLimit = 0
}

extension CustomAction {
    var request: ActionRequest {
        ActionRequest(
            label: name,
            prompt: prompt,
            inputMode: inputMode,
            providerID: providerID,
            model: model,
            inputLimit: inputLimit,
            outputLimit: outputLimit
        )
    }
}
