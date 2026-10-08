# Batched XML Chunking & Rolling Context Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement batched paragraph translation using XML tags (`<p id="X">`) and rolling context for EPUB translation, reducing LLM token consumption by 85–90% while improving narrative coherence and eliminating per-paragraph tone drift.

**Architecture:** A new `BatchChunker` divides untranslated chapter nodes into contiguous batches of ~1,000–1,500 words respecting heading boundaries. `BatchXMLParser` frames prompt user messages and parses responses with defensive regexes. `LLMTranslationService.translateBatchXML` manages request dispatch, rolling context injection, and a 2-tier fallback system (Tier 1 sub-batch retry, Tier 2 atomic node degradation) before committing completed batches to `TranslationViewModel`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing framework (`import Testing`), Foundation (`URLSession`, `NSRegularExpression`, `JSONSerialization`), EPUB XHTML parsing.

---

## Chunk 1: Core Engine (Chunker, XML Parser & LLM Batch Service)

### Task 1: Create Data Structures and Batch Chunker (`BatchChunker.swift`)

**Files:**
- Create: `Sources/DocTranslateApp/BatchChunker.swift`
- Test: `Tests/DocTranslateAppTests/BatchChunkerTests.swift`

- [ ] **Step 1: Write failing tests for `BatchChunker`**

Create `Tests/DocTranslateAppTests/BatchChunkerTests.swift`:
```swift
import Testing
import Foundation
@testable import DocTranslateApp

@Suite("Batch Chunker Tests")
struct BatchChunkerTests {

    @Test("Empty node list produces no batches")
    func testEmptyNodes() {
        let batches = BatchChunker.createBatches(from: [], chapterIndex: 0)
        #expect(batches.isEmpty)
    }

    @Test("Nodes under target word count form a single batch")
    func testSingleBatch() {
        let nodes = [
            TranslatableNode(id: 1, originalText: "Paragraph one with some text.", fullMatch: "<p>Paragraph one with some text.</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 2, originalText: "Paragraph two with another sentence.", fullMatch: "<p>Paragraph two with another sentence.</p>", tagOpen: "<p>", tagClose: "</p>")
        ]
        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 0, targetWordCount: 1200)

        #expect(batches.count == 1)
        #expect(batches[0].id == 0)
        #expect(batches[0].chapterIndex == 0)
        #expect(batches[0].nodes.count == 2)
        #expect(batches[0].wordCount == 10)
    }

    @Test("Nodes exceeding target word count split into multiple contiguous batches without mutating node text")
    func testWordLimitSplitting() {
        let text50Words = Array(repeating: "word", count: 50).joined(separator: " ")
        var nodes: [TranslatableNode] = []
        for i in 1...10 {
            nodes.append(TranslatableNode(
                id: i,
                originalText: "Node \(i) \(text50Words)",
                fullMatch: "<p>Node \(i) \(text50Words)</p>",
                tagOpen: "<p>",
                tagClose: "</p>"
            ))
        }

        // Each node is ~52 words. With target 150 words, each batch should hold ~3 nodes.
        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 1, targetWordCount: 150)

        #expect(batches.count > 1)
        let totalBatchedNodes = batches.reduce(0) { $0 + $1.nodes.count }
        #expect(totalBatchedNodes == 10)
        #expect(batches[0].nodes.first?.originalText.hasPrefix("Node 1") == true)
    }

    @Test("Heading boundary with substantial accumulated words triggers batch split")
    func testHeadingSplits() {
        let text250Words = Array(repeating: "word", count: 250).joined(separator: " ")
        let nodes = [
            TranslatableNode(id: 1, originalText: text250Words, fullMatch: "<p>\(text250Words)</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 2, originalText: "Section Two Title", fullMatch: "<h2>Section Two Title</h2>", tagOpen: "<h2>", tagClose: "</h2>"),
            TranslatableNode(id: 3, originalText: "Content of section two.", fullMatch: "<p>Content of section two.</p>", tagOpen: "<p>", tagClose: "</p>")
        ]

        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 0, targetWordCount: 1200)

        #expect(batches.count == 2)
        #expect(batches[0].nodes.count == 1)
        #expect(batches[0].nodes[0].id == 1)
        #expect(batches[1].nodes.count == 2)
        #expect(batches[1].nodes[0].id == 2)
    }

    @Test("Consecutive headings do not create single-word micro batches")
    func testConsecutiveHeadingsDoNotMicroSplit() {
        let nodes = [
            TranslatableNode(id: 1, originalText: "Chapter 1", fullMatch: "<h1>Chapter 1</h1>", tagOpen: "<h1>", tagClose: "</h1>"),
            TranslatableNode(id: 2, originalText: "The Departure", fullMatch: "<h2>The Departure</h2>", tagOpen: "<h2>", tagClose: "</h2>"),
            TranslatableNode(id: 3, originalText: "The sun was rising over the distant hills.", fullMatch: "<p>The sun was rising...</p>", tagOpen: "<p>", tagClose: "</p>")
        ]

        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 0, targetWordCount: 1200)

        #expect(batches.count == 1)
        #expect(batches[0].nodes.count == 3)
    }

    @Test("Already translated nodes preserve contiguity and are omitted from batches")
    func testOmitsAlreadyTranslatedNodes() {
        var node1 = TranslatableNode(id: 1, originalText: "First", fullMatch: "<p>First</p>", tagOpen: "<p>", tagClose: "</p>")
        node1.translatedText = "Đầu tiên"
        let node2 = TranslatableNode(id: 2, originalText: "Second", fullMatch: "<p>Second</p>", tagOpen: "<p>", tagClose: "</p>")

        let batches = BatchChunker.createBatches(from: [node1, node2], chapterIndex: 0)

        #expect(batches.count == 1)
        #expect(batches[0].nodes.count == 1)
        #expect(batches[0].nodes[0].id == 2)
    }

    @Test("Max node ceiling of 30 prevents infinite batch size on zero-space languages")
    func testMaxNodeCeiling() {
        var nodes: [TranslatableNode] = []
        for i in 1...65 {
            nodes.append(TranslatableNode(id: i, originalText: "测试段落\(i)", fullMatch: "<p>测试段落\(i)</p>", tagOpen: "<p>", tagClose: "</p>"))
        }

        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 0, targetWordCount: 5000)

        #expect(batches.count >= 3)
        #expect(batches[0].nodes.count <= 30)
        #expect(batches[1].nodes.count <= 30)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BatchChunkerTests`
Expected: Compilation failure (`Cannot find 'BatchChunker' in scope`).

- [ ] **Step 3: Implement `BatchChunker.swift`**

Create `Sources/DocTranslateApp/BatchChunker.swift`:
```swift
import Foundation

public struct TranslationBatch: Identifiable, Sendable {
    public let id: Int
    public let chapterIndex: Int
    public let nodes: [TranslatableNode]
    public let targetWordCount: Int

    public var wordCount: Int {
        nodes.reduce(0) { $0 + max(1, $1.originalText.split { $0.isWhitespace || $0.isNewline }.count) }
    }

    public init(id: Int, chapterIndex: Int, nodes: [TranslatableNode], targetWordCount: Int) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.nodes = nodes
        self.targetWordCount = targetWordCount
    }
}

public struct BatchTranslationResult: Sendable {
    public let completedTranslations: [Int: String]
    public let missingNodeIds: [Int]
    public let rawResponse: String

    public init(completedTranslations: [Int: String], missingNodeIds: [Int], rawResponse: String) {
        self.completedTranslations = completedTranslations
        self.missingNodeIds = missingNodeIds
        self.rawResponse = rawResponse
    }
}

public struct BatchChunker: Sendable {
    public static let defaultTargetWordCount = 1200
    public static let maxNodesPerBatch = 30

    public static func createBatches(
        from nodes: [TranslatableNode],
        chapterIndex: Int,
        targetWordCount: Int = defaultTargetWordCount
    ) -> [TranslationBatch] {
        guard !nodes.isEmpty else { return [] }

        let safeTargetWords = max(200, targetWordCount)
        var batches: [TranslationBatch] = []
        var currentNodes: [TranslatableNode] = []
        var currentWords = 0
        var batchId = 0

        for node in nodes {
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BatchChunkerTests`
Expected: PASS (All 7 tests in `BatchChunkerTests` pass).

- [ ] **Step 5: Check git status or note checkpoint**

Run: `swift build` to ensure clean SPM compilation.

---

### Task 2: Create Batch XML Parser & Prompt Formatter (`BatchXMLParser.swift`)

**Files:**
- Create: `Sources/DocTranslateApp/BatchXMLParser.swift`
- Test: `Tests/DocTranslateAppTests/BatchXMLParserTests.swift`

- [ ] **Step 1: Write failing tests for `BatchXMLParser`**

Create `Tests/DocTranslateAppTests/BatchXMLParserTests.swift`:
```swift
import Testing
import Foundation
@testable import DocTranslateApp

@Suite("Batch XML Parser Tests")
struct BatchXMLParserTests {

    @Test("Builds user prompt with formatted paragraphs and no context")
    func testBuildUserPromptWithoutContext() {
        let nodes = [
            TranslatableNode(id: 101, originalText: "Hello world.", fullMatch: "<p>Hello world.</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 102, originalText: "Second line.", fullMatch: "<p>Second line.</p>", tagOpen: "<p>", tagClose: "</p>")
        ]

        let prompt = BatchXMLParser.buildUserPrompt(nodes: nodes, from: "English", to: "Vietnamese", previousContext: nil)

        #expect(!prompt.contains("<prev_context>"))
        #expect(prompt.contains("<p id=\"101\">Hello world.</p>"))
        #expect(prompt.contains("<p id=\"102\">Second line.</p>"))
        #expect(prompt.contains("from English into Vietnamese"))
    }

    @Test("Builds user prompt with bounded rolling context")
    func testBuildUserPromptWithContext() {
        let nodes = [
            TranslatableNode(id: 101, originalText: "Hello world.", fullMatch: "<p>Hello world.</p>", tagOpen: "<p>", tagClose: "</p>")
        ]
        let context = "Original: \"Prev\"\nTranslated: \"Trước\""

        let prompt = BatchXMLParser.buildUserPrompt(nodes: nodes, from: "English", to: "Vietnamese", previousContext: context)

        #expect(prompt.contains("<prev_context>"))
        #expect(prompt.contains("Original: \"Prev\""))
        #expect(prompt.contains("<p id=\"101\">Hello world.</p>"))
    }

    @Test("Parses standard XML paragraph tags and ignores thinking tags")
    func testStandardXMLParsing() {
        let rawResponse = """
        <think>Translating chapter content...</think>
        <p id="1">Xin chào thế giới.</p>
        <p id="2">Đoạn văn thứ hai.</p>
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [1, 2])

        #expect(result.missingNodeIds.isEmpty)
        #expect(result.completedTranslations[1] == "Xin chào thế giới.")
        #expect(result.completedTranslations[2] == "Đoạn văn thứ hai.")
    }

    @Test("Preserves dialogue quotation marks and inline formatting")
    func testPreservesQuotesAndInlineTags() {
        let rawResponse = """
        <p id="10">"Chúng ta không thể quay lại," chàng nói.</p>
        <p id="11">Cô ấy nhìn vào <em>ánh lửa</em> bập bùng.</p>
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [10, 11])

        #expect(result.completedTranslations[10] == "\"Chúng ta không thể quay lại,\" chàng nói.")
        #expect(result.completedTranslations[11] == "Cô ấy nhìn vào <em>ánh lửa</em> bập bùng.")
    }

    @Test("Parses attributes with varying quotes and non-p tag variants")
    func testAttributeAndTagVariants() {
        let rawResponse = """
        ```xml
        <h2 id='100'>Chương 1</h2>
        <p class="story" id=101>Nội dung câu chuyện.</p>
        <blockquote id="102">Một danh ngôn.</blockquote>
        ```
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [100, 101, 102])

        #expect(result.missingNodeIds.isEmpty)
        #expect(result.completedTranslations[100] == "Chương 1")
        #expect(result.completedTranslations[101] == "Nội dung câu chuyện.")
        #expect(result.completedTranslations[102] == "Một danh ngôn.")
    }

    @Test("Identifies missing node IDs and discards hallucinated IDs")
    func testMissingAndHallucinatedIDs() {
        let rawResponse = """
        <p id="1">Đoạn một.</p>
        <p id="999">Đoạn ảo hallucination.</p>
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [1, 2, 3])

        #expect(result.completedTranslations[1] == "Đoạn một.")
        #expect(result.completedTranslations[999] == nil)
        #expect(result.missingNodeIds == [2, 3])
    }

    @Test("Defensive regex prevents unclosed tags from swallowing subsequent paragraphs")
    func testUnclosedTagDoesNotSwallowNextNode() {
        let rawResponse = """
        <p id="1">Đoạn một không có đóng thẻ
        <p id="2">Đoạn hai có đóng thẻ.</p>
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [1, 2])

        #expect(result.completedTranslations[2] == "Đoạn hai có đóng thẻ.")
        #expect(result.missingNodeIds == [1])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BatchXMLParserTests`
Expected: Compilation failure (`Cannot find 'BatchXMLParser' in scope`).

- [ ] **Step 3: Implement `BatchXMLParser.swift`**

Create `Sources/DocTranslateApp/BatchXMLParser.swift`:
```swift
import Foundation

public struct BatchXMLParser: Sendable {

    /// Formats batch nodes and optional rolling context into a parameterized LLM user prompt
    public static func buildUserPrompt(
        nodes: [TranslatableNode],
        from sourceLang: String,
        to targetLang: String,
        previousContext: String? = nil
    ) -> String {
        var sections: [String] = []

        if let context = previousContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
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

    /// Parses LLM response into a dictionary of [nodeId: translatedText] and reports missing IDs
    public static func parse(
        response: String,
        expectedNodeIds: [Int]
    ) -> BatchTranslationResult {
        // 1. Clean thinking tags and markdown code blocks
        var cleaned = LLMTranslationService.cleanAndValidateTranslation(rawResponse: response, originalText: "")

        if cleaned.hasPrefix("```xml") {
            cleaned = String(cleaned.dropFirst(6))
        } else if cleaned.hasPrefix("```markdown") {
            cleaned = String(cleaned.dropFirst(11))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        var completed: [Int: String] = [:]
        let expectedSet = Set(expectedNodeIds)

        // 2. Defensive regex preventing unclosed tags from swallowing following tags
        let pattern = #"(?i)<(?:p|h[1-6]|blockquote|li|div)\b[^>]*?\bid=["']?(\d+)["']?[^>]*>((?:(?!<(?:p|h[1-6]|blockquote|li|div)\b)[\s\S])*?)<\/(?:p|h[1-6]|blockquote|li|div)>"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let ns = cleaned as NSString
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let idString = ns.substring(with: match.range(at: 1))
                let content = ns.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let nodeId = Int(idString), expectedSet.contains(nodeId), !content.isEmpty {
                    completed[nodeId] = content
                }
            }
        }

        // 3. Audit missing IDs
        let missing = expectedNodeIds.filter { completed[$0] == nil }

        return BatchTranslationResult(
            completedTranslations: completed,
            missingNodeIds: missing,
            rawResponse: response
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BatchXMLParserTests`
Expected: PASS (All 7 tests in `BatchXMLParserTests` pass).

- [ ] **Step 5: Verify build**

Run: `swift build`

---

### Task 3: Implement Low-Level Dispatch & 2-Tier Fallback in LLM Service (`LLMTranslationService.swift`)

**Files:**
- Modify: `Sources/DocTranslateApp/LLMTranslationService.swift`
- Test: `Tests/DocTranslateAppTests/LLMBatchTranslationTests.swift`

- [ ] **Step 1: Write unit tests for batch XML translation and error recovery**

Create `Tests/DocTranslateAppTests/LLMBatchTranslationTests.swift`:
```swift
import Testing
import Foundation
@testable import DocTranslateApp

@Suite("LLM Batch XML Translation Tests")
struct LLMBatchTranslationTests {

    @Test("BatchXMLParser handles empty response gracefully")
    func testEmptyResponse() {
        let result = BatchXMLParser.parse(response: "", expectedNodeIds: [1, 2])
        #expect(result.completedTranslations.isEmpty)
        #expect(result.missingNodeIds == [1, 2])
    }

    @Test("BatchXMLParser extracts translations and reports only omitted node IDs")
    func testOmittedNodes() {
        let response = "<p id=\"1\">Chương 1</p>"
        let result = BatchXMLParser.parse(response: response, expectedNodeIds: [1, 2, 3])

        #expect(result.completedTranslations[1] == "Chương 1")
        #expect(result.missingNodeIds == [2, 3])
    }

    @Test("Sub-batch prompt accurately isolates missing nodes")
    func testSubBatchPrompt() {
        let missingNodes = [
            TranslatableNode(id: 2, originalText: "Second", fullMatch: "<p>Second</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 3, originalText: "Third", fullMatch: "<p>Third</p>", tagOpen: "<p>", tagClose: "</p>")
        ]

        let prompt = BatchXMLParser.buildUserPrompt(nodes: missingNodes, from: "English", to: "Vietnamese", previousContext: nil)
        #expect(prompt.contains("<p id=\"2\">Second</p>"))
        #expect(prompt.contains("<p id=\"3\">Third</p>"))
        #expect(!prompt.contains("<p id=\"1\">"))
    }


    @Test("Simulates Tier 1 sub-batch recovery and Tier 2 atomic fallback for missing nodes")
    func testFallbackSimulation() {
        let expectedIds = [1, 2, 3, 4]
        // Primary response misses node 2 and 4
        let primaryResponse = "<p id=\"1\">Đoạn 1</p><p id=\"3\">Đoạn 3</p>"
        let primaryResult = BatchXMLParser.parse(response: primaryResponse, expectedNodeIds: expectedIds)

        #expect(primaryResult.completedTranslations.count == 2)
        #expect(primaryResult.missingNodeIds == [2, 4])

        // Tier 1 sub-batch recovers node 2 but misses node 4
        let subResponse = "<p id=\"2\">Đoạn 2</p>"
        let subResult = BatchXMLParser.parse(response: subResponse, expectedNodeIds: primaryResult.missingNodeIds)

        var allCompleted = primaryResult.completedTranslations
        for (id, text) in subResult.completedTranslations {
            allCompleted[id] = text
        }
        let remainingMissing = subResult.missingNodeIds

        #expect(allCompleted[1] == "Đoạn 1")
        #expect(allCompleted[2] == "Đoạn 2")
        #expect(allCompleted[3] == "Đoạn 3")
        #expect(remainingMissing == [4])
        // Remaining node 4 will be handled by Tier 2 atomic fallback
    }

    @Test("translateBatchXML throws invalidURL when baseURL is invalid")
    func testInvalidURLThrows() async {
        let batch = TranslationBatch(
            id: 1,
            chapterIndex: 0,
            nodes: [TranslatableNode(id: 1, originalText: "Hello", fullMatch: "<p>Hello</p>", tagOpen: "<p>", tagClose: "</p>")],
            targetWordCount: 1200
        )
        let invalidConfig = LLMConfig(baseURL: "invalid-url", apiKey: "", modelName: "test")

        do {
            try await LLMTranslationService.translateBatchXML(
                batch: batch,
                from: "English",
                to: "Vietnamese",
                config: invalidConfig
            ) { _, _ in }
            #expect(Bool(false), "Expected invalidURL error")
        } catch let error as LLMError {
            switch error {
            case .invalidURL:
                #expect(true)
            default:
                #expect(Bool(false), "Expected invalidURL, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected LLMError, got \(error)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LLMBatchTranslationTests`
Expected: Compilation failure (`Type LLMTranslationService has no member translateBatchXML`).

- [ ] **Step 3: Add `sendRawChatCompletion` and `translateBatchXML` to `LLMTranslationService.swift`**

Add public methods to `Sources/DocTranslateApp/LLMTranslationService.swift`:
```swift
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
        fallbackConfig: LLMConfig? = nil,
        customSystemInstruction: String? = nil,
        previousContext: String? = nil,
        onFallbackUsed: (@Sendable (Int, String) async -> Void)? = nil,
        onNodeCompleted: @escaping @Sendable (Int, String) async -> Void
    ) async throws {
        guard !batch.nodes.isEmpty else { return }
        if Task.isCancelled { throw CancellationError() }

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
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw CancellationError()
        } catch {
            if let fallback = fallbackConfig {
                await onFallbackUsed?(batch.nodes.first?.id ?? 0, "Primary batch failed, retrying on fallback config")
                activeConfig = fallback
                do {
                    if Task.isCancelled { throw CancellationError() }
                    rawOutput = try await sendRawChatCompletion(
                        messages: [
                            ["role": "system", "content": effectiveSystemInstruction],
                            ["role": "user", "content": userPrompt]
                        ],
                        config: activeConfig
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch let urlErr as URLError where urlErr.code == .cancelled {
                    throw CancellationError()
                } catch {
                    // Fallback failed as well, trigger Tier 2 immediately
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
                    fallbackConfig: fallbackConfig,
                    customSystemInstruction: customSystemInstruction,
                    precedingContext: nil,
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
                fallbackConfig: fallbackConfig,
                customSystemInstruction: customSystemInstruction,
                precedingContext: nil,
                onFallbackUsed: onFallbackUsed
            )
            await onNodeCompleted(id, translated)
        }
    }
```

- [ ] **Step 4: Run all tests to verify they pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Verify build**

Run: `swift build`

---

## Chunk 2: Integration & UI (Config Persistence, ViewModel & UI Settings)

### Task 4: Add Batch Word Limit Configuration & Persistence (`EnvConfigManager.swift`)

**Files:**
- Modify: `Sources/DocTranslateApp/EnvConfigManager.swift`
- Test: `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`

- [ ] **Step 1: Write test for batch word limit persistence in `DocTranslateAppTests.swift`**

Add test to `EnvConfigManagerTests` suite in `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`:
```swift
    @Test("Loads and saves batch word limit")
    func testBatchWordLimitPersistence() {
        let initial = EnvConfigManager.loadBatchWordLimit()
        defer { EnvConfigManager.saveBatchWordLimit(initial) }

        EnvConfigManager.saveBatchWordLimit(1500)
        #expect(EnvConfigManager.loadBatchWordLimit() == 1500)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testBatchWordLimitPersistence`
Expected: Compilation failure (`Type 'EnvConfigManager' has no member 'loadBatchWordLimit'`).

- [ ] **Step 3: Implement `loadBatchWordLimit` and `saveBatchWordLimit` in `EnvConfigManager.swift`**

Add to `Sources/DocTranslateApp/EnvConfigManager.swift` adhering to GUI > .env > default precedence:
```swift
    public static let batchWordLimitKey = "EPUB_BATCH_WORD_LIMIT"

    public static func loadBatchWordLimit() -> Int {
        let saved = UserDefaults.standard.integer(forKey: batchWordLimitKey)
        if saved >= 500 {
            return min(max(500, saved), 2500)
        }
        if let envVal = loadEnvVariables()[batchWordLimitKey], let parsed = Int(envVal), parsed >= 500 {
            return min(max(500, parsed), 2500)
        }
        return 1200
    }

    public static func saveBatchWordLimit(_ limit: Int) {
        let safeLimit = min(max(500, limit), 2500)
        UserDefaults.standard.set(safeLimit, forKey: batchWordLimitKey)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testBatchWordLimitPersistence`
Expected: PASS.

---

### Task 5: Integrate Chapter Batch Execution in `TranslationViewModel.swift`

**Files:**
- Modify: `Sources/DocTranslateApp/TranslationViewModel.swift`
- Test: `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`

- [ ] **Step 1: Write unit test for `TranslationViewModel.batchWordLimit` in `DocTranslateAppTests.swift`**

Add test to `TranslationViewModelTests` suite in `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`:
```swift
    @Test("TranslationViewModel initializes and updates batch word limit")
    @MainActor
    func testViewModelBatchWordLimit() {
        let vm = TranslationViewModel()
        let initial = vm.batchWordLimit
        defer { vm.batchWordLimit = initial }

        #expect(initial >= 500)
        vm.batchWordLimit = 1600
        #expect(EnvConfigManager.loadBatchWordLimit() == 1600)
    }
```

- [ ] **Step 2: Update `batchWordLimit` property and `updateEPUBNodeTranslation` signature in `TranslationViewModel.swift`**

In `Sources/DocTranslateApp/TranslationViewModel.swift`:
1. Add property around line 125:
```swift
    @Published public var batchWordLimit: Int = 1200 {
        didSet {
            EnvConfigManager.saveBatchWordLimit(batchWordLimit)
        }
    }
```
2. In `init()`, initialize from config:
```swift
        self.batchWordLimit = EnvConfigManager.loadBatchWordLimit()
```
3. Update `updateEPUBNodeTranslation` implementation:
```swift
    func updateEPUBNodeTranslation(chapterIdx: Int, nodeId: Int, translatedText: String, saveDisk: Bool = true) {
        guard !isCancelled, var book = currentEPUB else { return }
        if let nIdx = book.chapters[chapterIdx].nodes.firstIndex(where: { $0.id == nodeId }) {
            book.chapters[chapterIdx].nodes[nIdx].translatedText = translatedText
            self.currentEPUB = book
            self.currentEPUBNodeProgress.completed += 1
            updateETA(currentDone: self.currentEPUBNodeProgress.completed, total: self.currentEPUBNodeProgress.total)
            if saveDisk && (self.currentEPUBNodeProgress.completed % 3 == 0 || self.currentEPUBNodeProgress.completed == self.currentEPUBNodeProgress.total) {
                saveCheckpoint()
            }
        }
    }
```

- [ ] **Step 3: Implement `translateChapterInBatches` in `TranslationViewModel.swift`**

Add private helper method to `TranslationViewModel.swift`:
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

        var rollingContext: String? = nil
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
                    await MainActor.run {
                        self?.fallbackNotice = "Paragraph #\(nodeId) used fallback: \(reason)"
                    }
                },
                onNodeCompleted: { [weak self] nodeId, translatedText in
                    await MainActor.run {
                        self?.updateEPUBNodeTranslation(chapterIdx: chapterIdx, nodeId: nodeId, translatedText: translatedText, saveDisk: false)
                    }
                }
            )

            saveCheckpoint()

            if let book = self.currentEPUB, chapterIdx < book.chapters.count {
                let batchNodeIds = Set(batch.nodes.map(\.id))
                let batchCompleted = book.chapters[chapterIdx].nodes.filter { batchNodeIds.contains($0.id) && !$0.translatedText.isEmpty }
                if !batchCompleted.isEmpty {
                    let lastNodes = Array(batchCompleted.suffix(2))
                    rollingContext = lastNodes.map { "Original: \"\($0.originalText)\"\nTranslated: \"\($0.translatedText)\"" }.joined(separator: "\n\n")
                }
            }
        }

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

- [ ] **Step 4: Refactor `translateEPUBLLM`, `fallbackToOllamaEPUB`, and `performTranslateSingleChapter`**

1. In `translateEPUBLLM(resume: Bool)`:
Clean up any unused outer `srcName` / `tgtName` variables.
Keep the `guard !untranslatedItems.isEmpty` check and the JIT character discovery block. Replace the prompt building, `LLMTranslationService.translateBatch`, and outer `applyTranslations`/`completedEPUBChapters` calls with:
```swift
    try await translateChapterInBatches(chapterIdx: chapterIdx, config: config, fallbackConfig: fallbackConfig)
```

2. In `fallbackToOllamaEPUB()`:
Inside `for chapterIdx in 0..<book.chapters.count`:
```swift
    if isCancelled { break }
    guard let currentBook = self.currentEPUB, chapterIdx < currentBook.chapters.count else { break }
    let chapter = currentBook.chapters[chapterIdx]
    let hasUntranslated = chapter.nodes.contains(where: { $0.translatedText.isEmpty })

    guard hasUntranslated else {
        if !chapter.isTranslated {
            var updatedBook = currentBook
            updatedBook.chapters[chapterIdx].isTranslated = true
            self.currentEPUB = updatedBook
            completedEPUBChapters += 1
        }
        continue
    }

    statusMessage = "Translating Chapter \(chapterIdx + 1) via Ollama (fallback): \(chapter.title)..."
    try await translateChapterInBatches(chapterIdx: chapterIdx, config: config, fallbackConfig: nil)
```

3. In `performTranslateSingleChapter(chapterIdx: Int)`:
In the `else` (non-apple) branch, replace the `LLMTranslationService.translateBatch` call and duplicate `applyTranslations` with:
```swift
    do {
        try await translateChapterInBatches(chapterIdx: chapterIdx, config: config, fallbackConfig: fallbackConfig)
        statusMessage = "Finished translating Chapter \(chapterIdx + 1) via \(engine.rawValue)!"
        saveCheckpoint()
    } catch {
        errorMessage = "Translation failed: \(error.localizedDescription)"
    }
```

- [ ] **Step 5: Run test suite to verify tests pass**

Run: `swift test --filter testViewModelBatchWordLimit`
Run: `swift test`
Expected: PASS (All tests pass).

---

### Task 6: Add Batch Word Limit Controls in Engine Settings UI (`DocTranslateApp.swift`)

**Files:**
- Modify: `Sources/DocTranslateApp/DocTranslateApp.swift`

- [ ] **Step 1: Add Batch Size Stepper to `engineSettingsView` in `DocTranslateApp.swift`**

In `Sources/DocTranslateApp/DocTranslateApp.swift`, locate `engineSettingsView`. Immediately following the `if viewModel.engine == .ollama { ollamaSettingsForm } else { openAISettingsForm }` block, above the following `Divider()`, add:
```swift
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Batch Size:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(viewModel.batchWordLimit) words/req")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.accentColor)
                }

                Stepper(
                    value: $viewModel.batchWordLimit,
                    in: 500...2500,
                    step: 100
                ) {
                    Text("Chunk size per API call")
                        .font(.caption)
                }

                Text("Batches consecutive paragraphs using XML tags. 1,000–1,500 words is optimal for cloud models; 600–800 words for local Ollama.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
```

- [ ] **Step 2: Run full build and test**

Run: `swift test`
Run: `./bundle.sh`
Expected: Test suites pass; App successfully re-bundled and signed.

- [ ] **Step 3: Verify app bundle launch and responsiveness**

Run: `open DocTranslateApp.app` and verify the settings popover opens cleanly without errors.
