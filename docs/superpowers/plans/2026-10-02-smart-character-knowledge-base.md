# Smart Multi-Chapter Character Knowledge Base Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement remaining components of the Smart Multi-Chapter Character Knowledge Base: targeted micro-character extraction in `LLMTranslationService`, fast entity candidate detection in `CharacterBibleFilter`, and integration in `TranslationViewModel`.

**Architecture:** 
- `CharacterBibleFilter` provides heuristic candidate scanning (`scanUnknownEntities(in:existingBible:threshold:)`) to detect recurring capitalized candidate names that are not in the known Character Bible.
- `LLMTranslationService.extractSingleCharacterProfile(candidateName:contextExcerpts:existingBible:config:)` performs a targeted micro-prompt call to resolve a single character profile without re-analyzing the full book.
- `TranslationViewModel` integrates candidate discovery for chapters and allows auto-enriching chapter scopes.
- Unit tests verify scanning, micro-extraction parsing, and chapter integration.

**Tech Stack:** Swift 6 Concurrency (`Sendable`), macOS 15.0+ Sequoia, Apple Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`).

---

## File Structure

### Files to Modify:
- `Sources/DocTranslateApp/CharacterBibleFilter.swift`: Implement candidate entity scanner `scanUnknownEntities(in:existingBible:threshold:)`.
- `Sources/DocTranslateApp/LLMTranslationService.swift`: Implement `extractSingleCharacterProfile(candidateName:contextExcerpts:existingBible:config:)` and helper `parseSingleCharacterProfile(fromJSON:candidateName:)`.
- `Sources/DocTranslateApp/TranslationViewModel.swift`: Add JIT discovery helper `discoverNewCharacters(forChapterIndex:)`.
- `Tests/DocTranslateAppTests/DocTranslateAppTests.swift`: Add test suites for candidate scanning, micro-extraction parsing, and scope integration.

---

### Task 1: Candidate Entity Scanner (`CharacterBibleFilter.swift`)

- [x] **Step 1: Write failing tests for candidate entity scanning**
Add test in `DocTranslateAppTests.swift` testing that `CharacterBibleFilter.scanUnknownEntities` detects repeated names (>= threshold) while ignoring known characters and common stopwords.

- [x] **Step 2: Run test to verify it fails**
Run `swift test --filter CharacterBibleFilterTests` and verify failure.

- [x] **Step 3: Implement `scanUnknownEntities` in `CharacterBibleFilter.swift`**
Add regex heuristic, stopword filtering, and count aggregation.

- [x] **Step 4: Run test to verify it passes**
Run `swift test --filter CharacterBibleFilterTests` and verify pass.

---

### Task 2: Targeted Micro-Character Extraction (`LLMTranslationService.swift`)

- [x] **Step 1: Write failing tests for single character parsing**
Add unit test in `DocTranslateAppTests.swift` for `LLMTranslationService.parseSingleCharacterProfile(fromJSON:candidateName:)`.

- [x] **Step 2: Run test to verify it fails**
Run `swift test --filter CharacterExtractionParsingTests` and verify failure.

- [x] **Step 3: Implement single character extraction and parsing in `LLMTranslationService.swift`**
Implement `parseSingleCharacterProfile` and `extractSingleCharacterProfile(candidateName:contextExcerpts:existingBible:config:)`.

- [x] **Step 4: Run test to verify it passes**
Run `swift test --filter CharacterExtractionParsingTests` and verify pass.

---

### Task 3: JIT Chapter Character Discovery in `TranslationViewModel.swift`

- [x] **Step 1: Write test for ViewModel chapter entity discovery**
Test that running candidate scan on a chapter detects unknown entities and prepares them for chapter scope.

- [x] **Step 2: Implement `discoverCandidatesForChapter(chapterIndex:)` in `TranslationViewModel.swift`**
Integrate candidate scanner into ViewModel.

- [x] **Step 3: Run all unit tests to verify end-to-end functionality**
Run full `swift test` suite.
