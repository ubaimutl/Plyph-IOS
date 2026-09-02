import Foundation

struct AIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transform(text: String, request: ActionRequest, settings: AppSettings) async throws -> String {
        let estimatedTokens = (text.count + 3) / 4
        if request.inputLimit > 0, estimatedTokens > request.inputLimit {
            throw AIError.message("Selected text is about \(estimatedTokens) tokens, above this action's \(request.inputLimit)-token input limit.")
        }

        let provider = Provider(rawValue: request.providerID).map { $0 } ?? settings.provider
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? settings.model(for: provider)
            : request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIError.message("Choose a model in Settings first.") }

        let prompt = expand(request.prompt, selection: text, settings: settings)
        let outputLimit = request.inputMode == .prompt && request.outputLimit == 0 ? 2_000 : request.outputLimit

        switch provider {
        case .ollama:
            return try await ollama(text: text, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit, settings: settings)
        case .gemini:
            return try await gemini(text: text, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
        case .groq:
            return try await openAICompatible(provider: provider, endpoint: "https://api.groq.com/openai/v1/chat/completions", text: text, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
        case .openrouter:
            return try await openAICompatible(provider: provider, endpoint: "https://openrouter.ai/api/v1/chat/completions", text: text, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit, extraHeaders: ["X-Title": "Plyph"])
        case .cerebras:
            return try await openAICompatible(provider: provider, endpoint: "https://api.cerebras.ai/v1/chat/completions", text: text, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit, completionTokenKey: "max_completion_tokens")
        case .openai:
            return try await openAICompatible(provider: provider, endpoint: "https://api.openai.com/v1/chat/completions", text: text, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
        case .vercel:
            return try await openAICompatible(provider: provider, endpoint: "https://ai-gateway.vercel.sh/v1/chat/completions", text: text, prompt: prompt, model: model, mode: request.inputMode, outputLimit: outputLimit)
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
        } else {
            values = (object["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        }
        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func openAICompatible(provider: Provider, endpoint: String, text: String, prompt: String, model: String, mode: InputMode, outputLimit: Int, extraHeaders: [String: String] = [:], completionTokenKey: String = "max_tokens") async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "messages": messages(prompt: prompt, text: text, mode: mode),
            completionTokenKey: maxTokens(text: text, outputLimit: outputLimit)
        ]
        if provider == .groq, model.hasPrefix("openai/gpt-oss-") {
            body["reasoning_effort"] = "low"
            body["include_reasoning"] = false
        }
        var headers = extraHeaders
        headers["Authorization"] = "Bearer \(try requiredKey(provider))"
        let request = try makeRequest(url: endpoint, method: "POST", headers: headers, body: body)
        let object = try await send(request, provider: provider)
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else {
            throw AIError.message("\(provider.displayName) returned an invalid response.")
        }
        if first["finish_reason"] as? String == "length" { throw AIError.outputLimit }
        guard let message = first["message"] as? [String: Any], let output = message["content"] as? String else {
            throw AIError.message("\(provider.displayName) returned an invalid response.")
        }
        return clean(output, mode: mode)
    }

    private func ollama(text: String, prompt: String, model: String, mode: InputMode, outputLimit: Int, settings: AppSettings) async throws -> String {
        var body: [String: Any] = ["model": model, "messages": messages(prompt: prompt, text: text, mode: mode), "stream": false]
        if outputLimit > 0 { body["options"] = ["num_predict": outputLimit] }
        let endpoint = settings.ollamaURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat"
        let object = try await send(try makeRequest(url: endpoint, method: "POST", body: body), provider: .ollama)
        if object["done_reason"] as? String == "length" { throw AIError.outputLimit }
        guard let message = object["message"] as? [String: Any], let output = message["content"] as? String else {
            throw AIError.message("Ollama returned an invalid response.")
        }
        return clean(output, mode: mode)
    }

    private func gemini(text: String, prompt: String, model: String, mode: InputMode, outputLimit: Int) async throws -> String {
        let key = try requiredKey(.gemini)
        var body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": mode == .prompt ? text : payload(text)]]]],
            "generationConfig": ["maxOutputTokens": maxTokens(text: text, outputLimit: outputLimit)]
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
                case 401, 403: throw AIError.message("\(provider.displayName) rejected the API key.")
                case 404: throw AIError.message("\(provider.displayName) could not find that model.")
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

    private func messages(prompt: String, text: String, mode: InputMode) -> [[String: String]] {
        var result: [[String: String]] = []
        if !prompt.isEmpty { result.append(["role": "system", "content": prompt]) }
        result.append(["role": "user", "content": mode == .prompt ? text : payload(text)])
        return result
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

    private func requiredKey(_ provider: Provider) throws -> String {
        let value = KeychainStore.value(for: provider)
        guard !value.isEmpty else { throw AIError.message("Add a \(provider.displayName) API key in Settings.") }
        return value
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
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
