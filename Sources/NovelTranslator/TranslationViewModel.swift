import SwiftUI
import Combine
@preconcurrency import Translation
import AppKit

public enum AppMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case document = "Text Document"
    case epub = "EPUB eBook"
    public var id: String { rawValue }
}

public enum TranslationEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case apple = "Apple Built-in"
    case ollama = "Ollama (Local LLM)"
    case openai = "OpenAI / Custom"
    public var id: String { rawValue }
}

@MainActor
public class TranslationViewModel: ObservableObject {
    // Mode & Engine
    @Published public var appMode: AppMode = .epub
    @Published public var engine: TranslationEngine = .apple

    // LLM Configs
    @Published public var showSettingsPopover: Bool = false
    @Published public var ollamaConfig: LLMConfig = .defaultOllama
    @Published public var openAIConfig: LLMConfig = .defaultOpenAI
    @Published public var availableOllamaModels: [String] = ["translategemma:4b"]
    @Published public var availableOpenAIModels: [String] = []
    @Published public var isTestingConnection: Bool = false
    @Published public var connectionTestResult: String? = nil
    @Published public var envSaveStatus: String? = nil

    // Multi-Model Profiles & Fallback Chain
    @Published public var modelProfiles: [LLMConfig] = []
    @Published public var activeProfileId: UUID? = nil
    @Published public var showModelManagerSheet: Bool = false

    // Model Prompt Customization
    public enum PromptTab: String, CaseIterable, Identifiable, Sendable {
        case translation = "Translation Prompt"
        case characterAnalysis = "Character Analysis Prompt"
        case knowledgeBase = "Knowledge Base Directives"
        case presetsAndTips = "Presets & Tips"
        public var id: String { rawValue }
    }

    @Published public var showPromptSettingsSheet: Bool = false
    @Published public var selectedPromptTab: PromptTab = .translation
    @Published public var customTranslationPrompt: String = ""
    @Published public var customCharacterAnalysisPrompt: String = ""
    @Published public var promptSaveFeedback: String? = nil

    // Multi-Session Checkpoint State
    @Published public var savedSessions: [TranslationCheckpointSummary] = []
    @Published public var showSavedSessionsSheet: Bool = false
    @Published public var activeCheckpointId: String? = nil
    @Published public var saveProgressFeedback: String? = nil

    // Document Mode State
    @Published public var sourceDocument: String = ""
    @Published public var translatedDocument: String = ""

    // Character Bible & Pronoun State
    @Published public var characterBible: CharacterBible? = nil
    @Published public var isAnalyzingCharacters: Bool = false
    @Published public var autoDiscoverChapterCharacters: Bool = true
    @Published public var showCharacterBibleSheet: Bool = false
    @Published public var showUnanalyzedBibleAlert: Bool = false
    @Published public var isTargetedForDrop: Bool = false

    // EPUB Mode State
    @Published public var currentEPUB: EPUBBook? = nil
    @Published public var selectedChapterIndex: Int = 0
    @Published public var completedEPUBChapters: Int = 0
    @Published public var totalEPUBChapters: Int = 0
    @Published public var currentEPUBNodeProgress: (completed: Int, total: Int) = (0, 0)
    @Published public var epubReaderMode: EPUBReaderMode = .full

    public enum EPUBReaderMode: String, CaseIterable, Identifiable, Sendable {
        case full = "Full Text"
        case paragraphs = "By Paragraph"
        public var id: String { rawValue }
    }

    // Language Selection
    @Published public var sourceLanguage: SupportedLanguage = .autoDetect {
        didSet {
            prepareAppleConfiguration()
        }
    }
    @Published public var targetLanguage: SupportedLanguage = SupportedLanguage.allTargets.first(where: { $0.id == "es" }) ?? SupportedLanguage.allTargets[0] {
        didSet {
            prepareAppleConfiguration()
        }
    }

    // Common Translation State
    @Published public var isTranslating: Bool = false
    @Published public var completedChunks: Int = 0
    @Published public var totalTranslatableChunks: Int = 0
    @Published public var statusMessage: String = "Ready"
    @Published public var errorMessage: String? = nil

    // ETA & Speed
    @Published public var estimatedTimeRemaining: String? = nil
    @Published public var translationSpeed: String? = nil
    private var sessionStartTime: Date? = nil
    private var sessionStartDone: Int = 0

    // Automatic Fallback Chain: OpenAI -> Ollama -> Apple Built-in
    @Published public var autoFallback: Bool = true
    @Published public var fallbackNotice: String? = nil

    // Batch Chunking State
    @Published public var batchWordLimit: Int = 1200 {
        didSet {
            EnvConfigManager.saveBatchWordLimit(batchWordLimit)
        }
    }

    private var lastCheckpointSaveTime: Date? = nil

    // MARK: - Text-to-Speech (TTS) State
    @Published public var ttsEngine: TTSEngine = .vieneu {
        didSet {
            Task { await loadTTSVoices() }
        }
    }
    @Published public var availableTTSVoices: [TTSVoice] = []
    @Published public var selectedTTSVoiceId: String = "Trúc Ly"
    @Published public var ttsSpeed: Double = 1.0
    @Published public var isSynthesizingAudio: Bool = false
    @Published public var ttsStatusMessage: String? = nil
    @Published public var ttsErrorMessage: String? = nil

    // Batch Audiobook Export
    public enum TTSExportScope: String, CaseIterable, Identifiable, Sendable {
        case allChapters = "All Chapters"
        case selected = "Custom Chapter Selection"
        case translatedOnly = "Translated Chapters Only"
        public var id: String { rawValue }
    }

    public enum TTSTextSource: String, CaseIterable, Identifiable, Sendable {
        case auto = "Auto (Translated if available, else Original)"
        case original = "Original Text (Untranslated / Native Book)"
        case translated = "Translated Text Only"
        public var id: String { rawValue }
    }

    @Published public var showTTSExportSheet: Bool = false
    @Published public var isBatchExportingAudio: Bool = false
    @Published public var isTestingTTSVoice: Bool = false
    @Published public var ttsTextSource: TTSTextSource = .auto
    @Published public var batchExportProgress: TTSBatchProgress? = nil
    @Published public var ttsExportOutputDir: URL? = nil
    @Published public var ttsExportVoiceId: String = "Trúc Ly"
    @Published public var ttsExportSpeed: Double = 1.0
    @Published public var ttsExportScope: TTSExportScope = .allChapters
    @Published public var ttsExportTextSource: TTSTextSource = .auto
    @Published public var ttsExportSelectedChapters: Set<Int> = []
    @Published public var ttsExportCompleted: Bool = false
    private var batchExportProcess: Process? = nil

    public let audioPlayer: AudioPlayerManager = .shared

    @Published public var configuration: TranslationSession.Configuration?
    public var appleSession: TranslationSession?

    private var activeChunks: [DocumentChunk] = []
    private var isCancelled: Bool = false
    private var currentTask: Task<Void, Never>? = nil

    public var hasSavedProgress: Bool {
        if let book = currentEPUB, !book.chapters.isEmpty {
            let doneNodes = book.chapters.reduce(0) { $0 + $1.nodes.filter { !$0.translatedText.isEmpty }.count }
            return doneNodes > 0 || characterBible != nil || book.characterBible != nil
        }
        return completedChunks > 0
    }

    public var canResume: Bool {
        if isTranslating { return false }
        if appMode == .document {
            return completedChunks > 0 && completedChunks < totalTranslatableChunks
        } else {
            if let book = currentEPUB, !book.chapters.isEmpty {
                let doneNodes = book.chapters.reduce(0) { $0 + $1.nodes.filter { !$0.translatedText.isEmpty }.count }
                return doneNodes > 0 && doneNodes < book.totalNodes
            }
            return false
        }
    }

    public init(autoRestoreCheckpoint: Bool = true) {
        self.appMode = .epub
        self.openAIConfig = EnvConfigManager.loadOpenAIConfig()
        self.modelProfiles = EnvConfigManager.loadModelProfiles()
        self.activeProfileId = EnvConfigManager.loadActiveProfileId() ?? self.modelProfiles.first?.id
        if let activeId = self.activeProfileId, let active = self.modelProfiles.first(where: { $0.id == activeId }) {
            self.openAIConfig = active
        }
        self.batchWordLimit = EnvConfigManager.loadBatchWordLimit()

        let loadedPrompts = EnvConfigManager.loadPrompts()
        self.customTranslationPrompt = loadedPrompts.translation ?? LLMTranslationService.defaultTranslationPromptTemplate
        self.customCharacterAnalysisPrompt = loadedPrompts.characterAnalysis ?? LLMTranslationService.defaultCharacterAnalysisPromptTemplate

        refreshSavedSessions()
        if autoRestoreCheckpoint {
            _ = restoreCheckpointIfAvailable()
        }
        Task {
            await autoDiscoverOllama()
            await loadTTSVoices()
        }
        prepareAppleConfiguration()
    }

    public func saveOpenAIEnvConfig() {
        if let activeId = activeProfileId, let idx = modelProfiles.firstIndex(where: { $0.id == activeId }) {
            modelProfiles[idx] = openAIConfig
            saveModelProfiles()
        }
        EnvConfigManager.saveOpenAIConfig(openAIConfig)
        self.envSaveStatus = "Saved to .env"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.envSaveStatus = nil
        }
    }

    // MARK: - Prompt Management & Rendering
    public var hasCustomTranslationPrompt: Bool {
        let trimmed = customTranslationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != LLMTranslationService.defaultTranslationPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasCustomCharacterAnalysisPrompt: Bool {
        let trimmed = customCharacterAnalysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != LLMTranslationService.defaultCharacterAnalysisPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasCustomPrompts: Bool {
        hasCustomTranslationPrompt || hasCustomCharacterAnalysisPrompt
    }

    public func currentTranslationSystemInstruction(from sourceLang: String, to targetLang: String) -> String {
        let template = customTranslationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? LLMTranslationService.defaultTranslationPromptTemplate
            : customTranslationPrompt
        return LLMTranslationService.renderTranslationPrompt(template: template, from: sourceLang, to: targetLang)
    }

    public func currentFullTranslationSystemInstruction(
        from sourceLang: String,
        to targetLang: String,
        includeKnowledgeBase: Bool = true,
        chapterText: String? = nil,
        chapterId: String? = nil
    ) -> String {
        let base = currentTranslationSystemInstruction(from: sourceLang, to: targetLang)
        guard includeKnowledgeBase else { return base }

        let activeBible = characterBible ?? currentEPUB?.characterBible ?? sampleBibleForPreview
        return PronounPromptBuilder.buildSystemInstruction(
            baseInstruction: base,
            targetLanguageCode: targetLanguage.id,
            bible: activeBible,
            chapterText: chapterText,
            chapterId: chapterId
        )
    }

    public var sampleBibleForPreview: CharacterBible {
        let sherlock = CharacterProfile(name: "Sherlock Holmes", aliases: ["Holmes"], gender: .male, relativeAge: "30s", roleOrStatus: "Consulting Detective", thirdPersonPronoun: "anh ta")
        let watson = CharacterProfile(name: "Dr. John Watson", aliases: ["Watson"], gender: .male, relativeAge: "30s", roleOrStatus: "Doctor / Colleague", thirdPersonPronoun: "anh ta")
        let hudson = CharacterProfile(name: "Mrs. Hudson", aliases: [], gender: .female, relativeAge: "elderly", roleOrStatus: "Landlady", thirdPersonPronoun: "bà")
        let pair1 = RelationshipPair(sourceCharacterId: sherlock.id, targetCharacterId: watson.id, selfPronoun: "tôi", addressingPronoun: "anh", contextNote: "close partners")
        let pair2 = RelationshipPair(sourceCharacterId: watson.id, targetCharacterId: sherlock.id, selfPronoun: "tôi", addressingPronoun: "anh", contextNote: "close partners")
        let pair3 = RelationshipPair(sourceCharacterId: sherlock.id, targetCharacterId: hudson.id, selfPronoun: "tôi", addressingPronoun: "bác Hudson", contextNote: "respectful to elder landlady")
        return CharacterBible(
            bookTitle: currentEPUB?.title ?? "The Adventures of Sherlock Holmes",
            bookGenre: .fiction,
            narrativePOV: .firstPerson,
            narratorCharacterId: watson.id,
            characters: [sherlock, watson, hudson],
            relationships: [pair1, pair2, pair3],
            generalNotes: "Victorian London detective mysteries."
        )
    }

    public func currentCharacterAnalysisSystemInstruction(
        entitiesSection: String = "",
        contextAppendix: String = ""
    ) -> String {
        let template = customCharacterAnalysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? LLMTranslationService.defaultCharacterAnalysisPromptTemplate
            : customCharacterAnalysisPrompt
        return LLMTranslationService.renderCharacterAnalysisPrompt(
            template: template,
            entitiesSection: entitiesSection,
            contextAppendix: contextAppendix
        )
    }

    public func savePrompts() {
        EnvConfigManager.savePrompts(
            translation: customTranslationPrompt,
            characterAnalysis: customCharacterAnalysisPrompt
        )
        self.promptSaveFeedback = "Prompts saved successfully"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.promptSaveFeedback = nil
        }
    }

    public func resetTranslationPromptToDefault() {
        customTranslationPrompt = LLMTranslationService.defaultTranslationPromptTemplate
        savePrompts()
    }

    public func resetCharacterAnalysisPromptToDefault() {
        customCharacterAnalysisPrompt = LLMTranslationService.defaultCharacterAnalysisPromptTemplate
        savePrompts()
    }

    public func resetAllPromptsToDefaults() {
        customTranslationPrompt = LLMTranslationService.defaultTranslationPromptTemplate
        customCharacterAnalysisPrompt = LLMTranslationService.defaultCharacterAnalysisPromptTemplate
        savePrompts()
    }

    public var activeModelProfile: LLMConfig? {
        if let id = activeProfileId, let match = modelProfiles.first(where: { $0.id == id }) {
            return match
        }
        return modelProfiles.first
    }

    public var activeLLMConfig: LLMConfig {
        get {
            if engine == .ollama {
                return ollamaConfig
            }
            return activeModelProfile ?? openAIConfig
        }
        set {
            if engine == .ollama {
                ollamaConfig = newValue
            } else {
                openAIConfig = newValue
                if let activeId = activeProfileId, let idx = modelProfiles.firstIndex(where: { $0.id == activeId }) {
                    modelProfiles[idx] = newValue
                    saveModelProfiles()
                }
            }
        }
    }

    /// Ordered fallback models: all other enabled model profiles besides the active one.
    public var activeFallbackConfigs: [LLMConfig] {
        guard autoFallback else { return [] }
        guard let active = activeModelProfile else {
            return (engine == .openai) ? [ollamaConfig] : []
        }
        var fallbacks = modelProfiles.filter { $0.isEnabled && $0.id != active.id }
        if engine == .openai && !fallbacks.contains(where: { $0.baseURL == ollamaConfig.baseURL }) {
            fallbacks.append(ollamaConfig)
        }
        return fallbacks
    }

    public func selectModelProfile(id: UUID) {
        guard let target = modelProfiles.first(where: { $0.id == id }) else { return }
        self.activeProfileId = id
        self.openAIConfig = target
        EnvConfigManager.saveActiveProfileId(id)
        EnvConfigManager.saveOpenAIConfig(target)
        statusMessage = "Switched to model: \(target.name) (\(target.modelName))"
    }

    public func addModelProfile(_ profile: LLMConfig) {
        modelProfiles.append(profile)
        saveModelProfiles()
    }

    public func addPresetProfile(_ preset: LLMConfig) {
        var newProfile = preset
        newProfile.id = UUID()
        let count = modelProfiles.filter { $0.name.starts(with: preset.name) }.count
        if count > 0 {
            newProfile.name = "\(preset.name) (\(count + 1))"
        }
        newProfile.isEnabled = true
        modelProfiles.append(newProfile)
        saveModelProfiles()
        selectModelProfile(id: newProfile.id)
    }

    public func updateModelProfile(_ profile: LLMConfig) {
        guard let idx = modelProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        modelProfiles[idx] = profile
        if activeProfileId == profile.id {
            self.openAIConfig = profile
            EnvConfigManager.saveOpenAIConfig(profile)
        }
        saveModelProfiles()
    }

    public func deleteModelProfile(id: UUID) {
        guard modelProfiles.count > 1 else {
            statusMessage = "Cannot delete the only model profile."
            return
        }
        modelProfiles.removeAll(where: { $0.id == id })
        if activeProfileId == id {
            activeProfileId = modelProfiles.first?.id
            if let first = modelProfiles.first {
                openAIConfig = first
                EnvConfigManager.saveOpenAIConfig(first)
                EnvConfigManager.saveActiveProfileId(first.id)
            }
        }
        saveModelProfiles()
    }

    public func duplicateModelProfile(id: UUID) {
        guard let original = modelProfiles.first(where: { $0.id == id }) else { return }
        var duplicate = original
        duplicate.id = UUID()
        duplicate.name = "\(original.name) (Copy)"
        if let idx = modelProfiles.firstIndex(where: { $0.id == id }) {
            modelProfiles.insert(duplicate, at: idx + 1)
        } else {
            modelProfiles.append(duplicate)
        }
        saveModelProfiles()
    }

    public func moveProfileUp(id: UUID) {
        guard let idx = modelProfiles.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        modelProfiles.swapAt(idx, idx - 1)
        saveModelProfiles()
    }

    public func moveProfileDown(id: UUID) {
        guard let idx = modelProfiles.firstIndex(where: { $0.id == id }), idx < modelProfiles.count - 1 else { return }
        modelProfiles.swapAt(idx, idx + 1)
        saveModelProfiles()
    }

    public func toggleProfileEnabled(id: UUID) {
        guard let idx = modelProfiles.firstIndex(where: { $0.id == id }) else { return }
        modelProfiles[idx].isEnabled.toggle()
        saveModelProfiles()
    }

    public func saveModelProfiles() {
        EnvConfigManager.saveModelProfiles(modelProfiles)
        EnvConfigManager.saveActiveProfileId(activeProfileId)
    }

    public enum CharacterAnalysisProvider: String, CaseIterable, Identifiable, Sendable {
        case auto = "Auto"
        case openAI = "API Model"
        case ollama = "Ollama (Local)"
        public var id: String { rawValue }
    }
    @Published public var characterAnalysisProvider: CharacterAnalysisProvider = .auto

    /// Configuration for Character Bible analysis.
    /// Follows explicit user provider choice, or uses active engine preference.
    public var characterAnalysisConfig: LLMConfig {
        switch characterAnalysisProvider {
        case .openAI:
            return openAIConfig
        case .ollama:
            return ollamaConfig
        case .auto:
            if engine == .ollama {
                return ollamaConfig
            }
            if engine == .openai {
                return openAIConfig
            }
            if !openAIConfig.baseURL.isEmpty && (!openAIConfig.apiKey.isEmpty || openAIConfig.baseURL != "https://api.openai.com/v1") {
                return openAIConfig
            }
            return ollamaConfig
        }
    }

    public var progressFraction: Double {
        if appMode == .document {
            guard totalTranslatableChunks > 0 else { return 0.0 }
            return Double(completedChunks) / Double(totalTranslatableChunks)
        } else {
            guard totalEPUBChapters > 0 else { return 0.0 }
            return Double(completedEPUBChapters) / Double(totalEPUBChapters)
        }
    }

    // MARK: - Auto-Discovery & Connection
    public func autoDiscoverOllama() async {
        do {
            let models = try await LLMTranslationService.fetchAvailableModels(config: ollamaConfig)
            if !models.isEmpty {
                self.availableOllamaModels = models
                if let translateModel = models.first(where: { $0.contains("translate") || $0.contains("gemma") }) {
                    self.ollamaConfig.modelName = translateModel
                } else if let first = models.first {
                    self.ollamaConfig.modelName = first
                }
            }
        } catch {
            // Ollama might not be running or custom endpoint
        }
    }

    public func refreshModels() async {
        isTestingConnection = true
        connectionTestResult = nil
        let targetConfig = (engine == .apple) ? openAIConfig : activeLLMConfig
        do {
            let models = try await LLMTranslationService.fetchAvailableModels(config: targetConfig)
            isTestingConnection = false
            if !models.isEmpty {
                if targetConfig.baseURL == ollamaConfig.baseURL {
                    availableOllamaModels = models
                } else {
                    availableOpenAIModels = models
                }
                connectionTestResult = "Found \(models.count) models."
            } else {
                connectionTestResult = "Connected, but no models found."
            }
        } catch {
            isTestingConnection = false
            connectionTestResult = "Connection failed: \(error.localizedDescription)"
        }
    }

    public func testConnection(for config: LLMConfig) async -> String {
        do {
            return try await LLMTranslationService.testConnection(config: config)
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }

    public func fetchAvailableModels(for config: LLMConfig) async -> [String] {
        do {
            return try await LLMTranslationService.fetchAvailableModels(config: config)
        } catch {
            return []
        }
    }

    public func testConnection() async {
        isTestingConnection = true
        connectionTestResult = nil
        let targetConfig = (engine == .apple) ? openAIConfig : activeLLMConfig
        do {
            let result = try await LLMTranslationService.testConnection(config: targetConfig)
            isTestingConnection = false
            connectionTestResult = result
        } catch {
            isTestingConnection = false
            connectionTestResult = "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Session Timing & ETA Helpers
    public func startSessionTimer(initialDone: Int) {
        sessionStartTime = Date()
        sessionStartDone = initialDone
        estimatedTimeRemaining = "Calculating ETA..."
        translationSpeed = nil
    }

    public func updateETA(currentDone: Int, total: Int) {
        guard let start = sessionStartTime, total > currentDone else {
            estimatedTimeRemaining = nil
            translationSpeed = nil
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        let doneInSession = currentDone - sessionStartDone

        guard elapsed >= 1.5 && doneInSession > 0 else {
            estimatedTimeRemaining = "Calculating ETA..."
            return
        }

        let speed = Double(doneInSession) / elapsed
        let remaining = total - currentDone
        let etaSeconds = Double(remaining) / speed

        if etaSeconds < 60 {
            estimatedTimeRemaining = "ETA: ~\(Int(ceil(etaSeconds)))s"
        } else if etaSeconds < 3600 {
            let mins = Int(etaSeconds) / 60
            let secs = Int(etaSeconds) % 60
            estimatedTimeRemaining = "ETA: ~\(mins)m \(secs)s"
        } else {
            let hours = Int(etaSeconds) / 3600
            let mins = (Int(etaSeconds) % 3600) / 60
            estimatedTimeRemaining = "ETA: ~\(hours)h \(mins)m"
        }

        translationSpeed = String(format: "%.1f items/s", speed)
    }

    // MARK: - Main Translation Dispatch
    public func startTranslation(resume: Bool = false) {
        errorMessage = nil
        fallbackNotice = nil
        isCancelled = false

        if appMode == .document {
            guard !sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Please enter or load some text to translate."
                return
            }
            prepareDocumentChunks(resume: resume)
            if engine == .apple {
                startDocumentTranslationApple(resume: resume)
            } else {
                currentTask?.cancel()
                currentTask = Task {
                    await translateDocumentLLM(resume: resume)
                }
            }
        } else {
            guard let book = currentEPUB, !book.chapters.isEmpty else {
                errorMessage = "Please open an EPUB eBook to translate."
                return
            }

            if engine == .apple {
                startEPUBTranslationApple(resume: resume)
            } else {
                currentTask?.cancel()
                currentTask = Task {
                    await translateEPUBLLM(resume: resume)
                }
            }
        }
    }

    public func prepareDocumentChunks(resume: Bool) {
        self.appMode = .document
        isCancelled = false
        if !resume || activeChunks.isEmpty {
            activeChunks = DocumentChunker.chunk(document: sourceDocument)
            completedChunks = 0
            translatedDocument = ""
            totalTranslatableChunks = activeChunks.filter(\.isTranslatable).count
            startSessionTimer(initialDone: 0)
        } else {
            startSessionTimer(initialDone: completedChunks)
        }
    }

    public func cancelTranslation() {
        isCancelled = true
        isTranslating = false
        currentTask?.cancel()
        estimatedTimeRemaining = nil
        translationSpeed = nil

        let countDesc = (appMode == .document)
            ? "\(completedChunks)/\(totalTranslatableChunks) paragraphs"
            : "\(currentEPUBNodeProgress.completed)/\(currentEPUBNodeProgress.total) paragraphs"
        statusMessage = "Paused at checkpoint (\(countDesc) saved). Safe to quit and resume anytime."
        saveCheckpoint()
    }


    // MARK: - Character Bible Actions
    public func analyzeCharactersForCurrentEPUB() async {
        await scanAndAnalyzeAllChapters()
    }

    /// Scans 100% of chapters across the entire EPUB book to identify all recurring characters,
    /// then uses full-book entity anchors to extract a complete, consistent Character Bible with zero hallucination.
    public func scanAndAnalyzeAllChapters() async {
        guard let book = currentEPUB, !book.chapters.isEmpty else { return }
        await MainActor.run {
            self.isAnalyzingCharacters = true
            self.errorMessage = nil
            self.statusMessage = "Scanning all \(book.chapters.count) chapters for character entities..."
        }

        // Phase 1: High-speed deterministic full-book entity scan across all chapters
        let candidates = CharacterBibleFilter.scanBookEntities(in: book, minOccurrences: 2, maxCandidates: 25)

        let config = characterAnalysisConfig
        await MainActor.run {
            self.statusMessage = "Identified \(candidates.count) entities. Calling \(config.modelName) (\(config.baseURL))..."
        }

        print("[NovelTranslator] Scanning complete. Identified \(candidates.count) entities.")
        print("[NovelTranslator] Dispatching Character Bible extraction to: \(config.baseURL), model: \(config.modelName)")

        // Phase 2: Stratified sample text as context + entity anchors (10,000 chars gives fast prompt processing without timeouts)
        let sampleText = EPUBProcessor.extractStratifiedSampleText(from: book, maxCharacters: 10_000)

        do {
            let customInstruction = customCharacterAnalysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customCharacterAnalysisPrompt
            let extracted = try await LLMTranslationService.extractCharacterBibleWithAnchors(
                candidateEntities: candidates,
                sampleText: sampleText,
                bookTitle: book.title,
                config: config,
                existingBible: characterBible ?? currentEPUB?.characterBible,
                customSystemInstruction: customInstruction
            )
            await MainActor.run {
                self.characterBible = extracted
                self.currentEPUB?.characterBible = extracted
                self.isAnalyzingCharacters = false
                self.showCharacterBibleSheet = true
                self.statusMessage = "Extracted \(extracted.characters.count) characters in \(book.title) using \(config.modelName)."
                saveCheckpoint()
            }
        } catch {
            print("[NovelTranslator] Primary model '\(config.modelName)' failed: \(error.localizedDescription)")

            // Check if fallback model is available
            let fallbackConfig: LLMConfig? = {
                if let fallback = activeFallbackConfigs.first {
                    return fallback
                }
                if config.baseURL == openAIConfig.baseURL && !availableOllamaModels.isEmpty {
                    return ollamaConfig
                } else if config.baseURL == ollamaConfig.baseURL && (!openAIConfig.baseURL.isEmpty && (!openAIConfig.apiKey.isEmpty || openAIConfig.baseURL != "https://api.openai.com/v1")) {
                    return openAIConfig
                }
                return nil
            }()

            if autoFallback, let fallback = fallbackConfig {
                await MainActor.run {
                    self.statusMessage = "\(config.modelName) failed. Trying fallback \(fallback.modelName)..."
                }
                print("[NovelTranslator] Attempting fallback extraction with: \(fallback.baseURL), model: \(fallback.modelName)")
                do {
                    let customInstruction = customCharacterAnalysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customCharacterAnalysisPrompt
                    let extracted = try await LLMTranslationService.extractCharacterBibleWithAnchors(
                        candidateEntities: candidates,
                        sampleText: sampleText,
                        bookTitle: book.title,
                        config: fallback,
                        existingBible: characterBible ?? currentEPUB?.characterBible,
                        customSystemInstruction: customInstruction
                    )
                    await MainActor.run {
                        self.characterBible = extracted
                        self.currentEPUB?.characterBible = extracted
                        self.isAnalyzingCharacters = false
                        self.showCharacterBibleSheet = true
                        self.statusMessage = "Extracted \(extracted.characters.count) characters using fallback \(fallback.modelName)."
                        saveCheckpoint()
                    }
                    return
                } catch {
                    print("[NovelTranslator] Fallback model '\(fallback.modelName)' also failed: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self.isAnalyzingCharacters = false
                self.errorMessage = "Character analysis failed (\(config.modelName)): \(error.localizedDescription)"
                self.statusMessage = "Character analysis failed."
                if self.characterBible == nil {
                    self.characterBible = CharacterBible(bookTitle: book.title)
                    self.currentEPUB?.characterBible = self.characterBible
                }
            }
        }
    }

    public func analyzeCharactersForChapter(chapterIndex: Int) async {
        guard let book = currentEPUB, book.chapters.indices.contains(chapterIndex) else { return }
        let chapter = book.chapters[chapterIndex]
        await MainActor.run {
            self.isAnalyzingCharacters = true
            self.errorMessage = nil
            self.statusMessage = "Analyzing characters for chapter \(chapter.title)..."
        }

        let chapterSample = EPUBProcessor.extractChapterSampleText(from: chapter, maxCharacters: 20_000)
        guard !chapterSample.isEmpty else {
            await MainActor.run {
                self.isAnalyzingCharacters = false
                self.statusMessage = "No text found in chapter \(chapter.title)."
            }
            return
        }

        let config = characterAnalysisConfig
        let currentBible = self.characterBible ?? self.currentEPUB?.characterBible ?? CharacterBible(bookTitle: book.title)

        do {
            let customInstruction = customCharacterAnalysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customCharacterAnalysisPrompt
            let extracted = try await LLMTranslationService.extractCharacterBible(
                from: chapterSample,
                bookTitle: "\(book.title) - \(chapter.title)",
                config: config,
                existingBible: currentBible,
                customSystemInstruction: customInstruction
            )
            await MainActor.run {
                var updatedBible = self.characterBible ?? self.currentEPUB?.characterBible ?? CharacterBible(bookTitle: book.title)

                // 1. Update Chapter Scope (Local)
                var scope = updatedBible.chapterScopes[chapter.id] ?? ChapterScope(
                    id: chapter.id,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapter.title
                )
                scope.characters = extracted.characters
                scope.relationships = extracted.relationships
                if !extracted.generalNotes.isEmpty {
                    scope.notes = extracted.generalNotes
                }
                updatedBible.chapterScopes[chapter.id] = scope

                // 2. Synchronize / Promote back into Global Knowledge Base
                for newChar in extracted.characters {
                    let lowerName = newChar.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if let existingIdx = updatedBible.characters.firstIndex(where: {
                        $0.name.lowercased() == lowerName ||
                        $0.aliases.contains(where: { $0.lowercased() == lowerName })
                    }) {
                        // Enrich existing character if more details found
                        if updatedBible.characters[existingIdx].roleOrStatus.isEmpty && !newChar.roleOrStatus.isEmpty {
                            updatedBible.characters[existingIdx].roleOrStatus = newChar.roleOrStatus
                        }
                        if updatedBible.characters[existingIdx].gender == .unknown && newChar.gender != .unknown {
                            updatedBible.characters[existingIdx].gender = newChar.gender
                        }
                        if updatedBible.characters[existingIdx].thirdPersonPronoun == nil && newChar.thirdPersonPronoun != nil {
                            updatedBible.characters[existingIdx].thirdPersonPronoun = newChar.thirdPersonPronoun
                        }
                        for alias in newChar.aliases {
                            if !updatedBible.characters[existingIdx].aliases.contains(where: { $0.lowercased() == alias.lowercased() }) {
                                updatedBible.characters[existingIdx].aliases.append(alias)
                            }
                        }
                    } else {
                        // Add newly discovered character to global list
                        updatedBible.characters.append(newChar)
                    }
                }

                // Promote new relationships to global
                let charNameMap = Dictionary(uniqueKeysWithValues: updatedBible.characters.map { ($0.name.lowercased(), $0.id) })
                for newRel in extracted.relationships {
                    let srcId = charNameMap[newRel.sourceCharacterId.lowercased()] ?? newRel.sourceCharacterId
                    let tgtId = charNameMap[newRel.targetCharacterId.lowercased()] ?? newRel.targetCharacterId
                    let normalizedRel = RelationshipPair(
                        sourceCharacterId: srcId,
                        targetCharacterId: tgtId,
                        selfPronoun: newRel.selfPronoun,
                        addressingPronoun: newRel.addressingPronoun,
                        contextNote: newRel.contextNote
                    )
                    let exists = updatedBible.relationships.contains(where: {
                        $0.sourceCharacterId == normalizedRel.sourceCharacterId && $0.targetCharacterId == normalizedRel.targetCharacterId
                    })
                    if !exists {
                        updatedBible.relationships.append(normalizedRel)
                    }
                }

                self.characterBible = updatedBible
                self.currentEPUB?.characterBible = updatedBible
                self.isAnalyzingCharacters = false
                self.statusMessage = "Analyzed \(extracted.characters.count) characters in chapter \(chapter.title) and synchronized to Global Bible."
                saveCheckpoint()
            }
        } catch {
            await MainActor.run {
                self.isAnalyzingCharacters = false
                self.errorMessage = "Chapter character analysis failed: \(error.localizedDescription)"
                self.statusMessage = "Chapter character analysis failed."
            }
        }
    }

    public func saveCharacterBible(_ bible: CharacterBible) {
        self.characterBible = bible
        self.currentEPUB?.characterBible = bible
        saveCheckpoint()
    }

    /// Discovers unknown recurring character candidates in a specific chapter
    public func discoverCandidatesForChapter(chapterIndex: Int, minOccurrences: Int = 2) -> [CharacterBibleFilter.CandidateEntity] {
        guard let book = currentEPUB, book.chapters.indices.contains(chapterIndex) else { return [] }
        let chapter = book.chapters[chapterIndex]
        let chapterText = EPUBProcessor.extractChapterSampleText(from: chapter, maxCharacters: 50_000)
        let bible = characterBible ?? book.characterBible ?? CharacterBible(bookTitle: book.title)
        return CharacterBibleFilter.scanUnknownEntities(
            in: chapterText,
            existingBible: bible,
            chapterId: chapter.id,
            minOccurrences: minOccurrences
        )
    }

    /// Automatically extracts and adds a discovered candidate character to the chapter scope,
    /// then promotes it to global so subsequent chapters benefit from the discovery.
    public func autoEnrichCandidateCharacter(
        candidate: CharacterBibleFilter.CandidateEntity,
        chapterIndex: Int
    ) async -> CharacterProfile? {
        guard let book = currentEPUB, book.chapters.indices.contains(chapterIndex) else { return nil }
        let chapter = book.chapters[chapterIndex]
        let currentBible = characterBible ?? book.characterBible ?? CharacterBible(bookTitle: book.title)
        let config = characterAnalysisConfig

        do {
            if let profile = try await LLMTranslationService.extractSingleCharacterProfile(
                candidateName: candidate.name,
                contextExcerpts: candidate.sampleExcerpts,
                existingBible: currentBible,
                config: config
            ) {
                await MainActor.run {
                    var updated = currentBible
                    var scope = updated.chapterScopes[chapter.id] ?? ChapterScope(
                        id: chapter.id,
                        chapterIndex: chapterIndex,
                        chapterTitle: chapter.title
                    )

                    let nameLower = profile.name.lowercased()

                    // Add to chapter scope
                    if !scope.characters.contains(where: { $0.name.lowercased() == nameLower }) {
                        scope.characters.append(profile)
                        updated.chapterScopes[chapter.id] = scope
                    }

                    // Auto-promote to global so future chapters recognize this character
                    if !updated.characters.contains(where: { $0.name.lowercased() == nameLower || $0.aliases.contains(where: { $0.lowercased() == nameLower }) }) {
                        updated.characters.append(profile)
                    }

                    self.characterBible = updated
                    self.currentEPUB?.characterBible = updated
                    self.saveCheckpoint()
                }
                return profile
            }
        } catch {
            print("Auto-enrich candidate failed: \(error)")
        }
        return nil
    }

    // MARK: - Multi-Session Checkpoint Management
    public func refreshSavedSessions() {
        self.savedSessions = CheckpointManager.listCheckpoints()
    }

    @discardableResult
    public func saveCheckpoint(force: Bool = true) -> String? {
        guard canResume || hasSavedProgress || (appMode == .epub && currentEPUB != nil) else { return nil }

        // Throttle non-forced saves to once every 30 seconds to prevent disk thrashing
        if !force, let lastTime = lastCheckpointSaveTime, Date().timeIntervalSince(lastTime) < 30 {
            return activeCheckpointId
        }
        lastCheckpointSaveTime = Date()

        let checkpointId = activeCheckpointId ?? UUID().uuidString
        let title: String = {
            if appMode == .epub, let book = currentEPUB {
                return book.title.isEmpty ? "Untitled eBook" : book.title
            } else {
                let first = sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? "Text Document"
                return String(first.prefix(40))
            }
        }()

        let checkpoint = TranslationCheckpoint(
            id: checkpointId,
            title: title,
            appMode: appMode,
            engine: engine,
            sourceLanguageId: sourceLanguage.id,
            targetLanguageId: targetLanguage.id,
            sourceDocument: sourceDocument,
            translatedDocument: translatedDocument,
            activeChunks: activeChunks,
            completedChunks: completedChunks,
            totalTranslatableChunks: totalTranslatableChunks,
            epubBook: currentEPUB,
            selectedChapterIndex: selectedChapterIndex,
            completedEPUBChapters: completedEPUBChapters,
            completedEPUBNodes: currentEPUBNodeProgress.completed,
            totalEPUBNodes: currentEPUBNodeProgress.total,
            characterBible: characterBible ?? currentEPUB?.characterBible
        )
        CheckpointManager.save(checkpoint: checkpoint)
        self.activeCheckpointId = checkpointId
        refreshSavedSessions()

        self.saveProgressFeedback = "Progress saved"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.saveProgressFeedback = nil
        }
        return checkpointId
    }

    @discardableResult
    public func resumeSession(withId id: String) -> Bool {
        // If an existing session is currently active with unsaved progress, preserve it first
        if let currentId = activeCheckpointId, currentId != id, hasSavedProgress {
            saveCheckpoint()
        }

        guard let checkpoint = CheckpointManager.load(id: id) else { return false }

        self.activeCheckpointId = id
        self.appMode = checkpoint.appMode
        self.engine = checkpoint.engine

        if let src = SupportedLanguage.allSources.first(where: { $0.id == checkpoint.sourceLanguageId }) {
            self.sourceLanguage = src
        }
        if let tgt = SupportedLanguage.allTargets.first(where: { $0.id == checkpoint.targetLanguageId }) {
            self.targetLanguage = tgt
        }

        if checkpoint.appMode == .document {
            self.sourceDocument = checkpoint.sourceDocument
            self.translatedDocument = checkpoint.translatedDocument
            self.activeChunks = checkpoint.activeChunks
            self.completedChunks = checkpoint.completedChunks
            self.totalTranslatableChunks = checkpoint.totalTranslatableChunks
            self.statusMessage = "Resumed '\(checkpoint.title)' (\(completedChunks)/\(totalTranslatableChunks) paragraphs saved)."
        } else if let book = checkpoint.epubBook {
            self.currentEPUB = book
            self.selectedChapterIndex = checkpoint.selectedChapterIndex
            self.completedEPUBChapters = checkpoint.completedEPUBChapters
            self.currentEPUBNodeProgress = (checkpoint.completedEPUBNodes, checkpoint.totalEPUBNodes)
            self.totalEPUBChapters = book.chapters.count
            let doneNodes = book.chapters.reduce(0) { $0 + $1.nodes.filter { !$0.translatedText.isEmpty }.count }
            self.characterBible = checkpoint.characterBible ?? book.characterBible
            self.statusMessage = "Resumed eBook '\(book.title)' (\(doneNodes)/\(book.totalNodes) paragraphs saved)."
        }

        self.isTranslating = false
        self.errorMessage = nil
        refreshSavedSessions()
        return true
    }

    @discardableResult
    public func restoreCheckpointIfAvailable() -> Bool {
        if let latest = CheckpointManager.loadLatest() {
            return resumeSession(withId: latest.id)
        }
        return false
    }

    public func deleteSession(withId id: String) {
        CheckpointManager.delete(id: id)
        if activeCheckpointId == id {
            activeCheckpointId = nil
        }
        refreshSavedSessions()
    }

    public func clearActiveSessionCheckpoint() {
        if let id = activeCheckpointId {
            CheckpointManager.delete(id: id)
            activeCheckpointId = nil
            refreshSavedSessions()
        }
    }

    public func clearCheckpoint() {
        clearActiveSessionCheckpoint()
    }

    // MARK: - Apple Translation Flow
    private func startDocumentTranslationApple(resume: Bool) {
        guard !sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter or load some text to translate."
            return
        }

        prepareDocumentChunks(resume: resume)

        let pendingCount = activeChunks.filter { $0.isTranslatable && $0.translatedText.isEmpty }.count
        if pendingCount == 0 {
            translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
            isTranslating = false
            statusMessage = "All paragraphs are already translated."
            return
        }

        isTranslating = true
        statusMessage = resume ? "Resuming Apple Translation..." : "Preparing Apple Translation session..."
        prepareAppleConfiguration()
    }

    private func startEPUBTranslationApple(resume: Bool) {
        guard var book = currentEPUB, !book.chapters.isEmpty else {
            errorMessage = "No EPUB ebook loaded."
            return
        }

        if !resume {
            for cIdx in 0..<book.chapters.count {
                book.chapters[cIdx].isTranslated = false
                for nIdx in 0..<book.chapters[cIdx].nodes.count {
                    book.chapters[cIdx].nodes[nIdx].translatedText = ""
                }
            }
            completedEPUBChapters = 0
            currentEPUBNodeProgress = (0, book.totalNodes)
            self.currentEPUB = book
            startSessionTimer(initialDone: 0)
        } else {
            let doneNodes = book.chapters.reduce(0) { $0 + $1.nodes.filter { !$0.translatedText.isEmpty }.count }
            currentEPUBNodeProgress = (doneNodes, book.totalNodes)
            startSessionTimer(initialDone: doneNodes)
        }

        isTranslating = true
        totalEPUBChapters = book.chapters.count
        statusMessage = resume ? "Resuming Apple Translation for EPUB..." : "Preparing Apple Translation session for EPUB..."
        prepareAppleConfiguration()
    }

    private func prepareAppleConfiguration() {
        let targetLang = targetLanguage.language ?? Locale.Language(identifier: "es")

        let newConfig: TranslationSession.Configuration
        if let sourceLang = sourceLanguage.language {
            newConfig = .init(source: sourceLang, target: targetLang)
        } else {
            newConfig = .init(target: targetLang)
        }

        if configuration != nil {
            configuration?.invalidate()
        }
        configuration = newConfig
    }

    public func translate(using session: TranslationSession) async {
        self.appleSession = session
        guard isTranslating, !isCancelled, engine == .apple else { return }

        if appMode == .document {
            await translateDocumentStreamingApple(using: session)
        } else {
            await translateEPUBStreamingApple(using: session)
        }
    }

    /// Translates a single text snippet using Apple Built-in Translator (used for temporary 1-2 sentence fallback)
    public func translateSingleWithApple(text: String) async throws -> String {
        if appleSession == nil {
            prepareAppleConfiguration()
            for _ in 0..<15 {
                if appleSession != nil { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        guard let session = appleSession else {
            throw LLMError.apiUnavailable("Apple Built-in Translator session is not initialized.")
        }
        let response = try await session.translate(text)
        return response.targetText
    }

    private func makeAppleFallbackHandler() -> (@Sendable (String) async throws -> String)? {
        guard autoFallback else { return nil }
        return { @Sendable [weak self] text in
            guard let self = self else { throw CancellationError() }
            return try await self.translateSingleWithApple(text: text)
        }
    }

    private func translateDocumentStreamingApple(using session: TranslationSession) async {
        statusMessage = "Translating document using Apple Translator..."

        // Only request chunks that haven't been translated yet (checkpointing)
        let requests: [TranslationSession.Request] = activeChunks.compactMap { chunk in
            guard chunk.isTranslatable && chunk.translatedText.isEmpty else { return nil }
            return TranslationSession.Request(sourceText: chunk.text, clientIdentifier: "\(chunk.id)")
        }

        do {
            for try await response in session.translate(batch: requests) {
                if isCancelled { break }

                if let idStr = response.clientIdentifier,
                   let chunkId = Int(idStr),
                   let index = activeChunks.firstIndex(where: { $0.id == chunkId }) {
                    activeChunks[index].translatedText = response.targetText
                    completedChunks += 1
                    updateETA(currentDone: completedChunks, total: totalTranslatableChunks)
                    statusMessage = "Translating chunk \(completedChunks) of \(totalTranslatableChunks)..."
                    translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
                }
            }

            if !isCancelled {
                clearCheckpoint()
                estimatedTimeRemaining = nil
                translationSpeed = nil
                statusMessage = "Translation complete! (\(totalTranslatableChunks) paragraphs)"
                translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
            }
        } catch {
            if !isCancelled {
                errorMessage = "Apple Translation failed: \(error.localizedDescription)"
                statusMessage = "Error during translation."
            }
        }

        isTranslating = false
    }

    private func translateEPUBStreamingApple(using session: TranslationSession) async {
        guard var book = currentEPUB else { return }

        let grandTotalNodes = book.totalNodes

        do {
            for chapterIdx in 0..<book.chapters.count {
                if isCancelled { break }

                let chapter = book.chapters[chapterIdx]
                let untranslatedNodes = chapter.nodes.filter { $0.translatedText.isEmpty }

                guard !untranslatedNodes.isEmpty else {
                    if !chapter.isTranslated {
                        book.chapters[chapterIdx].isTranslated = true
                        completedEPUBChapters += 1
                    }
                    continue
                }

                statusMessage = "Translating Chapter \(chapterIdx + 1) of \(book.chapters.count): \(chapter.title)..."

                let requests: [TranslationSession.Request] = untranslatedNodes.map { node in
                    TranslationSession.Request(sourceText: node.originalText, clientIdentifier: "\(node.id)")
                }

                for try await response in session.translate(batch: requests) {
                    if isCancelled { break }

                    if let idStr = response.clientIdentifier,
                       let nodeId = Int(idStr),
                       let nodeIdx = book.chapters[chapterIdx].nodes.firstIndex(where: { $0.id == nodeId }) {
                        book.chapters[chapterIdx].nodes[nodeIdx].translatedText = response.targetText
                        currentEPUBNodeProgress.completed += 1
                        updateETA(currentDone: currentEPUBNodeProgress.completed, total: grandTotalNodes)
                    }
                }

                EPUBProcessor.applyTranslations(to: &book.chapters[chapterIdx])
                completedEPUBChapters += 1
                self.currentEPUB = book
            }

            if !isCancelled {
                saveCheckpoint()
                estimatedTimeRemaining = nil
                translationSpeed = nil
                statusMessage = "EPUB translation complete! All \(book.chapters.count) chapters translated."
                self.currentEPUB = book
            }
        } catch {
            if !isCancelled {
                errorMessage = "Apple Translation failed: \(error.localizedDescription)"
                statusMessage = "Error translating EPUB."
            }
        }

        isTranslating = false
    }

    func updateDocumentChunkTranslation(chunkId: Int, translatedText: String) {
        guard !isCancelled else { return }
        if let index = activeChunks.firstIndex(where: { $0.id == chunkId }) {
            activeChunks[index].translatedText = translatedText
            completedChunks += 1
            updateETA(currentDone: completedChunks, total: totalTranslatableChunks)
            statusMessage = "Translated \(completedChunks) of \(totalTranslatableChunks) paragraphs..."
            translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
            if completedChunks % 2 == 0 {
                saveCheckpoint()
            }
        }
    }

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

    // MARK: - LLM Translation Flow (Ollama / OpenAI)
    private func translateDocumentLLM(resume: Bool) async {
        guard !sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter or load some text to translate."
            return
        }

        if activeChunks.isEmpty {
            prepareDocumentChunks(resume: resume)
        }

        let pendingItems = activeChunks.filter { $0.isTranslatable && $0.translatedText.isEmpty }.map { ($0.id, $0.text) }

        if pendingItems.isEmpty {
            translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
            isTranslating = false
            statusMessage = "All paragraphs are already translated."
            return
        }

        isTranslating = true
        let config = activeLLMConfig
        let fallbackConfig: LLMConfig? = (autoFallback && engine == .openai) ? ollamaConfig : nil
        let srcName = sourceLanguage.name
        let tgtName = targetLanguage.name
        let engineName = engine.rawValue

        statusMessage = resume
            ? "Resuming translation with \(engineName) (\(pendingItems.count) remaining)..."
            : "Translating with \(engineName) (\(config.modelName))..."

        let fallbackTracker = TemporaryFallbackTracker(maxConsecutiveFallbacks: 2)
        let appleHandler = makeAppleFallbackHandler()

        do {
            let batches = BatchChunker.createBatches(from: activeChunks, targetWordCount: batchWordLimit)
            let baseInstruction = currentTranslationSystemInstruction(from: srcName, to: tgtName)
            let customInstruction = (targetLanguage.id == "vi" || targetLanguage.id.hasPrefix("vi-"))
                ? PronounPromptBuilder.buildSystemInstruction(
                    baseInstruction: baseInstruction,
                    targetLanguageCode: targetLanguage.id,
                    bible: characterBible,
                    chapterText: sourceDocument
                  )
                : baseInstruction

            var rollingContext: String? = nil
            for (bIdx, batch) in batches.enumerated() {
                if isCancelled { break }
                statusMessage = "Translating document (Batch \(bIdx + 1)/\(batches.count))..."

                try await LLMTranslationService.translateBatchXML(
                    batch: batch,
                    from: srcName,
                    to: tgtName,
                    config: config,
                    fallbackConfigs: activeFallbackConfigs,
                    fallbackConfig: fallbackConfig,
                    customSystemInstruction: customInstruction,
                    previousContext: rollingContext,
                    fallbackTracker: fallbackTracker,
                    appleFallbackHandler: appleHandler,
                    onFallbackUsed: { [weak self] chunkId, reason in
                        Task { @MainActor in
                            self?.fallbackNotice = reason
                        }
                    },
                    onNodeCompleted: { [weak self] chunkId, translatedText in
                        await self?.updateDocumentChunkTranslation(chunkId: chunkId, translatedText: translatedText)
                    }
                )

                let batchCompleted = activeChunks.filter { batch.nodes.map(\.id).contains($0.id) && !$0.translatedText.isEmpty }
                if !batchCompleted.isEmpty {
                    let lastChunks = Array(batchCompleted.suffix(4))
                    rollingContext = lastChunks.map { "Original: \"\($0.text)\"\nTranslated: \"\($0.translatedText)\"" }.joined(separator: "\n\n")
                }
            }

            if !isCancelled {
                clearCheckpoint()
                estimatedTimeRemaining = nil
                translationSpeed = nil
                statusMessage = "Translation complete via \(engineName)!"
                translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
            }
        } catch {
            if isCancelled {
                isTranslating = false
                return
            }

            errorMessage = "\(engineName) Error: \(error.localizedDescription)"
            statusMessage = "Translation stopped: \(error.localizedDescription)"
        }

        isTranslating = false
    }

    private func fallbackToOllamaDocument() async {
        guard !isCancelled else { return }
        let remainingPending = activeChunks.filter { $0.isTranslatable && $0.translatedText.isEmpty }.map { ($0.id, $0.text) }
        guard !remainingPending.isEmpty else {
            statusMessage = "Translation complete!"
            translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
            isTranslating = false
            return
        }

        let config = ollamaConfig
        let srcName = sourceLanguage.name
        let tgtName = targetLanguage.name

        self.fallbackNotice = "Ollama (Fallback)"
        self.statusMessage = "Falling back to Ollama (\(config.modelName)) for remaining \(remainingPending.count) paragraphs..."

        do {
            try await LLMTranslationService.translateBatch(
                items: remainingPending,
                from: srcName,
                to: tgtName,
                config: config
            ) { [weak self] chunkId, translatedText in
                await self?.updateDocumentChunkTranslation(chunkId: chunkId, translatedText: translatedText)
            }

            if !isCancelled {
                estimatedTimeRemaining = nil
                translationSpeed = nil
                statusMessage = "Translation complete via Ollama (fallback from OpenAI)!"
                translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
                isTranslating = false
            }
        } catch {
            if isCancelled {
                isTranslating = false
                return
            }
            errorMessage = "Ollama Error: \(error.localizedDescription)"
            statusMessage = "Translation stopped: \(error.localizedDescription)"
            isTranslating = false
        }
    }

    private func translateChapterInBatches(
        chapterIdx: Int,
        config: LLMConfig,
        fallbackConfigs: [LLMConfig] = [],
        fallbackConfig: LLMConfig? = nil,
        fallbackTracker: TemporaryFallbackTracker? = nil,
        appleFallbackHandler: (@Sendable (String) async throws -> String)? = nil
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
                fallbackConfigs: fallbackConfigs,
                fallbackConfig: fallbackConfig,
                customSystemInstruction: customInstruction,
                previousContext: rollingContext,
                fallbackTracker: fallbackTracker,
                appleFallbackHandler: appleFallbackHandler,
                onFallbackUsed: { [weak self] nodeId, reason in
                    await MainActor.run {
                        self?.fallbackNotice = reason
                    }
                },
                onNodeCompleted: { [weak self] nodeId, translatedText in
                    await MainActor.run {
                        self?.updateEPUBNodeTranslation(chapterIdx: chapterIdx, nodeId: nodeId, translatedText: translatedText, saveDisk: false)
                    }
                }
            )

            saveCheckpoint(force: false)

            if let book = self.currentEPUB, chapterIdx < book.chapters.count {
                let batchNodeIds = Set(batch.nodes.map(\.id))
                let batchCompleted = book.chapters[chapterIdx].nodes.filter { batchNodeIds.contains($0.id) && !$0.translatedText.isEmpty }
                if !batchCompleted.isEmpty {
                    let lastNodes = Array(batchCompleted.suffix(4))
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

    private func translateEPUBLLM(resume: Bool) async {
        guard var book = currentEPUB, !book.chapters.isEmpty else {
            errorMessage = "No EPUB ebook loaded."
            return
        }

        if !resume {
            for cIdx in 0..<book.chapters.count {
                book.chapters[cIdx].isTranslated = false
                for nIdx in 0..<book.chapters[cIdx].nodes.count {
                    book.chapters[cIdx].nodes[nIdx].translatedText = ""
                }
            }
            completedEPUBChapters = 0
            currentEPUBNodeProgress = (0, book.totalNodes)
            self.currentEPUB = book
            startSessionTimer(initialDone: 0)
        } else {
            let doneNodes = book.chapters.reduce(0) { $0 + $1.nodes.filter { !$0.translatedText.isEmpty }.count }
            currentEPUBNodeProgress = (doneNodes, book.totalNodes)
            startSessionTimer(initialDone: doneNodes)
        }

        isTranslating = true
        totalEPUBChapters = book.chapters.count

        let config = activeLLMConfig
        let engineName = engine.rawValue
        let fallbackConfig: LLMConfig? = (autoFallback && engine == .openai) ? ollamaConfig : nil
        let fallbackTracker = TemporaryFallbackTracker(maxConsecutiveFallbacks: 2)
        let appleHandler = makeAppleFallbackHandler()

        do {
            for chapterIdx in 0..<book.chapters.count {
                if isCancelled { break }

                guard let currentBook = self.currentEPUB, chapterIdx < currentBook.chapters.count else { break }
                let chapter = currentBook.chapters[chapterIdx]
                let untranslatedItems = chapter.nodes.filter { $0.translatedText.isEmpty }

                guard !untranslatedItems.isEmpty else {
                    if !chapter.isTranslated {
                        var updatedBook = currentBook
                        updatedBook.chapters[chapterIdx].isTranslated = true
                        self.currentEPUB = updatedBook
                        completedEPUBChapters += 1
                    }
                    continue
                }

                // Auto JIT character discovery & micro-enrichment for Vietnamese target
                let isVietnamese = targetLanguage.id == "vi" || targetLanguage.id.hasPrefix("vi-")
                if isVietnamese && autoDiscoverChapterCharacters {
                    if characterBible == nil && currentEPUB?.characterBible == nil {
                        let initialBible = CharacterBible(bookTitle: currentBook.title)
                        self.characterBible = initialBible
                        self.currentEPUB?.characterBible = initialBible
                    }

                    let candidates = discoverCandidatesForChapter(chapterIndex: chapterIdx, minOccurrences: 3)
                    if !candidates.isEmpty {
                        let topCandidates = Array(candidates.prefix(2))
                        for candidate in topCandidates {
                            if isCancelled { break }
                            await MainActor.run {
                                self.statusMessage = "Ch. \(chapterIdx + 1): Auto-discovering character '\(candidate.name)'..."
                            }
                            _ = await autoEnrichCandidateCharacter(candidate: candidate, chapterIndex: chapterIdx)
                        }
                    }
                }

                try await translateChapterInBatches(
                    chapterIdx: chapterIdx,
                    config: config,
                    fallbackConfigs: activeFallbackConfigs,
                    fallbackConfig: fallbackConfig,
                    fallbackTracker: fallbackTracker,
                    appleFallbackHandler: appleHandler
                )
                saveCheckpoint(force: true)
            }

            if !isCancelled {
                saveCheckpoint(force: true)
                estimatedTimeRemaining = nil
                translationSpeed = nil
                statusMessage = "EPUB translation complete via \(engineName)!"
            }
        } catch {
            if isCancelled {
                isTranslating = false
                return
            }

            saveCheckpoint(force: true)
            errorMessage = "\(engineName) Error: \(error.localizedDescription)"
            statusMessage = "Translation stopped: \(error.localizedDescription)"
        }

        isTranslating = false
    }

    private func fallbackToOllamaEPUB() async {
        guard !isCancelled, let book = currentEPUB else { return }

        let config = ollamaConfig

        self.fallbackNotice = "Ollama (Fallback)"
        self.statusMessage = "Falling back to Ollama (\(config.modelName)) for EPUB..."

        let fallbackTracker = TemporaryFallbackTracker(maxConsecutiveFallbacks: 2)
        let appleHandler = makeAppleFallbackHandler()

        do {
            for chapterIdx in 0..<book.chapters.count {
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
                try await translateChapterInBatches(
                    chapterIdx: chapterIdx,
                    config: config,
                    fallbackConfig: nil,
                    fallbackTracker: fallbackTracker,
                    appleFallbackHandler: appleHandler
                )
            }

            if !isCancelled {
                estimatedTimeRemaining = nil
                translationSpeed = nil
                statusMessage = "EPUB translation complete via Ollama (fallback)!"
                isTranslating = false
            }
        } catch {
            if isCancelled {
                isTranslating = false
                return
            }
            saveCheckpoint()
            errorMessage = "Ollama Error: \(error.localizedDescription)"
            statusMessage = "Translation stopped: \(error.localizedDescription)"
            isTranslating = false
        }
    }

    /// Manually switches to Apple Built-in Translator and resumes unfinished chunks/nodes
    public func fallbackToApple(resume: Bool) {
        self.engine = .apple
        self.fallbackNotice = "Apple Built-in (Fallback)"
        self.statusMessage = "Switched to Apple Built-in Translator..."
        if appMode == .document {
            startDocumentTranslationApple(resume: resume)
        } else {
            startEPUBTranslationApple(resume: resume)
        }
    }

    // MARK: - Selective & Re-translation Actions
    public func translateChapter(index chapterIdx: Int, force: Bool = false) {
        guard let book = currentEPUB, chapterIdx >= 0, chapterIdx < book.chapters.count else { return }
        guard !isTranslating else { return }

        isCancelled = false
        isTranslating = true

        if force {
            // Clear existing translations in this chapter
            var updatedBook = book
            updatedBook.chapters[chapterIdx].isTranslated = false
            for nIdx in 0..<updatedBook.chapters[chapterIdx].nodes.count {
                updatedBook.chapters[chapterIdx].nodes[nIdx].translatedText = ""
            }
            self.currentEPUB = updatedBook
        }

        let chapterTitle = book.chapters[chapterIdx].title
        statusMessage = "Translating Chapter \(chapterIdx + 1): \(chapterTitle)..."

        currentTask?.cancel()
        currentTask = Task {
            await performTranslateSingleChapter(chapterIdx: chapterIdx)
        }
    }

    private func performTranslateSingleChapter(chapterIdx: Int) async {
        guard let book = currentEPUB, chapterIdx < book.chapters.count else {
            isTranslating = false
            return
        }

        let chapter = book.chapters[chapterIdx]
        let pending = chapter.nodes.filter { $0.translatedText.isEmpty }.map { ($0.id, $0.originalText) }

        if pending.isEmpty {
            statusMessage = "Chapter \(chapterIdx + 1) is already translated."
            isTranslating = false
            return
        }

        if engine == .apple {
            if let session = appleSession {
                let requests = pending.map { TranslationSession.Request(sourceText: $0.1, clientIdentifier: "\($0.0)") }
                do {
                    for try await response in session.translate(batch: requests) {
                        if isCancelled { break }
                        if let idStr = response.clientIdentifier, let nodeId = Int(idStr) {
                            updateEPUBNodeTranslation(chapterIdx: chapterIdx, nodeId: nodeId, translatedText: response.targetText)
                        }
                    }
                    if var updatedBook = currentEPUB, chapterIdx < updatedBook.chapters.count {
                        EPUBProcessor.applyTranslations(to: &updatedBook.chapters[chapterIdx])
                        currentEPUB = updatedBook
                    }
                    statusMessage = "Translated Chapter \(chapterIdx + 1) via Apple Translator!"
                } catch {
                    errorMessage = "Apple Translation failed: \(error.localizedDescription)"
                }
            } else {
                prepareAppleConfiguration()
                statusMessage = "Please click Translate eBook to initialize Apple session."
            }
        } else {
            let config = activeLLMConfig
            let fallbackConfig: LLMConfig? = (autoFallback && engine == .openai) ? ollamaConfig : nil
            let fallbackTracker = TemporaryFallbackTracker(maxConsecutiveFallbacks: 2)
            let appleHandler = makeAppleFallbackHandler()

            do {
                try await translateChapterInBatches(
                    chapterIdx: chapterIdx,
                    config: config,
                    fallbackConfigs: activeFallbackConfigs,
                    fallbackConfig: fallbackConfig,
                    fallbackTracker: fallbackTracker,
                    appleFallbackHandler: appleHandler
                )
                statusMessage = "Finished translating Chapter \(chapterIdx + 1) via \(engine.rawValue)!"
                saveCheckpoint()
            } catch {
                errorMessage = "Translation failed: \(error.localizedDescription)"
            }
        }

        isTranslating = false
    }

    public func retranslateEPUBNode(chapterIndex: Int, nodeId: Int) {
        guard let book = currentEPUB, chapterIndex < book.chapters.count else { return }
        guard let node = book.chapters[chapterIndex].nodes.first(where: { $0.id == nodeId }) else { return }

        Task { @MainActor in
            statusMessage = "Re-translating paragraph #\(nodeId)..."
            do {
                let srcName = sourceLanguage.name
                let tgtName = targetLanguage.name
                let translated: String

                if engine == .apple, let session = appleSession {
                    let response = try await session.translate(node.originalText)
                    translated = response.targetText
                } else {
                    let config = activeLLMConfig
                    let baseInstruction = currentTranslationSystemInstruction(from: srcName, to: tgtName)
                    let customInstruction = PronounPromptBuilder.buildSystemInstruction(
                        baseInstruction: baseInstruction,
                        targetLanguageCode: targetLanguage.id,
                        bible: characterBible ?? currentEPUB?.characterBible,
                        chapterText: book.chapters[chapterIndex].originalContent
                    )
                    let precedingContext: String? = {
                        if let nIdx = book.chapters[chapterIndex].nodes.firstIndex(where: { $0.id == nodeId }), nIdx > 0 {
                            return book.chapters[chapterIndex].nodes[nIdx - 1].originalText
                        }
                        return nil
                    }()
                    translated = try await LLMTranslationService.translate(
                        text: node.originalText,
                        from: srcName,
                        to: tgtName,
                        config: config,
                        customSystemInstruction: customInstruction,
                        precedingContext: precedingContext
                    )
                }

                updateEPUBNodeTranslation(chapterIdx: chapterIndex, nodeId: nodeId, translatedText: translated)
                if var updatedBook = currentEPUB, chapterIndex < updatedBook.chapters.count {
                    EPUBProcessor.applyTranslations(to: &updatedBook.chapters[chapterIndex])
                    currentEPUB = updatedBook
                }
                saveCheckpoint()
                statusMessage = "Re-translated paragraph #\(nodeId) successfully!"
            } catch {
                errorMessage = "Re-translation failed: \(error.localizedDescription)"
                statusMessage = "Re-translation failed."
            }
        }
    }

    public func retranslateDocumentChunk(chunkId: Int) {
        guard let index = activeChunks.firstIndex(where: { $0.id == chunkId }) else { return }
        let originalText = activeChunks[index].text

        Task { @MainActor in
            statusMessage = "Re-translating chunk #\(chunkId)..."
            do {
                let srcName = sourceLanguage.name
                let tgtName = targetLanguage.name
                let translated: String

                if engine == .apple, let session = appleSession {
                    let response = try await session.translate(originalText)
                    translated = response.targetText
                } else {
                    let config = activeLLMConfig
                    let precedingContext: String? = {
                        if index > 0 {
                            return activeChunks[index - 1].text
                        }
                        return nil
                    }()
                    translated = try await LLMTranslationService.translate(
                        text: originalText,
                        from: srcName,
                        to: tgtName,
                        config: config,
                        precedingContext: precedingContext
                    )
                }

                updateDocumentChunkTranslation(chunkId: chunkId, translatedText: translated)
                translatedDocument = DocumentChunker.assemble(chunks: activeChunks, useTranslated: true)
                saveCheckpoint()
                statusMessage = "Re-translated chunk #\(chunkId) successfully!"
            } catch {
                errorMessage = "Re-translation failed: \(error.localizedDescription)"
                statusMessage = "Re-translation failed."
            }
        }
    }

    // MARK: - EPUB File Management
    public func loadEPUB(from url: URL) {
        do {
            // 1. If currently loaded book has progress, preserve its checkpoint first so it is not lost
            if hasSavedProgress {
                saveCheckpoint()
            }

            statusMessage = "Unpacking and parsing EPUB..."
            let book = try EPUBProcessor.unpack(epubURL: url)

            // 2. Check if a saved session already exists for this book
            let existingSessions = CheckpointManager.listCheckpoints()
            if let matchingSession = existingSessions.first(where: { $0.title == book.title && !book.title.isEmpty }) {
                _ = resumeSession(withId: matchingSession.id)
            } else {
                self.activeCheckpointId = UUID().uuidString
                self.currentEPUB = book
                self.characterBible = book.characterBible
                self.selectedChapterIndex = 0
                self.completedEPUBChapters = 0
                self.totalEPUBChapters = book.chapters.count
                self.currentEPUBNodeProgress = (0, book.totalNodes)
                self.appMode = .epub
                self.statusMessage = "Loaded eBook: \(book.title) (\(book.chapters.count) chapters, \(book.totalWords) words)"
                self.errorMessage = nil
            }
        } catch {
            errorMessage = "Failed to load EPUB: \(error.localizedDescription)"
        }
    }

    public func loadSampleEPUB() {
        do {
            let tempSampleURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Voyage_to_the_Cosmos.epub")
            try EPUBProcessor.createSampleEPUB(at: tempSampleURL)
            loadEPUB(from: tempSampleURL)
        } catch {
            errorMessage = "Failed to create sample EPUB: \(error.localizedDescription)"
        }
    }

    public func exportTranslatedEPUB(to destinationURL: URL) {
        guard let book = currentEPUB else {
            errorMessage = "No EPUB available to export."
            return
        }

        do {
            let targetCode = targetLanguage.code ?? "es"
            try EPUBProcessor.repack(book: book, targetURL: destinationURL, targetLanguageCode: targetCode)
            statusMessage = "Successfully exported translated eBook to \(destinationURL.lastPathComponent)!"
        } catch {
            errorMessage = "Failed to export EPUB: \(error.localizedDescription)"
        }
    }

    // MARK: - Document Sample & Clearing
    public func loadSampleDocument() {
        sourceDocument = """
# The Wonders of Deep Space Exploration

Space exploration is the use of astronomy and space technology to explore outer space. While the exploration of space is carried out mainly by astronomers with telescopes, its physical exploration though is conducted both by unmanned robotic space probes and human spaceflight.

## Early Observations and the Space Race

Early space exploration was driven by a "Space Race" between the Soviet Union and the United States. The launch of the first human-made object to orbit Earth, the Soviet Union's Sputnik 1, on 4 October 1957, and the first Moon landing by the American Apollo 11 mission on 20 July 1969 are often taken as landmarks for this initial period.

During the next decades, scientific missions to Mars, Venus, Jupiter, and Saturn unveiled diverse terrains, weather systems, and moons harboring subsurface oceans. The Voyager probes, launched in 1977, have traveled beyond the heliosphere and entered interstellar space, continuing to transmit scientific data across billions of kilometers.

## Modern Telescopes and the Future of Astronomy

With modern instruments such as the Hubble Space Telescope and the James Webb Space Telescope (JWST), humanity can peer into the cosmic dawn, capturing light emitted over 13 billion years ago. These observatories analyze atmospheric compositions of exoplanets in distant star systems, searching for biosignatures that might hint at extraterrestrial life.

Looking toward the coming century, international collaborations and private aerospace enterprises aim to establish permanent settlements on the Moon and embark on crewed expeditions to Mars. As our knowledge expands, the mysteries of dark matter, dark energy, and quantum gravity continue to challenge our understanding of the cosmos.
"""
        translatedDocument = ""
        statusMessage = "Sample document loaded."
        errorMessage = nil
    }

    public func clear() {
        cancelTranslation()
        activeCheckpointId = nil
        isCancelled = false
        if appMode == .document {
            sourceDocument = ""
            translatedDocument = ""
            activeChunks = []
            completedChunks = 0
            totalTranslatableChunks = 0
        } else {
            currentEPUB = nil
            selectedChapterIndex = 0
            completedEPUBChapters = 0
            totalEPUBChapters = 0
            currentEPUBNodeProgress = (0, 0)
        }
        statusMessage = "Ready"
        errorMessage = nil
    }

    public func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentChapterTranslatedText, forType: .string)
        statusMessage = "Copied translated chapter to clipboard!"
    }

    public var currentChapterOriginalText: String {
        guard let book = currentEPUB, selectedChapterIndex < book.chapters.count else { return "" }
        let ch = book.chapters[selectedChapterIndex]
        return ch.nodes.map(\.originalText).joined(separator: "\n\n")
    }

    public var currentChapterTranslatedText: String {
        guard let book = currentEPUB, selectedChapterIndex < book.chapters.count else { return "" }
        let ch = book.chapters[selectedChapterIndex]
        return ch.nodes.map { $0.translatedText.isEmpty ? $0.originalText : $0.translatedText }.joined(separator: "\n\n")
    }

    public func loadFromFile(url: URL) {
        if url.pathExtension.lowercased() == "epub" {
            loadEPUB(from: url)
        } else {
            errorMessage = "Please select an .epub file. NovelTranslator is designed specifically for eBooks and novels."
        }
    }

    public func saveToFile(url: URL) {
        exportTranslatedEPUB(to: url)
    }

    // MARK: - Text-to-Speech (TTS) Operations

    public func loadTTSVoices() async {
        let voices = await TTSService.shared.getAvailableVoices(
            engine: ttsEngine,
            targetLanguageCode: targetLanguage.id
        )
        await MainActor.run {
            self.availableTTSVoices = voices
            if !voices.contains(where: { $0.id == self.selectedTTSVoiceId }) {
                if let first = voices.first {
                    self.selectedTTSVoiceId = first.id
                }
            }
        }
    }

    public func chapterSpeechText(for chapterIndex: Int, source: TTSTextSource = .auto) -> String {
        guard let book = currentEPUB, book.chapters.indices.contains(chapterIndex) else { return "" }
        let ch = book.chapters[chapterIndex]

        switch source {
        case .original:
            if !ch.nodes.isEmpty {
                let texts = ch.nodes.map(\.originalText).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                return TTSService.cleanTextForSpeech(texts.joined(separator: "\n\n"))
            } else {
                return TTSService.cleanTextForSpeech(ch.originalContent)
            }
        case .translated:
            if !ch.nodes.isEmpty {
                let texts = ch.nodes.map(\.translatedText).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if !texts.isEmpty {
                    return TTSService.cleanTextForSpeech(texts.joined(separator: "\n\n"))
                }
            }
            let raw = ch.translatedContent.isEmpty ? ch.originalContent : ch.translatedContent
            return TTSService.cleanTextForSpeech(raw)
        case .auto:
            if !ch.nodes.isEmpty {
                // If chapter has translated nodes, use them; otherwise use original
                let hasTranslations = ch.nodes.contains { !$0.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let texts = ch.nodes.map { node in
                    if hasTranslations {
                        return node.translatedText.isEmpty ? node.originalText : node.translatedText
                    } else {
                        return node.originalText
                    }
                }
                return TTSService.cleanTextForSpeech(texts.joined(separator: "\n\n"))
            } else {
                let raw = ch.translatedContent.isEmpty ? ch.originalContent : ch.translatedContent
                return TTSService.cleanTextForSpeech(raw)
            }
        }
    }

    public func hasCachedAudioForChapter(chapterIndex: Int, source: TTSTextSource = .auto) -> Bool {
        guard let book = currentEPUB else { return false }
        let suffix = source == .original ? "orig" : "trans"
        return audioPlayer.hasCachedAudio(for: book.title, chapterIndex: chapterIndex, voiceId: selectedTTSVoiceId, suffix: suffix)
    }

    public func playCurrentChapterAudio(source: TTSTextSource = .auto) {
        playChapterAudio(chapterIndex: selectedChapterIndex, source: source)
    }

    public func playChapterAudio(chapterIndex: Int, source: TTSTextSource = .auto) {
        guard let book = currentEPUB, book.chapters.indices.contains(chapterIndex) else {
            ttsErrorMessage = "No chapter loaded."
            return
        }

        let chapter = book.chapters[chapterIndex]
        let suffix = source == .original ? "orig" : "trans"
        let cacheURL = audioPlayer.cachedAudioURL(for: book.title, chapterIndex: chapterIndex, voiceId: selectedTTSVoiceId, suffix: suffix)

        if audioPlayer.isPlaying && audioPlayer.currentAudioURL == cacheURL {
            audioPlayer.pause()
            return
        } else if audioPlayer.isPaused && audioPlayer.currentAudioURL == cacheURL {
            audioPlayer.play()
            return
        }

        let text = chapterSpeechText(for: chapterIndex, source: source)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ttsErrorMessage = "Chapter content is empty."
            return
        }

        ttsErrorMessage = nil
        let sourceLabel = source == .original ? " (Original)" : ""
        let title = "\(book.title) — \(chapter.title)\(sourceLabel)"

        if ttsEngine == .apple {
            audioPlayer.speakLiveWithApple(
                text: text,
                voiceIdentifier: selectedTTSVoiceId,
                title: title
            )
            return
        }

        // Vieneu Engine: Check cache or synthesize
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            audioPlayer.loadAndPlay(url: cacheURL, title: title)
            return
        }

        // Need synthesis
        isSynthesizingAudio = true
        ttsStatusMessage = "Synthesizing audio for '\(chapter.title)' with Vieneu (\(selectedTTSVoiceId))..."

        Task {
            do {
                try await TTSService.shared.synthesize(
                    text: text,
                    voiceId: selectedTTSVoiceId,
                    speed: ttsSpeed,
                    engine: .vieneu,
                    outputURL: cacheURL
                )
                await MainActor.run {
                    self.isSynthesizingAudio = false
                    self.ttsStatusMessage = nil
                    self.audioPlayer.loadAndPlay(url: cacheURL, title: title)
                }
            } catch {
                await MainActor.run {
                    self.isSynthesizingAudio = false
                    self.ttsStatusMessage = nil
                    self.ttsErrorMessage = "TTS generation error: \(error.localizedDescription)"
                }
            }
        }
    }

    public func testListeningCurrentVoice() {
        if isTestingTTSVoice || isSynthesizingAudio { return }

        let testSentence = (targetLanguage.id == "vi" || targetLanguage.id == "vi-VN" || ttsEngine == .vieneu)
            ? "Xin chào! Đây là bản nghe thử giọng đọc \(selectedTTSVoiceId) trong NovelTranslator."
            : "Hello! This is a test of voice \(selectedTTSVoiceId) in NovelTranslator."

        ttsErrorMessage = nil

        if ttsEngine == .apple {
            audioPlayer.speakLiveWithApple(
                text: testSentence,
                voiceIdentifier: selectedTTSVoiceId,
                title: "Test Voice: \(selectedTTSVoiceId)"
            )
            return
        }

        let tempURL = audioPlayer.cacheDirectory.appendingPathComponent("test_voice_\(selectedTTSVoiceId.replacingOccurrences(of: " ", with: "_")).wav")

        if FileManager.default.fileExists(atPath: tempURL.path) {
            audioPlayer.loadAndPlay(url: tempURL, title: "Test Voice: \(selectedTTSVoiceId)")
            return
        }

        isTestingTTSVoice = true
        ttsStatusMessage = "Generating sample audio for \(selectedTTSVoiceId)..."

        Task {
            do {
                try await TTSService.shared.synthesize(
                    text: testSentence,
                    voiceId: selectedTTSVoiceId,
                    speed: ttsSpeed,
                    engine: .vieneu,
                    outputURL: tempURL
                )
                await MainActor.run {
                    self.isTestingTTSVoice = false
                    self.ttsStatusMessage = nil
                    self.audioPlayer.loadAndPlay(url: tempURL, title: "Test Voice: \(selectedTTSVoiceId)")
                }
            } catch {
                await MainActor.run {
                    self.isTestingTTSVoice = false
                    self.ttsStatusMessage = nil
                    self.ttsErrorMessage = "Voice test failed: \(error.localizedDescription)"
                }
            }
        }
    }

    public func stopAudioPlayback() {
        audioPlayer.stop()
    }

    // MARK: - Batch Audiobook Export & Chapter Selection

    public func selectAllChaptersForExport() {
        guard let book = currentEPUB else { return }
        ttsExportSelectedChapters = Set(0..<book.chapters.count)
    }

    public func deselectAllChaptersForExport() {
        ttsExportSelectedChapters.removeAll()
    }

    public func selectTranslatedChaptersOnlyForExport() {
        guard let book = currentEPUB else { return }
        ttsExportSelectedChapters = Set(book.chapters.enumerated().compactMap { idx, ch in
            ch.isTranslated ? idx : nil
        })
    }

    public func toggleChapterExportSelection(_ index: Int) {
        if ttsExportSelectedChapters.contains(index) {
            ttsExportSelectedChapters.remove(index)
        } else {
            ttsExportSelectedChapters.insert(index)
        }
    }

    public func startBatchAudioExport(
        outputDirectory: URL,
        selectedVoiceId: String,
        speed: Double,
        textSource: TTSTextSource,
        chapterIndices: [Int]
    ) async {
        guard let book = currentEPUB, !book.chapters.isEmpty else {
            ttsErrorMessage = "No eBook loaded for export."
            return
        }

        isBatchExportingAudio = true
        ttsErrorMessage = nil

        let selectedChapters = chapterIndices.sorted().compactMap { idx -> (index: Int, chapter: EPUBChapter)? in
            guard book.chapters.indices.contains(idx) else { return nil }
            return (index: idx, chapter: book.chapters[idx])
        }

        guard !selectedChapters.isEmpty else {
            isBatchExportingAudio = false
            ttsErrorMessage = "No chapters selected for audio export."
            return
        }

        let manifestItems: [TTSChapterManifestItem] = selectedChapters.map { item in
            let rawText = chapterSpeechText(for: item.index, source: textSource)
            let safeTitle = item.chapter.title
                .replacingOccurrences(of: "[^a-zA-Z0-9_ -]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let outName = String(format: "%03d_%@.wav", item.index + 1, safeTitle.isEmpty ? "Chapter" : safeTitle)

            return TTSChapterManifestItem(
                id: item.chapter.id,
                title: item.chapter.title,
                text: rawText,
                output_filename: outName
            )
        }

        let manifest = TTSBatchManifest(
            voice: selectedVoiceId,
            speed: speed,
            output_dir: outputDirectory.path,
            chapters: manifestItems
        )

        do {
            try await TTSService.shared.batchSynthesize(
                manifest: manifest,
                activeProcessReceiver: { [weak self] proc in
                    Task { @MainActor [weak self] in
                        self?.batchExportProcess = proc
                    }
                },
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.batchExportProgress = progress
                        if progress.isCompleted {
                            self?.isBatchExportingAudio = false
                        }
                    }
                }
            )
        } catch {
            await MainActor.run {
                self.isBatchExportingAudio = false
                if (error as? TTSError) != .cancelled {
                    self.ttsErrorMessage = "Batch export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    public func cancelBatchAudioExport() {
        batchExportProcess?.terminate()
        batchExportProcess = nil
        isBatchExportingAudio = false
        batchExportProgress = nil
    }
}
