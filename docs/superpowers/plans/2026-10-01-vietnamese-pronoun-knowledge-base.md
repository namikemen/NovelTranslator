# Vietnamese Pronoun Knowledge Base (Character Bible) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Character Bible and pronoun knowledge base for EPUB eBooks to ensure consistent, natural English-to-Vietnamese pronoun translation using local and cloud LLMs.

**Architecture:** A standalone domain model (`CharacterBible`) represents characters, relative ages, and reciprocal pronoun pairs. A clean extraction pipeline (`EPUBProcessor.extractSampleText` -> `LLMTranslationService.extractCharacterBible`) identifies characters upfront with user review in `CharacterBibleSheet`. During translation, `CharacterBibleFilter` extracts only characters active in the chapter, and `PronounPromptBuilder` injects targeted relationship guidelines into `LLMTranslationService.translateBatch`.

**Tech Stack:** Swift 6 Concurrency (`Sendable`, `TaskGroup`), macOS 15.0+ Sequoia, SwiftUI, Apple Swift Testing library (`import Testing`, `@Suite`, `@Test`, `#expect`).

---

## File Structure

### New Files to Create:
- `Sources/DocTranslateApp/CharacterBible.swift`: Defines `CharacterGender`, `NarrativePOV`, `CharacterProfile`, `RelationshipPair`, and `CharacterBible`.
- `Sources/DocTranslateApp/CharacterBibleFilter.swift`: Implements `CharacterBibleFilter.filterRelationships(in:forChapterText:)`.
- `Sources/DocTranslateApp/PronounPromptBuilder.swift`: Implements `PronounPromptBuilder.buildSystemInstruction(...)`.
- `Sources/DocTranslateApp/CharacterBibleSheet.swift`: SwiftUI review sheet displaying narrative POV, characters list, and relationship matrix with Vietnamese presets.

### Existing Files to Modify:
- `Sources/DocTranslateApp/EPUBProcessor.swift`: Adds `characterBible: CharacterBible?` to `EPUBBook` and `extractSampleText(from:maxCharacters:)`.
- `Sources/DocTranslateApp/CheckpointManager.swift`: Adds `characterBible: CharacterBible?` to `TranslationCheckpoint` and persists it.
- `Sources/DocTranslateApp/LLMTranslationService.swift`: Adds `customSystemInstruction` parameter to `translate` and `translateBatch`, exposes `defaultSystemInstruction(from:to:)`, and implements `extractCharacterBible`.
- `Sources/DocTranslateApp/TranslationViewModel.swift`: Adds `@Published` properties (`characterBible`, `isAnalyzingCharacters`, `showCharacterBibleSheet`, `showUnanalyzedBibleAlert`), methods for character analysis and saving, and hooks prompt builder into EPUB translation.
- `Sources/DocTranslateApp/DocTranslateApp.swift`: Adds "Character Bible" toolbar button, status badge, unanalyzed confirmation alert, and sheet presentation.
- `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`: Adds Swift Testing suites for models, filtering, prompt generation, extraction parsing, and checkpoint persistence.

---

### Task 1: Domain Models (`CharacterBible.swift`)

**Files:**
- Create: `Sources/DocTranslateApp/CharacterBible.swift`
- Test: `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`

- [x] **Step 1: Write failing tests for CharacterBible models**

Add `@Suite("Character Bible Model Tests")` to `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`:

```swift
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
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter CharacterBibleModelTests`
Expected: FAIL (Cannot find `CharacterBible`, `CharacterProfile` in scope)

- [x] **Step 3: Implement `CharacterBible.swift`**

Create `Sources/DocTranslateApp/CharacterBible.swift` containing:
- `CharacterGender` (`.male`, `.female`, `.neutral`, `.unknown`)
- `NarrativePOV` (`.thirdPerson`, `.firstPerson`)
- `CharacterProfile` (conforming to `Identifiable`, `Sendable`, `Codable`, `Hashable`, `Equatable`)
- `RelationshipPair` (conforming to `Identifiable`, `Sendable`, `Codable`, `Hashable`, `Equatable`)
- `CharacterBible` (conforming to `Sendable`, `Codable`, `Equatable`, `Hashable`)

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter CharacterBibleModelTests`
Expected: PASS

---

### Task 2: Chapter Character Filter (`CharacterBibleFilter.swift`)

**Files:**
- Create: `Sources/DocTranslateApp/CharacterBibleFilter.swift`
- Test: `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`

- [x] **Step 1: Write failing tests for CharacterBibleFilter**

Add `@Suite("Character Bible Filter Tests")` to `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`:

```swift
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
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter CharacterBibleFilterTests`
Expected: FAIL (Cannot find `CharacterBibleFilter` in scope)

- [x] **Step 3: Implement `CharacterBibleFilter.swift`**

Create `Sources/DocTranslateApp/CharacterBibleFilter.swift`:
- Regex word-boundary matcher `\b\(NSRegularExpression.escapedPattern(for: token))\b` for names and aliases.
- Evaluates `presentCharacterIds`.
- Implements first-person narrator retention rule.

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter CharacterBibleFilterTests`
Expected: PASS

---

### Task 3: Pronoun Prompt Builder (`PronounPromptBuilder.swift`)

**Files:**
- Create: `Sources/DocTranslateApp/PronounPromptBuilder.swift`
- Test: `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`

- [x] **Step 1: Write failing tests for PronounPromptBuilder**

Add `@Suite("Pronoun Prompt Builder Tests")` to `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`:

```swift
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
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter PronounPromptBuilderTests`
Expected: FAIL (Cannot find `PronounPromptBuilder` in scope)

- [x] **Step 3: Implement `PronounPromptBuilder.swift`**

Create `Sources/DocTranslateApp/PronounPromptBuilder.swift`:
- Checks `targetLanguageCode == "vi" || targetLanguageCode == "vi-VN"`.
- If `chapterText` is non-empty, calls `CharacterBibleFilter.filterRelationships`. If empty/nil, uses all pairs.
- Formats character pairs and general notes.
- Returns enriched instruction.

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter PronounPromptBuilderTests`
Expected: PASS

---

### Task 4: Sample Extraction & LLM Extraction Service (`EPUBProcessor.swift` & `LLMTranslationService.swift`)

**Files:**
- Modify: `Sources/DocTranslateApp/EPUBProcessor.swift`
- Modify: `Sources/DocTranslateApp/LLMTranslationService.swift`
- Test: `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`

- [x] **Step 1: Write failing tests for extraction DTO parsing and sample extraction**

Add `@Suite("Character Extraction Parsing Tests")` to `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`:

```swift
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
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter CharacterExtractionParsingTests`
Expected: FAIL (`extractSampleText` and `parseCharacterBibleFromJSON` not found)

- [x] **Step 3: Implement extraction methods in `EPUBProcessor` and `LLMTranslationService`**

- In `EPUBProcessor.swift`: Implement `public static func extractSampleText(from book: EPUBBook, maxCharacters: Int = 25_000) -> String`.
- In `LLMTranslationService.swift`:
  - Expose `defaultSystemInstruction(from:to:) -> String`.
  - Add `customSystemInstruction: String? = nil` to `translate` and `translateBatch`.
  - Define `ExtractionResponseDTO` and implement `parseCharacterBibleFromJSON`.
  - Implement `extractCharacterBible(from sampleText: String, bookTitle: String, config: LLMConfig) async throws -> CharacterBible`.

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter CharacterExtractionParsingTests`
Expected: PASS

---

### Task 5: Checkpoints, EPUB Book, and ViewModel State Integration

**Files:**
- Modify: `Sources/DocTranslateApp/EPUBProcessor.swift` (`EPUBBook`)
- Modify: `Sources/DocTranslateApp/CheckpointManager.swift` (`TranslationCheckpoint`)
- Modify: `Sources/DocTranslateApp/TranslationViewModel.swift`
- Test: `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`

- [x] **Step 1: Write failing tests for Checkpoint persistence and ViewModel state**

Add tests to `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`:

```swift
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
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter testCheckpointWithCharacterBible`
Expected: FAIL (`characterBible` property missing on checkpoint)

- [x] **Step 3: Update `EPUBBook`, `TranslationCheckpoint`, and `TranslationViewModel`**

- Add `public var characterBible: CharacterBible?` to `EPUBBook` and `TranslationCheckpoint`.
- In `TranslationViewModel.swift`:
  - Add `@Published public var characterBible: CharacterBible? = nil`
  - Add `@Published public var isAnalyzingCharacters: Bool = false`
  - Add `@Published public var showCharacterBibleSheet: Bool = false`
  - Add `@Published public var showUnanalyzedBibleAlert: Bool = false`
  - Implement `analyzeCharactersForCurrentEPUB() async`
  - Implement `saveCharacterBible(_ bible: CharacterBible)`
  - In `translateEPUBStreamingLLM`: Compute `customSystemInstruction` per chapter using `PronounPromptBuilder.buildSystemInstruction` and pass it to `LLMTranslationService.translateBatch`.
  - In `retranslateEPUBNode`: Pass chapter's enriched instruction to `LLMTranslationService.translate`.

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter testCheckpointWithCharacterBible`
Expected: PASS

---

### Task 6: Review Sheet & UI Integration (`CharacterBibleSheet.swift` & `DocTranslateApp.swift`)

**Files:**
- Create: `Sources/DocTranslateApp/CharacterBibleSheet.swift`
- Modify: `Sources/DocTranslateApp/DocTranslateApp.swift`

- [x] **Step 1: Create `CharacterBibleSheet.swift`**

Implement SwiftUI view with:
- POV Picker (`Third Person`, `First Person`).
- Characters Tab: Table/list of `CharacterProfile` with inline editing, add, and delete (cascading to relationships).
- Pronoun Relationships Tab: Table of `RelationshipPair` with preset buttons (`anh - em`, `chị - em`, `ông - cháu`, `bà - cháu`, `chú - cháu`, `bác - cháu`, `cô - cháu`, `mình - cậu`, `tôi - bạn`, `tao - mày`, `bệ hạ - thần`).
- Notes Tab: TextEditor for `generalNotes`.
- Save & Cancel buttons calling `viewModel.saveCharacterBible(...)`.

- [x] **Step 2: Add toolbar button and alerts to `DocTranslateApp.swift`**

- When `viewModel.appMode == .epub && (viewModel.targetLanguage.id == "vi" || viewModel.targetLanguage.id == "vi-VN")`:
  - Add "Character Bible" button with badge indicator.
  - Bind `.sheet(isPresented: $viewModel.showCharacterBibleSheet) { CharacterBibleSheet(viewModel: viewModel) }`.
  - Bind `.alert` for `showUnanalyzedBibleAlert` when clicking "Translate" without character analysis.
  - Show informational warning when `viewModel.engine == .apple` that Apple Translator does not support custom bibles.

- [x] **Step 3: Build app to verify compilation**

Run: `swift build`
Expected: Build complete with 0 errors.

---

### Task 7: Full Test Suite & Bundle Verification

- [x] **Step 1: Run complete test suite**

Run: `swift test`
Expected: All 30+ tests in all suites pass.

- [x] **Step 2: Build release application bundle**

Run: `./bundle.sh`
Expected: `DocTranslateApp.app created successfully at .../DocTranslateApp.app`
