# Copilot Instructions for NovelTranslator

NovelTranslator is a native macOS SwiftUI application targeting macOS 15.0+ (Sequoia). It translates long text/markdown documents and EPUB eBooks/novels using Apple's on-device Translation framework, local Ollama LLMs, or remote OpenAI-compatible endpoints, featuring specialized character bibles, pronoun consistency, and audiobook TTS generation.

---

## 1. Build, Test, and Packaging Commands

### Build Commands
- **Debug build**: `swift build`
- **Release build**: `swift build -c release`
- **Package macOS App Bundle**: `./bundle.sh`
  - Compiles the release binary, creates `NovelTranslator.app`, generates `Info.plist` with `CFBundleIdentifier` (`com.antigravity.NovelTranslator`), and ad-hoc signs the bundle via `codesign`.
  - Required for proper integration with Apple's Translation framework daemon and on-device language pack downloads.

### Run Commands
- **Run pre-packaged bundle (Recommended)**: `open NovelTranslator.app`
- **Run directly via SPM**: `swift run NovelTranslator`
  - Note: Activates as a regular GUI application via `NSApp.setActivationPolicy(.regular)` in `AppDelegate`.

### Test Commands
The test suite uses Apple's **Swift Testing** framework (`import Testing`, `@Suite`, `@Test`, `#expect`), configured with the `libTestingMacros.dylib` compiler plugin in `Package.swift`.

- **Run all tests**: `swift test`
- **Run a specific test suite**: `swift test --filter "<SuiteName>"`
  - Example: `swift test --filter DocumentChunkerTests`
  - Example: `swift test --filter EPUBProcessorTests`
  - Example: `swift test --filter "LLM Translation Service Tests"`
- **Run a single test case**: `swift test --filter "<SuiteName>/<testFunctionName>"`
  - Example: `swift test --filter DocumentChunkerTests/testEmptyDocument`
  - Example: `swift test --filter EPUBProcessorTests/testSampleEPUBWorkflow`
  - Example: `swift test --filter "LLM Translation Service Tests/testSanitizeThinkingTags"`

---

## 2. High-Level Architecture

The codebase is organized into a single Swift Package target (`NovelTranslator`) and a test target (`NovelTranslatorTests`).

```
Sources/NovelTranslator/
├── NovelTranslatorApp.swift       # App entry point, AppDelegate, SwiftUI views (ContentView, toolbar, reader)
├── TranslationViewModel.swift     # Central ObservableObject coordinator for all translation modes & engines
├── SupportedLanguage.swift        # Language models, language pairs, and Locale.Language mappings
├── DocumentChunker.swift          # Paragraph chunking and formatting-preserving document reassembly
├── EPUBProcessor.swift            # EPUB container/OPF parser, XHTML node extractor, zip/unzip repackager
├── CharacterBible.swift           # Domain models for characters, relationships, and pronoun matrices
├── CharacterBibleFilter.swift     # Per-chapter dynamic character and relationship filtering
├── PronounPromptBuilder.swift     # Systematic Vietnamese pronoun & literary directive prompt builder
├── CharacterBibleSheet.swift      # Interactive UI for reviewing & editing character bibles
├── BatchXMLParser.swift           # Batched XHTML node translation and omitted node recovery
├── BatchChunker.swift             # Token-budgeted batch node chunking
├── AudioPlayerManager.swift       # Chapter audio playback manager, cache, and scrub control
├── TTSService.swift               # Text-to-Speech service (Apple Speech Synthesis + VieNeu TTS bridge)
├── TTSPlayerBarView.swift         # Sleek bottom audio bar with controls and speed adjustments
├── TTSExportSheet.swift           # Audio batch export sheet
├── ModelManagerSheet.swift        # Multi-model profile manager and fallback chains
├── PromptSettingsSheet.swift      # Customizable prompts for translation and analysis
├── LLMTranslationService.swift    # OpenAI/Ollama REST client, TaskGroup concurrency, output sanitization
├── CheckpointManager.swift        # Multi-session state persistence and resume management
└── EnvConfigManager.swift         # Multi-tiered .env, ProcessInfo, and UserDefaults configuration loader
```

### Core Data & Control Flow

1. **Dual Application Modes (`AppMode`)**:
   - `.document`: Translates plain text or markdown files (`.txt`, `.md`).
   - `.epub`: Unpacks `.epub` archives, parses the spine to maintain chapter reading order, extracts translatable text nodes from XHTML tags, and rebuilds a valid EPUB upon completion.

2. **Triple Translation Engines (`TranslationEngine`)**:
   - `.apple`: Apple's native `Translation` framework. Translates on-device without internet access.
   - `.ollama`: Local LLM engine connecting to `http://localhost:11434/v1` with dynamic model discovery.
   - `.openAI`: Remote or custom OpenAI-compatible API (e.g. OpenAI, OpenRouter, LM Studio, vLLM, DeepSeek).

3. **SwiftUI & Apple Translation Bridge**:
   - `NovelTranslatorApp.swift` binds `.translationTask(viewModel.configuration)` on `ContentView`.
   - When the user starts translation with the `.apple` engine, `TranslationViewModel.prepareAppleConfiguration()` sets a new `TranslationSession.Configuration`.
   - The view modifier receives an active `TranslationSession` and invokes `await viewModel.translate(using: session)`, which streams translations via `session.translate(batch:)`.

4. **Concurrent Batch LLM Translation**:
   - `LLMTranslationService.translateBatch` uses a worker-queue pattern built on `withThrowingTaskGroup`.
   - Concurrency is throttled to `config.concurrency` (default 3–4 workers) to prevent rate limits or local GPU exhaustion.
   - An optional fallback configuration (`fallbackConfig`) automatically retries failed items using a secondary model/engine.

5. **Multi-Session Checkpoint & Resume Pipeline**:
   - In-progress translations save checkpoints to `~/Library/Application Support/NovelTranslator/Checkpoints/<id>.json`.
   - For EPUB mode, the unpacked working directory is saved under `<id>_EPUB/`.
   - Sessions are saved automatically on app quit (`AppDelegate.applicationWillTerminate`), when cancelling translation, or manually.
   - Supports pausing, resuming from partial progress, and managing multiple distinct translation sessions.

6. **Configuration Precedence**:
   - `EnvConfigManager.loadEnvVariables()` resolves configuration in descending priority:
     1. `UserDefaults` standard values (GUI overrides)
     2. `~/Library/Application Support/NovelTranslator/.env`
     3. Project root `.env`
     4. Process environment variables (`ProcessInfo.processInfo.environment`)

---

## 3. Key Conventions & Technical Invariants

### Swift Concurrency & Sendability
- Target platform is macOS 15.0+ with `.enableUpcomingFeature("ApproachableConcurrency")`.
- All model structs (`DocumentChunk`, `TranslatableNode`, `EPUBChapter`, `EPUBBook`, `SupportedLanguage`, `TranslationCheckpoint`, `TranslationCheckpointSummary`, `LLMConfig`) conform to `Sendable`, `Codable`, and `Identifiable`.
- State updates intended for SwiftUI must be dispatched on `@MainActor` or through `@Published` properties on `TranslationViewModel`.

### Formatting Preservation & Delimiters
- `DocumentChunk` and `TranslatableNode` store their associated delimiters (`delimiter`, `tagOpen`, `tagClose`, `fullMatch`).
- `DocumentChunker.assemble()` and `EPUBProcessor.applyTranslations()` reconstruct the final document by substituting only translatable content while preserving whitespace, empty lines, and original XHTML layout.
- When modifying chunking or node extraction, ensure that assembling untranslated chunks or nodes reproduces the exact original document.

### LLM Output Sanitization
- Reasoning models (e.g., DeepSeek-R1, Qwen reasoning variants, TranslateGemma) often include thinking traces, markdown blocks, or conversational commentary.
- All LLM translations pass through `LLMTranslationService.cleanAndValidateTranslation()`:
  - Strips `<think>`, `<thought>`, `<reasoning>` tags (including unclosed tags).
  - Detects `Thinking Process:` headers and extracts downstream final translation sections.
  - Strips markdown code fences (````markdown ... ````) and conversational preambles/postambles.
  - Strips outer quotation marks when the source text was unquoted.
  - Never allow raw LLM thought chains or markdown code fences into translated documents or EPUB chapters.

### EPUB File Invariants
- EPUB packing and unpacking use system binaries (`/usr/bin/unzip` and `/usr/bin/zip`).
- Per the EPUB specification, the `mimetype` file must be stored uncompressed (`-X0`) as the first entry in the archive before other files are added with standard compression (`-r9`).
- Extracted XHTML translatable tags include `<p>`, `<h1>`–`<h6>`, `<li>`, `<blockquote>`, `<figcaption>`, and `<title>`.

### Testing Conventions
- Do not use `XCTest`. Write new tests using the `Testing` library (`@Suite`, `@Test`, `#expect(...)`).
- Temporary files in tests must be created in `FileManager.default.temporaryDirectory` and cleaned up with `defer { try? FileManager.default.removeItem(at: tempURL) }`.
