# NovelTranslator

<p align="center">
  <strong>Native macOS AI Studio for Translating Novels, EPUB eBooks, and Long-Form Literature</strong><br>
  <em>Preserves book formatting, maintains character & pronoun consistency, and narrates chapters with neural Text-to-Speech.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2015.0+%20(Sequoia)-black?style=flat-square&logo=apple" alt="macOS 15.0+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/Engines-Apple%20|%20Ollama%20|%20OpenAI-blue?style=flat-square" alt="Engines">
  <img src="https://img.shields.io/badge/Features-Character%20Bible%20|%20TTS%20Audiobook-purple?style=flat-square" alt="Features">
</p>

---

## Overview

Translating literary fiction, web novels, and EPUB eBooks with generic machine translation frequently breaks down:
1. **Pronoun & Dialogue Inconsistency**: In nuanced languages like Vietnamese, pronouns encode age, relationship status, and intimacy (*anh/em*, *cô/chú*, *tôi/bạn*, *chàng/nàng*). Standard translators scramble pronouns between paragraphs.
2. **Broken Formatting & Layout**: Naive translators strip EPUB XHTML structure, destroying chapter spines, styling, footnotes, and typography.
3. **Context Window Loss**: Translating sentence-by-sentence loses tone, character motivations, and narrative pacing.

**NovelTranslator** is purpose-built to solve these challenges. Built specifically for macOS Sequoia with Swift 6 Concurrency and SwiftUI, it integrates an upfront **Character Bible knowledge base**, **batched XML chapter chunking**, **triple AI translation engines** (Apple on-device, local Ollama, and cloud LLMs), and an **audiobook narration studio**.

---

## Key Features

### 1. Smart Character Bible & Pronoun Knowledge Base
- **Automatic Character Discovery**: Scans book chapters using LLM entity extraction to identify character names, aliases, genders, approximate ages, and social roles.
- **Reciprocal Pronoun Matrix (*Xưng hô*)**: Maps dialogue pronoun pairs between interacting characters (e.g., senior peer vs. junior peer, lovers, formal rivals).
- **Narrative POV & Third-Person Rules**: Detects first-person vs. third-person narrative points of view and enforces consistent narrator pronouns.
- **Dynamic Chapter-Scoped Filtering**: Only injects characters active within the current chapter into the translation prompt, preventing token explosion while guaranteeing consistent tone.
- **Interactive Review Sheet**: Inspect, modify, or add character entries and pronoun rules before or during translation.

### 2. 100% Structure-Preserving EPUB Processing
- **Compliant EPUB Container Parser**: Unpacks `.epub` archives and parses OPF package manifests and spines in true reading order.
- **XML Tag Protection**: Extracts translatable text from XHTML elements (`<p>`, `<h1>`–`<h6>`, `<li>`, `<blockquote>`, `<figcaption>`, `<title>`) while preserving attributes, inline formatting, images, and CSS stylesheets.
- **Batched XML Processing**: Groups contiguous chapter paragraphs up to a configurable word target (default: 1,200 words) inside structured `<batch>` tags, enabling LLMs to understand conversational flow without hallucinating tag positions.
- **Omitted Node Recovery**: Automatically identifies missing node IDs and translates omitted items individually to prevent text drops.
- **Clean EPUB Repackaging**: Reassembles translated XHTML and archives standard EPUBs compatible with Apple Books, Kindle, and e-readers.

### 3. Triple Translation Engines
- **Apple On-Device Translation**: 100% private, zero-latency, on-device translation using Apple's native `Translation` framework (macOS 15.0+). No internet connection or API keys required.
- **Ollama (Local LLMs)**: Connects to local Ollama instances (`http://localhost:11434/v1`) with automatic model discovery (`translategemma:4b`, `qwen3.5:2b`, `deepseek-r1`, etc.).
- **OpenAI & Custom Endpoints**: Supports OpenAI (`gpt-4o-mini`, `gpt-4o`), Claude, DeepSeek, OpenRouter, vLLM, LM Studio, or any OpenAI-compatible API.
- **Multi-Model Profiles & Fallback Chain**: Define prioritized model profiles. If a primary endpoint experiences rate limits or network errors, NovelTranslator automatically fails over to backup models.

### 4. Integrated Audiobook Studio (TTS)
- **High-Fidelity Neural Narration**: Integrated bridge to **VieNeu TTS** for ultra-natural Vietnamese voice synthesis (Trúc Ly, Phạm Tuyên, Mỹ Duyên, etc.).
- **Apple Speech Synthesis**: Native on-device system speech synthesis for dozens of global languages.
- **Interactive Audio Player Bar**: Floating bottom player with live progress scrubbing, play/pause, chapter jumping, and variable playback speeds (0.75x to 2.0x).
- **Batch Chapter Audio Export**: Export individual or full book chapters to `.wav` files with custom voice assignments and speed settings.

### 5. Multi-Session Checkpoint & Resume Pipeline
- **Auto-Save on Progress & Quit**: State is automatically persisted under `~/Library/Application Support/NovelTranslator/Checkpoints/`.
- **Multi-Book Session Manager**: Switch between multiple ongoing novel translations seamlessly.
- **Selective & Re-translation**: Re-translate individual chapters or selective paragraphs without re-running the entire book.

---

## Architecture Overview

```
Sources/NovelTranslator/
├── NovelTranslatorApp.swift       # App entry point, menu commands, and main window
├── TranslationViewModel.swift     # Central ObservableObject coordinating state & engines
├── SupportedLanguage.swift        # Language definitions and Locale.Language mappings
├── DocumentChunker.swift          # Text & Markdown paragraph chunker
├── EPUBProcessor.swift            # EPUB container/OPF parser, node extractor, and zip packager
├── CharacterBible.swift           # Domain models: CharacterProfile, RelationshipPair, CharacterBible
├── CharacterBibleFilter.swift     # Dynamic chapter entity scanning and prompt filtering
├── PronounPromptBuilder.swift     # Vietnamese pronoun prompt builder & literary directives
├── CharacterBibleSheet.swift      # SwiftUI review sheet for characters and relationships
├── BatchXMLParser.swift           # Batched XML translation parser with omitted node recovery
├── BatchChunker.swift             # Token-budgeted batch node chunking
├── AudioPlayerManager.swift       # Chapter audio playback manager, cache, and scrubbing
├── TTSService.swift               # Text-to-Speech coordinator (Apple Speech + VieNeu TTS)
├── TTSPlayerBarView.swift         # Sleek bottom audio control bar
├── TTSExportSheet.swift           # Audio batch export sheet
├── ModelManagerSheet.swift        # Multi-model profile manager and fallback chains
├── PromptSettingsSheet.swift      # Customizable prompts for translation and analysis
├── LLMTranslationService.swift    # REST client for Ollama/OpenAI, task throttling, output sanitizer
├── CheckpointManager.swift        # Multi-session state persistence and resume management
└── EnvConfigManager.swift         # Multi-tiered configuration loader (.env, UserDefaults)
```

---

## How to Run

### Method 1: Launch Application Bundle (Recommended)

Apple's Translation framework and macOS window manager require an application bundle (`.app`) with a valid bundle identifier (`com.antigravity.NovelTranslator`):

```bash
# Build and package the release application bundle
./bundle.sh

# Launch the app
open NovelTranslator.app
```

### Method 2: Terminal / SPM Direct Run

```bash
swift run NovelTranslator
```

The app will activate as a regular GUI application with a dock icon and bring its main window to the front.

---

## Configuration

NovelTranslator loads configuration from multiple tiers with automatic fallback:
1. GUI Preferences / `UserDefaults`
2. `~/Library/Application Support/NovelTranslator/.env`
3. Project root `.env`
4. Process Environment Variables

To configure remote or local API endpoints, create a `.env` file in the project root:

```bash
cp .env.example .env
```

```ini
# OpenAI or Compatible API
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_API_KEY=your-api-key-here
OPENAI_MODEL=gpt-4o-mini
OPENAI_TEMPERATURE=0.30
OPENAI_CONCURRENCY=5

# Ollama Local Engine (Optional)
OLLAMA_BASE_URL=http://localhost:11434/v1
OLLAMA_MODEL=translategemma:4b
```

---

## Running Tests

NovelTranslator uses Apple's **Swift Testing** framework (`@Suite`, `@Test`, `#expect`):

```bash
# Run the entire test suite (97 tests in 15 suites)
swift test

# Run specific test suites
swift test --filter "EPUB Processor Tests"
swift test --filter "Character Bible Filter Tests"
swift test --filter "TTS Service & Player Tests"
swift test --filter "Multi-Model Profiles & Fallback Chain Tests"
```

---

## Requirements

- **Operating System**: macOS 15.0+ (Sequoia)
- **Toolchain**: Swift 6.0+ / Xcode 16+ Command Line Tools
- **Optional**: Python with `mlx` environment for VieNeu local TTS narration:
  ```bash
  conda activate mlx
  pip install -r scripts/requirements.txt # if needed for VieNeu TTS
  ```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
