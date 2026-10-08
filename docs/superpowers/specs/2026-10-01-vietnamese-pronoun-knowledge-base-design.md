# Design Spec: English-to-Vietnamese Pronoun Knowledge Base (Character Bible)

- **Date:** 2026-10-01
- **Status:** Approved
- **Target Platform:** macOS 15.0+ (Sequoia), Swift 6 Concurrency
- **Module:** DocTranslateApp

---

## 1. Problem Statement & Motivation

### 1.1 Linguistic Context
In English, personal pronouns (`I`, `you`, `he`, `she`, `we`, `they`) are largely neutral with respect to social hierarchy, age differences, and interpersonal relationships. 

In Vietnamese, personal pronouns encode intricate dimensions of:
- **Relative Age & Seniority:** *anh* (older brother / older male peer), *em* (younger sibling / younger peer), *chị* (older sister), *chú / bác / cô / dì* (uncle / aunt), *ông / bà* (grandfather / grandmother).
- **Interpersonal Closeness & Intimacy:** *mình / cậu* (close friends), *tôi / bạn* (polite / formal), *anh / em* (lovers / spouses), *tao / mày* (informal / intimate / rivals).
- **Social Status & Roles:** *thầy / cô - em* (teacher - student), *bệ hạ / ngài - thần / tôi* (royalty/lord - subject).

### 1.2 The Failure Mode in Document Translation
Because `DocTranslateApp` processes long documents and EPUB eBooks in chunked or paragraph units (typically 1,200 characters or chapter XHTML block nodes), LLMs without global context will translate pronouns inconsistently across paragraphs. For example, two interacting characters might fluctuate between *tôi / bạn* (stiff and distant), *anh / em* (romantic/familial), and *tao / mày* (hostile) within the exact same dialogue sequence.

### 1.3 Goals
1. Establish a **Character Bible** (knowledge base) for EPUB eBooks to track characters, genders, relative ages, and reciprocal pronoun pairs.
2. Provide **AI-assisted extraction** of characters and relationships from opening chapters, paired with a user review UI before translation starts.
3. Dynamically filter the Character Bible per chapter to inject only active character relationships into the translation system prompt, preventing token bloat.
4. Persist the Character Bible within translation checkpoints so sessions can be paused, resumed, or edited.

### 1.4 Non-Goals
- Overriding Apple Built-in Translator internals: Apple's on-device `Translation` framework does not accept custom system prompts or bibles. We inform the user of this limitation rather than attempting undocumented runtime hooks.
- General NLP entity linking for unreferenced side characters.
- Document Mode (`.document`) scoping: Phase 1 focuses exclusively on EPUB eBooks where multi-character narrative interactions occur. Single text/markdown document pronoun styling remains standard/neutral.

---

## 2. Architecture & Data Models

### 2.1 Core Domain Entities

```swift
import Foundation

public enum CharacterGender: String, CaseIterable, Identifiable, Codable, Sendable {
    case male = "Male"
    case female = "Female"
    case neutral = "Neutral"
    case unknown = "Unknown"
    public var id: String { rawValue }
}

public enum NarrativePOV: String, CaseIterable, Identifiable, Codable, Sendable {
    case thirdPerson = "Third Person"
    case firstPerson = "First Person"
    public var id: String { rawValue }
}

public struct CharacterProfile: Identifiable, Sendable, Codable, Hashable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var gender: CharacterGender
    public var relativeAge: String       // e.g. "elder", "adult", "younger", "child"
    public var roleOrStatus: String      // e.g. "ship captain", "younger sister", "mentor"

    public init(
        id: String = UUID().uuidString,
        name: String,
        aliases: [String] = [],
        gender: CharacterGender = .unknown,
        relativeAge: String = "adult",
        roleOrStatus: String = ""
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.gender = gender
        self.relativeAge = relativeAge
        self.roleOrStatus = roleOrStatus
    }
}

public struct RelationshipPair: Identifiable, Sendable, Codable, Hashable {
    public var id: String
    public var sourceCharacterId: String   // Character A
    public var targetCharacterId: String   // Character B
    public var selfPronoun: String         // How Character A refers to self (e.g. "anh", "tôi")
    public var addressingPronoun: String   // How Character A addresses Character B (e.g. "em", "bạn")
    public var contextNote: String?        // e.g. "Older brother to younger sister; warm/protective"

    public init(
        id: String = UUID().uuidString,
        sourceCharacterId: String,
        targetCharacterId: String,
        selfPronoun: String,
        addressingPronoun: String,
        contextNote: String? = nil
    ) {
        self.id = id
        self.sourceCharacterId = sourceCharacterId
        self.targetCharacterId = targetCharacterId
        self.selfPronoun = selfPronoun
        self.addressingPronoun = addressingPronoun
        self.contextNote = contextNote
    }
}

public struct CharacterBible: Sendable, Codable, Equatable, Hashable {
    public var bookTitle: String
    public var narrativePOV: NarrativePOV
    public var narratorCharacterId: String? // Set if narrativePOV == .firstPerson
    public var characters: [CharacterProfile]
    public var relationships: [RelationshipPair]
    public var generalNotes: String

    public init(
        bookTitle: String = "",
        narrativePOV: NarrativePOV = .thirdPerson,
        narratorCharacterId: String? = nil,
        characters: [CharacterProfile] = [],
        relationships: [RelationshipPair] = [],
        generalNotes: String = ""
    ) {
        self.bookTitle = bookTitle
        self.narrativePOV = narrativePOV
        self.narratorCharacterId = narratorCharacterId
        self.characters = characters
        self.relationships = relationships
        self.generalNotes = generalNotes
    }
}
```

### 2.2 Integration with Checkpoints, EPUB, and ViewModel
- `EPUBBook` gains an optional property: `public var characterBible: CharacterBible?`.
- `TranslationCheckpoint` gains an optional property: `public var characterBible: CharacterBible?` (mirrored from `currentEPUB?.characterBible` when saving).
- Checkpoints encode and decode `characterBible` automatically via `Codable`, allowing resume without re-analyzing the book.
- `TranslationViewModel` integrates the following state and control properties:
  ```swift
  @Published public var characterBible: CharacterBible? = nil
  @Published public var isAnalyzingCharacters: Bool = false
  @Published public var showCharacterBibleSheet: Bool = false
  @Published public var showUnanalyzedBibleAlert: Bool = false

  public func analyzeCharactersForCurrentEPUB() async
  public func saveCharacterBible(_ bible: CharacterBible)
  ```

---

## 3. Extraction & Prompt Injection Pipeline

### 3.1 Upfront Extraction (`LLMTranslationService.extractCharacterBible`)
When triggered by the user in the UI:
1. `EPUBProcessor.extractSampleText` compiles clean text from parsed chapter nodes (`chapter.nodes.map(\.originalText)`), avoiding raw XHTML tags:
   ```swift
   public static func extractSampleText(
       from book: EPUBBook,
       maxCharacters: Int = 25_000
   ) -> String
   ```
2. The service sends an extraction prompt to the active LLM:
   ```swift
   public static func extractCharacterBible(
       from sampleText: String,
       bookTitle: String,
       config: LLMConfig
   ) async throws -> CharacterBible
   ```
   Prompt schema:
   ```text
   You are an expert literary translator and linguist specializing in English-to-Vietnamese translation.
   Analyze the provided text sample from a book and identify the main characters and their social/familial relationships.
   Determine the appropriate reciprocal Vietnamese pronouns (xưng hô) for dialogues between each pair.
   
   Return ONLY a valid JSON object matching this schema:
   {
     "narrativePOV": "First Person" | "Third Person",
     "narratorName": "string or null",
     "characters": [
       { "name": "Name", "aliases": ["alias1"], "gender": "Male"|"Female"|"Neutral"|"Unknown", "relativeAge": "string", "roleOrStatus": "string" }
     ],
     "relationships": [
       { "source": "CharA", "target": "CharB", "selfPronoun": "e.g. anh", "addressingPronoun": "e.g. em", "contextNote": "string" }
     ],
     "generalNotes": "string"
   }
   ```
3. To bridge the name-based extraction output to UUID-based domain models and guarantee decoding resilience against missing fields or keys:
   ```swift
   struct ExtractionResponseDTO: Codable {
       let narrativePOV: String?
       let narratorName: String?
       struct CharDTO: Codable {
           let name: String
           let aliases: [String]?
           let gender: String?
           let relativeAge: String?
           let roleOrStatus: String?
       }
       let characters: [CharDTO]?
       struct RelDTO: Codable {
           let source: String
           let target: String
           let selfPronoun: String
           let addressingPronoun: String
           let contextNote: String?
       }
       let relationships: [RelDTO]?
       let generalNotes: String?
   }
   ```
   The service builds `CharacterProfile` instances with unique UUIDs, maps names and aliases to IDs, resolves `sourceCharacterId` and `targetCharacterId`, and identifies `narratorCharacterId` if present.

### 3.2 Chapter-Specific Context Filter (`CharacterBibleFilter`)
Defined as an isolated, independently testable component:

```swift
public struct CharacterBibleFilter: Sendable {
    /// Filters the global character bible to return only relationship pairs active in the specified chapter text.
    public static func filterRelationships(
        in bible: CharacterBible,
        forChapterText chapterText: String
    ) -> [RelationshipPair]
}
```

Implementation logic:
1. Scans `chapterText` for each character's `name` and `aliases` using word-boundary regular expressions (`\b\(NSRegularExpression.escapedPattern(for: token))\b`, case-insensitive).
2. Sets `presentCharacterIds = Set(bible.characters.filter { char in containsNameOrAlias(text: chapterText, char: char) }.map { $0.id })`.
3. Filter rules:
   - A `RelationshipPair` is included if:
     - Both `sourceCharacterId` and `targetCharacterId` are in `presentCharacterIds`, OR
     - If `bible.narrativePOV == .firstPerson` and either party is `bible.narratorCharacterId` and the other party is in `presentCharacterIds` (first-person narrators rarely speak their own names in dialogue).
   - If no characters are matched in Chapter $K$, an empty list of relationship pairs is returned.

### 3.3 Prompt Builder (`PronounPromptBuilder`)
Defined as an isolated, independently testable component:

```swift
public struct PronounPromptBuilder: Sendable {
    /// Enriches the base system instruction with Vietnamese pronoun directives if target is Vietnamese and a bible is available.
    public static func buildSystemInstruction(
        baseInstruction: String,
        targetLanguageCode: String,
        bible: CharacterBible?,
        chapterText: String?
    ) -> String
}
```

When `targetLanguageCode` is `"vi"` or `"vi-VN"` and a `bible` is provided:
1. Relationship resolution:
   - If `chapterText` is non-nil and non-empty, calls `CharacterBibleFilter.filterRelationships(in: bible, forChapterText: text)`.
   - If `chapterText` is nil or empty (e.g. global fallback), uses all relationship pairs in `bible.relationships`.
2. Formats a structured directive:
   ```text
   VIETNAMESE PRONOUN & CHARACTER GUIDELINES:
   Narrative Perspective: [POV]
   Active Character Pronoun Pairs:
   - John -> Mary: Calls self "anh", addresses Mary as "em" (Context: older brother / protective)
   - Mary -> John: Calls self "em", addresses John as "anh"
   - Elena -> Arthur: Calls self "tôi", addresses Arthur as "anh" (Context: colleagues, Arthur older)
   General Notes: [bible.generalNotes if non-empty]
   Directives:
   1. Strictly maintain these reciprocal pronouns in dialogues between these characters.
   2. Do NOT default to generic or sterile "tôi / bạn" in dialogue when character relationships dictate intimacy or seniority.
   3. Keep narrative description natural and consistent with the identified perspective.
   ```
3. Appends directives to `baseInstruction`. If target is not Vietnamese or bible is nil, returns `baseInstruction` unchanged.
4. Single-node re-translations (`retranslateEPUBNode`) also invoke `PronounPromptBuilder` with the parent chapter's text to preserve contextual consistency.

### 3.4 Service Signatures & Integration Contracts
`LLMTranslationService` exposes its default system instruction builder:
```swift
public static func defaultSystemInstruction(
    from sourceLang: String,
    to targetLang: String
) -> String
```
Method signatures accept an optional `customSystemInstruction`:
```swift
public static func translate(
    text: String,
    from sourceLang: String,
    to targetLang: String,
    config: LLMConfig,
    customSystemInstruction: String? = nil
) async throws -> String

public static func translateBatch(
    items: [(id: Int, text: String)],
    from sourceLang: String,
    to targetLang: String,
    config: LLMConfig,
    fallbackConfig: LLMConfig? = nil,
    customSystemInstruction: String? = nil,
    onFallbackUsed: (@Sendable (Int, String) async -> Void)? = nil,
    onItemCompleted: @escaping @Sendable (Int, String) async -> Void
) async throws
```

---

## 4. User Interface & Review Workflow

### 4.1 Trigger Points
- **Strictly User-Initiated**: Character extraction never executes automatically in the background to prevent unprompted API billing or local compute load.
- **Toolbar Action**: A "Character Bible" button (`person.2.badge.gearshape`) is displayed in the EPUB toolbar when target language is Vietnamese.
- **Badge Indicators**:
  - `Not Analyzed` (gray badge)
  - `Analyzing...` (spinning progress indicator, disabled interaction)
  - `N Characters Configured` (accent color)
- **Translation Prompt**: If the user clicks "Translate" on an EPUB with Vietnamese target language without having analyzed characters, a non-blocking confirmation dialog (`showUnanalyzedBibleAlert`) offers: *"Analyze characters first for consistent Vietnamese pronouns, or translate directly with standard neutral pronouns?"*

### 4.2 Review Sheet (`CharacterBibleSheet`)
A dedicated sheet presented modally or via inspector:
1. **Header**: Book title, Narrative POV picker, and "Analyze with AI" button.
2. **Characters Tab**:
   - Editable list: Name, Gender picker, Relative Age, and Role.
   - "+ Add Character" and "Delete" buttons.
   - Deleting a character automatically cascade-deletes all `RelationshipPair` entries where that character is the `source` or `target`.
3. **Pronoun Relationships Tab**:
   - Matrix showing Character A $\rightarrow$ Character B interactions.
   - Quick-preset dropdowns automatically create both directed reciprocal pairs when selected:
     - Selecting `anh - em` between A and B creates:
       - Pair 1 (A $\rightarrow$ B): self=`anh`, addressing=`em`
       - Pair 2 (B $\rightarrow$ A): self=`em`, addressing=`anh`
     - Distinct gender-disambiguated presets include:
       - `anh - em` (older male - younger female/male, lovers)
       - `chị - em` (older female - younger)
       - `ông - cháu` (grandfather - grandchild)
       - `bà - cháu` (grandmother - grandchild)
       - `chú - cháu` (younger uncle - younger)
       - `bác - cháu` (older uncle/aunt - younger)
       - `cô - cháu` (aunt - younger)
       - `mình - cậu` (close friends)
       - `tôi - bạn` (polite peers)
       - `tao - mày` (intimate informal or rivals)
       - `bệ hạ - thần` (monarch - subject)
4. **General Notes Section**:
   - Multi-line text editor for `generalNotes` (e.g. style hints, custom historical tone like "chàng / nàng").
5. **Footer**: "Save & Close" and "Reset to Defaults".

---

## 5. Compatibility, Fallback, and Error Handling

### 5.1 Apple Translation Framework
- Apple's `TranslationSession` takes `(sourceText, clientIdentifier)` without custom instruction support.
- If the user selects the `.apple` engine when a Character Bible is active:
  - An informational banner displays: *"Apple Built-in Translator does not support custom Character Bibles. Switch to Ollama or OpenAI to apply pronoun guidelines."*
  - If auto-fallback cascades to Apple Translator during an outage, the fallback banner notes: *"Fell back to Apple Translator (Character Bible temporarily bypassed)."*
- **Extraction Engine Selection**: If the user clicks "Analyze Characters" while the active engine is `.apple`, `analyzeCharactersForCurrentEPUB()` checks if local Ollama is reachable, falling back to OpenAI if an API key is present. If neither is available, an error banner is displayed: *"Cannot analyze characters: Apple Built-in Translator does not support LLM extraction, and neither local Ollama nor OpenAI credentials are available."*

### 5.2 Extraction Failure Resilience
- If extraction fails to return valid JSON, `LLMTranslationService` attempts regex extraction of `{ ... }` blocks.
- If completely unparsable, an empty `CharacterBible` is initialized, and an informational banner appears: *"Could not automatically detect characters. You can add characters manually or continue with standard translation."*

---

## 6. Testing Strategy

Using Apple's modern **Swift Testing** framework (`import Testing`, `@Suite`, `@Test`, `#expect`):

1. **`CharacterBibleModelTests`**:
   - Test JSON encoding and decoding of `CharacterBible`, `CharacterProfile`, and `RelationshipPair`.
   - Test checkpoint persistence and restoration containing a `CharacterBible`.
2. **`CharacterBibleFilterTests`**:
   - Test that given a chapter with only 2 of 5 characters present, the filter returns only relevant relationship pairs.
   - Test that first-person POV narrator rules are always retained.
3. **`PronounPromptBuilderTests`**:
   - Test that the prompt builder formats valid Vietnamese pronoun directives when target is Vietnamese.
   - Test that prompt builder skips pronoun directives when target is Spanish, French, or other non-Vietnamese languages.
4. **`ExtractionParsingTests`**:
   - Test parser resilience against LLM outputs wrapped in `<think>` tags, markdown code blocks, or preamble commentary.
