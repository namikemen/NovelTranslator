import Foundation

public struct LLMConfig: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var baseURL: String
    public var apiKey: String
    public var modelName: String
    public var temperature: Double
    public var concurrency: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Custom Model",
        baseURL: String = "http://localhost:11434/v1",
        apiKey: String = "",
        modelName: String = "translategemma:4b",
        temperature: Double = 0.0,
        concurrency: Int = 3,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.temperature = temperature
        self.concurrency = concurrency
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, modelName, temperature, concurrency, isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Model Profile"
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "http://localhost:11434/v1"
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? "translategemma:4b"
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.0
        self.concurrency = try container.decodeIfPresent(Int.self, forKey: .concurrency) ?? 3
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(concurrency, forKey: .concurrency)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    public static let defaultOllama = LLMConfig(
        name: "Ollama (Local)",
        baseURL: "http://localhost:11434/v1",
        apiKey: "",
        modelName: "translategemma:4b",
        temperature: 0.0,
        concurrency: 3,
        isEnabled: true
    )

    public static let defaultOpenAI = LLMConfig(
        name: "OpenAI GPT-4o-mini",
        baseURL: "https://api.openai.com/v1",
        apiKey: "",
        modelName: "gpt-4o-mini",
        temperature: 0.1,
        concurrency: 4,
        isEnabled: true
    )

    public static let presetDeepSeek = LLMConfig(
        name: "DeepSeek API",
        baseURL: "https://api.deepseek.com/v1",
        apiKey: "",
        modelName: "deepseek-chat",
        temperature: 0.1,
        concurrency: 4,
        isEnabled: true
    )

    public static let presetOpenRouter = LLMConfig(
        name: "OpenRouter",
        baseURL: "https://openrouter.ai/api/v1",
        apiKey: "",
        modelName: "google/gemma-2-9b-it",
        temperature: 0.1,
        concurrency: 4,
        isEnabled: true
    )

    public static let presetGroq = LLMConfig(
        name: "Groq Cloud",
        baseURL: "https://api.groq.com/openai/v1",
        apiKey: "",
        modelName: "llama-3.3-70b-versatile",
        temperature: 0.1,
        concurrency: 4,
        isEnabled: true
    )

    public static let presetLMStudio = LLMConfig(
        name: "LM Studio (Local)",
        baseURL: "http://localhost:1234/v1",
        apiKey: "",
        modelName: "local-model",
        temperature: 0.0,
        concurrency: 3,
        isEnabled: true
    )

    public static let allPresets: [LLMConfig] = [
        defaultOpenAI,
        presetDeepSeek,
        presetOpenRouter,
        presetGroq,
        defaultOllama,
        presetLMStudio
    ]
}

public enum LLMError: LocalizedError {
    case invalidURL(String)
    case serverError(statusCode: Int, message: String)
    case emptyResponse
    case decodingError(String)
    case apiUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let str): return "Invalid endpoint URL: \(str)"
        case .serverError(let code, let msg): return "Server error (HTTP \(code)): \(msg)"
        case .emptyResponse: return "The model returned an empty response."
        case .decodingError(let msg): return "Failed to decode model response: \(msg)"
        case .apiUnavailable(let msg): return msg
        }
    }
}

/// Thread-safe tracker for limiting consecutive temporary fallbacks (e.g. Apple Built-in Translator)
/// when the primary translation API experiences transient errors.
/// If the API succeeds, consecutive failures reset to 0.
/// If the API fails consecutively beyond `maxConsecutiveFallbacks` (default 2), further fallbacks are rejected
/// so the application halts translation instead of silently translating the entire document/book.
public actor TemporaryFallbackTracker {
    public let maxConsecutiveFallbacks: Int
    private(set) public var consecutiveFailures: Int = 0
    private(set) public var totalFallbacksUsed: Int = 0

    public init(maxConsecutiveFallbacks: Int = 2) {
        self.maxConsecutiveFallbacks = maxConsecutiveFallbacks
    }

    public func recordAPISuccess() {
        consecutiveFailures = 0
    }

    /// Checks if a temporary fallback is allowed for the current API failure.
    /// Returns (allowed: true, count: consecutiveFailures) if within limits;
    /// otherwise (allowed: false, count: consecutiveFailures).
    public func recordAPIFailureAndRequestFallback() -> (allowed: Bool, count: Int) {
        if consecutiveFailures < maxConsecutiveFallbacks {
            consecutiveFailures += 1
            totalFallbacksUsed += 1
            return (true, consecutiveFailures)
        } else {
            return (false, consecutiveFailures)
        }
    }

    public func reset() {
        consecutiveFailures = 0
        totalFallbacksUsed = 0
    }
}

public struct LLMTranslationService: Sendable {

    /// Dedicated URLSession configured with a generous 5-minute timeout for LLM inference (Ollama / OpenAI)
    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes
        config.timeoutIntervalForResource = 600 // 10 minutes
        return URLSession(configuration: config)
    }()

    /// Robust JSON dictionary parser handling SSE trails, data: [DONE], and leading/trailing whitespace
    public static func parseJSONDictionary(from data: Data) -> [String: Any]? {
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return json
        }
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        guard let firstBrace = str.firstIndex(of: "{"),
              let lastBrace = str.lastIndex(of: "}"),
              firstBrace <= lastBrace else { return nil }
        let clean = String(str[firstBrace...lastBrace])
        guard let cleanData = clean.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: cleanData)) as? [String: Any]
    }

    // MARK: - Prompt Templates
    public static let defaultTranslationPromptTemplate: String = """
    You are a professional, direct document translator.
    Translate the user input from {sourceLang} to {targetLang}.
    Preserve all original formatting, paragraphs, indentation, and markdown/HTML tags.
    Return ONLY the translated text.
    CRITICAL: Do NOT output any thinking process, reasoning, internal monologue, analysis, or draft steps. Do NOT wrap output in <think> tags. Output ONLY the raw final translated text directly.
    """

    public static let defaultCharacterAnalysisPromptTemplate: String = """
    You are an expert literary translator and linguist specializing in English-to-Vietnamese translation.
    Analyze the confirmed character entities identified across the whole book, along with the background sample text.

    {entitiesSection}

    EXTRACTION RULES:
    1. Examine each entity candidate above. Exclude any candidate that is solely a geographical location, city, building, or organization (e.g., London, England, Scotland Yard).
    2. For all valid characters:
       - "name": Canonical character name
       - "aliases": Surnames, nicknames, or titles used for this person
       - "gender": "Male" | "Female" | "Neutral" | "Unknown"
       - "relativeAge": Approximate age description (e.g. "elderly", "30s", "teenager", "child")
       - "roleOrStatus": Social role or occupation
       - "thirdPersonPronoun": Natural narrative third-person pronoun (cô, anh, ông, bà, chú, bác, hắn, gã, chàng, nàng, thằng bé, cô bé...)
    3. Identify key dialogue pronoun pairs (xưng hô) between interacting characters.
    4. Determine narrativePOV ("First Person" or "Third Person") and narrator name if applicable.

    Return ONLY a valid JSON object matching this schema:
    {
      "narrativePOV": "First Person" | "Third Person",
      "narratorName": "string or null",
      "characters": [
        { "name": "Name", "aliases": ["alias1"], "gender": "Male"|"Female"|"Neutral"|"Unknown", "relativeAge": "string", "roleOrStatus": "string", "thirdPersonPronoun": "cô"|"bà"|"anh"|"ông"|"chị"|"bé"|"hắn"|"gã"|"chàng"|"nàng" }
      ],
      "relationships": [
        { "source": "CharA", "target": "CharB", "selfPronoun": "e.g. anh", "addressingPronoun": "e.g. em", "contextNote": "string" }
      ],
      "generalNotes": "string"
    }
    {contextAppendix}
    CRITICAL: Do NOT wrap output in any thinking tags. Return ONLY the raw JSON object.
    """

    public static func renderTranslationPrompt(
        template: String,
        from sourceLang: String,
        to targetLang: String
    ) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{sourceLang}", with: sourceLang)
        result = result.replacingOccurrences(of: "{targetLang}", with: targetLang)
        return result
    }

    public static func renderCharacterAnalysisPrompt(
        template: String,
        entitiesSection: String,
        contextAppendix: String
    ) -> String {
        var rendered = template
        if rendered.contains("{entitiesSection}") {
            rendered = rendered.replacingOccurrences(of: "{entitiesSection}", with: entitiesSection)
        } else if !entitiesSection.isEmpty {
            rendered = entitiesSection + "\n\n" + rendered
        }

        if rendered.contains("{contextAppendix}") {
            rendered = rendered.replacingOccurrences(of: "{contextAppendix}", with: contextAppendix)
        } else if !contextAppendix.isEmpty {
            rendered = rendered + "\n" + contextAppendix
        }

        // Safety fallback: ensure JSON schema directive is preserved if missing from customized prompt
        if !rendered.contains("\"characters\"") && !rendered.contains("JSON") {
            rendered += """
            \n\nReturn ONLY a valid JSON object matching this schema:
            {
              "narrativePOV": "First Person" | "Third Person",
              "narratorName": "string or null",
              "characters": [
                { "name": "Name", "aliases": ["alias1"], "gender": "Male"|"Female"|"Neutral"|"Unknown", "relativeAge": "string", "roleOrStatus": "string", "thirdPersonPronoun": "string" }
              ],
              "relationships": [
                { "source": "CharA", "target": "CharB", "selfPronoun": "string", "addressingPronoun": "string", "contextNote": "string" }
              ],
              "generalNotes": "string"
            }
            CRITICAL: Return ONLY valid JSON, do NOT wrap in thinking tags or markdown blocks.
            """
        }

        return rendered
    }

    // MARK: - Default System Instruction
    public static func defaultSystemInstruction(from sourceLang: String, to targetLang: String) -> String {
        renderTranslationPrompt(template: defaultTranslationPromptTemplate, from: sourceLang, to: targetLang)
    }

    // MARK: - Single Chunk Translation
    public static func translate(
        text: String,
        from sourceLang: String,
        to targetLang: String,
        config: LLMConfig,
        customSystemInstruction: String? = nil,
        precedingContext: String? = nil
    ) async throws -> String {
        let cleanBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleanBase)/chat/completions"),
              let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil else {
            throw LLMError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }

        let systemInstruction = customSystemInstruction ?? defaultSystemInstruction(from: sourceLang, to: targetLang)

        let userContent: String
        if let context = precedingContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            userContent = """
            [Preceding context for background reference only - who is speaking/acting - DO NOT translate this part]:
            \(context)

            [Current text to translate]:
            \(text)
            """
        } else {
            userContent = text
        }

        let payload: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": userContent]
            ],
            "temperature": config.temperature,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.serverError(statusCode: 0, message: "Non-HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            // Check if error response has json error message
            if let errJson = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                if let errorObj = errJson["error"] as? [String: Any],
                   let errorMsg = errorObj["message"] as? String {
                    let errorType = (errorObj["type"] as? String).map { " (\($0))" } ?? ""
                    throw LLMError.serverError(statusCode: httpResponse.statusCode, message: "\(errorMsg)\(errorType)")
                }
                if let detail = errJson["detail"] as? String {
                    throw LLMError.serverError(statusCode: httpResponse.statusCode, message: detail)
                }
                if let msg = errJson["message"] as? String {
                    throw LLMError.serverError(statusCode: httpResponse.statusCode, message: msg)
                }
            }
            let errMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(statusCode: httpResponse.statusCode, message: errMsg)
        }

        guard let json = parseJSONDictionary(from: data) else {
            if let plainText = String(data: data, encoding: .utf8), !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let cleaned = cleanAndValidateTranslation(rawResponse: plainText, originalText: text)
                guard !cleaned.isEmpty else {
                    throw LLMError.decodingError("Model output contained only thinking/reasoning without translation.")
                }
                return cleaned
            }
            throw LLMError.decodingError("Server returned non-JSON response.")
        }

        let rawContent = try extractContentFromJSON(json, originalText: text)
        let cleaned = cleanAndValidateTranslation(rawResponse: rawContent, originalText: text)
        guard !cleaned.isEmpty else {
            throw LLMError.decodingError("Model output contained only thinking/reasoning without translation.")
        }
        return cleaned
    }

    /// Flexible content extractor supporting standard OpenAI, reasoning models, stream deltas, array parts, and error payloads
    public static func extractContentFromJSON(_ json: [String: Any], originalText: String) throws -> String {
        // 1. Check for explicit error responses returned even with HTTP 200
        if let errorObj = json["error"] as? [String: Any] {
            let msg = (errorObj["message"] as? String) ?? (errorObj["detail"] as? String) ?? "Unknown API error"
            let type = (errorObj["type"] as? String).map { " (\($0))" } ?? ""
            throw LLMError.serverError(statusCode: 200, message: "\(msg)\(type)")
        }
        if let errorStr = json["error"] as? String {
            throw LLMError.serverError(statusCode: 200, message: errorStr)
        }
        if let detail = json["detail"] as? String {
            throw LLMError.serverError(statusCode: 200, message: detail)
        }
        if let messageStr = json["message"] as? String, json["choices"] == nil {
            throw LLMError.serverError(statusCode: 200, message: messageStr)
        }

        // 2. Check standard choices array
        if let choices = json["choices"] as? [[String: Any]] {
            guard !choices.isEmpty else {
                throw LLMError.decodingError("Choices array is empty.")
            }

            for choice in choices {
                // A. message object
                if let message = choice["message"] as? [String: Any] {
                    // Direct string content
                    if let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return content
                    }
                    // Content array of text blocks (e.g. [{ "type": "text", "text": "..." }])
                    if let contentArray = message["content"] as? [[String: Any]] {
                        let textParts = contentArray.compactMap { part -> String? in
                            return (part["text"] as? String) ?? (part["content"] as? String)
                        }
                        if !textParts.isEmpty {
                            return textParts.joined(separator: "\n")
                        }
                    }
                    // Note: We deliberately do NOT fall back to message["reasoning_content"] / message["thought"]
                    // because reasoning is internal model scratchpad, not the translated document text.
                }

                // B. delta object (streaming format chunks)
                if let delta = choice["delta"] as? [String: Any] {
                    if let content = delta["content"] as? String, !content.isEmpty {
                        return content
                    }
                }

                // C. text field (completions API format)
                if let text = choice["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
        }

        // 3. Root-level text/response shortcuts (common in local LLM wrappers)
        if let response = json["response"] as? String, !response.isEmpty {
            return response
        }
        if let text = json["text"] as? String, !text.isEmpty {
            return text
        }
        if let output = json["output"] as? String, !output.isEmpty {
            return output
        }

        throw LLMError.decodingError("Could not extract message content from choices.")
    }

    /// Sanitizes and extracts clean translation text from raw LLM output, handling preambles, reasoning/thinking blocks, code blocks, or option lists
    public static func cleanAndValidateTranslation(rawResponse: String, originalText: String) -> String {
        var cleaned = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        var hadThinking = false

        // 0A. Strip HTML-style thinking/reasoning tags: <think>...</think>, <thought>...</thought>, <reasoning>...</reasoning>
        let tagPatterns = [
            #"(?i)<think>[\s\S]*?</think>"#,
            #"(?i)<thought>[\s\S]*?</thought>"#,
            #"(?i)<reasoning>[\s\S]*?</reasoning>"#,
            #"(?i)<think>[\s\S]*$"#, // unclosed <think> tag
            #"(?i)<thought>[\s\S]*$"#,
            #"(?i)<reasoning>[\s\S]*$"#
        ]
        for pattern in tagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: (cleaned as NSString).length)
                if regex.firstMatch(in: cleaned, options: [], range: range) != nil {
                    hadThinking = true
                    cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // 0B. Detect textual thinking blocks (e.g. "Thinking Process:", "Thought Process:", "Reasoning:", "Analysis:")
        let thinkingHeaderPattern = #"(?i)(?:^|\n)(?:Thinking(?:\s+Process)?|Thought(?:\s+Process)?|Reasoning(?:\s+Process)?|Analysis|Internal\s+Monologue)\s*:\s*"#
        if let headerRegex = try? NSRegularExpression(pattern: thinkingHeaderPattern) {
            let range = NSRange(location: 0, length: (cleaned as NSString).length)
            if headerRegex.firstMatch(in: cleaned, options: [], range: range) != nil {
                hadThinking = true

                // Check for explicit final translation section
                let finalSectionPatterns = [
                    #"(?i)(?:^|\n)(?:#{1,4}\s*|\*{1,3}\s*)?(?:Final(?:\s+(?:Polished|Direct))?\s+Translation|Direct\s+Translation|Translation\s*(?:to\s+[a-zA-Z\s]+)?|Translated\s+(?:Text|Document|Output)|Bản\s+dịch(?:\s+tiếng\s+[a-zA-Z\s]+)?|Kết\s+quả\s+dịch|Output|Result)(?::?\*{1,3}|\*{1,3}:?|:)?\s*\n+([\s\S]+)$"#,
                    #"(?:\n-{3,}|\n\*{3,}|\n_{3,})\s*\n+([\s\S]+)$"#
                ]

                var extractedFinal: String? = nil
                for finalPattern in finalSectionPatterns {
                    if let finalRegex = try? NSRegularExpression(pattern: finalPattern),
                       let match = finalRegex.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: (cleaned as NSString).length)),
                       match.numberOfRanges >= 2 {
                        let captureRange = match.range(at: 1)
                        if captureRange.location != NSNotFound {
                            let candidate = (cleaned as NSString).substring(with: captureRange).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !candidate.isEmpty {
                                extractedFinal = candidate
                                break
                            }
                        }
                    }
                }

                if let finalResult = extractedFinal {
                    cleaned = finalResult
                } else {
                    // Entire response was thinking steps without final translation
                    cleaned = ""
                }
            }
        }

        // 1. If wrapped in markdown code fences (```markdown ... ``` or ``` ... ```), strip them
        if cleaned.hasPrefix("```") && cleaned.hasSuffix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            if lines.count >= 2 {
                let middleLines = lines.dropFirst().dropLast()
                cleaned = middleLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 2. Strip conversational preambles (e.g. "Here is the translation:", "Translation:", "Translated text:")
        let preamblePatterns = [
            #"^\[(?:Current )?[Tt]ext to translate\]:?\s*"#,
            #"^(Here(?:'s| is) (?:the )?(?:direct )?translation[^\n:]*:?\s*)"#,
            #"^(Translation(?:\s+to\s+[a-zA-Z]+)?:\s*)"#,
            #"^(Translated (?:text|document|content):\s*)"#,
            #"^(Sure!?\s*(?:here is the translation:?)?\s*)"#,
            #"^(Certainement!?\s*)"#
        ]
        for pattern in preamblePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: (cleaned as NSString).length)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 3. Handle models returning alternative options or bullet points (e.g. "Here are a few options:\n* **Hola mundo**\n* ...")
        if cleaned.contains("Here are a few options") || cleaned.contains("The best option is likely") {
            if let bestMatch = cleaned.range(of: #"(?:The best option is likely|Option 1:?)\s*\**([^\*\n]+)\**"#, options: .regularExpression) {
                let sub = String(cleaned[bestMatch])
                cleaned = sub.replacingOccurrences(of: #"(?:The best option is likely|Option 1:?)\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let bulletMatch = cleaned.range(of: #"\*\s+\*\*([^\*]+)\*\*"#, options: .regularExpression) {
                let sub = String(cleaned[bulletMatch])
                cleaned = sub.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 4. Strip trailing conversational pleasantries ("Hope this helps!", "Let me know if you need anything else.")
        let postamblePatterns = [
            #"(?:\n\s*)*\n*(?:Hope this helps!?|Let me know if you need (?:further|more) (?:help|translations)[\.!]?|Note:\s*.*)$"#
        ]
        for pattern in postamblePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: (cleaned as NSString).length)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 5. Strip enclosing quotes if original text was not quoted
        if cleaned.count >= 2 {
            if (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && !originalText.hasPrefix("\"")) ||
               (cleaned.hasPrefix("“") && cleaned.hasSuffix("”") && !originalText.hasPrefix("“")) {
                cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 6. Safety handling: If text had thinking and was stripped to empty, return empty so translate fails/falls back
        if hadThinking && cleaned.isEmpty {
            return ""
        }

        // 7. Fallback safety: If empty and no thinking was involved, preserve original text
        if cleaned.isEmpty {
            return originalText
        }

        return cleaned
    }

    // MARK: - Batch Concurrent Translation
    public static func translateBatch(
        items: [(id: Int, text: String)],
        from sourceLang: String,
        to targetLang: String,
        config: LLMConfig,
        fallbackConfigs: [LLMConfig] = [],
        fallbackConfig: LLMConfig? = nil,
        customSystemInstruction: String? = nil,
        contextMap: [Int: String]? = nil,
        fallbackTracker: TemporaryFallbackTracker? = nil,
        appleFallbackHandler: (@Sendable (String) async throws -> String)? = nil,
        onFallbackUsed: (@Sendable (Int, String) async -> Void)? = nil,
        onItemCompleted: @escaping @Sendable (Int, String) async -> Void
    ) async throws {
        let effectiveFallbacks = !fallbackConfigs.isEmpty ? fallbackConfigs : (fallbackConfig.map { [$0] } ?? [])
        let maxConcurrent = max(1, config.concurrency)

        // Queue worker pattern with TaskGroup
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var submittedIndex = 0

            // Initial fill
            while submittedIndex < items.count && submittedIndex < maxConcurrent {
                let item = items[submittedIndex]
                let context = contextMap?[item.id] ?? ((submittedIndex > 0) ? items[submittedIndex - 1].text : nil)
                submittedIndex += 1
                group.addTask {
                    return try await translateItemWithFallback(
                        id: item.id,
                        text: item.text,
                        from: sourceLang,
                        to: targetLang,
                        config: config,
                        fallbackConfigs: effectiveFallbacks,
                        customSystemInstruction: customSystemInstruction,
                        precedingContext: context,
                        fallbackTracker: fallbackTracker,
                        appleFallbackHandler: appleFallbackHandler,
                        onFallbackUsed: onFallbackUsed
                    )
                }
            }

            // Consume and feed next
            for try await (id, result) in group {
                await onItemCompleted(id, result)

                if submittedIndex < items.count {
                    let nextItem = items[submittedIndex]
                    let context = contextMap?[nextItem.id] ?? ((submittedIndex > 0) ? items[submittedIndex - 1].text : nil)
                    submittedIndex += 1
                    group.addTask {
                        return try await translateItemWithFallback(
                            id: nextItem.id,
                            text: nextItem.text,
                            from: sourceLang,
                            to: targetLang,
                            config: config,
                            fallbackConfigs: effectiveFallbacks,
                            customSystemInstruction: customSystemInstruction,
                            precedingContext: context,
                            fallbackTracker: fallbackTracker,
                            appleFallbackHandler: appleFallbackHandler,
                            onFallbackUsed: onFallbackUsed
                        )
                    }
                }
            }
        }
    }

    private static func translateItemWithFallback(
        id: Int,
        text: String,
        from sourceLang: String,
        to targetLang: String,
        config: LLMConfig,
        fallbackConfigs: [LLMConfig] = [],
        fallbackConfig: LLMConfig? = nil,
        customSystemInstruction: String?,
        precedingContext: String?,
        fallbackTracker: TemporaryFallbackTracker? = nil,
        appleFallbackHandler: (@Sendable (String) async throws -> String)? = nil,
        onFallbackUsed: (@Sendable (Int, String) async -> Void)?
    ) async throws -> (Int, String) {
        var primaryError: Error?
        do {
            if Task.isCancelled { throw CancellationError() }
            let translated = try await translate(
                text: text,
                from: sourceLang,
                to: targetLang,
                config: config,
                customSystemInstruction: customSystemInstruction,
                precedingContext: precedingContext
            )
            await fallbackTracker?.recordAPISuccess()
            return (id, translated)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw CancellationError()
        } catch {
            primaryError = error
        }

        let effectiveFallbacks = !fallbackConfigs.isEmpty ? fallbackConfigs : (fallbackConfig.map { [$0] } ?? [])
        for fallback in effectiveFallbacks {
            do {
                if Task.isCancelled { throw CancellationError() }
                await onFallbackUsed?(id, "Paragraph \(id): '\(config.name)' failed. Trying fallback model '\(fallback.name)' (\(fallback.modelName))...")
                let fallbackTranslated = try await translate(
                    text: text,
                    from: sourceLang,
                    to: targetLang,
                    config: fallback,
                    customSystemInstruction: customSystemInstruction,
                    precedingContext: precedingContext
                )
                await fallbackTracker?.recordAPISuccess()
                return (id, fallbackTranslated)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw CancellationError()
            } catch {
                primaryError = error
            }
        }

        if let tracker = fallbackTracker, let appleHandler = appleFallbackHandler {
            let (allowed, count) = await tracker.recordAPIFailureAndRequestFallback()
            let maxLimit = tracker.maxConsecutiveFallbacks
            if allowed {
                do {
                    if Task.isCancelled { throw CancellationError() }
                    await onFallbackUsed?(id, "Paragraph #\(id): API unavailable. Using temporary Apple fallback (\(count)/\(maxLimit))...")
                    let appleTranslated = try await appleHandler(text)
                    return (id, appleTranslated)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let urlErr as URLError where urlErr.code == .cancelled {
                    throw CancellationError()
                } catch let appleErr {
                    throw LLMError.apiUnavailable("API failed (\(primaryError?.localizedDescription ?? "unknown")), and Apple fallback also failed: \(appleErr.localizedDescription)")
                }
            } else {
                throw LLMError.apiUnavailable("API is still not working after \(maxLimit) temporary fallback sentences. Stopping translation.")
            }
        }

        throw primaryError ?? LLMError.emptyResponse
    }

    // MARK: - Model Discovery & Connection Testing
    public static func fetchAvailableModels(config: LLMConfig) async throws -> [String] {
        let cleanBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleanBase)/models"),
              let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil else {
            throw LLMError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Could not fetch models")
        }

        guard let json = parseJSONDictionary(from: data),
              let dataArray = json["data"] as? [[String: Any]] else {
            return []
        }

        let models = dataArray.compactMap { $0["id"] as? String }
        return models.sorted()
    }

    public static func testConnection(config: LLMConfig) async throws -> String {
        let testResponse = try await translate(
            text: "Hello",
            from: "English",
            to: "Spanish",
            config: config
        )
        return "Success! Model responded: \"\(testResponse)\""
    }

    // MARK: - Character Bible Extraction DTO & Service
    public struct ExtractionResponseDTO: Codable {
        public let narrativePOV: String?
        public let narratorName: String?
        public struct CharDTO: Codable {
            public let name: String?
            public let aliases: [String]?
            public let gender: String?
            public let relativeAge: String?
            public let roleOrStatus: String?
            public let thirdPersonPronoun: String?
        }
        public let characters: [CharDTO]?
        public struct RelDTO: Codable {
            public let source: String?
            public let target: String?
            public let selfPronoun: String?
            public let addressingPronoun: String?
            public let contextNote: String?
        }
        public let relationships: [RelDTO]?
        public let generalNotes: String?
    }

    public static func parseCharacterBibleFromJSON(_ rawResponse: String, bookTitle: String) throws -> CharacterBible {
        let cleaned = cleanAndValidateTranslation(rawResponse: rawResponse, originalText: "")

        // Find outermost JSON object
        guard let openBrace = cleaned.firstIndex(of: "{"),
              let closeBrace = cleaned.lastIndex(of: "}") else {
            throw LLMError.decodingError("No JSON object found in response.")
        }

        let jsonString = String(cleaned[openBrace...closeBrace])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw LLMError.decodingError("Invalid UTF-8 JSON string.")
        }

        let dto = try JSONDecoder().decode(ExtractionResponseDTO.self, from: jsonData)

        // Map narrative POV
        let pov: NarrativePOV = {
            if let rawPOV = dto.narrativePOV?.lowercased(), rawPOV.contains("first") {
                return .firstPerson
            }
            return .thirdPerson
        }()

        // Build characters and name-to-id mapping
        var characters: [CharacterProfile] = []
        var nameToId: [String: String] = [:]

        for charDTO in (dto.characters ?? []) {
            let name = (charDTO.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let id = UUID().uuidString
            nameToId[name.lowercased()] = id
            for alias in (charDTO.aliases ?? []) {
                nameToId[alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = id
            }

            let gender: CharacterGender = {
                switch charDTO.gender?.lowercased() {
                case "male": return .male
                case "female": return .female
                case "neutral": return .neutral
                default: return .unknown
                }
            }()

            characters.append(CharacterProfile(
                id: id,
                name: name,
                aliases: charDTO.aliases ?? [],
                gender: gender,
                relativeAge: charDTO.relativeAge ?? "adult",
                roleOrStatus: charDTO.roleOrStatus ?? "",
                thirdPersonPronoun: charDTO.thirdPersonPronoun
            ))
        }

        // Resolve narrator id
        var narratorId: String? = nil
        if let narratorName = dto.narratorName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            narratorId = nameToId[narratorName]
        }

        // Build relationships
        var relationships: [RelationshipPair] = []
        for rel in (dto.relationships ?? []) {
            let srcName = (rel.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tgtName = (rel.target ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !srcName.isEmpty && !tgtName.isEmpty else { continue }

            let srcId = nameToId[srcName.lowercased()] ?? {
                let newId = UUID().uuidString
                nameToId[srcName.lowercased()] = newId
                characters.append(CharacterProfile(id: newId, name: srcName))
                return newId
            }()

            let tgtId = nameToId[tgtName.lowercased()] ?? {
                let newId = UUID().uuidString
                nameToId[tgtName.lowercased()] = newId
                characters.append(CharacterProfile(id: newId, name: tgtName))
                return newId
            }()

            let selfP = (rel.selfPronoun ?? "tôi").trimmingCharacters(in: .whitespacesAndNewlines)
            let addrP = (rel.addressingPronoun ?? "bạn").trimmingCharacters(in: .whitespacesAndNewlines)

            relationships.append(RelationshipPair(
                sourceCharacterId: srcId,
                targetCharacterId: tgtId,
                selfPronoun: selfP.isEmpty ? "tôi" : selfP,
                addressingPronoun: addrP.isEmpty ? "bạn" : addrP,
                contextNote: rel.contextNote
            ))
        }

        return CharacterBible(
            bookTitle: bookTitle,
            narrativePOV: pov,
            narratorCharacterId: narratorId,
            characters: characters,
            relationships: relationships,
            generalNotes: dto.generalNotes ?? ""
        )
    }

    public static func extractCharacterBible(
        from sampleText: String,
        bookTitle: String,
        config: LLMConfig,
        existingBible: CharacterBible? = nil,
        customSystemInstruction: String? = nil
    ) async throws -> CharacterBible {
        let cleanBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleanBase)/chat/completions"),
              let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil else {
            throw LLMError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }

        var contextAppendix = ""
        if let existing = existingBible, !existing.characters.isEmpty {
            let names = existing.characters.map { char -> String in
                var s = "- \(char.name)"
                if !char.aliases.isEmpty {
                    s += " (aliases: \(char.aliases.joined(separator: ", ")))"
                }
                s += " [\(char.gender.rawValue), \(char.ageTier.displayName)]"
                let p = char.thirdPersonPronoun ?? char.resolvedThirdPersonPronoun
                s += " (3rd pronoun: \(p))"
                if !char.roleOrStatus.isEmpty {
                    s += " (\(char.roleOrStatus))"
                }
                return s
            }.joined(separator: "\n")

            var rels = ""
            if !existing.relationships.isEmpty {
                rels = "\nExisting Known Relationships:\n" + existing.relationships.map {
                    "- \($0.sourceCharacterId) -> \($0.targetCharacterId): self='\($0.selfPronoun)', addressing='\($0.addressingPronoun)'"
                }.joined(separator: "\n")
            }

            contextAppendix = """

            ALREADY ESTABLISHED GLOBAL KNOWLEDGE BASE:
            \(names)\(rels)

            FAST-SCAN & RESOLUTION DIRECTIVE:
            1. Use the above established global character profiles to immediately resolve known persons in this text.
            2. Focus specifically on discovering any NEW characters and NEW relationships introduced in this chapter.
            3. For already known characters, preserve their established profiles unless there is an explicit chapter-specific change.
            """
        }

        let template = (customSystemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? customSystemInstruction!
            : defaultCharacterAnalysisPromptTemplate

        let systemInstruction = renderCharacterAnalysisPrompt(
            template: template,
            entitiesSection: "",
            contextAppendix: contextAppendix
        )

        let payload: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": sampleText]
            ],
            "temperature": 0.1,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Character extraction failed.")
        }

        guard let json = parseJSONDictionary(from: data) else {
            let plainText = String(data: data, encoding: .utf8) ?? ""
            return try parseCharacterBibleFromJSON(plainText, bookTitle: bookTitle)
        }

        let rawContent = try extractContentFromJSON(json, originalText: "")
        return try parseCharacterBibleFromJSON(rawContent, bookTitle: bookTitle)
    }

    /// Extracts Character Bible using deterministic book-wide entity anchors, ensuring full chapter coverage and consistent results
    public static func extractCharacterBibleWithAnchors(
        candidateEntities: [CharacterBibleFilter.CandidateEntity],
        sampleText: String,
        bookTitle: String,
        config: LLMConfig,
        existingBible: CharacterBible? = nil,
        customSystemInstruction: String? = nil
    ) async throws -> CharacterBible {
        let cleanBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleanBase)/chat/completions"),
              let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil else {
            throw LLMError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }

        var entitiesSection = ""
        if !candidateEntities.isEmpty {
            entitiesSection = "CONFIRMED ENTITY ANCHORS SCANNED ACROSS ENTIRE BOOK (ordered by occurrence count):\n" + candidateEntities.prefix(30).map { c in
                var line = "- \(c.name) (\(c.occurrenceCount) occurrences in book)"
                if !c.sampleExcerpts.isEmpty {
                    line += "\n  Context excerpts: " + c.sampleExcerpts.prefix(2).map { "\"\($0)\"" }.joined(separator: " / ")
                }
                return line
            }.joined(separator: "\n")
        }

        var contextAppendix = ""
        if let existing = existingBible, !existing.characters.isEmpty {
            let names = existing.characters.map { char -> String in
                var s = "- \(char.name)"
                if !char.aliases.isEmpty {
                    s += " (aliases: \(char.aliases.joined(separator: ", ")))"
                }
                s += " [\(char.gender.rawValue), \(char.ageTier.displayName)]"
                let p = char.thirdPersonPronoun ?? char.resolvedThirdPersonPronoun
                s += " (3rd pronoun: \(p))"
                if !char.roleOrStatus.isEmpty {
                    s += " (\(char.roleOrStatus))"
                }
                return s
            }.joined(separator: "\n")

            contextAppendix = """

            ALREADY ESTABLISHED GLOBAL KNOWLEDGE BASE:
            \(names)
            """
        }

                let template = (customSystemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? customSystemInstruction!
                    : defaultCharacterAnalysisPromptTemplate

                let systemInstruction = renderCharacterAnalysisPrompt(
                    template: template,
                    entitiesSection: entitiesSection,
                    contextAppendix: contextAppendix
                )

        let payload: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": sampleText]
            ],
            "temperature": 0.1,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Anchored character extraction failed.")
        }

        guard let json = parseJSONDictionary(from: data) else {
            let plainText = String(data: data, encoding: .utf8) ?? ""
            return try parseCharacterBibleFromJSON(plainText, bookTitle: bookTitle)
        }

        let rawContent = try extractContentFromJSON(json, originalText: "")
        return try parseCharacterBibleFromJSON(rawContent, bookTitle: bookTitle)
    }

    public static func parseSingleCharacterProfile(fromJSON rawResponse: String, candidateName: String) throws -> CharacterProfile {
        let cleaned = cleanAndValidateTranslation(rawResponse: rawResponse, originalText: "")
        guard let openBrace = cleaned.firstIndex(of: "{"),
              let closeBrace = cleaned.lastIndex(of: "}") else {
            throw LLMError.decodingError("No JSON object found in response.")
        }

        let jsonString = String(cleaned[openBrace...closeBrace])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw LLMError.decodingError("Invalid UTF-8 JSON string.")
        }

        let dto = try JSONDecoder().decode(ExtractionResponseDTO.CharDTO.self, from: jsonData)
        let trimmedName = (dto.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? candidateName : trimmedName

        let gender: CharacterGender = {
            switch dto.gender?.lowercased() {
            case "male": return .male
            case "female": return .female
            case "neutral": return .neutral
            default: return .unknown
            }
        }()

        return CharacterProfile(
            name: resolvedName,
            aliases: dto.aliases ?? [],
            gender: gender,
            relativeAge: dto.relativeAge ?? "adult",
            roleOrStatus: dto.roleOrStatus ?? "",
            thirdPersonPronoun: dto.thirdPersonPronoun
        )
    }

    public static func extractSingleCharacterProfile(
        candidateName: String,
        contextExcerpts: [String],
        existingBible: CharacterBible,
        config: LLMConfig
    ) async throws -> CharacterProfile? {
        let trimmedCandidate = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else { return nil }

        let cleanBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleanBase)/chat/completions"),
              let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil else {
            throw LLMError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }

        let existingNames = existingBible.characters.map(\.name).joined(separator: ", ")
        let systemInstruction = """
        You are an expert literary linguist and translator. Analyze the excerpts featuring candidate character "\(trimmedCandidate)".
        Existing known characters in this story include: \(existingNames.isEmpty ? "None" : existingNames).
        Determine the gender, approximate age or age description, role/occupation, and suitable Vietnamese narrative third-person pronoun (anh ta, cô ta, ông ta, bà ta, thằng bé, cô bé, gã, hắn, etc.).

        Return ONLY a valid JSON object matching this schema:
        {
          "name": "\(trimmedCandidate)",
          "aliases": ["optional alias"],
          "gender": "Male"|"Female"|"Neutral"|"Unknown",
          "relativeAge": "e.g. 30s / adult / elderly / child",
          "roleOrStatus": "e.g. detective / soldier / shopkeeper",
          "thirdPersonPronoun": "e.g. anh ta / cô ta / ông ta / bà ta"
        }
        CRITICAL: Do NOT wrap output in any thinking tags. Return ONLY the raw JSON object.
        """

        let promptContent = contextExcerpts.isEmpty ? trimmedCandidate : contextExcerpts.joined(separator: "\n\n")

        let payload: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": promptContent]
            ],
            "temperature": 0.1,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Single character extraction failed.")
        }

        guard let json = parseJSONDictionary(from: data) else {
            let plainText = String(data: data, encoding: .utf8) ?? ""
            return try? parseSingleCharacterProfile(fromJSON: plainText, candidateName: trimmedCandidate)
        }

        let rawContent = try extractContentFromJSON(json, originalText: "")
        return try? parseSingleCharacterProfile(fromJSON: rawContent, candidateName: trimmedCandidate)
    }

    // MARK: - Low-Level Batch Dispatch
    public static func sendRawChatCompletion(
        messages: [[String: String]],
        config: LLMConfig
    ) async throws -> String {
        let cleanBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleanBase)/chat/completions"),
              let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil else {
            throw LLMError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5-minute timeout

        let cleanKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanKey.isEmpty {
            let authHeader = "Bearer " + cleanKey
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        var payload: [String: Any] = [
            "model": config.modelName,
            "messages": messages,
            "temperature": config.temperature,
            "stream": false
        ]

        if config.baseURL.contains("11434") || config.baseURL.lowercased().contains("ollama") {
            payload["options"] = ["num_ctx": 8192]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let errMsg = String(data: data, encoding: .utf8) ?? "HTTP \(code) error"
            throw LLMError.serverError(statusCode: code, message: errMsg)
        }

        guard let json = parseJSONDictionary(from: data) else {
            if let plainText = String(data: data, encoding: .utf8), !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cleanAndValidateTranslation(rawResponse: plainText, originalText: "")
            }
            throw LLMError.decodingError("Server returned non-JSON response.")
        }

        let rawContent = try extractContentFromJSON(json, originalText: "")
        return cleanAndValidateTranslation(rawResponse: rawContent, originalText: "")
    }

    // MARK: - Batched XML Translation with 2-Tier Fallback
    public static func translateBatchXML(
        batch: TranslationBatch,
        from sourceLang: String,
        to targetLang: String,
        config: LLMConfig,
        fallbackConfigs: [LLMConfig] = [],
        fallbackConfig: LLMConfig? = nil,
        customSystemInstruction: String? = nil,
        previousContext: String? = nil,
        fallbackTracker: TemporaryFallbackTracker? = nil,
        appleFallbackHandler: (@Sendable (String) async throws -> String)? = nil,
        onFallbackUsed: (@Sendable (Int, String) async -> Void)? = nil,
        onNodeCompleted: @escaping @Sendable (Int, String) async -> Void
    ) async throws {
        guard !batch.nodes.isEmpty else { return }
        if Task.isCancelled { throw CancellationError() }

        let effectiveFallbacks = !fallbackConfigs.isEmpty ? fallbackConfigs : (fallbackConfig.map { [$0] } ?? [])
        var activeConfig = config
        let xmlConstraint = """

        Formatting rule:
        - For every input paragraph marked with <p id="X">...</p>, output the translated text wrapped in the identical <p id="X">...</p> tag.
        - Never omit, merge, or change any ID attribute.
        """
        let effectiveSystemInstruction = (customSystemInstruction ?? defaultSystemInstruction(from: sourceLang, to: targetLang)) + xmlConstraint

        let userPrompt = BatchXMLParser.buildUserPrompt(
            nodes: batch.nodes,
            from: sourceLang,
            to: targetLang,
            previousContext: previousContext
        )

        var rawOutput: String? = nil
        do {
            if Task.isCancelled { throw CancellationError() }
            rawOutput = try await sendRawChatCompletion(
                messages: [
                    ["role": "system", "content": effectiveSystemInstruction],
                    ["role": "user", "content": userPrompt]
                ],
                config: activeConfig
            )
            await fallbackTracker?.recordAPISuccess()
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw CancellationError()
        } catch {
            for fallback in effectiveFallbacks {
                if Task.isCancelled { throw CancellationError() }
                await onFallbackUsed?(batch.nodes.first?.id ?? 0, "Batch translation on '\(activeConfig.name)' failed. Retrying on fallback model '\(fallback.name)' (\(fallback.modelName))...")
                activeConfig = fallback
                do {
                    rawOutput = try await sendRawChatCompletion(
                        messages: [
                            ["role": "system", "content": effectiveSystemInstruction],
                            ["role": "user", "content": userPrompt]
                        ],
                        config: activeConfig
                    )
                    await fallbackTracker?.recordAPISuccess()
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch let urlErr as URLError where urlErr.code == .cancelled {
                    throw CancellationError()
                } catch {
                    // Try next fallback in chain
                    continue
                }
            }
        }

        guard let output = rawOutput, !output.isEmpty else {
            // Degrade entire batch to Tier 2 atomic translation
            for node in batch.nodes {
                if Task.isCancelled { throw CancellationError() }
                let (id, translated) = try await translateItemWithFallback(
                    id: node.id,
                    text: node.originalText,
                    from: sourceLang,
                    to: targetLang,
                    config: activeConfig,
                    fallbackConfigs: effectiveFallbacks,
                    customSystemInstruction: customSystemInstruction,
                    precedingContext: nil,
                    fallbackTracker: fallbackTracker,
                    appleFallbackHandler: appleFallbackHandler,
                    onFallbackUsed: onFallbackUsed
                )
                await onNodeCompleted(id, translated)
            }
            return
        }

        let primaryResult = BatchXMLParser.parse(response: output, expectedNodeIds: batch.nodes.map(\.id))
        for (nodeId, text) in primaryResult.completedTranslations {
            await onNodeCompleted(nodeId, text)
        }

        var missingNodeIds = primaryResult.missingNodeIds
        if missingNodeIds.isEmpty { return }

        // Tier 1: Sub-batch retry if minor omission (<= max(4, count / 4))
        let tier1Threshold = max(4, batch.nodes.count / 4)
        if missingNodeIds.count < batch.nodes.count && missingNodeIds.count <= tier1Threshold {
            let missingNodes = batch.nodes.filter { missingNodeIds.contains($0.id) }
            let subUserPrompt = BatchXMLParser.buildUserPrompt(
                nodes: missingNodes,
                from: sourceLang,
                to: targetLang,
                previousContext: nil
            )

            do {
                if Task.isCancelled { throw CancellationError() }
                let subResponse = try await sendRawChatCompletion(
                    messages: [
                        ["role": "system", "content": effectiveSystemInstruction],
                        ["role": "user", "content": subUserPrompt]
                    ],
                    config: activeConfig
                )
                await fallbackTracker?.recordAPISuccess()
                let subResult = BatchXMLParser.parse(response: subResponse, expectedNodeIds: missingNodeIds)
                for (nodeId, text) in subResult.completedTranslations {
                    await onNodeCompleted(nodeId, text)
                }
                missingNodeIds = subResult.missingNodeIds
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw CancellationError()
            } catch {
                // Continue to Tier 2 on sub-batch error
            }
        }

        if missingNodeIds.isEmpty { return }

        // Tier 2: Atomic Degradation for remaining missing nodes
        for missingId in missingNodeIds {
            if Task.isCancelled { throw CancellationError() }
            guard let node = batch.nodes.first(where: { $0.id == missingId }) else { continue }
            let (id, translated) = try await translateItemWithFallback(
                id: node.id,
                text: node.originalText,
                from: sourceLang,
                to: targetLang,
                config: activeConfig,
                fallbackConfigs: effectiveFallbacks,
                customSystemInstruction: customSystemInstruction,
                precedingContext: nil,
                fallbackTracker: fallbackTracker,
                appleFallbackHandler: appleFallbackHandler,
                onFallbackUsed: onFallbackUsed
            )
            await onNodeCompleted(id, translated)
        }
    }
}
