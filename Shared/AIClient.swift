import Foundation

struct AIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transform(text: String, request: ActionRequest, settings: AppSettings) async throws -> String {
        let initialMessage = AIConversationMessage(
            role: .user,
            content: request.inputMode == .prompt ? text : payload(text)
        )

        let output = try await generate(
            sourceText: text,
            messages: [initialMessage],
            request: request,
            settings: settings,
            isFollowUp: false
        )

        return request.plainTextOutput ?
            MarkdownPlainTextConverter.convert(output) : output
    }

    func continueConversation(
        sourceText: String,
        history: [AIConversationMessage],
        request: ActionRequest,
        settings: AppSettings
    ) async throws -> String {
        let initialMessage = AIConversationMessage(
            role: .user,
            content: request.inputMode == .prompt ?
                sourceText : payload(sourceText)
        )

        let output = try await generate(
            sourceText: sourceText,
            messages: [initialMessage] + history,
            request: request,
            settings: settings,
            isFollowUp: true
        )

        return request.plainTextOutput ?
            MarkdownPlainTextConverter.convert(output) : output
    }

    private func generate(
        sourceText: String,
        messages: [AIConversationMessage],
        request: ActionRequest,
        settings: AppSettings,
        isFollowUp: Bool
    ) async throws -> String {
        let inputCharacterCount = messages.reduce(0) {
            $0 + $1.content.count
        }
        let estimatedTokens = (inputCharacterCount + 3) / 4

        if request.inputLimit > 0, estimatedTokens > request.inputLimit {
            throw AIError.message(
                "This conversation is about \(estimatedTokens) tokens, above this action's \(request.inputLimit)-token input limit."
            )
        }

        let provider = Provider(rawValue: request.providerID).map { $0 } ?? settings.provider
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? settings.model(for: provider)
            : request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AIError.message(
                provider == .customOpenAI ?
                    "Enter a model ID for the custom provider in Settings." :
                    "Choose a model in Settings first."
            )
        }

        var prompt = expand(
            request.prompt,
            selection: sourceText,
            settings: settings
        )

        if request.plainTextOutput {
            prompt += """


            Output format requirement: Return plain text only. Do not use Markdown syntax, tables, headings, emphasis markers, backticks, or fenced code blocks. Preserve useful line breaks and list structure.
            """
        }

        if isFollowUp {
            prompt += followUpGuidance(for: request.inputMode)
        }

        var outputLimit = request.inputMode == .prompt && request.outputLimit == 0 ? 2_000 : request.outputLimit
        let inputText = messages.map(\.content).joined(separator: "\n")

        let cloudflareReasoningModel = isCloudflareQwenReasoningModel(
            provider: provider,
            model: model
        )
        let cloudflareReasoningEnabled = cloudflareReasoningModel &&
            settings.isCloudflareReasoningEnabled

        if cloudflareReasoningEnabled, request.outputLimit == 0 {
            outputLimit = max(outputLimit, 4_096)
        }

        switch provider {
        case .ollama:
            return try await ollama(messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit, settings: settings)
        case .gemini:
            return try await gemini(messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
        case .cloudflare:
            let accountID = try cloudflareAccountID(settings)
            let endpoint = "https://api.cloudflare.com/client/v4/accounts/\(urlEncode(accountID))/ai/v1/chat/completions"
            return try await openAICompatible(provider: provider, endpoint: endpoint, inputText: inputText, messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit, extraHeaders: ["cf-aig-gateway-id": "default"], cloudflareReasoningEnabled: cloudflareReasoningEnabled)
        case .groq:
            return try await openAICompatible(provider: provider, endpoint: "https://api.groq.com/openai/v1/chat/completions", inputText: inputText, messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
        case .openrouter:
            return try await openAICompatible(provider: provider, endpoint: "https://openrouter.ai/api/v1/chat/completions", inputText: inputText, messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit, extraHeaders: ["X-Title": "Plyph"])
        case .cerebras:
            return try await openAICompatible(provider: provider, endpoint: "https://api.cerebras.ai/v1/chat/completions", inputText: inputText, messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit, completionTokenKey: "max_completion_tokens")
        case .openai:
            return try await openAICompatible(provider: provider, endpoint: "https://api.openai.com/v1/chat/completions", inputText: inputText, messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
        case .vercel:
            return try await openAICompatible(provider: provider, endpoint: "https://ai-gateway.vercel.sh/v1/chat/completions", inputText: inputText, messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
        case .customOpenAI:
            return try await openAICompatible(provider: provider, endpoint: try customOpenAIEndpoint(settings, path: "chat/completions"), inputText: inputText, messages: messages, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
        }
    }

    func fetchModels(settings: AppSettings, provider: Provider) async throws -> [String] {
        var request: URLRequest
        switch provider {
        case .ollama:
            request = try makeRequest(url: settings.ollamaURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/tags")
        case .gemini:
            let key = try requiredKey(provider)
            request = try makeRequest(url: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&key=\(urlEncode(key))")
        case .cloudflare:
            let accountID = try cloudflareAccountID(settings)
            request = try makeRequest(
                url: "https://api.cloudflare.com/client/v4/accounts/\(urlEncode(accountID))/ai/models/search?task=Text%20Generation&hide_experimental=true&per_page=100",
                headers: ["Authorization": "Bearer \(try requiredKey(provider))"]
            )
        case .customOpenAI:
            var headers: [String: String] = [:]
            let key = KeychainStore.value(for: provider)
            if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
            request = try makeRequest(
                url: try customOpenAIEndpoint(settings, path: "models"),
                headers: headers
            )
        default:
            let endpoints: [Provider: String] = [
                .groq: "https://api.groq.com/openai/v1/models",
                .openrouter: "https://openrouter.ai/api/v1/models?output_modalities=text",
                .cerebras: "https://api.cerebras.ai/v1/models",
                .openai: "https://api.openai.com/v1/models",
                .vercel: "https://ai-gateway.vercel.sh/v1/models"
            ]
            request = try makeRequest(url: endpoints[provider]!, headers: ["Authorization": "Bearer \(try requiredKey(provider))"])
        }
        let object = try await send(request, provider: provider)
        let values: [String]
        if provider == .ollama {
            values = (object["models"] as? [[String: Any]] ?? []).compactMap { ($0["model"] ?? $0["name"]) as? String }
        } else if provider == .gemini {
            values = (object["models"] as? [[String: Any]] ?? []).compactMap { item in
                guard let methods = item["supportedGenerationMethods"] as? [String], methods.contains("generateContent"),
                      let name = item["name"] as? String else { return nil }
                return name.replacingOccurrences(of: "models/", with: "")
            }
        } else if provider == .cloudflare {
            values = (object["result"] as? [[String: Any]] ?? []).compactMap {
                ($0["name"] ?? $0["id"]) as? String
            }
        } else {
            values = (object["data"] as? [[String: Any]] ?? []).compactMap {
                ($0["id"] ?? $0["name"]) as? String
            }
        }
        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func openAICompatible(provider: Provider, endpoint: String, inputText: String, messages: [AIConversationMessage], prompt: String, model: String, mode: InputMode, outputLimit: Int, extraHeaders: [String: String] = [:], completionTokenKey: String = "max_tokens", cloudflareReasoningEnabled: Bool = false) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "messages": providerMessages(prompt: prompt, messages: messages),
            completionTokenKey: maxTokens(text: inputText, outputLimit: outputLimit)
        ]
        if provider == .groq, model.hasPrefix("openai/gpt-oss-") {
            body["reasoning_effort"] = "low"
            body["include_reasoning"] = false
        }
        let cloudflareReasoningModel = isCloudflareQwenReasoningModel(
            provider: provider,
            model: model
        )
        if cloudflareReasoningModel {
            body["chat_template_kwargs"] = [
                "enable_thinking": cloudflareReasoningEnabled
            ]
        }
        var headers = extraHeaders
        let key = provider.requiresAPIKey ?
            try requiredKey(provider) : KeychainStore.value(for: provider)
        if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
        let request = try makeRequest(url: endpoint, method: "POST", headers: headers, body: body)
        let object = try await send(request, provider: provider)
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else {
            throw AIError.message("\(provider.displayName) returned an invalid response.")
        }
        if first["finish_reason"] as? String == "length" { throw AIError.outputLimit }
        guard let message = first["message"] as? [String: Any] else {
            throw AIError.message("\(provider.displayName) returned an invalid response.")
        }
        let content = message["content"] as? String ?? ""
        let reasoningFallback = !cloudflareReasoningEnabled && cloudflareReasoningModel ?
            ((message["reasoning_content"] ?? message["reasoning"]) as? String ?? "") : ""
        let output = content.isEmpty ? reasoningFallback : content
        guard !output.isEmpty else {
            throw AIError.message("\(provider.displayName) returned an empty response.")
        }
        return clean(output, mode: mode)
    }

    private func ollama(messages: [AIConversationMessage], prompt: String, model: String, mode: InputMode, outputLimit: Int, settings: AppSettings) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "messages": providerMessages(prompt: prompt, messages: messages),
            "stream": false
        ]
        if outputLimit > 0 { body["options"] = ["num_predict": outputLimit] }
        let endpoint = settings.ollamaURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat"
        let object = try await send(try makeRequest(url: endpoint, method: "POST", body: body), provider: .ollama)
        if object["done_reason"] as? String == "length" { throw AIError.outputLimit }
        guard let message = object["message"] as? [String: Any], let output = message["content"] as? String else {
            throw AIError.message("Ollama returned an invalid response.")
        }
        return clean(output, mode: mode)
    }

    private func gemini(messages: [AIConversationMessage], prompt: String, model: String, mode: InputMode, outputLimit: Int) async throws -> String {
        let key = try requiredKey(.gemini)
        let contents: [[String: Any]] = messages.map { message in
            [
                "role": message.role == .assistant ? "model" : "user",
                "parts": [["text": message.content]]
            ]
        }
        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": maxTokens(
                    text: messages.map(\.content).joined(separator: "\n"),
                    outputLimit: outputLimit
                )
            ]
        ]
        if !prompt.isEmpty { body["systemInstruction"] = ["parts": [["text": prompt]]] }
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(urlEncode(model)):generateContent?key=\(urlEncode(key))"
        let object = try await send(try makeRequest(url: endpoint, method: "POST", body: body), provider: .gemini)
        guard let candidates = object["candidates"] as? [[String: Any]], let first = candidates.first else {
            throw AIError.message("Gemini returned an invalid response.")
        }
        if first["finishReason"] as? String == "MAX_TOKENS" { throw AIError.outputLimit }
        let content = first["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        let output = parts.compactMap { $0["text"] as? String }.joined()
        guard !output.isEmpty else { throw AIError.message("Gemini returned an invalid response.") }
        return clean(output, mode: mode)
    }

    private func send(_ request: URLRequest, provider: Provider) async throws -> [String: Any] {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.message("The provider returned an invalid response.") }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard (200...299).contains(http.statusCode) else {
                switch http.statusCode {
                case 401, 403:
                    throw AIError.message(
                        provider == .cloudflare ?
                            "Cloudflare rejected the API token or Account ID." :
                            "\(provider.displayName) rejected the API key."
                    )
                case 404:
                    throw AIError.message(
                        provider == .cloudflare ?
                            "Cloudflare could not find that account or model." :
                            "\(provider.displayName) could not find that model."
                    )
                case 429: throw AIError.message("\(provider.displayName) rate limit reached. Wait and try again.")
                case 500...599: throw AIError.message("\(provider.displayName) is temporarily unavailable (\(http.statusCode)).")
                default: throw AIError.message("\(provider.displayName) rejected the request (\(http.statusCode)).")
                }
            }
            return object
        } catch let error as AIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIError.message("Could not connect. Check your internet connection or local server.")
        }
    }

    private func makeRequest(url: String, method: String = "GET", headers: [String: String] = [:], body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: url) else { throw AIError.message("The provider URL is invalid.") }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func providerMessages(
        prompt: String,
        messages: [AIConversationMessage]
    ) -> [[String: String]] {
        var result: [[String: String]] = []
        if !prompt.isEmpty { result.append(["role": "system", "content": prompt]) }
        result += messages.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }
        return result
    }

    private func followUpGuidance(for mode: InputMode) -> String {
        switch mode {
        case .transform:
            return """


            Continue refining the original text using the user's follow-up instructions and the prior versions as context. Return only the complete updated text with no commentary. Do not use Markdown unless the user explicitly requests it.
            """
        case .prompt:
            return """


            Continue the conversation using the prior messages as context. Respond directly to the user's latest message.
            """
        }
    }

    private func payload(_ text: String) -> String {
        "Transform only the text inside the tags.\nReturn only the transformed text.\n<text>\n\(text)\n</text>"
    }

    private func expand(_ template: String, selection: String, settings: AppSettings) -> String {
        template
            .replacingOccurrences(of: "${selection}", with: selection)
            .replacingOccurrences(of: "${language}", with: settings.language)
            .replacingOccurrences(of: "${tone}", with: settings.tone)
            .replacingOccurrences(of: "${style}", with: settings.style)
    }

    private func clean(_ value: String, mode: InputMode) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .transform else { return result }
        if result.lowercased().hasPrefix("<text>"), result.lowercased().hasSuffix("</text>") {
            result = String(result.dropFirst(6).dropLast(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if result.hasPrefix("```") && result.hasSuffix("```") {
            result = result.replacingOccurrences(of: "^```(?:text)?\\s*", with: "", options: .regularExpression)
            result = result.replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
        }
        return result
    }

    private func maxTokens(text: String, outputLimit: Int) -> Int {
        outputLimit > 0 ? outputLimit : min(max((text.count + 3) / 4 + 180, 220), 2_000)
    }

    private func customOpenAIEndpoint(
        _ settings: AppSettings,
        path: String
    ) throws -> String {
        var base = settings.configuredCustomOpenAIBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !base.isEmpty else {
            throw AIError.message("Enter the custom provider Base URL in Settings.")
        }

        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            base.removeLast("/chat/completions".count)
        }

        return "\(base)/\(path)"
    }

    private func cloudflareAccountID(_ settings: AppSettings) throws -> String {
        let value = settings.configuredCloudflareAccountID
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else {
            throw AIError.message("Add your Cloudflare Account ID in Settings.")
        }

        return value
    }

    private func isCloudflareQwenReasoningModel(
        provider: Provider,
        model: String
    ) -> Bool {
        guard provider == .cloudflare else { return false }
        return model.range(
            of: #"^@cf/qwen/qwen3(?:[.-]|$)"#,
            options: .regularExpression
        ) != nil
    }

    private func requiredKey(_ provider: Provider) throws -> String {
        let value = KeychainStore.value(for: provider)
        guard !value.isEmpty else {
            throw AIError.message(
                provider == .cloudflare ?
                    "Add a Cloudflare Workers AI API token in Settings." :
                    "Add a \(provider.displayName) API key in Settings."
            )
        }
        return value
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

enum MarkdownPlainTextConverter {
    static func convert(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let separatorIndexes = Set(
            lines.indices.filter { isTableSeparator(lines[$0]) }
        )
        var tableRows = Set<Int>()

        for separatorIndex in separatorIndexes {
            let headerIndex = separatorIndex - 1
            if lines.indices.contains(headerIndex),
               lines[headerIndex].contains("|") {
                tableRows.insert(headerIndex)
            }

            var rowIndex = separatorIndex + 1
            while lines.indices.contains(rowIndex),
                  !lines[rowIndex].isEmpty,
                  lines[rowIndex].contains("|") {
                tableRows.insert(rowIndex)
                rowIndex += 1
            }
        }

        var insideFence = false
        var output: [String] = []

        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideFence.toggle()
                continue
            }

            if separatorIndexes.contains(index) {
                continue
            }

            if tableRows.contains(index) {
                output.append(plainTableRow(line))
                continue
            }

            if insideFence {
                output.append(line)
                continue
            }

            var plain = line
            plain = replace(
                #"^(\s{0,3})#{1,6}\s+"#,
                in: plain,
                with: "$1"
            )
            plain = replace(
                #"^(\s{0,3})>\s?"#,
                in: plain,
                with: "$1"
            )
            plain = replace(
                #"^(\s*)[-+*]\s+"#,
                in: plain,
                with: "$1• "
            )

            if plain.range(
                of: #"^\s*(?:-{3,}|\*{3,}|_{3,})\s*$"#,
                options: .regularExpression
            ) != nil {
                output.append("")
            } else {
                output.append(removeInlineSyntax(from: plain))
            }
        }

        var result = output.joined(separator: "\n")
        while result.hasPrefix("\n") { result.removeFirst() }
        while result.hasSuffix("\n") { result.removeLast() }
        return result
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.range(
            of: #"^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func plainTableRow(_ line: String) -> String {
        var cells = line.components(separatedBy: "|")
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeLast()
        }

        return cells
            .map {
                removeInlineSyntax(
                    from: $0.trimmingCharacters(in: .whitespaces)
                )
            }
            .joined(separator: "  ")
    }

    private static func removeInlineSyntax(from value: String) -> String {
        var result = value
        result = replace(#"!\[([^\]]*)\]\([^\)]*\)"#, in: result, with: "$1")
        result = replace(#"\[([^\]]+)\]\([^\)]*\)"#, in: result, with: "$1")
        result = replace(#"`([^`\n]+)`"#, in: result, with: "$1")
        result = replace(#"\*\*([^*\n]+)\*\*"#, in: result, with: "$1")
        result = replace(#"__([^_\n]+)__"#, in: result, with: "$1")
        result = replace(#"~~([^~\n]+)~~"#, in: result, with: "$1")
        result = replace(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: result, with: "$1")
        result = replace(#"(?<![A-Za-z0-9_])_([^_\n]+)_(?![A-Za-z0-9_])"#, in: result, with: "$1")
        result = replace(#"\\([\\`*_{}\[\]()#+\-.!|>~])"#, in: result, with: "$1")
        return result
    }

    private static func replace(
        _ pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        value.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
        )
    }
}

enum AIError: LocalizedError {
    case message(String)
    case outputLimit

    var errorDescription: String? {
        switch self {
        case .message(let value): value
        case .outputLimit: "The response reached the output limit. Raise the limit or use less text."
        }
    }
}
