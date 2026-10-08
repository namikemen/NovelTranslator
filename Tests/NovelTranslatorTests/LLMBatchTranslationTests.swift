import Testing
import Foundation
@testable import NovelTranslator

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

    @Test("TemporaryFallbackTracker limits consecutive fallbacks to 2 and resets on success")
    func testTemporaryFallbackTrackerLimitsAndReset() async {
        let tracker = TemporaryFallbackTracker(maxConsecutiveFallbacks: 2)

        // 1st failure allowed
        let first = await tracker.recordAPIFailureAndRequestFallback()
        #expect(first.allowed == true)
        #expect(first.count == 1)

        // 2nd failure allowed
        let second = await tracker.recordAPIFailureAndRequestFallback()
        #expect(second.allowed == true)
        #expect(second.count == 2)

        // 3rd failure disallowed (limit reached)
        let third = await tracker.recordAPIFailureAndRequestFallback()
        #expect(third.allowed == false)
        #expect(third.count == 2)

        // API success resets consecutive count
        await tracker.recordAPISuccess()
        #expect(await tracker.consecutiveFailures == 0)

        // Now failure is allowed again
        let fourth = await tracker.recordAPIFailureAndRequestFallback()
        #expect(fourth.allowed == true)
        #expect(fourth.count == 1)
    }

    @Test("translateBatch uses Apple fallback for up to 2 sentences and halts on 3rd failure")
    func testTranslateBatchAppleFallbackLimit() async {
        actor TestCollector {
            var items: [Int: String] = [:]
            func record(id: Int, text: String) {
                items[id] = text
            }
        }

        let items = [
            (id: 1, text: "Sentence 1"),
            (id: 2, text: "Sentence 2"),
            (id: 3, text: "Sentence 3")
        ]
        let invalidConfig = LLMConfig(baseURL: "invalid-url", apiKey: "", modelName: "test", concurrency: 1)
        let tracker = TemporaryFallbackTracker(maxConsecutiveFallbacks: 2)
        let collector = TestCollector()

        do {
            try await LLMTranslationService.translateBatch(
                items: items,
                from: "English",
                to: "Vietnamese",
                config: invalidConfig,
                fallbackTracker: tracker,
                appleFallbackHandler: { text in "Apple: \(text)" },
                onItemCompleted: { id, text in
                    await collector.record(id: id, text: text)
                }
            )
            #expect(Bool(false), "Expected error after exceeding fallback limit")
        } catch let error as LLMError {
            switch error {
            case .apiUnavailable(let msg):
                #expect(msg.contains("temporary fallback sentences"))
            default:
                #expect(Bool(false), "Expected apiUnavailable error, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected LLMError, got \(error)")
        }

        // Only first 2 sentences should have been translated by Apple fallback
        let completedMap = await collector.items
        #expect(completedMap.count == 2)
        #expect(completedMap[1] == "Apple: Sentence 1")
        #expect(completedMap[2] == "Apple: Sentence 2")
        #expect(completedMap[3] == nil)
    }

    @Test("translateBatchXML Tier 2 halts when consecutive Apple fallback limit is exceeded")
    func testBatchXMLTier2AppleFallbackHalt() async {
        actor TestCollector {
            var items: [Int: String] = [:]
            func record(id: Int, text: String) {
                items[id] = text
            }
        }

        let nodes = [
            TranslatableNode(id: 1, originalText: "One", fullMatch: "<p>One</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 2, originalText: "Two", fullMatch: "<p>Two</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 3, originalText: "Three", fullMatch: "<p>Three</p>", tagOpen: "<p>", tagClose: "</p>")
        ]
        let batch = TranslationBatch(id: 1, chapterIndex: 0, nodes: nodes, targetWordCount: 1200)
        let invalidConfig = LLMConfig(baseURL: "invalid-url", apiKey: "", modelName: "test")
        let tracker = TemporaryFallbackTracker(maxConsecutiveFallbacks: 2)
        let collector = TestCollector()

        do {
            try await LLMTranslationService.translateBatchXML(
                batch: batch,
                from: "English",
                to: "Vietnamese",
                config: invalidConfig,
                fallbackTracker: tracker,
                appleFallbackHandler: { text in "Apple: \(text)" },
                onNodeCompleted: { id, text in
                    await collector.record(id: id, text: text)
                }
            )
            #expect(Bool(false), "Expected translateBatchXML to throw apiUnavailable")
        } catch let error as LLMError {
            switch error {
            case .apiUnavailable(let msg):
                #expect(msg.contains("temporary fallback sentences"))
            default:
                #expect(Bool(false), "Expected apiUnavailable, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected LLMError, got \(error)")
        }

        let completedNodes = await collector.items
        #expect(completedNodes.count == 2)
        #expect(completedNodes[1] == "Apple: One")
        #expect(completedNodes[2] == "Apple: Two")
        #expect(completedNodes[3] == nil)
    }
}
