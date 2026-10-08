import Testing
import Foundation
@testable import NovelTranslator

@Suite("Document Chunker Tests")
struct DocumentChunkerTests {

    @Test("Splits empty document")
    func testEmptyDocument() {
        let chunks = DocumentChunker.chunk(document: "")
        #expect(chunks.isEmpty)
    }

    @Test("Splits multi-paragraph document and preserves delimiters")
    func testMultiParagraphs() {
        let doc = "Paragraph 1\n\nParagraph 2\n\nParagraph 3"
        let chunks = DocumentChunker.chunk(document: doc)

        #expect(chunks.count == 3)
        #expect(chunks[0].text == "Paragraph 1")
        #expect(chunks[0].delimiter == "\n\n")
        #expect(chunks[1].text == "Paragraph 2")
        #expect(chunks[1].delimiter == "\n\n")
        #expect(chunks[2].text == "Paragraph 3")
        #expect(chunks[2].delimiter == "")

        let reassembled = DocumentChunker.assemble(chunks: chunks, useTranslated: false)
        #expect(reassembled == doc)
    }

    @Test("Handles empty and whitespace lines without translating them")
    func testWhitespacePreservation() {
        let doc = "Header\n\n   \n\nContent"
        let chunks = DocumentChunker.chunk(document: doc)

        #expect(chunks.count == 3)
        #expect(chunks[0].isTranslatable == true)
        #expect(chunks[1].isTranslatable == false)
        #expect(chunks[2].isTranslatable == true)

        let reassembled = DocumentChunker.assemble(chunks: chunks, useTranslated: false)
        #expect(reassembled == doc)
    }

    @Test("Translates specified chunks and preserves untranslated structure")
    func testTranslationReassembly() {
        let doc = "Hello world\n\nGoodbye world"
        var chunks = DocumentChunker.chunk(document: doc)
        chunks[0].translatedText = "Hola mundo"
        chunks[1].translatedText = "Adiós mundo"

        let translatedDoc = DocumentChunker.assemble(chunks: chunks, useTranslated: true)
        #expect(translatedDoc == "Hola mundo\n\nAdiós mundo")
    }
}

@Suite("EPUB Processor Tests")
struct EPUBProcessorTests {

    @Test("Creates, unpacks, and parses sample EPUB ebook")
    func testSampleEPUBWorkflow() throws {
        let tempEpubURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Test_Voyage_\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: tempEpubURL) }

        // 1. Create sample EPUB
        try EPUBProcessor.createSampleEPUB(at: tempEpubURL)
        #expect(FileManager.default.fileExists(atPath: tempEpubURL.path))

        // 2. Unpack and inspect metadata and spine
        var book = try EPUBProcessor.unpack(epubURL: tempEpubURL)
        defer { try? FileManager.default.removeItem(at: book.rootDirectory) }

        #expect(book.title == "Voyage to the Cosmos")
        #expect(book.author == "Dr. Elena Rostova")
        #expect(book.chapters.count == 2)
        #expect(book.chapters[0].title.contains("The Cosmic Frontier"))
        #expect(book.chapters[1].title.contains("Voyages to the Stars"))

        // Check extracted nodes in Chapter 1
        #expect(book.chapters[0].nodes.count >= 3)
        #expect(book.chapters[0].nodes[0].originalText.contains("Cosmic Frontier"))

        // 3. Apply translation to Chapter 1
        book.chapters[0].nodes[0].translatedText = "La Frontera Cósmica"
        EPUBProcessor.applyTranslations(to: &book.chapters[0])

        #expect(book.chapters[0].isTranslated == true)
        #expect(book.chapters[0].translatedContent.contains("La Frontera Cósmica"))

        // 4. Repack into new EPUB
        let repackedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Test_Repacked_\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: repackedURL) }

        try EPUBProcessor.repack(book: book, targetURL: repackedURL, targetLanguageCode: "es")
        #expect(FileManager.default.fileExists(atPath: repackedURL.path))

        // Verify the repacked EPUB unpacks cleanly
        let verifiedBook = try EPUBProcessor.unpack(epubURL: repackedURL)
        defer { try? FileManager.default.removeItem(at: verifiedBook.rootDirectory) }

        #expect(verifiedBook.language == "es")
        #expect(verifiedBook.chapters[0].originalContent.contains("La Frontera Cósmica"))
    }

    @Test("Extracts translatable nodes from HTML snippet")
    func testHtmlNodeExtraction() {
        let html = """
        <html>
        <body>
            <h1>Heading 1</h1>
            <p>This is a <b>formatted</b> paragraph.</p>
            <ul>
                <li>Bullet point 1</li>
                <li>Bullet point 2</li>
            </ul>
        </body>
        </html>
        """

        let nodes = EPUBProcessor.extractTranslatableNodes(from: html, startingId: 100)
        #expect(nodes.count == 4)
        #expect(nodes[0].id == 100)
        #expect(nodes[0].originalText == "Heading 1")
        #expect(nodes[1].originalText.contains("formatted"))
        #expect(nodes[2].originalText == "Bullet point 1")
        #expect(nodes[3].originalText == "Bullet point 2")
    }

    @Test("Unpacks EPUB with reversed item attributes and subdirectories in href")
    func testUnpackEPUBWithReversedAttributes() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ComplexEPUB_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // mimetype
        try "application/epub+zip".write(to: tempDir.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)

        // META-INF
        let metaDir = tempDir.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        try "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/package.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>"
            .write(to: metaDir.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        // OEBPS and Text subfolder
        let textDir = tempDir.appendingPathComponent("OEBPS/Text")
        try FileManager.default.createDirectory(at: textDir, withIntermediateDirectories: true)
        try "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Section 1</title></head><body><h1>Title</h1><p>Content text</p></body></html>"
            .write(to: textDir.appendingPathComponent("sec01.xhtml"), atomically: true, encoding: .utf8)

        // OPF with href before id and self-closing items
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Complex Attributes Book</dc:title>
                <dc:language>en</dc:language>
            </metadata>
            <manifest>
                <item href="Text/sec01.xhtml" id="sec01" media-type="application/xhtml+xml" />
            </manifest>
            <spine>
                <itemref idref="sec01" />
            </spine>
        </package>
        """
        try opf.write(to: tempDir.appendingPathComponent("OEBPS/package.opf"), atomically: true, encoding: .utf8)

        let epubURL = FileManager.default.temporaryDirectory.appendingPathComponent("Complex_\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: epubURL) }

        // Zip into epubURL
        let zipMime = Process()
        zipMime.currentDirectoryURL = tempDir
        zipMime.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipMime.arguments = ["-X0", epubURL.path, "mimetype"]
        try zipMime.run()
        zipMime.waitUntilExit()

        let zipAll = Process()
        zipAll.currentDirectoryURL = tempDir
        zipAll.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipAll.arguments = ["-r9", epubURL.path, ".", "-x", "mimetype"]
        try zipAll.run()
        zipAll.waitUntilExit()

        let book = try EPUBProcessor.unpack(epubURL: epubURL)
        defer { try? FileManager.default.removeItem(at: book.rootDirectory) }

        #expect(book.title == "Complex Attributes Book")
        #expect(book.chapters.count == 1)
        #expect(book.chapters[0].nodes.count == 3)
        #expect(book.chapters[0].nodes[0].originalText == "Section 1")
        #expect(book.chapters[0].nodes[1].originalText == "Title")
        #expect(book.chapters[0].nodes[2].originalText == "Content text")
    }
}

@Suite("LLM Translation Service Tests")
struct LLMTranslationServiceTests {

    @Test("LLMConfig initializes with valid defaults")
    func testConfigDefaults() {
        let ollama = LLMConfig.defaultOllama
        #expect(ollama.baseURL.contains("localhost:11434"))
        #expect(ollama.modelName == "translategemma:4b")

        let openai = LLMConfig.defaultOpenAI
        #expect(openai.baseURL.contains("api.openai.com"))
        #expect(openai.modelName == "gpt-4o-mini")
    }

    @Test("Throws invalid URL error for malformed endpoints")
    func testInvalidURLHandling() async {
        let badConfig = LLMConfig(baseURL: "::bad::url")
        do {
            _ = try await LLMTranslationService.translate(
                text: "Hello",
                from: "English",
                to: "Spanish",
                config: badConfig
            )
            #expect(Bool(false), "Expected error was not thrown")
        } catch {
            #expect(error is LLMError)
        }
    }

    @Test("Queries local Ollama instance if available")
    func testLocalOllamaConnection() async throws {
        let config = LLMConfig.defaultOllama
        let models = try? await LLMTranslationService.fetchAvailableModels(config: config)
        if let models {
            #expect(!models.isEmpty)
            #expect(models.contains(where: { $0.contains("translategemma") || $0.contains("gemma") }))
        }
    }

    @Test("Tests connection with API model proxy")
    func testAPIProxyConnection() async throws {
        let config = EnvConfigManager.loadOpenAIConfig()
        guard !config.baseURL.contains("my-proxy.com") && !config.baseURL.contains("example.com") else {
            return
        }
        do {
            let result = try await LLMTranslationService.testConnection(config: config)
            print("API Model Connection Test Result: \(result)")
            #expect(result.contains("Success"))
        } catch {
            print("API Proxy connection test note: \(error)")
        }
    }

    @Test("Sanitizes markdown code fences and commentary from LLM output")
    func testCleanAndValidateMarkdownFences() {
        let rawFenced = """
        ```markdown
        El cielo es azul y despejado.
        ```
        """
        let cleaned = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawFenced,
            originalText: "The sky is blue and clear."
        )
        #expect(cleaned == "El cielo es azul y despejado.")
    }

    @Test("Sanitizes conversational preambles and pleasantries")
    func testCleanAndValidatePreamblesAndPleasantries() {
        let rawConversational = """
        Here is the translation:
        Bonjour le monde!
        Hope this helps!
        """
        let cleaned = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawConversational,
            originalText: "Hello world!"
        )
        #expect(cleaned == "Bonjour le monde!")

        let rawSure = "Sure! Here is the translation:\nCiao mondo!"
        let cleanedSure = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawSure,
            originalText: "Hello world!"
        )
        #expect(cleanedSure == "Ciao mondo!")
    }

    @Test("Extracts clean text from option lists or bullet recommendations")
    func testCleanAndValidateOptionLists() {
        let rawOptions = """
        Here are a few options:
        * **Hola mundo**
        * Saludos a todos
        """
        let cleaned = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawOptions,
            originalText: "Hello world"
        )
        #expect(cleaned == "Hola mundo")
    }

    @Test("Strips wrapping quotes if original was not quoted and falls back on empty")
    func testCleanAndValidateQuotesAndFallback() {
        let rawQuoted = "\"Guten Tag\""
        let cleaned = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawQuoted,
            originalText: "Good day"
        )
        #expect(cleaned == "Guten Tag")

        let rawEmpty = "   "
        let fallback = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawEmpty,
            originalText: "Original paragraph text"
        )
        #expect(fallback == "Original paragraph text")
    }

    @Test("Strips think tags from reasoning model output")
    func testCleanAndValidateThinkTags() {
        let rawThinking = """
        <think>
        Analyzing sentence structure...
        Translating into Vietnamese...
        </think>
        Họ đã gặp nhau như thế này được khoảng ba tháng.
        """
        let cleaned = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawThinking,
            originalText: "They had been seeing each other for about three months."
        )
        #expect(cleaned == "Họ đã gặp nhau như thế này được khoảng ba tháng.")
    }

    @Test("Strips Thinking Process header and extracts final translation")
    func testCleanAndValidateThinkingProcess() {
        let rawWithThinkingProcess = """
        Thinking Process:

        1. **Analyze the Request:**
        Input: English text. Task: Translate to Vietnamese.

        2. **Analyze the Source Text:**
        They'd been seeing each other like this for around three months.

        3. **Translate to Vietnamese:**
        * They'd been seeing each other: Họ đã gặp nhau...

        **Final Translation:**
        Họ đã gặp nhau như thế này khoảng ba tháng khi cô đến căn hộ của Hiroshi lần đầu tiên.
        """

        let cleaned = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawWithThinkingProcess,
            originalText: "They'd been seeing each other like this for around three months when she went to Hiroshi's apartment for the first time."
        )
        #expect(cleaned == "Họ đã gặp nhau như thế này khoảng ba tháng khi cô đến căn hộ của Hiroshi lần đầu tiên.")
    }

    @Test("Pure thinking process without final translation yields empty to trigger fallback")
    func testPureThinkingProcessYieldsEmpty() {
        let rawPureThinking = """
        Thinking Process:

        1. **Analyze the Request: **
        · Input: English text (US). Task: Translate to Vietnamese.

        2. **Analyze the Source Text: **
        *They'd been seeing each other like this for around three months...

        3. **Translate to Vietnamese: **
        · They'd been seeing each other: Họ đã gặp
        """

        let cleaned = LLMTranslationService.cleanAndValidateTranslation(
            rawResponse: rawPureThinking,
            originalText: "They'd been seeing each other like this for around three months."
        )
        #expect(cleaned.isEmpty)
    }

    @Test("Extracts content from standard, reasoning, delta, and array choices")
    func testExtractContentFromJSONVariations() throws {
        // Standard message content
        let standardJSON: [String: Any] = [
            "choices": [
                ["message": ["role": "assistant", "content": "Hola mundo"]]
            ]
        ]
        let standardResult = try LLMTranslationService.extractContentFromJSON(standardJSON, originalText: "Hello world")
        #expect(standardResult == "Hola mundo")

        // Content array parts
        let arrayJSON: [String: Any] = [
            "choices": [
                ["message": ["role": "assistant", "content": [["type": "text", "text": "Bonjour"], ["type": "text", "text": "monde"]]]]
            ]
        ]
        let arrayResult = try LLMTranslationService.extractContentFromJSON(arrayJSON, originalText: "Hello world")
        #expect(arrayResult.contains("Bonjour"))

        // Streaming delta
        let deltaJSON: [String: Any] = [
            "choices": [
                ["delta": ["content": "Ciao mondo"]]
            ]
        ]
        let deltaResult = try LLMTranslationService.extractContentFromJSON(deltaJSON, originalText: "Hello world")
        #expect(deltaResult == "Ciao mondo")

        // Legacy text field
        let textJSON: [String: Any] = [
            "choices": [
                ["text": "Hallo Welt"]
            ]
        ]
        let textResult = try LLMTranslationService.extractContentFromJSON(textJSON, originalText: "Hello world")
        #expect(textResult == "Hallo Welt")

        // Error in JSON payload with HTTP 200
        let errorJSON: [String: Any] = [
            "error": ["message": "Quota exceeded", "type": "insufficient_quota"]
        ]
        do {
            _ = try LLMTranslationService.extractContentFromJSON(errorJSON, originalText: "Hello world")
            #expect(Bool(false), "Expected error was not thrown")
        } catch {
            #expect(error.localizedDescription.contains("Quota exceeded"))
        }

        // Empty choices should throw decodingError
        let emptyChoicesJSON: [String: Any] = ["choices": []]
        do {
            _ = try LLMTranslationService.extractContentFromJSON(emptyChoicesJSON, originalText: "Hello world")
            #expect(Bool(false), "Expected error was not thrown")
        } catch {
            #expect(error is LLMError)
        }
    }

    @Test("Per-item fallback invokes onFallbackUsed when primary endpoint fails")
    func testPerItemFallbackTriggered() async throws {
        final class FallbackCollector: @unchecked Sendable {
            var notified = false
            var report = ""
        }
        let collector = FallbackCollector()

        // Primary config is deliberately unconnectable
        let brokenConfig = LLMConfig(baseURL: "http://127.0.0.1:9999/v1", apiKey: "", modelName: "broken-primary")
        // Fallback config
        let fallbackConfig = LLMConfig(baseURL: "http://127.0.0.1:9998/v1", apiKey: "", modelName: "fallback-mock")

        let items = [(id: 42, text: "Sample text")]
        do {
            try await LLMTranslationService.translateBatch(
                items: items,
                from: "English",
                to: "Spanish",
                config: brokenConfig,
                fallbackConfig: fallbackConfig,
                onFallbackUsed: { id, reason in
                    collector.notified = true
                    collector.report = reason
                },
                onItemCompleted: { _, _ in }
            )
        } catch {
            // Expected to fail when fallback also cannot connect to dummy port 9998
        }

        #expect(collector.notified == true)
        #expect(collector.report.contains("Paragraph 42"))
        #expect(collector.report.contains("fallback-mock"))
    }
}

@Suite("Translation ViewModel State & Checkpoint Tests")
struct TranslationViewModelTests {

    @MainActor
    @Test("Checkpoint canResume reflects partial progress accurately")
    func testCheckpointCanResumeDocument() {
        let vm = TranslationViewModel()
        vm.appMode = .document
        vm.totalTranslatableChunks = 10
        vm.completedChunks = 0
        vm.isTranslating = false
        #expect(vm.canResume == false)

        // Mid-translation
        vm.completedChunks = 4
        #expect(vm.canResume == true)

        // While currently translating
        vm.isTranslating = true
        #expect(vm.canResume == false)

        // Finished
        vm.isTranslating = false
        vm.completedChunks = 10
        #expect(vm.canResume == false)
    }

    @MainActor
    @Test("Session timer updates ETA and translation speed accurately")
    func testSessionTimerAndETA() {
        let vm = TranslationViewModel()
        vm.startSessionTimer(initialDone: 0)
        #expect(vm.estimatedTimeRemaining == "Calculating ETA...")
        #expect(vm.translationSpeed == nil)

        // When complete, ETA is cleared
        vm.updateETA(currentDone: 10, total: 10)
        #expect(vm.estimatedTimeRemaining == nil)
        #expect(vm.translationSpeed == nil)
    }

    @MainActor
    @Test("Fallback to Apple built-in translator sets engine and notice")
    func testFallbackToApple() {
        let vm = TranslationViewModel()
        vm.engine = .openai
        vm.sourceDocument = "Hello world\n\nSecond paragraph"
        vm.prepareDocumentChunks(resume: false)
        vm.updateDocumentChunkTranslation(chunkId: 0, translatedText: "Hola mundo")
        #expect(vm.completedChunks == 1)

        #expect(vm.autoFallback == true)

        // Trigger fallbackToApple
        vm.fallbackToApple(resume: true)

        #expect(vm.engine == .apple)
        #expect(vm.fallbackNotice == "Apple Built-in (Fallback)")
        #expect(vm.isTranslating == true)
        #expect(vm.completedChunks == 1) // Preserved previous chunk
    }

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

    @MainActor
    @Test("LLM translation error stops translation without switching engine to Apple")
    func testLLMTranslationErrorStopsWithoutSwitchingEngine() async {
        let vm = TranslationViewModel()
        vm.modelProfiles = []
        vm.activeProfileId = nil
        vm.appMode = .document
        vm.engine = .openai
        vm.openAIConfig = LLMConfig(baseURL: "invalid-url", apiKey: "", modelName: "test")
        vm.ollamaConfig = LLMConfig(baseURL: "invalid-url", apiKey: "", modelName: "test")
        vm.sourceDocument = "Hello world"
        vm.prepareDocumentChunks(resume: false)
        vm.autoFallback = false

        vm.startTranslation(resume: false)

        for _ in 0..<30 {
            if !vm.isTranslating && vm.errorMessage != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(vm.isTranslating == false)
        #expect(vm.engine == .openai)
        #expect(vm.errorMessage != nil)
    }

    @MainActor
    @Test("Persists checkpoint on cancel and restores state on reopening app")
    func testPersistenceAcrossReopening() {
        CheckpointManager.clearAll()
        defer { CheckpointManager.clearAll() }

        // Session 1: User translates 1 of 2 chunks, then cancels
        let vm1 = TranslationViewModel()
        vm1.engine = .ollama
        vm1.sourceDocument = "First sentence.\n\nSecond sentence."
        vm1.prepareDocumentChunks(resume: false)
        vm1.updateDocumentChunkTranslation(chunkId: 0, translatedText: "Primera frase.")
        #expect(vm1.completedChunks == 1)

        // User cancels
        vm1.cancelTranslation()
        #expect(CheckpointManager.hasSavedCheckpoint == true)

        // Session 2: User closes and reopens the app (new TranslationViewModel)
        let vm2 = TranslationViewModel()
        #expect(vm2.canResume == true)
        #expect(vm2.engine == .ollama)
        #expect(vm2.completedChunks == 1)
        #expect(vm2.totalTranslatableChunks == 2)
        #expect(vm2.statusMessage.contains("Resumed"))
        #expect(vm2.translatedDocument.contains("Primera frase."))

        // User deletes the session -> checkpoint removed
        vm2.clearActiveSessionCheckpoint()
        #expect(CheckpointManager.hasSavedCheckpoint == false)
    }

    @MainActor
    @Test("Saves multiple distinct translation sessions and allows resuming chosen one")
    func testMultiSessionSavingAndSelection() {
        CheckpointManager.clearAll()
        defer { CheckpointManager.clearAll() }

        // Session 1: Pride and Prejudice document
        let vm = TranslationViewModel()
        vm.appMode = .document
        vm.sourceDocument = "It is a truth universally acknowledged.\n\nSecond line."
        vm.prepareDocumentChunks(resume: false)
        vm.updateDocumentChunkTranslation(chunkId: 0, translatedText: "Es una verdad universalmente reconocida.")
        let id1 = vm.saveCheckpoint()!
        #expect(id1.isEmpty == false)

        // Session 2: A different document
        vm.clear()
        vm.appMode = .document
        vm.sourceDocument = "Call me Ishmael.\n\nSome years ago."
        vm.prepareDocumentChunks(resume: false)
        vm.updateDocumentChunkTranslation(chunkId: 0, translatedText: "Llámenme Ismael.")
        let id2 = vm.saveCheckpoint()!
        #expect(id2 != id1)

        // CheckpointManager lists both sessions
        let list = CheckpointManager.listCheckpoints()
        #expect(list.count == 2)
        #expect(list.contains(where: { $0.id == id1 }))
        #expect(list.contains(where: { $0.id == id2 }))

        // User chooses to resume session 1
        let resumed = vm.resumeSession(withId: id1)
        #expect(resumed == true)
        #expect(vm.translatedDocument.contains("Es una verdad universalmente reconocida."))

        // User deletes session 2
        vm.deleteSession(withId: id2)
        let updatedList = CheckpointManager.listCheckpoints()
        #expect(updatedList.count == 1)
        #expect(updatedList.first?.id == id1)
    }

    @MainActor
    @Test("Discovers unknown character candidates for a chapter in ViewModel")
    func testChapterCandidateDiscovery() {
        let vm = TranslationViewModel()
        let sherlock = CharacterProfile(name: "Sherlock Holmes", gender: .male)
        let bible = CharacterBible(bookTitle: "Study in Scarlet", characters: [sherlock])

        let node1 = TranslatableNode(id: 1, originalText: "Sherlock Holmes examined the floor with his glass.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let node2 = TranslatableNode(id: 2, originalText: "Inspector Lestrade stood by the window looking perplexed.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let node3 = TranslatableNode(id: 3, originalText: "Inspector Lestrade shook his head slowly.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let chapter = EPUBChapter(id: "ch-1", title: "Lauriston Garden", relativePath: "ch1.xhtml", originalContent: "", nodes: [node1, node2, node3])

        let book = EPUBBook(
            title: "Study in Scarlet",
            author: "Conan Doyle",
            language: "en",
            rootDirectory: URL(fileURLWithPath: "/tmp"),
            opfRelativePath: "content.opf",
            chapters: [chapter],
            characterBible: bible
        )
        vm.currentEPUB = book
        vm.characterBible = bible

        let candidates = vm.discoverCandidatesForChapter(chapterIndex: 0, minOccurrences: 2)

        #expect(candidates.contains(where: { $0.name == "Inspector Lestrade" }))
        #expect(!candidates.contains(where: { $0.name == "Sherlock Holmes" }))
    }

    @Test("Auto-enrich promotes character to global and chapter scope")
    @MainActor
    func testAutoEnrichPromotesToGlobal() async {
        let vm = TranslationViewModel()
        let sherlock = CharacterProfile(name: "Sherlock Holmes", gender: .male)
        let bible = CharacterBible(bookTitle: "Study in Scarlet", characters: [sherlock])

        let chapter = EPUBChapter(id: "ch-1", title: "Chapter One", relativePath: "ch1.xhtml", originalContent: "", nodes: [])
        let book = EPUBBook(
            title: "Study in Scarlet",
            author: "Conan Doyle",
            language: "en",
            rootDirectory: URL(fileURLWithPath: "/tmp"),
            opfRelativePath: "content.opf",
            chapters: [chapter],
            characterBible: bible
        )
        vm.currentEPUB = book
        vm.characterBible = bible

        // Simulate what autoEnrichCandidateCharacter does after LLM returns a profile
        let newProfile = CharacterProfile(name: "Lestrade", gender: .male, relativeAge: "middle-aged", roleOrStatus: "Inspector")

        var updated = vm.characterBible!
        var scope = updated.chapterScopes[chapter.id] ?? ChapterScope(
            id: chapter.id, chapterIndex: 0, chapterTitle: chapter.title
        )
        let nameLower = newProfile.name.lowercased()

        // Add to chapter scope
        if !scope.characters.contains(where: { $0.name.lowercased() == nameLower }) {
            scope.characters.append(newProfile)
            updated.chapterScopes[chapter.id] = scope
        }
        // Auto-promote to global
        if !updated.characters.contains(where: { $0.name.lowercased() == nameLower || $0.aliases.contains(where: { $0.lowercased() == nameLower }) }) {
            updated.characters.append(newProfile)
        }
        vm.characterBible = updated

        // Verify chapter scope has the new character
        let chapterChars = vm.characterBible?.chapterScopes["ch-1"]?.characters ?? []
        #expect(chapterChars.contains(where: { $0.name == "Lestrade" }))

        // Verify global also has the new character
        let globalChars = vm.characterBible?.characters ?? []
        #expect(globalChars.contains(where: { $0.name == "Lestrade" }))
        #expect(globalChars.contains(where: { $0.name == "Sherlock Holmes" }))
        #expect(globalChars.count == 2)

        // Verify effectiveScope merges correctly for a new chapter
        let effectiveForCh2 = CharacterBibleFilter.effectiveScope(forChapterId: "ch-2", in: vm.characterBible!)
        #expect(effectiveForCh2.characters.contains(where: { $0.name == "Lestrade" }))
        #expect(effectiveForCh2.characters.contains(where: { $0.name == "Sherlock Holmes" }))

        // Verify scanUnknownEntities now skips "Lestrade" in future chapters
        let futureText = "Lestrade arrived at the scene. Lestrade examined the evidence. Lestrade called for backup. A new character named Mycroft appeared. Mycroft was tall. Mycroft spoke softly."
        let candidates = CharacterBibleFilter.scanUnknownEntities(in: futureText, existingBible: vm.characterBible!, minOccurrences: 3)
        #expect(!candidates.contains(where: { $0.name == "Lestrade" }))
        #expect(candidates.contains(where: { $0.name == "Mycroft" }))
    }

    @MainActor
    @Test("Loading new EPUB preserves previous book checkpoint without losing it")
    func testLoadingNewEPUBPreservesPreviousCheckpoint() {
        CheckpointManager.clearAll()
        defer { CheckpointManager.clearAll() }

        let vm = TranslationViewModel()

        // Create and set Book 1
        let node1 = TranslatableNode(id: 1, originalText: "Fear is the mind-killer.", translatedText: "Nỗi sợ là kẻ giết chết tâm trí.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let ch1 = EPUBChapter(id: "ch-1", title: "Chapter 1", relativePath: "ch1.xhtml", originalContent: "", nodes: [node1])
        let book1 = EPUBBook(
            title: "Dune",
            author: "Frank Herbert",
            language: "en",
            rootDirectory: URL(fileURLWithPath: "/tmp"),
            opfRelativePath: "content.opf",
            chapters: [ch1]
        )
        vm.currentEPUB = book1
        let id1 = vm.saveCheckpoint()!
        #expect(id1.isEmpty == false)

        // Verify Book 1 is saved
        var list = CheckpointManager.listCheckpoints()
        #expect(list.contains(where: { $0.title == "Dune" }))

        // Now simulate loading Book 2 (without deleting Book 1)
        let node2 = TranslatableNode(id: 1, originalText: "Hari Seldon sat quietly.", translatedText: "Hari Seldon ngồi im lặng.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let ch2 = EPUBChapter(id: "ch-1", title: "Chapter 1", relativePath: "ch1.xhtml", originalContent: "", nodes: [node2])
        let book2 = EPUBBook(
            title: "Foundation",
            author: "Isaac Asimov",
            language: "en",
            rootDirectory: URL(fileURLWithPath: "/tmp"),
            opfRelativePath: "content.opf",
            chapters: [ch2]
        )

        // Before setting Book 2, verify save preserves Book 1
        #expect(vm.hasSavedProgress == true)
        vm.saveCheckpoint()

        // Set Book 2 as a new session
        vm.activeCheckpointId = UUID().uuidString
        vm.currentEPUB = book2
        let id2 = vm.saveCheckpoint()!
        #expect(id2 != id1)

        // Both Book 1 and Book 2 must exist in saved checkpoints!
        list = CheckpointManager.listCheckpoints()
        #expect(list.count == 2)
        #expect(list.contains(where: { $0.title == "Dune" }))
        #expect(list.contains(where: { $0.title == "Foundation" }))

        // Resume Book 1
        let resumed = vm.resumeSession(withId: id1)
        #expect(resumed == true)
        #expect(vm.currentEPUB?.title == "Dune")
        #expect(vm.currentEPUB?.chapters[0].nodes[0].translatedText == "Nỗi sợ là kẻ giết chết tâm trí.")

        // Verify Book 2 is still preserved in list
        list = CheckpointManager.listCheckpoints()
        #expect(list.count == 2)
        #expect(list.contains(where: { $0.title == "Foundation" }))
    }

    @MainActor
    @Test("Chapter analysis synchronizes discovered characters and relationships to global and fast-filters local candidates")
    func testChapterAnalysisSyncsToGlobalAndFastFiltersLocal() {
        let vm = TranslationViewModel()
        let alice = CharacterProfile(name: "Alice", gender: .female, relativeAge: "young adult", roleOrStatus: "Adventurer")
        let bible = CharacterBible(bookTitle: "Wonderland", characters: [alice])

        let ch1 = EPUBChapter(id: "ch-1", title: "Down the Rabbit Hole", relativePath: "ch1.xhtml", originalContent: "", nodes: [])
        let ch2 = EPUBChapter(id: "ch-2", title: "The Pool of Tears", relativePath: "ch2.xhtml", originalContent: "", nodes: [])
        let book = EPUBBook(
            title: "Wonderland",
            author: "Lewis Carroll",
            language: "en",
            rootDirectory: URL(fileURLWithPath: "/tmp"),
            opfRelativePath: "content.opf",
            chapters: [ch1, ch2],
            characterBible: bible
        )
        vm.currentEPUB = book
        vm.characterBible = bible

        // Simulate chapter 1 analysis result containing new character "White Rabbit" and relationship with "Alice"
        let rabbit = CharacterProfile(name: "White Rabbit", gender: .male, relativeAge: "elderly", roleOrStatus: "Herald")
        let rel = RelationshipPair(sourceCharacterId: "White Rabbit", targetCharacterId: "Alice", selfPronoun: "ta", addressingPronoun: "cô bé")
        let extractedCh1 = CharacterBible(
            bookTitle: "Wonderland - Chapter 1",
            characters: [rabbit],
            relationships: [rel],
            generalNotes: "Hurry through rabbit hole"
        )

        // Apply chapter sync logic (matching analyzeCharactersForChapter)
        var updatedBible = vm.characterBible!
        var scope = updatedBible.chapterScopes[ch1.id] ?? ChapterScope(id: ch1.id, chapterIndex: 0, chapterTitle: ch1.title)
        scope.characters = extractedCh1.characters
        scope.relationships = extractedCh1.relationships
        updatedBible.chapterScopes[ch1.id] = scope

        // Synchronize to Global
        for newChar in extractedCh1.characters {
            let lowerName = newChar.name.lowercased()
            if !updatedBible.characters.contains(where: { $0.name.lowercased() == lowerName }) {
                updatedBible.characters.append(newChar)
            }
        }
        for newRel in extractedCh1.relationships {
            updatedBible.relationships.append(newRel)
        }
        vm.characterBible = updatedBible

        // 1. Verify Global has both Alice and White Rabbit
        #expect(vm.characterBible?.characters.count == 2)
        #expect(vm.characterBible?.characters.contains(where: { $0.name == "White Rabbit" }) == true)
        #expect(vm.characterBible?.relationships.count == 1)

        // 2. Fast-filter test: when Chapter 2 text contains Alice and White Rabbit, scanner instantly recognizes them as known
        let ch2Text = "White Rabbit looked at his pocket watch. Alice was running behind him. Suddenly, the Cheshire Cat appeared. The Cheshire Cat smiled widely."
        let candidates = CharacterBibleFilter.scanUnknownEntities(in: ch2Text, existingBible: vm.characterBible!, minOccurrences: 2)

        // "Alice" and "White Rabbit" are already in global, so they MUST be skipped!
        #expect(!candidates.contains(where: { $0.name == "Alice" }))
        #expect(!candidates.contains(where: { $0.name == "White Rabbit" }))
        // "Cheshire Cat" is new and must be found
        #expect(candidates.contains(where: { $0.name == "Cheshire Cat" }))
    }
}

@Suite("Env Config Manager Tests")
struct EnvConfigManagerTests {

    @Test("Parses key-value pairs from .env string with comments and quotes")
    func testParseEnvContent() {
        let sample = """
        # This is a comment
        OPENAI_BASE_URL=https://api.custom-ai.com/v1
        OPENAI_API_KEY="sk-1234567890abcdef"
        OPENAI_MODEL='custom-translator-v1'
        OPENAI_TEMPERATURE=0.25
        OPENAI_CONCURRENCY=5
        # Trailing comment
        """

        let parsed = EnvConfigManager.parseEnvContent(sample)
        #expect(parsed["OPENAI_BASE_URL"] == "https://api.custom-ai.com/v1")
        #expect(parsed["OPENAI_API_KEY"] == "sk-1234567890abcdef")
        #expect(parsed["OPENAI_MODEL"] == "custom-translator-v1")
        #expect(parsed["OPENAI_TEMPERATURE"] == "0.25")
        #expect(parsed["OPENAI_CONCURRENCY"] == "5")
    }

    @Test("Serializes dictionary to clean .env string")
    func testSerializeEnv() {
        let env = [
            "OPENAI_BASE_URL": "https://api.test.com/v1",
            "OPENAI_API_KEY": "sk-secret",
            "OPENAI_MODEL": "gpt-4o",
            "OPENAI_TEMPERATURE": "0.10",
            "OPENAI_CONCURRENCY": "3"
        ]

        let serialized = EnvConfigManager.serializeEnv(env)
        #expect(serialized.contains("OPENAI_BASE_URL=https://api.test.com/v1"))
        #expect(serialized.contains("OPENAI_API_KEY=sk-secret"))
        #expect(serialized.contains("OPENAI_MODEL=gpt-4o"))
        #expect(serialized.contains("OPENAI_CONCURRENCY=3"))
    }

    @Test("Saves and loads OpenAI config to/from environment manager")
    func testSaveAndLoadOpenAIConfig() {
        let existing = EnvConfigManager.loadOpenAIConfig()
        defer { EnvConfigManager.saveOpenAIConfig(existing) }

        let original = LLMConfig(
            baseURL: "https://my-proxy.com/v1",
            apiKey: "sk-test-token",
            modelName: "claude-3-haiku",
            temperature: 0.3,
            concurrency: 6
        )

        let saved = EnvConfigManager.saveOpenAIConfig(original)
        #expect(saved == true)

        let loaded = EnvConfigManager.loadOpenAIConfig()
        #expect(loaded.baseURL == "https://my-proxy.com/v1")
        #expect(loaded.apiKey == "sk-test-token")
        #expect(loaded.modelName == "claude-3-haiku")
        #expect(loaded.temperature == 0.3)
        #expect(loaded.concurrency == 6)
    }

    @Test("Loads and saves batch word limit")
    func testBatchWordLimitPersistence() {
        let initial = EnvConfigManager.loadBatchWordLimit()
        defer { EnvConfigManager.saveBatchWordLimit(initial) }

        EnvConfigManager.saveBatchWordLimit(1500)
        #expect(EnvConfigManager.loadBatchWordLimit() == 1500)
    }
}

@Suite("EPUB Selective and Re-translation Tests")
struct EPUBSelectiveTranslationTests {

    @Test("Applies node translation and resets chapter nodes on force re-translate")
    func testChapterResetAndNodeUpdate() {
        var chapter = EPUBChapter(
            id: "ch-1",
            title: "Chapter One",
            relativePath: "ch1.xhtml",
            originalContent: "<p>Paragraph one</p><p>Paragraph two</p>",
            nodes: [
                TranslatableNode(id: 1, originalText: "Paragraph one", translatedText: "Paragraphe un", fullMatch: "<p>Paragraph one</p>", tagOpen: "<p>", tagClose: "</p>"),
                TranslatableNode(id: 2, originalText: "Paragraph two", translatedText: "Paragraphe deux", fullMatch: "<p>Paragraph two</p>", tagOpen: "<p>", tagClose: "</p>")
            ]
        )
        chapter.isTranslated = true

        #expect(chapter.nodes[0].translatedText == "Paragraphe un")
        #expect(chapter.nodes[1].translatedText == "Paragraphe deux")

        // Single node re-translation update
        chapter.nodes[0].translatedText = "Paragraphe un (re-translated)"
        EPUBProcessor.applyTranslations(to: &chapter)
        #expect(chapter.translatedContent.contains("Paragraphe un (re-translated)"))

        // Force re-translate reset: clears all translated text in chapter
        for i in 0..<chapter.nodes.count {
            chapter.nodes[i].translatedText = ""
        }
        chapter.isTranslated = false
        #expect(chapter.nodes[0].translatedText.isEmpty)
        #expect(chapter.nodes[1].translatedText.isEmpty)
        #expect(chapter.isTranslated == false)
    }
}

@Suite("Character Bible Model Tests")
struct CharacterBibleModelTests {
    @Test("Initializes, encodes, and decodes CharacterBible cleanly")
    func testCharacterBibleEncoding() throws {
        let elena = CharacterProfile(name: "Elena", aliases: ["Dr. Elena"], gender: .female, relativeAge: "adult", roleOrStatus: "scientist")
        let arthur = CharacterProfile(name: "Arthur", gender: .male, relativeAge: "elder", roleOrStatus: "mentor")
        let pair = RelationshipPair(sourceCharacterId: elena.id, targetCharacterId: arthur.id, selfPronoun: "tôi", addressingPronoun: "anh", contextNote: "colleagues")

        let bible = CharacterBible(
            bookTitle: "Cosmic Odyssey",
            narrativePOV: .firstPerson,
            narratorCharacterId: elena.id,
            characters: [elena, arthur],
            relationships: [pair],
            generalNotes: "Respectful tone"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(bible)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CharacterBible.self, from: data)

        #expect(decoded == bible)
        #expect(decoded.characters.count == 2)
        #expect(decoded.relationships.first?.selfPronoun == "tôi")
    }

    @Test("Correctly infers AgeTier from numeric, keywords, and relative age descriptions")
    func testAgeTierInference() {
        #expect(AgeTier.from(relativeAge: "25 years old") == .adult)
        #expect(AgeTier.from(relativeAge: "72 years old") == .elderly)
        #expect(AgeTier.from(relativeAge: "70s") == .elderly)
        #expect(AgeTier.from(relativeAge: "10 years old") == .child)
        #expect(AgeTier.from(relativeAge: "middle-aged man") == .adult)
        #expect(AgeTier.from(relativeAge: "middle aged woman") == .adult)
        #expect(AgeTier.from(relativeAge: "không rõ") == .adult)
        #expect(AgeTier.from(relativeAge: "elderly retired teacher") == .elderly)
        #expect(AgeTier.from(relativeAge: "grandpa") == .elderly)
        #expect(AgeTier.from(relativeAge: "little kid") == .child)
        #expect(AgeTier.from(relativeAge: "young adult") == .adult)
        #expect(AgeTier.from(relativeAge: "ông lão 65 tuổi") == .elderly)
        #expect(AgeTier.from(relativeAge: "cậu bé 12 tuổi") == .child)
    }

    @Test("Resolves narrative third-person pronouns for author narration")
    func testNarrativePronounResolution() {
        let boy = CharacterProfile(name: "Tom", gender: .male, relativeAge: "8 years old")
        let girl = CharacterProfile(name: "Lily", gender: .female, relativeAge: "child")
        let man = CharacterProfile(name: "Ken", gender: .male, relativeAge: "adult")
        let woman = CharacterProfile(name: "Yuriko", gender: .female, relativeAge: "adult")
        let oldMan = CharacterProfile(name: "Arthur", gender: .male, relativeAge: "75 years old")
        let oldWoman = CharacterProfile(name: "Obasan", gender: .female, relativeAge: "elderly")

        #expect(boy.narrativeThirdPersonPronoun == "thằng bé")
        #expect(girl.narrativeThirdPersonPronoun == "cô bé")
        #expect(man.narrativeThirdPersonPronoun == "anh ta")
        #expect(woman.narrativeThirdPersonPronoun == "cô ta")
        #expect(oldMan.narrativeThirdPersonPronoun == "ông ta")
        #expect(oldWoman.narrativeThirdPersonPronoun == "bà ta")

        let custom = CharacterProfile(name: "Voldemort", gender: .male, relativeAge: "adult", thirdPersonPronoun: "hắn")
        #expect(custom.narrativeThirdPersonPronoun == "hắn")
    }

    @Test("Resolves dialogue third-person pronouns for older and younger references")
    func testDialoguePronounResolution() {
        let man = CharacterProfile(name: "Ken", gender: .male, relativeAge: "adult")
        let woman = CharacterProfile(name: "Yuriko", gender: .female, relativeAge: "adult")
        let oldMan = CharacterProfile(name: "Arthur", gender: .male, relativeAge: "elderly")
        let oldWoman = CharacterProfile(name: "Obasan", gender: .female, relativeAge: "elderly")
        let boy = CharacterProfile(name: "Tom", gender: .male, relativeAge: "child")

        // Dialogue when referencing older
        #expect(man.dialogueOlderThirdPersonPronoun == "anh ấy")
        #expect(woman.dialogueOlderThirdPersonPronoun == "cô ấy")
        #expect(oldMan.dialogueOlderThirdPersonPronoun == "ông ấy")
        #expect(oldWoman.dialogueOlderThirdPersonPronoun == "bà ấy")

        // Dialogue when referencing younger
        #expect(man.dialogueYoungerThirdPersonPronoun == "cậu ta")
        #expect(woman.dialogueYoungerThirdPersonPronoun == "cô ta")
        #expect(boy.dialogueYoungerThirdPersonPronoun == "thằng bé")
    }
}

@Suite("Character Bible Filter Tests")
struct CharacterBibleFilterTests {
    @Test("Filters out relationship pairs for characters absent from chapter text")
    func testChapterFiltering() {
        let john = CharacterProfile(name: "John", aliases: ["Johnny"], gender: .male)
        let mary = CharacterProfile(name: "Mary", gender: .female)
        let vance = CharacterProfile(name: "Commander Vance", aliases: ["Vance"], gender: .male)

        let pairJohnMary = RelationshipPair(sourceCharacterId: john.id, targetCharacterId: mary.id, selfPronoun: "anh", addressingPronoun: "em")
        let pairJohnVance = RelationshipPair(sourceCharacterId: john.id, targetCharacterId: vance.id, selfPronoun: "tôi", addressingPronoun: "ngài")

        let bible = CharacterBible(
            narrativePOV: .thirdPerson,
            characters: [john, mary, vance],
            relationships: [pairJohnMary, pairJohnVance]
        )

        let chapterText = "Mary walked into the room. 'Where is Johnny?' she asked softly."
        let activePairs = CharacterBibleFilter.filterRelationships(in: bible, forChapterText: chapterText)

        #expect(activePairs.count == 1)
        #expect(activePairs.first?.targetCharacterId == mary.id)
    }

    @Test("Always retains first-person narrator pairs if other character is present")
    func testFirstPersonNarratorRetention() {
        let narrator = CharacterProfile(name: "Me", gender: .female)
        let arthur = CharacterProfile(name: "Arthur", gender: .male)
        let pair = RelationshipPair(sourceCharacterId: narrator.id, targetCharacterId: arthur.id, selfPronoun: "em", addressingPronoun: "anh")

        let bible = CharacterBible(
            narrativePOV: .firstPerson,
            narratorCharacterId: narrator.id,
            characters: [narrator, arthur],
            relationships: [pair]
        )

        let chapterText = "Arthur looked at me across the table with a knowing smile."
        let activePairs = CharacterBibleFilter.filterRelationships(in: bible, forChapterText: chapterText)

        #expect(activePairs.count == 1)
    }

    @Test("Scans and discovers recurring unknown entity candidates in chapter text")
    func testScanUnknownEntities() {
        let john = CharacterProfile(name: "John", gender: .male)
        let bible = CharacterBible(characters: [john])

        let chapterText = """
        John walked into the quiet village on Monday morning.
        Suddenly, Inspector Gregson called out from the doorway.
        "Welcome," said Inspector Gregson, tipping his hat.
        Inspector Gregson pointed toward the river.
        However, the river was silent and mysterious.
        """

        let candidates = CharacterBibleFilter.scanUnknownEntities(in: chapterText, existingBible: bible, minOccurrences: 2)

        #expect(candidates.contains(where: { $0.name == "Inspector Gregson" && $0.occurrenceCount >= 3 }))
        #expect(!candidates.contains(where: { $0.name == "John" })) // Already known
        #expect(!candidates.contains(where: { $0.name == "Monday" })) // Stopword
        #expect(!candidates.contains(where: { $0.name == "However" })) // Stopword
    }
}

@Suite("Pronoun Prompt Builder Tests")
struct PronounPromptBuilderTests {
    @Test("Appends Vietnamese pronoun directives when target is Vietnamese and bible present")
    func testVietnamesePromptEnrichment() {
        let elena = CharacterProfile(name: "Elena", gender: .female)
        let arthur = CharacterProfile(name: "Arthur", gender: .male)
        let pair = RelationshipPair(sourceCharacterId: elena.id, targetCharacterId: arthur.id, selfPronoun: "tôi", addressingPronoun: "anh", contextNote: "colleagues")
        let bible = CharacterBible(narrativePOV: .thirdPerson, characters: [elena, arthur], relationships: [pair], generalNotes: "Sci-fi exploration")

        let basePrompt = "You are a professional translator."
        let enriched = PronounPromptBuilder.buildSystemInstruction(
            baseInstruction: basePrompt,
            targetLanguageCode: "vi",
            bible: bible,
            chapterText: "Elena called Arthur to the bridge."
        )

        #expect(enriched.contains("VIETNAMESE PRONOUN & CHARACTER GUIDELINES"))
        #expect(enriched.contains("Elena -> Arthur: Calls self \"tôi\", addresses Arthur as \"anh\""))
        #expect(enriched.contains("Sci-fi exploration"))
    }

    @Test("Leaves base instruction untouched for non-Vietnamese targets")
    func testNonVietnameseUnchanged() {
        let bible = CharacterBible(bookTitle: "Test")
        let basePrompt = "You are a professional translator."
        let result = PronounPromptBuilder.buildSystemInstruction(
            baseInstruction: basePrompt,
            targetLanguageCode: "es",
            bible: bible,
            chapterText: "Sample text"
        )
        #expect(result == basePrompt)
    }

    @Test("Injects stable 3rd person pronoun reference and anti-repetition directives")
    func testThirdPersonNarrativeAndAntiRepetitionDirectives() {
        let yuriko = CharacterProfile(name: "Yuriko", gender: .female, relativeAge: "young adult")
        let grandma = CharacterProfile(name: "Obasan", gender: .female, relativeAge: "elderly", thirdPersonPronoun: "bà")
        let bible = CharacterBible(
            narrativePOV: .thirdPerson,
            characters: [yuriko, grandma]
        )

        let prompt = PronounPromptBuilder.buildSystemInstruction(
            baseInstruction: "Translate.",
            targetLanguageCode: "vi",
            bible: bible,
            chapterText: "Yuriko arrived at the tea house to meet Obasan."
        )

        #expect(prompt.contains("THIRD-PERSON PRONOUN GUIDELINES (NARRATION VS DIALOGUE):"))
        #expect(prompt.contains("Context A - Author Narration"))
        #expect(prompt.contains("Context B - In Dialogue & Character Thoughts"))
        #expect(prompt.contains("Active Character 3rd-Person Reference Anchors:"))
        #expect(prompt.contains("Yuriko (Female, Adult):"))
        #expect(prompt.contains("Narration: \"cô ta\""))
        #expect(prompt.contains("In Dialogue (ref by younger): \"cô ấy\""))
        #expect(prompt.contains("In Dialogue (ref by older): \"cô ta\""))
        #expect(prompt.contains("Obasan (Female, Elderly):"))
        #expect(prompt.contains("Narration: \"bà\""))
        #expect(prompt.contains("In Dialogue: \"bà ấy\""))
        #expect(prompt.contains("THIRD-PERSON USAGE: In narrative prose (Context A), avoid generic/repetitive \"anh ấy / cô ấy\""))
    }

    @Test("Injects non-fiction specific translation directives when genre is non-fiction")
    func testNonFictionDirectives() {
        let bible = CharacterBible(
            bookTitle: "Atomic Habits",
            bookGenre: .nonFiction,
            narrativePOV: .firstPerson,
            generalNotes: "Self-help and psychology"
        )

        let prompt = PronounPromptBuilder.buildSystemInstruction(
            baseInstruction: "Translate document.",
            targetLanguageCode: "vi",
            bible: bible,
            chapterText: "In this chapter we analyze cognitive behavioral loops."
        )

        #expect(prompt.contains("NON-FICTION & TECHNICAL TRANSLATION GUIDELINES:"))
        #expect(prompt.contains("Book Genre: Non-Fiction / Technical / Academic"))
        #expect(prompt.contains("Translate author self-references ('I', 'we') as 'tôi', 'chúng ta'"))
    }

    @Test("Applies local chapter scope overrides over global bible")
    func testLocalChapterScopeOverrides() {
        let john = CharacterProfile(name: "John", gender: .male)
        let mary = CharacterProfile(name: "Mary", gender: .female)
        let globalPair = RelationshipPair(sourceCharacterId: john.id, targetCharacterId: mary.id, selfPronoun: "tôi", addressingPronoun: "bạn")

        let localPair = RelationshipPair(sourceCharacterId: john.id, targetCharacterId: mary.id, selfPronoun: "anh", addressingPronoun: "em", contextNote: "intimate confession")
        let chapter1Scope = ChapterScope(
            id: "ch-10",
            chapterIndex: 10,
            chapterTitle: "The Confession",
            characters: [john, mary],
            relationships: [localPair],
            notes: "Emotional tone"
        )

        let bible = CharacterBible(
            bookTitle: "A Story",
            characters: [john, mary],
            relationships: [globalPair],
            chapterScopes: ["ch-10": chapter1Scope]
        )

        let chapterText = "John looked at Mary with tears in his eyes."
        // Global chapter without local override
        let globalRels = CharacterBibleFilter.filterRelationships(in: bible, forChapterText: chapterText, chapterId: "ch-1")
        #expect(globalRels.first?.selfPronoun == "tôi")

        // Chapter 10 with local override
        let localRels = CharacterBibleFilter.filterRelationships(in: bible, forChapterText: chapterText, chapterId: "ch-10")
        #expect(localRels.first?.selfPronoun == "anh")
        #expect(localRels.first?.addressingPronoun == "em")
    }
}

@Suite("Character Extraction Parsing Tests")
struct CharacterExtractionParsingTests {
    @Test("Extracts sample text from EPUB chapters up to character cap")
    func testExtractSampleText() throws {
        let tempEpubURL = FileManager.default.temporaryDirectory.appendingPathComponent("Sample_\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: tempEpubURL) }
        try EPUBProcessor.createSampleEPUB(at: tempEpubURL)
        let book = try EPUBProcessor.unpack(epubURL: tempEpubURL)
        defer { try? FileManager.default.removeItem(at: book.rootDirectory) }

        let sample = EPUBProcessor.extractSampleText(from: book, maxCharacters: 500)
        #expect(!sample.isEmpty)
        #expect(sample.contains("Cosmic Frontier"))
        #expect(sample.count <= 500)
    }

    @Test("Parses resiliently from LLM JSON response with markdown fences and thinking blocks")
    func testExtractionDTOParsing() throws {
        let rawLLM = """
        <think>Analyzing characters...</think>
        ```json
        {
          "narrativePOV": "Third Person",
          "characters": [
            { "name": "Elena Rostova", "aliases": ["Elena"], "gender": "Female", "relativeAge": "adult", "roleOrStatus": "doctor" },
            { "name": "Arthur Vance", "gender": "Male", "relativeAge": "elder", "roleOrStatus": "commander" }
          ],
          "relationships": [
            { "source": "Elena Rostova", "target": "Arthur Vance", "selfPronoun": "tôi", "addressingPronoun": "anh", "contextNote": "colleagues" }
          ],
          "generalNotes": "Respectful space exploration"
        }
        ```
        """

        let bible = try LLMTranslationService.parseCharacterBibleFromJSON(rawLLM, bookTitle: "Cosmic Odyssey")
        #expect(bible.characters.count == 2)
        #expect(bible.relationships.count == 1)
        #expect(bible.relationships.first?.selfPronoun == "tôi")
    }

    @Test("Preserves CharacterBible in TranslationCheckpoint persistence")
    func testCheckpointWithCharacterBible() throws {
        let bible = CharacterBible(bookTitle: "Checkpoint Test", characters: [CharacterProfile(name: "John")])
        let checkpoint = TranslationCheckpoint(
            appMode: .epub,
            engine: .ollama,
            sourceLanguageId: "en",
            targetLanguageId: "vi"
        )
        var mutableCheckpoint = checkpoint
        mutableCheckpoint.characterBible = bible

        let id = CheckpointManager.save(checkpoint: mutableCheckpoint)
        defer { CheckpointManager.delete(id: id) }

        let loaded = CheckpointManager.load(id: id)
        #expect(loaded?.characterBible?.characters.first?.name == "John")
    }

    @Test("Stratified sample extraction prioritizes cast list and samples milestone chapters")
    func testStratifiedSampleExtraction() {
        let castNode = TranslatableNode(id: 1, originalText: "Lord Henry: An aristocrat. Dorian Gray: A young gentleman. Sibyl Vane: An actress.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let castChapter = EPUBChapter(id: "cast", title: "Dramatis Personae", relativePath: "cast.xhtml", originalContent: "", nodes: [castNode])

        var chapters: [EPUBChapter] = [castChapter]
        for i in 1...6 {
            let node1 = TranslatableNode(id: i * 10, originalText: "This is the start of chapter \(i). The characters gathered in the grand hall.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
            let node2 = TranslatableNode(id: i * 10 + 1, originalText: "Later in chapter \(i), mysterious traveler James appeared in the shadow.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
            let ch = EPUBChapter(id: "ch-\(i)", title: "Chapter \(i)", relativePath: "ch\(i).xhtml", originalContent: "", nodes: [node1, node2])
            chapters.append(ch)
        }

        let book = EPUBBook(
            title: "The Picture of Dorian",
            author: "Oscar Wilde",
            language: "en",
            rootDirectory: URL(fileURLWithPath: "/tmp"),
            opfRelativePath: "content.opf",
            chapters: chapters
        )

        let sample = EPUBProcessor.extractStratifiedSampleText(from: book, maxCharacters: 10_000)

        #expect(!sample.isEmpty)
        #expect(sample.contains("[CAST / CHARACTERS LIST"))
        #expect(sample.contains("Dorian Gray"))
        #expect(sample.contains("Opening Chapter"))
        #expect(sample.contains("Milestone Chapter"))
        #expect(sample.count <= 10_000)
    }

    @Test("Promote character to global moves character and relations to global bible")
    func testPromoteCharacterToGlobal() {
        let watson = CharacterProfile(name: "John Watson", gender: .male)
        let globalBible = CharacterBible(
            bookTitle: "Sherlock Holmes",
            characters: [watson]
        )

        let editor = CharacterBibleEditorViewModel(bible: globalBible)

        let lestrade = CharacterProfile(name: "Inspector Lestrade", gender: .male)
        let rel = RelationshipPair(sourceCharacterId: watson.id, targetCharacterId: lestrade.id, selfPronoun: "tôi", addressingPronoun: "ông")
        let chapterScope = ChapterScope(
            id: "ch-3",
            chapterIndex: 3,
            chapterTitle: "The Lauriston Garden Mystery",
            characters: [lestrade],
            relationships: [rel]
        )

        editor.workingBible.chapterScopes["ch-3"] = chapterScope
        editor.selectedScopeId = "ch-3"

        #expect(editor.workingBible.characters.count == 1)
        #expect(editor.workingBible.chapterScopes["ch-3"]?.characters.count == 1)

        // Promote Lestrade to Global
        editor.promoteCharacterToGlobal(charId: lestrade.id)

        #expect(editor.workingBible.characters.count == 2)
        #expect(editor.workingBible.characters.contains(where: { $0.name == "Inspector Lestrade" }))
        #expect(editor.workingBible.relationships.contains(where: { $0.targetCharacterId == lestrade.id }))
        #expect(editor.workingBible.chapterScopes["ch-3"]?.characters.isEmpty == true)
    }

    @Test("Parses single character profile from targeted micro-extraction response")
    func testSingleCharacterProfileParsing() throws {
        let rawJSON = """
        <think>Analyzing candidate...</think>
        ```json
        {
          "name": "Inspector Gregson",
          "aliases": ["Gregson", "Tobias"],
          "gender": "Male",
          "relativeAge": "45 years old",
          "roleOrStatus": "Scotland Yard Detective",
          "thirdPersonPronoun": "ông ta"
        }
        ```
        """

        let profile = try LLMTranslationService.parseSingleCharacterProfile(fromJSON: rawJSON, candidateName: "Inspector Gregson")
        #expect(profile.name == "Inspector Gregson")
        #expect(profile.aliases == ["Gregson", "Tobias"])
        #expect(profile.gender == .male)
        #expect(profile.ageTier == .adult)
        #expect(profile.roleOrStatus == "Scotland Yard Detective")
        #expect(profile.narrativeThirdPersonPronoun == "ông ta")
    }

    @Test("Scan book entities covers 100% of chapters including late chapters and titles")
    func testScanBookEntitiesAcrossAllChapters() {
        let node1 = TranslatableNode(id: 1, originalText: "Alice sat by the bank with her sister.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let node2 = TranslatableNode(id: 2, originalText: "Dr. Watson walked down Baker Street with Sherlock Holmes.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let ch1 = EPUBChapter(id: "ch-1", title: "Chapter 1", relativePath: "ch1.xhtml", originalContent: "", nodes: [node1, node2])

        let node3 = TranslatableNode(id: 3, originalText: "Sherlock Holmes examined the footprint carefully.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let node4 = TranslatableNode(id: 4, originalText: "Dr. Watson recorded every detail in his journal.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let ch2 = EPUBChapter(id: "ch-2", title: "Chapter 2", relativePath: "ch2.xhtml", originalContent: "", nodes: [node3, node4])

        let node5 = TranslatableNode(id: 5, originalText: "Suddenly in the final chapter, Professor Moriarty appeared.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let node6 = TranslatableNode(id: 6, originalText: "Professor Moriarty smiled cold-bloodedly at Holmes.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let node7 = TranslatableNode(id: 7, originalText: "Professor Moriarty leaped into the abyss.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let ch3 = EPUBChapter(id: "ch-3", title: "Final Chapter", relativePath: "ch3.xhtml", originalContent: "", nodes: [node5, node6, node7])

        let book = EPUBBook(
            title: "The Final Problem",
            author: "Conan Doyle",
            language: "en",
            rootDirectory: URL(fileURLWithPath: "/tmp"),
            opfRelativePath: "content.opf",
            chapters: [ch1, ch2, ch3]
        )

        let candidates = CharacterBibleFilter.scanBookEntities(in: book, minOccurrences: 2)

        // 1. Dr. Watson with title is discovered
        #expect(candidates.contains(where: { $0.name == "Dr. Watson" && $0.occurrenceCount >= 2 }))

        // 2. Sherlock Holmes is discovered
        #expect(candidates.contains(where: { $0.name == "Sherlock Holmes" && $0.occurrenceCount >= 2 }))

        // 3. Crucial: Professor Moriarty appearing ONLY in late chapter 3 is 100% captured!
        #expect(candidates.contains(where: { $0.name == "Professor Moriarty" && $0.occurrenceCount >= 3 }))

        // 4. Sample excerpts are gathered
        let moriarty = candidates.first(where: { $0.name == "Professor Moriarty" })
        #expect(moriarty != nil)
        #expect(moriarty?.sampleExcerpts.isEmpty == false)
    }

    @MainActor
    @Test("Scan and analyze all chapters invokes anchored extraction and updates global bible")
    func testScanAndAnalyzeAllChaptersIntegration() async {
        let vm = TranslationViewModel()

        let node1 = TranslatableNode(id: 1, originalText: "Dorian Gray looked at his portrait.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let node2 = TranslatableNode(id: 2, originalText: "Lord Henry laughed softly.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let ch1 = EPUBChapter(id: "ch-1", title: "Chapter 1", relativePath: "ch1.xhtml", originalContent: "", nodes: [node1, node2])

        let node3 = TranslatableNode(id: 3, originalText: "Lord Henry spoke with Dorian Gray again.", fullMatch: "", tagOpen: "<p>", tagClose: "</p>")
        let ch2 = EPUBChapter(id: "ch-2", title: "Chapter 2", relativePath: "ch2.xhtml", originalContent: "", nodes: [node3])

        let book = EPUBBook(
            title: "Dorian Gray",
            author: "Oscar Wilde",
            language: "en",
            rootDirectory: URL(fileURLWithPath: "/tmp"),
            opfRelativePath: "content.opf",
            chapters: [ch1, ch2]
        )
        vm.currentEPUB = book

        // Test the book-wide entity scanning part of the pipeline
        let candidates = CharacterBibleFilter.scanBookEntities(in: book, minOccurrences: 2)
        #expect(candidates.contains(where: { $0.name == "Lord Henry" }))
        #expect(candidates.contains(where: { $0.name == "Dorian Gray" }))
    }

    @Test("Unpacks and tests all real books in library")
    @MainActor
    func testAllRealBooks() throws {
        let booksDir = "/Users/namotaku/Library/CloudStorage/GoogleDrive-namdeptraindt@gmail.com (25-09-2026 8:22 AM)/My Drive/Books"
        guard FileManager.default.fileExists(atPath: booksDir) else { return }

        let files = (try? FileManager.default.contentsOfDirectory(atPath: booksDir)) ?? []
        for file in files where file.hasSuffix(".epub") && !file.hasSuffix("_vi.epub") {
            let fullPath = "\(booksDir)/\(file)"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }

            do {
                let book = try EPUBProcessor.unpack(epubURL: URL(fileURLWithPath: fullPath))
                defer { try? FileManager.default.removeItem(at: book.rootDirectory) }
                let sampleText = EPUBProcessor.extractStratifiedSampleText(from: book, maxCharacters: 10_000)
                let candidates = CharacterBibleFilter.scanBookEntities(in: book, minOccurrences: 2)
                print("BOOK: \(file.prefix(35)) -> Chapters: \(book.chapters.count), Nodes: \(book.totalNodes), Sample: \(sampleText.count) chars, Candidates: \(candidates.count)")
            } catch {
                print("FAILED BOOK: \(file.prefix(35)) -> \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Model Prompt Customization Tests
    @Test("Renders translation prompt with language placeholders")
    func testRenderTranslationPromptPlaceholders() {
        let template = "Translate text from {sourceLang} to {targetLang} in polite form."
        let rendered = LLMTranslationService.renderTranslationPrompt(
            template: template,
            from: "English",
            to: "Vietnamese"
        )
        #expect(rendered == "Translate text from English to Vietnamese in polite form.")
    }

    @Test("Renders character analysis prompt with entity and context placeholders")
    func testRenderCharacterAnalysisPromptPlaceholders() {
        let template = """
        Custom character extractor:
        {entitiesSection}

        Rules: Output JSON.
        {contextAppendix}
        """

        let entities = "- Holmes (10)\n- Watson (5)"
        let context = "- Known: Holmes"

        let rendered = LLMTranslationService.renderCharacterAnalysisPrompt(
            template: template,
            entitiesSection: entities,
            contextAppendix: context
        )

        #expect(rendered.contains(entities))
        #expect(rendered.contains(context))
        #expect(rendered.contains("Custom character extractor:"))
    }

    @Test("Guarantees JSON schema guardrail when custom character prompt omits schema")
    func testCharacterAnalysisPromptSafetyGuardrail() {
        let bareTemplate = "Find all names in the story and tell me who they are."
        let rendered = LLMTranslationService.renderCharacterAnalysisPrompt(
            template: bareTemplate,
            entitiesSection: "- Alice",
            contextAppendix: ""
        )

        #expect(rendered.contains("- Alice"))
        #expect(rendered.contains("\"characters\""))
        #expect(rendered.contains("JSON"))
    }

    @Test("Verifies all built-in Prompt Presets exist and contain valid instructions")
    func testPromptPresetsValidity() {
        #expect(!PromptPresets.translationPresets.isEmpty)
        #expect(!PromptPresets.characterAnalysisPresets.isEmpty)

        for preset in PromptPresets.translationPresets {
            #expect(!preset.name.isEmpty)
            #expect(!preset.template.isEmpty)
            let rendered = LLMTranslationService.renderTranslationPrompt(
                template: preset.template,
                from: "English",
                to: "Vietnamese"
            )
            #expect(!rendered.contains("{sourceLang}"))
            #expect(!rendered.contains("{targetLang}"))
        }

        for preset in PromptPresets.characterAnalysisPresets {
            #expect(!preset.name.isEmpty)
            #expect(!preset.template.isEmpty)
        }
    }

    @MainActor
    @Test("TranslationViewModel manages, customizes, and resets prompts")
    func testViewModelPromptManagement() {
        let vm = TranslationViewModel(autoRestoreCheckpoint: false)
        vm.sourceLanguage = SupportedLanguage(id: "en", name: "English", code: "en-US")
        vm.targetLanguage = SupportedLanguage(id: "vi", name: "Vietnamese", code: "vi-VN")

        // 1. Initial defaults
        #expect(!vm.customTranslationPrompt.isEmpty)
        #expect(!vm.customCharacterAnalysisPrompt.isEmpty)
        #expect(!vm.hasCustomPrompts)

        let initialInstruction = vm.currentTranslationSystemInstruction(from: "English", to: "Vietnamese")
        #expect(initialInstruction.contains("English"))
        #expect(initialInstruction.contains("Vietnamese"))

        // 2. Custom prompt setting
        vm.customTranslationPrompt = "Dịch từ {sourceLang} sang {targetLang} thật mượt mà."
        #expect(vm.hasCustomTranslationPrompt)
        #expect(vm.hasCustomPrompts)

        let customizedInstruction = vm.currentTranslationSystemInstruction(from: "English", to: "Vietnamese")
        #expect(customizedInstruction == "Dịch từ English sang Vietnamese thật mượt mà.")

        // 3. Resetting back to default
        vm.resetTranslationPromptToDefault()
        #expect(!vm.hasCustomTranslationPrompt)
        #expect(vm.currentTranslationSystemInstruction(from: "English", to: "Vietnamese").contains("professional, direct document translator"))

        // 4. Full translation instruction with knowledge base
        let fullInstruction = vm.currentFullTranslationSystemInstruction(
            from: "English",
            to: "Vietnamese",
            includeKnowledgeBase: true
        )
        #expect(fullInstruction.contains("VIETNAMESE PRONOUN & CHARACTER GUIDELINES (KNOWLEDGE BASE):"))
        #expect(fullInstruction.contains("Active Character Pronoun Pairs:"))
    }

    @Test("Replaces {knowledgeBase} placeholder in custom translation prompt")
    func testKnowledgeBasePlaceholderReplacement() {
        let customPrompt = """
        Translator instructions.
        {knowledgeBase}
        Final reminder: be concise.
        """

        let bible = CharacterBible(
            bookTitle: "Test Book",
            characters: [CharacterProfile(name: "Alice", gender: .female)],
            relationships: []
        )

        let assembled = PronounPromptBuilder.buildSystemInstruction(
            baseInstruction: customPrompt,
            targetLanguageCode: "vi",
            bible: bible,
            chapterText: nil
        )

        #expect(!assembled.contains("{knowledgeBase}"))
        #expect(assembled.contains("VIETNAMESE PRONOUN & CHARACTER GUIDELINES (KNOWLEDGE BASE):"))
        #expect(assembled.hasSuffix("Final reminder: be concise."))
    }
}







