# Batched XML Chunking & Rolling Context for Literary Translation

**Date:** 2026-10-03  
**Status:** Draft / Proposed  
**Author:** AI Assistant & User  

---

## 1. Problem Statement & Motivation

Currently in DocTranslateApp, EPUB and document translation uses an atomic single-paragraph model:
- In EPUB, every `<p>`, `<h1>`...`<h6>`, `<blockquote>` is extracted as an independent `TranslatableNode`.
- Each node is sent to the LLM in its own separate HTTP request via `LLMTranslationService.translateBatch` (with TaskGroup concurrency).

### Severe Disadvantages of the Current Model:
1. **Catastrophic Token Waste (85% - 90% Overhead):**
   - Each individual paragraph (typically 30–60 words, ~40 tokens) is sent with the full `system` prompt (literary style instructions, pronoun rules, Character Bible entity/relationship tables, ~1,200–2,500 tokens).
   - For an average chapter of 80 paragraphs (~3,500 words), the app sends 80 separate requests. The system prompt is re-transmitted 80 times, burning ~120,000–160,000 input tokens per chapter instead of ~10,000 tokens.
2. **Context Fragmentation & Tone Drift:**
   - Literary translation strongly depends on continuous dialogue and emotional arc across consecutive paragraphs.
   - Even with a 1-paragraph `precedingContext`, the LLM cannot see who spoke earlier in a 4-turn exchange.
   - When requests run concurrently, adjacent paragraphs are processed by different LLM instances simultaneously, causing jarring shifts in pronouns and tone (e.g. Paragraph 1 translates "he" as "chàng", Paragraph 2 translates "he" as "hắn", Paragraph 3 as "anh").
3. **Network Latency & Rate Limits:**
   - 80–120 individual HTTP roundtrips per chapter frequently trigger provider rate limits (`429 Too Many Requests`) on platforms like OpenRouter, OpenAI, and Groq.

---

## 2. Goals & Non-Goals

### Goals:
- **Batched Grouping:** Group consecutive paragraph nodes into batches of ~1,000–1,500 words (~12–25 paragraphs) per LLM request for EPUB translation.
- **XML Tag Preserved Mapping:** Wrap each paragraph in `<p id="X">...</p>` tags in the prompt and parse them back to assign translated text to exact node IDs without breaking EPUB XHTML structure.
- **Rolling Context:** Pass the last 1–2 translated paragraphs of the previous batch dynamically at runtime (`<prev_context>`) to maintain pronoun and stylistic continuity across batches.
- **Graceful Error Recovery:** 
  - Save all successfully parsed paragraphs immediately.
  - Automatically retry missing or malformed node IDs in a small sub-batch (Tier 1).
  - Degrade to atomic single-node translation only for stubborn missing nodes (Tier 2).
- **User Configuration:** Allow adjusting the target batch word count (500–2,500 words, default 1,200) in App Settings.

### Non-Goals:
- **Document Mode Scope:** Phase 1 focuses exclusively on EPUB eBook translation (`translateEPUBLLM`). Plain text document mode (`DocumentChunker`) is unchanged in this phase and will be unified in a future phase.
- Modifying the underlying EPUB XHTML spine or unpacking logic.
- Altering the Apple Translation engine (which only supports on-device text sessions).
- Merging HTML paragraphs into a single output paragraph (format preservation is strict).

---

## 3. Architecture & Core Data Structures

### 3.1 Data Structures

Location: `Sources/DocTranslateApp/BatchChunker.swift`

```swift
public struct TranslationBatch: Identifiable, Sendable {
    public let id: Int
    public let chapterIndex: Int
    public let nodes: [TranslatableNode]
    public let targetWordCount: Int

    public var wordCount: Int {
        nodes.reduce(0) { $0 + $1.originalText.split { $0.isWhitespace || $0.isNewline }.count }
    }

    public init(id: Int, chapterIndex: Int, nodes: [TranslatableNode], targetWordCount: Int) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.nodes = nodes
        self.targetWordCount = targetWordCount
    }
}

public struct BatchTranslationResult: Sendable {
    public let completedTranslations: [Int: String] // nodeId -> translated text
    public let missingNodeIds: [Int]
    public let rawResponse: String

    public init(completedTranslations: [Int: String], missingNodeIds: [Int], rawResponse: String) {
        self.completedTranslations = completedTranslations
        self.missingNodeIds = missingNodeIds
        self.rawResponse = rawResponse
    }
}
```

### 3.2 Batch Chunking Algorithm (`BatchChunker`)

Location: `Sources/DocTranslateApp/BatchChunker.swift`

```swift
public struct BatchChunker {
    public static let defaultTargetWordCount = 1200

    public static func createBatches(
        from nodes: [TranslatableNode],
        chapterIndex: Int,
        targetWordCount: Int = defaultTargetWordCount
    ) -> [TranslationBatch] {
        guard !nodes.isEmpty else { return [] }

        let safeTargetWords = max(200, targetWordCount)
        let maxNodesPerBatch = 30 // Prevents infinite batch accumulation in CJK languages lacking whitespace

        var batches: [TranslationBatch] = []
        var currentNodes: [TranslatableNode] = []
        var currentWords = 0
        var batchId = 0

        for node in nodes {
            // If node is already translated, finalize any existing batch to preserve contiguity
            if !node.translatedText.isEmpty {
                if !currentNodes.isEmpty {
                    batches.append(TranslationBatch(
                        id: batchId,
                        chapterIndex: chapterIndex,
                        nodes: currentNodes,
                        targetWordCount: safeTargetWords
                    ))
                    batchId += 1
                    currentNodes = []
                    currentWords = 0
                }
                continue
            }

            let nodeWords = max(1, node.originalText.split { $0.isWhitespace || $0.isNewline }.count)
            let isHeading = node.tagOpen.range(of: #"<h[1-6]\b"#, options: [.regularExpression, .caseInsensitive]) != nil

            // Split on headings (if batch has >= 200 words), target word limit, or safety node count ceiling
            let shouldSplit = (isHeading && currentWords >= 200)
                || (currentWords + nodeWords > safeTargetWords)
                || (currentNodes.count >= maxNodesPerBatch)

            if shouldSplit && !currentNodes.isEmpty {
                batches.append(TranslationBatch(
                    id: batchId,
                    chapterIndex: chapterIndex,
                    nodes: currentNodes,
                    targetWordCount: safeTargetWords
                ))
                batchId += 1
                currentNodes = []
                currentWords = 0
            }

            currentNodes.append(node)
            currentWords += nodeWords
        }

        if !currentNodes.isEmpty {
            batches.append(TranslationBatch(
                id: batchId,
                chapterIndex: chapterIndex,
                nodes: currentNodes,
                targetWordCount: safeTargetWords
            ))
        }

        return batches
    }
}
```

---

## 4. Prompt XML Framing & Rolling Context

### 4.1 Prompt Framing & Helper API

Location: `Sources/DocTranslateApp/BatchXMLParser.swift`

```swift
extension BatchXMLParser {
    /// Formats batch nodes and optional rolling context into a parameterized LLM user prompt
    public static func buildUserPrompt(
        nodes: [TranslatableNode],
        from sourceLang: String,
        to targetLang: String,
        previousContext: String? = nil
    ) -> String {
        var sections: [String] = []

        if let context = previousContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            // Defensively cap rolling context to 1,000 characters to prevent eating model context budget
            let boundedContext = context.count > 1000 ? String(context.suffix(1000)) : context
            sections.append("""
            [PREVIOUS CONTEXT - For reference only to maintain pronoun and tone continuity. DO NOT translate this section]:
            <prev_context>
            \(boundedContext)
            </prev_context>
            """)
        }

        let paragraphsBlock = nodes.map { "<p id=\"\($0.id)\">\($0.originalText)</p>" }.joined(separator: "\n")
        sections.append("""
        [PARAGRAPHS TO TRANSLATE]:
        Translate the following paragraphs from \(sourceLang) into \(targetLang). Preserve each paragraph inside its exact <p id="X">...</p> tag. Do not omit, combine, or change any ID:

        \(paragraphsBlock)
        """)

        return sections.joined(separator: "\n\n")
    }
}
```

The user message sent to the LLM is constructed parameterized by source and target languages:

```
[PREVIOUS CONTEXT - For reference only to maintain pronoun and tone continuity. DO NOT translate this section]:
<prev_context>
Original: "I don't think we should enter," Ellen whispered. Mark shook his head.
Translated: "Em không nghĩ chúng ta nên vào trong," Ellen thì thầm. Mark lắc đầu.
</prev_context>

[PARAGRAPHS TO TRANSLATE]:
Translate the following paragraphs from {sourceLang} into {targetLang}. Preserve each paragraph inside its exact <p id="X">...</p> tag. Do not omit, combine, or change any ID:

<p id="101">Mark gripped the bronze door handle. The metal was ice cold against his palm.</p>
<p id="102">"We've come too far to turn back now," he replied, pushing the heavy oak door open.</p>
<p id="103">A gust of stale wind escaped the dark corridor inside.</p>
```

### 4.2 System Instruction & XML Prompt Constraint

To strictly prevent affecting Document Mode (`DocumentChunker`), XML tag constraints are **NOT** appended globally to `renderTranslationPrompt`. Instead, `translateBatchXML` dynamically appends the structural XML constraint to the effective system instruction for batch execution:

```swift
let xmlConstraint = """

Formatting rule:
- For every input paragraph marked with <p id="X">...</p>, output the translated text wrapped in the identical <p id="X">...</p> tag.
- Never omit, merge, or change any ID attribute.
"""
let effectiveSystemInstruction = (customSystemInstruction ?? defaultSystemInstruction(from: sourceLang, to: targetLang)) + xmlConstraint
```

---

## 5. Parser & Normalization (`BatchXMLParser`)

Location: `Sources/DocTranslateApp/BatchXMLParser.swift`

### 5.1 API Contract

```swift
public struct BatchXMLParser {
    /// Parses LLM response into a dictionary of [nodeId: translatedText] and reports missing IDs
    public static func parse(
        response: String,
        expectedNodeIds: [Int]
    ) -> BatchTranslationResult
}
```

### 5.2 Parsing Pipeline
1. **Thinking Tags & Markdown Fence Stripping:**
   - Remove `<think>[\s\S]*?<\/think>` reasoning tags via `LLMTranslationService.cleanAndValidateTranslation`.
   - Strip outer ````xml ... ```` or ````markdown ... ```` code blocks if present.
2. **Defensive Regex Extraction:**
   - Use negative lookahead `(?:(?!<(?:p|h[1-6]|blockquote|li|div)\b)[\s\S])*?` so that if a closing tag is accidentally omitted by the LLM, the parser does not swallow subsequent nodes into the current one:
   - Pattern: `(?i)<(?:p|h[1-6]|blockquote|li|div)\b[^>]*?\bid=["']?(\d+)["']?[^>]*>((?:(?!<(?:p|h[1-6]|blockquote|li|div)\b)[\s\S])*?)<\/(?:p|h[1-6]|blockquote|li|div)>`
   - Captures Group 1 as `nodeId: Int` and Group 2 as `translatedContent: String`.
3. **Content Sanitization & Hallucination Filter:**
   - Trim leading and trailing whitespace/newlines only.
   - Do **NOT** strip quotation marks (`"`, `«`, `»`, `“`, `”`) as these represent essential literary dialogue formatting.
   - Discard any captured `nodeId` that is not present in `expectedNodeIds` to prevent hallucinated IDs from polluting book state.
   - Ignore empty entries.
4. **Missing Node Audit:**
   - Match `expectedNodeIds` against captured keys in `[Int: String]`.
   - Any expected ID not present is listed in `missingNodeIds`.

---

## 6. Error Handling & 2-Tier Fallback Protocol

### 6.1 Execution Ownership (`LLMTranslationService.translateBatchXML`)

`LLMTranslationService` owns the execution, parsing, network retry, cancellation checks, and 2-tier fallback loop for a single batch:

```swift
public static func translateBatchXML(
    batch: TranslationBatch,
    from sourceLang: String,
    to targetLang: String,
    config: LLMConfig,
    fallbackConfig: LLMConfig? = nil,
    customSystemInstruction: String? = nil,
    previousContext: String? = nil,
    onFallbackUsed: (@Sendable (Int, String) async -> Void)? = nil,
    onNodeCompleted: @escaping @Sendable (Int, String) async -> Void
) async throws
```

### 6.2 Low-Level Request Dispatcher

To cleanly dispatch batch requests without inheriting single-item wrappers, reusing existing robust JSON/error extraction helpers:

```swift
private static func sendRawChatCompletion(
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
    request.timeoutInterval = 300 // 5-minute timeout aligned with URLSession configuration

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

    // Provide 8192 context window specifically for Ollama endpoints (identified by port 11434 or ollama in url)
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
```

### 6.3 Execution, Cancellation & Fallback Flow:

1. **Cancellation Guard:** At each step, check `if Task.isCancelled { throw CancellationError() }`.
2. **Active Config Tracking & Primary Request:**
   - Maintain `var activeConfig = config`.
   - Build messages with `effectiveSystemInstruction`, `previousContext`, and `<p id="X">` user prompt.
   - Dispatch via `sendRawChatCompletion(messages: messages, config: activeConfig)`.
   - **Primary Network Error Handling:**
     - If the error is a `CancellationError`, re-throw immediately.
     - If `fallbackConfig` is provided:
       - Notify fallback via `await onFallbackUsed?(batch.nodes.first?.id ?? 0, "Primary batch failed, retrying on fallback config")`.
       - Retry the batch on `fallbackConfig`.
       - On success, set `activeConfig = fallbackConfig` and continue to step 3.
     - If fallback throws `CancellationError`, re-throw immediately.
     - If primary fails (and fallback retry fails or is nil):
       - Immediately degrade all nodes in this batch directly to **Tier 2 (Atomic Degradation)** using `translateItemWithFallback` (1-by-1) with the unconstrained `customSystemInstruction`.
       - For each completed node, call `await onNodeCompleted(id, translated)`.
       - **Return immediately** from `translateBatchXML`, bypassing Step 3 parsing.
3. **Parse Primary Response:** Call `let primaryResult = BatchXMLParser.parse(response: rawOutput, expectedNodeIds: batch.nodes.map(\.id))`.
   - For every successfully parsed node ID, call `await onNodeCompleted(nodeId, translatedText)`.
   - Track remaining missing IDs in mutable variable: `var missingNodeIds = primaryResult.missingNodeIds`.
4. **Missing Node Evaluation:**
   - If `missingNodeIds.isEmpty`: Batch complete. Return.
   - **Tier 1 Condition (`missingNodeIds.count < batch.nodes.count && missingNodeIds.count <= max(4, batch.nodes.count / 4)`):**
     - Filter `batch.nodes` to only those missing IDs: `let missingNodes = batch.nodes.filter { missingNodeIds.contains($0.id) }`.
     - Construct missing nodes user prompt: `"The following paragraphs were omitted. Translate them from \(sourceLang) into \(targetLang), wrapping each in its original <p id=\"X\">...</p> tag:\n\n" + missingNodes.map { "<p id=\"\($0.id)\">\($0.originalText)</p>" }.joined(separator: "\n")`.
     - Dispatch via `sendRawChatCompletion` with `effectiveSystemInstruction` and `activeConfig` inside a `do-catch` block:
       ```swift
       do {
           if Task.isCancelled { throw CancellationError() }
           let subResponse = try await sendRawChatCompletion(
               messages: [
                   ["role": "system", "content": effectiveSystemInstruction],
                   ["role": "user", "content": subUserPrompt]
               ],
               config: activeConfig
           )
           let subResult = BatchXMLParser.parse(response: subResponse, expectedNodeIds: missingNodeIds)
           for (nodeId, text) in subResult.completedTranslations {
               await onNodeCompleted(nodeId, text)
           }
           missingNodeIds = subResult.missingNodeIds
       } catch is CancellationError {
           throw CancellationError()
       } catch {
           // Network/timeout error on sub-batch; log and fall through to Tier 2
       }
       ```
   - **Tier 2 Condition (Severe truncation / 100% format refusal OR nodes still missing after Tier 1):**
     - Loop sequentially through whatever nodes remain in `missingNodeIds`:
       ```swift
       for missingId in missingNodeIds {
           if Task.isCancelled { throw CancellationError() }
           guard let node = batch.nodes.first(where: { $0.id == missingId }) else { continue }
           let (id, translated) = try await translateItemWithFallback(
               id: node.id,
               text: node.originalText,
               from: sourceLang,
               to: targetLang,
               config: activeConfig,
               fallbackConfig: fallbackConfig,
               customSystemInstruction: customSystemInstruction, // Base instruction WITHOUT xmlConstraint
               precedingContext: nil,
               onFallbackUsed: onFallbackUsed
           )
           await onNodeCompleted(id, translated)
       }
       ```
5. Guaranteed: 100% of nodes in the batch are translated and committed, and user cancellation is respected immediately at every point.

---

## 7. Integration with ViewModel & Pipelines

### 7.1 `TranslationViewModel.swift` Integration Points

All EPUB translation paths in `TranslationViewModel` are unified around `translateChapterInBatches`:
1. `translateEPUBLLM(resume: Bool)`:
   - For each chapter `0..<book.chapters.count`:
   - Runs Auto JIT Character Discovery & Micro-enrichment (`discoverCandidatesForChapter` & `autoEnrichCandidateCharacter`) exactly as before.
   - Then delegates translation to `try await translateChapterInBatches(chapterIdx: cIdx, config: config, fallbackConfig: fallbackConfig)`.
2. `fallbackToOllamaEPUB()`: Iterates untranslated chapters, calling `try await translateChapterInBatches(chapterIdx: cIdx, config: ollamaConfig, fallbackConfig: nil)`.
3. `performTranslateSingleChapter(chapterIndex: Int)`: When `engine != .apple`, calls `try await translateChapterInBatches(chapterIdx: chapterIndex, config: activeLLMConfig, fallbackConfig: fallbackConfig)` directly; when `engine == .apple`, retains the Apple Translation on-device session logic.

#### Documenting `updateEPUBNodeTranslation` Parameter Update:
Update `updateEPUBNodeTranslation` in `TranslationViewModel.swift`:
```swift
@MainActor
private func updateEPUBNodeTranslation(
    chapterIdx: Int,
    nodeId: Int,
    translatedText: String,
    saveDisk: Bool = true // Added default true parameter, preserving existing synchronous signature
)
```
When called from `translateBatchXML`'s `onNodeCompleted`, `saveDisk: false` is passed. Disk checkpointing is executed once per completed batch at the batch boundary via `saveCheckpoint()`.

#### Complete Chapter Batch Execution Implementation:
```swift
private func translateChapterInBatches(
    chapterIdx: Int,
    config: LLMConfig,
    fallbackConfig: LLMConfig?
) async throws {
    guard let currentBook = self.currentEPUB, chapterIdx < currentBook.chapters.count else { return }
    let chapter = currentBook.chapters[chapterIdx]

    let batches = BatchChunker.createBatches(
        from: chapter.nodes,
        chapterIndex: chapterIdx,
        targetWordCount: batchWordLimit
    )

    guard !batches.isEmpty else {
        if !chapter.isTranslated {
            var updatedBook = currentBook
            updatedBook.chapters[chapterIdx].isTranslated = true
            self.currentEPUB = updatedBook
            completedEPUBChapters += 1
        }
        return
    }

    let srcName = sourceLanguage.name
    let tgtName = targetLanguage.name
    let baseInstruction = currentTranslationSystemInstruction(from: srcName, to: tgtName)
    let customInstruction = PronounPromptBuilder.buildSystemInstruction(
        baseInstruction: baseInstruction,
        targetLanguageCode: targetLanguage.id,
        bible: characterBible ?? currentEPUB?.characterBible,
        chapterText: chapter.originalContent,
        chapterId: chapter.id
    )

    // Rolling context resets to nil at the start of each chapter
    var rollingContext: String? = nil

    // When resuming mid-chapter, extract up to 2 trailing translated nodes from the current book state on MainActor
    let completedNodes = chapter.nodes.filter { !$0.translatedText.isEmpty }
    if !completedNodes.isEmpty {
        let lastNodes = Array(completedNodes.suffix(2))
        rollingContext = lastNodes.map { "Original: \"\($0.originalText)\"\nTranslated: \"\($0.translatedText)\"" }.joined(separator: "\n\n")
    }

    for (batchIdx, batch) in batches.enumerated() {
        if isCancelled { break }

        statusMessage = "Translating Chapter \(chapterIdx + 1) of \(currentBook.chapters.count) (Batch \(batchIdx + 1)/\(batches.count)): \(chapter.title)..."

        try await LLMTranslationService.translateBatchXML(
            batch: batch,
            from: srcName,
            to: tgtName,
            config: config,
            fallbackConfig: fallbackConfig,
            customSystemInstruction: customInstruction,
            previousContext: rollingContext,
            onFallbackUsed: { [weak self] nodeId, reason in
                Task { @MainActor in
                    self?.fallbackNotice = "Paragraph #\(nodeId) used fallback: \(reason)"
                }
            },
            onNodeCompleted: { [weak self] nodeId, translatedText in
                await MainActor.run { self?.updateEPUBNodeTranslation(chapterIdx: chapterIdx, nodeId: nodeId, translatedText: translatedText, saveDisk: false) }
            }
        )

        // Save checkpoint at the batch boundary
        saveCheckpoint()

        // Update rollingContext for next batch using the trailing nodes of this batch
        if let book = self.currentEPUB, chapterIdx < book.chapters.count {
            let batchNodeIds = Set(batch.nodes.map(\.id))
            let batchCompleted = book.chapters[chapterIdx].nodes.filter { batchNodeIds.contains($0.id) && !$0.translatedText.isEmpty }
            if !batchCompleted.isEmpty {
                let lastNodes = Array(batchCompleted.suffix(2))
                rollingContext = lastNodes.map { "Original: \"\($0.originalText)\"\nTranslated: \"\($0.translatedText)\"" }.joined(separator: "\n\n")
            }
        }
    }

    // Apply translations to chapter XHTML and increment completed chapters safely
    guard !isCancelled else { return }
    if var updatedBook = self.currentEPUB, chapterIdx < updatedBook.chapters.count {
        let wasAlreadyTranslated = updatedBook.chapters[chapterIdx].isTranslated
        EPUBProcessor.applyTranslations(to: &updatedBook.chapters[chapterIdx])
        if !wasAlreadyTranslated {
            completedEPUBChapters += 1
        }
        self.currentEPUB = updatedBook
    }
}
```

### 7.2 Configuration & Settings
- In `TranslationViewModel.swift`:
  ```swift
  @Published public var batchWordLimit: Int = 1200 {
      didSet {
          EnvConfigManager.saveBatchWordLimit(batchWordLimit)
      }
  }
  ```
  In `TranslationViewModel.init()`:
  ```swift
  self.batchWordLimit = EnvConfigManager.loadBatchWordLimit()
  ```
- In `EnvConfigManager.swift`:
  Add `loadBatchWordLimit() -> Int` (defaults to 1200) and `saveBatchWordLimit(_ limit: Int)` persisted via `UserDefaults` (key: `"EPUB_BATCH_WORD_LIMIT"`).
- In `DocTranslateApp.swift` (`engineSettingsView`):
  Add a stepper control for "Batch Size: \(viewModel.batchWordLimit) words per request" with range 500...2,500 words (step: 100), accompanied by a tooltip explaining token and context tradeoffs (e.g. recommending 600–800 words for local Ollama models with 2K/4K limits, and 1,200–1,500 words for cloud models).

---

## 8. Testing Strategy

1. **`BatchChunkerTests`:**
   - Verify nodes under target word count form 1 batch.
   - Verify nodes over target word count split into multiple batches at whole node boundaries without mutating internal node text.
   - Verify heading boundaries trigger clean batch splits.
2. **`BatchXMLParserTests`:**
   - Parse standard `<p id="1">Text</p>`.
   - Parse single-quoted `<p id='2'>Text</p>` and unquoted `<p id=3>Text</p>`.
   - Parse outputs wrapped in markdown code blocks.
   - Verify preservation of inline tags (`<em>`, `<b>`, `<span class="...">`) and dialogue quotation marks (`"`, `«`, `»`) inside tags.
   - Verify unclosed tag isolation (preventing regex swallowing of subsequent paragraphs).
   - Verify rejection of hallucinated IDs not present in `expectedNodeIds`.
   - Identify missing node IDs correctly.
3. **`FallbackIntegrationTests`:**
   - Simulate a response missing node ID 2 and verify Tier 1/Tier 2 recovery.
