# Design Spec: Smart Multi-Chapter Character Knowledge Base (Stratified Sampling & Incremental Discovery)

- **Date:** 2026-10-02
- **Status:** Approved
- **Target Platform:** macOS 15.0+ (Sequoia), Swift 6 Concurrency
- **Module:** DocTranslateApp

---

## 1. Problem Statement & Motivation

### 1.1 Limitations of Initial 25k Character Sampling
Currently, `EPUBProcessor.extractSampleText(from:maxCharacters: 25_000)` iterates through the beginning chapters of an EPUB book and cuts off as soon as 25,000 characters are reached. In standard novels (often 300,000 to 1,000,000+ characters across 20–50 chapters), 25,000 characters only covers Chapter 1 and part of Chapter 2.
- Major and secondary characters introduced in later chapters (e.g. Chapter 5, Chapter 12) are completely omitted from the `CharacterBible`.
- Relationships established later in the story lack pronoun definitions, causing the LLM to revert to inconsistent, stiff defaults (such as *tôi / bạn*) when those characters finally appear.

### 1.2 The Dilemma of Per-Chapter Global Updates
A naive approach is to run character extraction after every chapter and update the `CharacterBible.characters` and `relationships` globally. However, this causes severe architectural problems:
1. **Context Pollution & Hallucinations:** Repeated unstructured extraction creates duplicate entries for the same person (e.g. *"The Captain"*, *"John"*, *"Johnny"*, *"Mr. Watson"*, *"Dr. Watson"*) without a unified entity resolution pass.
2. **Relationship Mutation Across Time:** Social hierarchies and intimacies change as plots progress (e.g. enemies become lovers, subordinates get promoted). Forcing changes into a flat `Global` scope overwrites earlier relational states, causing retrospective inconsistency if earlier chapters are re-translated.
3. **Translation Latency & Token Overhead:** Running an extra LLM extraction call before every chapter doubles translation time and costs.

### 1.3 Goals
1. **Stratified Book Sampling:** Redesign initial sample extraction to take representative samples across the whole book (prologue/opening chapters + evenly distributed chapter snapshots + dedicated cast/character pages if present) within a token-friendly budget (~25,000–30,000 characters).
2. **Deduplicated & Scoped Character Management:** Clear separation between **Global Ground Truth** (book-wide main characters) and **Chapter Scope** (chapter-specific characters and mutating relationships).
3. **Incremental Just-In-Time (JIT) Discovery:** Lightweight detection of novel named entities in individual chapters before translation, with optional micro-extraction.
4. **Interactive UI Capabilities:** Allow users to trigger "Analyze Current Chapter" on demand and "Promote to Global" for characters discovered locally.

---

## 2. Architecture & Algorithmic Strategy

```
                          [EPUB eBook Loaded]
                                   │
                                   ▼
             [Stratified Book Sampling (25k-30k chars)]
        ┌──────────────────────────┬──────────────────────────┐
        │ Opening Chapters (40%)   │ Distributed Slices (50%) │ Cast Pages (10%)
        └──────────────────────────┴──────────────────────────┘
                                   │
                                   ▼
                 [Initial Global Character Bible]
                                   │
                                   ▼
                    [Translate Chapter k Loop]
                                   │
        ┌──────────────────────────┴──────────────────────────┐
        ▼                                                     ▼
[Known Characters Present?]                           [Unknown Entities?]
  Matched in Global / Scope                             Candidate Capitalized Tokens
        │                                                     │
        │                                             [JIT Micro-Discovery]
        │                                         (Extracts only new character)
        │                                                     │
        └──────────────────────────┬──────────────────────────┘
                                   │
                                   ▼
                     [ChapterScope vs Global Merge]
                                   │
                                   ▼
                [PronounPromptBuilder: Scoped System Prompt]
                                   │
                                   ▼
                        [Translate Chapter Content]
```

### 2.1 Stratified Book Sampling Algorithm (`EPUBProcessor`)

Instead of greedy sequential reading from byte 0, `EPUBProcessor.extractStratifiedSampleText` applies weighted distribution:
1. **Cast / Dramatis Personae Detection:**
   Inspect chapter titles or file IDs for keywords (`character`, `dramatis personae`, `cast`, `danh sách nhân vật`, `nhân vật`). If present, include up to 4,000 characters directly.
2. **Anchor Slices (Opening):**
   Reserve 40% of the sample budget (~10,000 characters) for Chapter 1 & 2 to capture the narrator, setting, and primary protagonist.
3. **Distributed Milestone Slices:**
   Evenly distribute the remaining 50–60% budget across the rest of the chapters:
   - For a book with $N$ remaining chapters, calculate step interval $s = \max(1, N / 10)$.
   - Extract dialogue-dense or text-dense windows (~1,000–1,500 characters each) from selected milestone chapters.
   - Tag each section with a clear chapter separator comment (e.g. `--- [Excerpt from Chapter 8: The Meeting] ---`) so the LLM understands multi-scene context.

### 2.2 Scoping & State Management: Global vs. Chapter

The `CharacterBible` data model already supports `chapterScopes: [String: ChapterScope]`. We formalize the rules:
- **Global Scope:**
  - Contains enduring characters who appear across multiple arcs.
  - Baseline relationship pairs (e.g. Holmes & Watson are lifelong colleagues/friends: *tôi - anh* or *anh - em*).
- **Chapter Scope (`ChapterScope`):**
  - Contains ephemeral characters (e.g. a coachman or shopkeeper who only speaks in Chapter 4).
  - Contains situational relationship overrides (e.g. Chapter 12: Character A is disguised and addresses Character B as a stranger).
  - Merged deterministically via `CharacterBibleFilter.effectiveScope(forChapterId:in:)`: Local definitions override Global definitions for that chapter only.

### 2.3 Incremental JIT Discovery (Just-In-Time)

When translating Chapter $C$:
1. **Lightweight Candidate Scan:**
   A fast heuristic scans words matching `\b[A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,})*\b`.
   Filter out common stopwords (days, months, standard capitalized English nouns).
2. **Diff Against Known Registry:**
   Tokens matching known `name` or `aliases` in the `CharacterBible` are ignored.
3. **Trigger Threshold:**
   If an unrecognized candidate entity occurs $\ge 3$ times in the chapter:
   - Mark as an "Unresolved Candidate".
   - If user enabled automatic enrichment, run a lightweight micro-prompt with LLM sending only sentences containing the entity:
     *"Determine gender, age tier, and Vietnamese dialogue pronouns for [Entity] interacting with known characters."*
   - Add the resolved entity to `ChapterScope.characters`.

---

## 3. Component Details & Interface Changes

### 3.1 `EPUBProcessor.swift`
Add method:
```swift
public static func extractStratifiedSampleText(
    from book: EPUBBook,
    maxCharacters: Int = 30_000
) -> String
```
- Preserves backward compatibility by falling back to standard extraction if book has $\le 2$ chapters.

### 3.2 `LLMTranslationService.swift`
Support targeted micro-extraction:
```swift
public static func extractSingleCharacterProfile(
    candidateName: String,
    contextExcerpts: [String],
    existingBible: CharacterBible,
    config: LLMConfig
) async throws -> CharacterProfile?
```

### 3.3 `CharacterBibleSheet.swift`
- Add button: **"Analyze Current Chapter"** allowing on-demand AI analysis of just the active chapter.
- Add row action: **"Promote to Global"** on any character listed in a chapter scope, migrating it into `workingBible.characters`.

---

## 4. Edge Cases & Safeguards

1. **Short Books / Novellas (< 30,000 characters total):**
   The entire text is analyzed at once, ensuring 100% coverage without sampling artifacts.
2. **Homonyms & Name Variations (Deduplication):**
   Before creating any new character profile, fuzzy substring matching checks if the candidate is already an alias or surname of an existing character (e.g. "Elizabeth" vs "Lizzy" vs "Miss Bennet").
3. **Token Budgets & Non-English/Multi-Language Texts:**
   Regex word boundaries properly support Unicode characters.

---

## 5. Verification & Testing Strategy

1. **Unit Test for Stratified Extraction:**
   Verify `extractStratifiedSampleText` returns text from beginning, middle, and late chapters in synthetic multi-chapter EPUB fixtures.
2. **Unit Test for Cast Page Detection:**
   Verify that chapters titled "Characters" or "Dramatis Personae" receive highest sampling priority.
3. **Filter & Scope Verification:**
   Verify that local chapter characters take precedence in translation prompts without contaminating the global registry.
