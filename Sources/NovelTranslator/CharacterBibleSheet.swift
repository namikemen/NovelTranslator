import SwiftUI

public class CharacterBibleEditorViewModel: ObservableObject {
    @Published public var workingBible: CharacterBible
    @Published public var selectedScopeId: String = "global"
    @Published public var selectedTab: Int = 0
    @Published public var presetCharAId: String = ""
    @Published public var presetCharBId: String = ""
    @Published public var showApiSettingsPopover: Bool = false
    @Published public var showPromptPreviewSheet: Bool = false

    public init(bible: CharacterBible) {
        self.workingBible = bible
        if let first = bible.characters.first {
            self.presetCharAId = first.id
            if bible.characters.count > 1 {
                self.presetCharBId = bible.characters[1].id
            }
        }
    }

    public func ensureChapterScope(chapterId: String, chapterIndex: Int, chapterTitle: String) {
        if workingBible.chapterScopes[chapterId] == nil {
            workingBible.chapterScopes[chapterId] = ChapterScope(
                id: chapterId,
                chapterIndex: chapterIndex,
                chapterTitle: chapterTitle,
                characters: [],
                relationships: [],
                notes: ""
            )
        }
    }

    public func copyGlobalToCurrentChapter(chapterIndex: Int, chapterTitle: String) {
        guard selectedScopeId != "global" else { return }
        workingBible.chapterScopes[selectedScopeId] = ChapterScope(
            id: selectedScopeId,
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            characters: workingBible.characters,
            relationships: workingBible.relationships,
            notes: workingBible.generalNotes
        )
    }

    public func clearCurrentChapterScope() {
        guard selectedScopeId != "global" else { return }
        workingBible.chapterScopes.removeValue(forKey: selectedScopeId)
    }

    public var isCurrentScopeChapterCustomized: Bool {
        guard selectedScopeId != "global" else { return false }
        if let scope = workingBible.chapterScopes[selectedScopeId] {
            return !scope.characters.isEmpty || !scope.relationships.isEmpty || !scope.notes.isEmpty
        }
        return false
    }

    public var availableCharactersForPresets: [CharacterProfile] {
        if selectedScopeId == "global" {
            return workingBible.characters
        }
        let local = workingBible.chapterScopes[selectedScopeId]?.characters ?? []
        return local.isEmpty ? workingBible.characters : local
    }

    public func deleteCharacter(charId: String) {
        if selectedScopeId == "global" {
            workingBible.characters.removeAll(where: { $0.id == charId })
            workingBible.relationships.removeAll {
                $0.sourceCharacterId == charId || $0.targetCharacterId == charId
            }
            if workingBible.narratorCharacterId == charId {
                workingBible.narratorCharacterId = nil
            }
        } else {
            workingBible.chapterScopes[selectedScopeId]?.characters.removeAll(where: { $0.id == charId })
            workingBible.chapterScopes[selectedScopeId]?.relationships.removeAll {
                $0.sourceCharacterId == charId || $0.targetCharacterId == charId
            }
        }
    }

    public func promoteCharacterToGlobal(charId: String) {
        guard selectedScopeId != "global" else { return }
        guard let scope = workingBible.chapterScopes[selectedScopeId],
              let char = scope.characters.first(where: { $0.id == charId }) else { return }

        // 1. Add to global characters if not already present
        if !workingBible.characters.contains(where: { $0.id == charId || $0.name.lowercased() == char.name.lowercased() }) {
            workingBible.characters.append(char)
        }

        // 2. Promote any relationships in this chapter involving this character
        let relevantRels = scope.relationships.filter {
            $0.sourceCharacterId == charId || $0.targetCharacterId == charId
        }
        for rel in relevantRels {
            if !workingBible.relationships.contains(where: {
                $0.sourceCharacterId == rel.sourceCharacterId && $0.targetCharacterId == rel.targetCharacterId
            }) {
                workingBible.relationships.append(rel)
            }
        }

        // 3. Remove character from local scope so it cleanly resolves from global
        workingBible.chapterScopes[selectedScopeId]?.characters.removeAll(where: { $0.id == charId })
    }

    public func applyPreset(selfA: String, addrA: String, selfB: String, addrB: String) {
        guard !presetCharAId.isEmpty, !presetCharBId.isEmpty, presetCharAId != presetCharBId else { return }

        if selectedScopeId == "global" {
            workingBible.relationships.removeAll {
                ($0.sourceCharacterId == presetCharAId && $0.targetCharacterId == presetCharBId) ||
                ($0.sourceCharacterId == presetCharBId && $0.targetCharacterId == presetCharAId)
            }
            workingBible.relationships.append(RelationshipPair(
                sourceCharacterId: presetCharAId,
                targetCharacterId: presetCharBId,
                selfPronoun: selfA,
                addressingPronoun: addrA
            ))
            workingBible.relationships.append(RelationshipPair(
                sourceCharacterId: presetCharBId,
                targetCharacterId: presetCharAId,
                selfPronoun: selfB,
                addressingPronoun: addrB
            ))
        } else {
            var scope = workingBible.chapterScopes[selectedScopeId] ?? ChapterScope(id: selectedScopeId, chapterIndex: 0, chapterTitle: "")
            scope.relationships.removeAll {
                ($0.sourceCharacterId == presetCharAId && $0.targetCharacterId == presetCharBId) ||
                ($0.sourceCharacterId == presetCharBId && $0.targetCharacterId == presetCharAId)
            }
            scope.relationships.append(RelationshipPair(
                sourceCharacterId: presetCharAId,
                targetCharacterId: presetCharBId,
                selfPronoun: selfA,
                addressingPronoun: addrA
            ))
            scope.relationships.append(RelationshipPair(
                sourceCharacterId: presetCharBId,
                targetCharacterId: presetCharAId,
                selfPronoun: selfB,
                addressingPronoun: addrB
            ))
            workingBible.chapterScopes[selectedScopeId] = scope
        }
    }
}

public struct CharacterBibleSheet: View {
    @ObservedObject var viewModel: TranslationViewModel
    @StateObject private var editor: CharacterBibleEditorViewModel

    public init(viewModel: TranslationViewModel) {
        self.viewModel = viewModel
        let initial = viewModel.characterBible ?? CharacterBible(bookTitle: viewModel.currentEPUB?.title ?? "Untitled eBook")
        _editor = StateObject(wrappedValue: CharacterBibleEditorViewModel(bible: initial))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Control Toolbar Bar (Model Picker, API Config, POV, AI Scan)
            toolbarControlBarView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            Divider()

            // In-Sheet Live Progress Banner
            if viewModel.isAnalyzingCharacters {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))
                Divider()
            }

            // In-Sheet Error Banner
            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                Divider()
            }

            // Scope & Chapter Control Bar
            scopeBarView
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            // Tab Selector
            Picker("", selection: $editor.selectedTab) {
                let charCount = (editor.selectedScopeId == "global")
                    ? editor.workingBible.characters.count
                    : (editor.workingBible.chapterScopes[editor.selectedScopeId]?.characters.count ?? 0)
                let relCount = (editor.selectedScopeId == "global")
                    ? editor.workingBible.relationships.count
                    : (editor.workingBible.chapterScopes[editor.selectedScopeId]?.relationships.count ?? 0)

                Text("Characters (\(charCount))").tag(0)
                Text("Pronoun Pairs (\(relCount))").tag(1)
                Text("Notes & Translation Style").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Content Area (Flexible height so List scrolls properly without pushing footer off-screen)
            Group {
                switch editor.selectedTab {
                case 0:
                    charactersTabView
                case 1:
                    relationshipsTabView
                default:
                    notesTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer (Permanently visible and anchored at bottom)
            footerView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 840, idealWidth: 920, minHeight: 650, idealHeight: 720)
        .sheet(isPresented: $viewModel.showPromptSettingsSheet) {
            PromptSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $editor.showPromptPreviewSheet) {
            promptPreviewSheet
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "person.2.badge.gearshape.fill")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Character & Pronoun Bible")
                        .font(.headline)
                    Text(editor.workingBible.bookGenre.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(editor.workingBible.bookGenre == .nonFiction ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                        .foregroundColor(editor.workingBible.bookGenre == .nonFiction ? .purple : .blue)
                        .cornerRadius(4)
                }
                Text("Book: \(editor.workingBible.bookTitle.isEmpty ? "Current eBook" : editor.workingBible.bookTitle)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Header Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    editor.showPromptPreviewSheet = true
                }) {
                    Label("Preview Prompt", systemImage: "doc.text.magnifyingglass")
                }
                .controlSize(.small)
                .help("Preview full translation system prompt with this character bible")

                Button(action: {
                    viewModel.selectedPromptTab = .characterAnalysis
                    viewModel.showPromptSettingsSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "character.cursor.ibeam")
                        Text("Prompt")
                        if viewModel.hasCustomCharacterAnalysisPrompt {
                            Circle().fill(Color.purple).frame(width: 5, height: 5)
                        }
                    }
                }
                .controlSize(.small)
                .help("Customize Character Analysis Prompt")

                Button("Save & Apply") {
                    viewModel.saveCharacterBible(editor.workingBible)
                    viewModel.showCharacterBibleSheet = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Save changes and apply to eBook")

                Button("Close") {
                    viewModel.showCharacterBibleSheet = false
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Control Toolbar Bar
    private var toolbarControlBarView: some View {
        HStack(spacing: 12) {
            // Model Picker & Inline API Settings Button
            HStack(spacing: 6) {
                Image(systemName: "cpu.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption)

                Text(viewModel.characterAnalysisConfig.modelName)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)

                Button(action: { editor.showApiSettingsPopover.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Configure API URL, API Key, and Model")
                .popover(isPresented: $editor.showApiSettingsPopover, arrowEdge: .bottom) {
                    inlineApiSettingsView
                        .frame(width: 380)
                        .padding()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            Divider().frame(height: 18)

            // Perspective (POV) Picker
            Picker("POV:", selection: $editor.workingBible.narrativePOV) {
                ForEach(NarrativePOV.allCases) { pov in
                    Text(pov.rawValue).tag(pov)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 145)

            // Narrator Picker (if First Person)
            if editor.workingBible.narrativePOV == .firstPerson && !editor.workingBible.characters.isEmpty {
                Picker("Narrator:", selection: Binding(
                    get: { editor.workingBible.narratorCharacterId ?? editor.workingBible.characters.first?.id ?? "" },
                    set: { editor.workingBible.narratorCharacterId = $0 }
                )) {
                    ForEach(editor.workingBible.characters) { char in
                        Text(char.name).tag(char.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 135)
            }

            Spacer()

            // AI Action: Scan All Chapters Button
            Button {
                Task {
                    await viewModel.scanAndAnalyzeAllChapters()
                    if let updated = viewModel.characterBible {
                        editor.workingBible = updated
                    }
                }
            } label: {
                if viewModel.isAnalyzingCharacters {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Scanning...")
                    }
                } else {
                    Label("Scan All Chapters (AI)", systemImage: "sparkles")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(viewModel.isAnalyzingCharacters)
            .help("Scan 100% of chapters across the book to extract all characters and dialogue relationships")
        }
    }

    // MARK: - Inline API Settings View (Direct in-sheet editing!)
    private var inlineApiSettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.accentColor)
                Text("AI Model & API Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    editor.showApiSettingsPopover = false
                    viewModel.saveOpenAIEnvConfig()
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // Provider Picker
            Picker("Provider", selection: $viewModel.characterAnalysisProvider) {
                Text("API (OpenAI / 9router)").tag(TranslationViewModel.CharacterAnalysisProvider.openAI)
                Text("Ollama (Local)").tag(TranslationViewModel.CharacterAnalysisProvider.ollama)
                Text("Auto").tag(TranslationViewModel.CharacterAnalysisProvider.auto)
            }
            .pickerStyle(.segmented)

            if viewModel.characterAnalysisProvider == .ollama {
                // Ollama form
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ollama Server URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("http://localhost:11434/v1", text: $viewModel.ollamaConfig.baseURL)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Model Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Refresh Models") {
                            Task { await viewModel.refreshModels() }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }

                    if !viewModel.availableOllamaModels.isEmpty {
                        Picker("", selection: $viewModel.ollamaConfig.modelName) {
                            ForEach(viewModel.availableOllamaModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    } else {
                        TextField("translategemma:4b", text: $viewModel.ollamaConfig.modelName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            } else {
                // API (OpenAI / 9router / etc.)
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Base URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("http://localhost:20128/v1", text: $viewModel.openAIConfig.baseURL)
                        .textFieldStyle(.roundedBorder)

                    Text("API Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("sk-...", text: $viewModel.openAIConfig.apiKey)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Model Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Fetch Models") {
                            Task { await viewModel.refreshModels() }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }

                    if !viewModel.availableOpenAIModels.isEmpty {
                        Picker("", selection: $viewModel.openAIConfig.modelName) {
                            ForEach(viewModel.availableOpenAIModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    } else {
                        TextField("gh/gpt-4o-mini-2024-07-18", text: $viewModel.openAIConfig.modelName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            Divider()

            // Test Connection & Save
            HStack {
                Button(action: {
                    Task { await viewModel.testConnection() }
                }) {
                    if viewModel.isTestingConnection {
                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(viewModel.isTestingConnection)

                Spacer()

                Button("Save to .env") {
                    viewModel.saveOpenAIEnvConfig()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if let result = viewModel.connectionTestResult {
                Text(result)
                    .font(.caption2)
                    .foregroundColor(result.contains("Success") || result.contains("Found") ? .green : .orange)
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Prompt Preview Sheet
    private var promptPreviewSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Assembled Translation System Prompt")
                        .font(.headline)
                    Text("This is the exact full prompt sent to the LLM for this book, including Character Bible knowledge base directives.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Copy Prompt") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    let full = viewModel.currentFullTranslationSystemInstruction(
                        from: viewModel.sourceLanguage.name,
                        to: viewModel.targetLanguage.name,
                        includeKnowledgeBase: true
                    )
                    pasteboard.setString(full, forType: .string)
                }
                .controlSize(.small)

                Button("Done") {
                    editor.showPromptPreviewSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                Text(viewModel.currentFullTranslationSystemInstruction(
                    from: viewModel.sourceLanguage.name,
                    to: viewModel.targetLanguage.name,
                    includeKnowledgeBase: true
                ))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 550)
    }

    // MARK: - Scope Bar View
    private var scopeBarView: some View {
        HStack(spacing: 12) {
            // Scope Picker
            HStack(spacing: 6) {
                Text("Scope:")
                    .font(.caption.bold())
                Picker("", selection: $editor.selectedScopeId) {
                    Text("🌐 Global (Entire Book)").tag("global")
                    if let book = viewModel.currentEPUB, !book.chapters.isEmpty {
                        Divider()
                        ForEach(Array(book.chapters.enumerated()), id: \.element.id) { idx, ch in
                            Text("📖 Ch. \(idx + 1): \(ch.title)").tag(ch.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
            }

            // Book Genre Picker
            HStack(spacing: 6) {
                Text("Genre:")
                    .font(.caption.bold())
                Picker("", selection: $editor.workingBible.bookGenre) {
                    ForEach(BookGenre.allCases) { genre in
                        Text(genre.rawValue).tag(genre)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            Spacer()

            if editor.selectedScopeId != "global" {
                if let book = viewModel.currentEPUB,
                   let chIdx = book.chapters.firstIndex(where: { $0.id == editor.selectedScopeId }) {
                    let ch = book.chapters[chIdx]

                    Button {
                        Task {
                            await viewModel.analyzeCharactersForChapter(chapterIndex: chIdx)
                            if let updated = viewModel.characterBible {
                                editor.workingBible = updated
                            }
                        }
                    } label: {
                        if viewModel.isAnalyzingCharacters {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Analyze Chapter", systemImage: "sparkles")
                                .font(.caption)
                        }
                    }
                    .disabled(viewModel.isAnalyzingCharacters)

                    if editor.isCurrentScopeChapterCustomized {
                        Button(role: .destructive) {
                            editor.clearCurrentChapterScope()
                        } label: {
                            Text("Reset to Global")
                                .font(.caption)
                        }
                    } else {
                        Button {
                            editor.copyGlobalToCurrentChapter(chapterIndex: chIdx, chapterTitle: ch.title)
                        } label: {
                            Text("Copy Global Bible Here")
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Characters Tab
    private var charactersTabView: some View {
        VStack(spacing: 8) {
            HStack {
                if editor.selectedScopeId == "global" {
                    Text("Global characters applied across the entire book:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Chapter-specific characters (overrides or extends global list for this chapter):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if editor.selectedScopeId == "global" {
                    Button {
                        Task {
                            await viewModel.scanAndAnalyzeAllChapters()
                            if let updated = viewModel.characterBible {
                                editor.workingBible = updated
                            }
                        }
                    } label: {
                        Label("Scan All Chapters", systemImage: "books.vertical.fill")
                    }
                    .controlSize(.small)
                    .disabled(viewModel.isAnalyzingCharacters)
                    .help("Scan 100% of chapters to extract characters")
                }

                Button {
                    let newChar = CharacterProfile(name: "New Character", gender: .unknown, relativeAge: "adult", roleOrStatus: "")
                    if editor.selectedScopeId == "global" {
                        editor.workingBible.characters.append(newChar)
                    } else {
                        var scope = editor.workingBible.chapterScopes[editor.selectedScopeId] ?? ChapterScope(id: editor.selectedScopeId, chapterIndex: 0, chapterTitle: "")
                        scope.characters.append(newChar)
                        editor.workingBible.chapterScopes[editor.selectedScopeId] = scope
                    }
                } label: {
                    Label("Add Character", systemImage: "plus")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            let charBinding: Binding<[CharacterProfile]> = Binding(
                get: {
                    if editor.selectedScopeId == "global" {
                        return editor.workingBible.characters
                    } else {
                        return editor.workingBible.chapterScopes[editor.selectedScopeId]?.characters ?? []
                    }
                },
                set: {
                    if editor.selectedScopeId == "global" {
                        editor.workingBible.characters = $0
                    } else {
                        var scope = editor.workingBible.chapterScopes[editor.selectedScopeId] ?? ChapterScope(id: editor.selectedScopeId, chapterIndex: 0, chapterTitle: "")
                        scope.characters = $0
                        editor.workingBible.chapterScopes[editor.selectedScopeId] = scope
                    }
                }
            )

            if charBinding.wrappedValue.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    if editor.selectedScopeId == "global" {
                        Text("No global characters defined yet.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Click 'Scan All Chapters' to scan all chapters across the eBook and extract characters.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button {
                            Task {
                                await viewModel.scanAndAnalyzeAllChapters()
                                if let updated = viewModel.characterBible {
                                    editor.workingBible = updated
                                }
                            }
                        } label: {
                            Label("Scan All Chapters for Characters", systemImage: "books.vertical.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isAnalyzingCharacters)
                        .padding(.top, 4)
                    } else {
                        Text("No chapter-specific overrides.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("This chapter inherits all global characters. Click 'Copy Global Bible Here' to customize.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(charBinding) { $char in
                        HStack(spacing: 10) {
                            TextField("Name", text: $char.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)

                            Picker("", selection: $char.gender) {
                                ForEach(CharacterGender.allCases) { gender in
                                    Text(gender.rawValue).tag(gender)
                                }
                            }
                            .frame(width: 90)

                            Picker("", selection: Binding(
                                get: { char.ageTier },
                                set: { char.ageTier = $0 }
                            )) {
                                ForEach(AgeTier.allCases) { tier in
                                    Text(tier.displayName).tag(tier)
                                }
                            }
                            .frame(width: 105)

                            TextField("Age desc", text: $char.relativeAge)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 95)
                                .help("Age details, e.g. 25 years old, 70s, or freeform description")

                            TextField("3rd person (cô, anh, bà...)", text: Binding(
                                get: { char.thirdPersonPronoun ?? char.resolvedThirdPersonPronoun },
                                set: { char.thirdPersonPronoun = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                            .help("Third-person narrative pronoun override (e.g. cô ta, anh ta, bà ta, ông ta, thằng bé, cô bé, gã, hắn).")

                            TextField("Role / Status", text: $char.roleOrStatus)
                                .textFieldStyle(.roundedBorder)

                            if editor.selectedScopeId != "global" {
                                Button {
                                    editor.promoteCharacterToGlobal(charId: char.id)
                                } label: {
                                    Image(systemName: "globe.badge.chevron.backward")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .help("Promote character to Global (entire book)")
                            }

                            Button {
                                editor.deleteCharacter(charId: char.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Relationships Tab
    private var relationshipsTabView: some View {
        VStack(spacing: 8) {
            let availableChars = editor.availableCharactersForPresets

            // Preset Bar
            if availableChars.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Quick Preset:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        Picker("Char A", selection: $editor.presetCharAId) {
                            ForEach(availableChars) { char in
                                Text(char.name).tag(char.id)
                            }
                        }
                        .frame(width: 120)

                        Text("⇄")

                        Picker("Char B", selection: $editor.presetCharBId) {
                            ForEach(availableChars) { char in
                                Text(char.name).tag(char.id)
                            }
                        }
                        .frame(width: 120)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            presetButton("anh - em", selfA: "anh", addrA: "em", selfB: "em", addrB: "anh")
                            presetButton("chị - em", selfA: "chị", addrA: "em", selfB: "em", addrB: "chị")
                            presetButton("ông - cháu", selfA: "ông", addrA: "cháu", selfB: "cháu", addrB: "ông")
                            presetButton("bà - cháu", selfA: "bà", addrA: "cháu", selfB: "cháu", addrB: "bà")
                            presetButton("chú - cháu", selfA: "chú", addrA: "cháu", selfB: "cháu", addrB: "chú")
                            presetButton("bác - cháu", selfA: "bác", addrA: "cháu", selfB: "cháu", addrB: "bác")
                            presetButton("cô - cháu", selfA: "cô", addrA: "cháu", selfB: "cháu", addrB: "cô")
                            presetButton("mình - cậu", selfA: "mình", addrA: "cậu", selfB: "cậu", addrB: "mình")
                            presetButton("tôi - bạn", selfA: "tôi", addrA: "bạn", selfB: "tôi", addrB: "bạn")
                            presetButton("tao - mày", selfA: "tao", addrA: "mày", selfB: "tao", addrB: "mày")
                            presetButton("bệ hạ - thần", selfA: "trẫm", addrA: "khanh", selfB: "thần", addrB: "bệ hạ")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                Divider()
            }

            HStack {
                Text("Reciprocal dialogue pronouns (xưng hô):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    if let first = availableChars.first,
                       let second = availableChars.dropFirst().first {
                        let newPair = RelationshipPair(
                            sourceCharacterId: first.id,
                            targetCharacterId: second.id,
                            selfPronoun: "tôi",
                            addressingPronoun: "bạn"
                        )
                        if editor.selectedScopeId == "global" {
                            editor.workingBible.relationships.append(newPair)
                        } else {
                            var scope = editor.workingBible.chapterScopes[editor.selectedScopeId] ?? ChapterScope(id: editor.selectedScopeId, chapterIndex: 0, chapterTitle: "")
                            scope.relationships.append(newPair)
                            editor.workingBible.chapterScopes[editor.selectedScopeId] = scope
                        }
                    }
                } label: {
                    Label("Add Pair", systemImage: "plus")
                }
                .disabled(availableChars.count < 2)
            }
            .padding(.horizontal)

            let relBinding: Binding<[RelationshipPair]> = Binding(
                get: {
                    if editor.selectedScopeId == "global" {
                        return editor.workingBible.relationships
                    } else {
                        return editor.workingBible.chapterScopes[editor.selectedScopeId]?.relationships ?? []
                    }
                },
                set: {
                    if editor.selectedScopeId == "global" {
                        editor.workingBible.relationships = $0
                    } else {
                        var scope = editor.workingBible.chapterScopes[editor.selectedScopeId] ?? ChapterScope(id: editor.selectedScopeId, chapterIndex: 0, chapterTitle: "")
                        scope.relationships = $0
                        editor.workingBible.chapterScopes[editor.selectedScopeId] = scope
                    }
                }
            )

            if relBinding.wrappedValue.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No reciprocal pairs configured for this scope.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Use the quick presets above or click 'Add Pair' to specify dialogue pronouns.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(relBinding) { $pair in
                        HStack(spacing: 8) {
                            Picker("From", selection: $pair.sourceCharacterId) {
                                ForEach(availableChars) { char in
                                    Text(char.name).tag(char.id)
                                }
                            }
                            .frame(width: 120)

                            Text("calls self")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("anh, tôi", text: $pair.selfPronoun)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)

                            Text("and calls")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("To", selection: $pair.targetCharacterId) {
                                ForEach(availableChars) { char in
                                    Text(char.name).tag(char.id)
                                }
                            }
                            .frame(width: 120)

                            Text("as")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("em, bạn", text: $pair.addressingPronoun)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)

                            TextField("Context (e.g. siblings, rivals)", text: Binding(
                                get: { pair.contextNote ?? "" },
                                set: { pair.contextNote = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Button {
                                if editor.selectedScopeId == "global" {
                                    editor.workingBible.relationships.removeAll(where: { $0.id == pair.id })
                                } else {
                                    editor.workingBible.chapterScopes[editor.selectedScopeId]?.relationships.removeAll(where: { $0.id == pair.id })
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func presetButton(_ label: String, selfA: String, addrA: String, selfB: String, addrB: String) -> some View {
        Button(label) {
            editor.applyPreset(selfA: selfA, addrA: addrA, selfB: selfB, addrB: addrB)
        }
        .controlSize(.small)
    }

    // MARK: - Notes Tab
    private var notesTabView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editor.selectedScopeId == "global" {
                Text("Global translation & tone guidelines (injected into all chapter prompts):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $editor.workingBible.generalNotes)
                    .font(.body)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            } else {
                Text("Chapter-specific translation notes (injected only when translating this chapter):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                let noteBinding: Binding<String> = Binding(
                    get: { editor.workingBible.chapterScopes[editor.selectedScopeId]?.notes ?? "" },
                    set: {
                        var scope = editor.workingBible.chapterScopes[editor.selectedScopeId] ?? ChapterScope(id: editor.selectedScopeId, chapterIndex: 0, chapterTitle: "")
                        scope.notes = $0
                        editor.workingBible.chapterScopes[editor.selectedScopeId] = scope
                    }
                )

                TextEditor(text: noteBinding)
                    .font(.body)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Knowledge Base in Translation Prompt", systemImage: "character.book.closed")
                        .font(.subheadline.bold())
                    Spacer()
                    Button(action: {
                        editor.showPromptPreviewSheet = true
                    }) {
                        Label("Preview Full Prompt", systemImage: "doc.text.magnifyingglass")
                    }
                    .controlSize(.small)
                }

                Text("When translating to Vietnamese, all characters, reciprocal pronouns (xưng hô), and 3rd-person rules from this Character Bible are automatically assembled and injected into the translation model's system prompt.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button("Reset to Blank") {
                editor.workingBible = CharacterBible(bookTitle: viewModel.currentEPUB?.title ?? "")
            }
            .foregroundColor(.secondary)

            Spacer()

            // Info count summary badge
            Text("\(editor.workingBible.characters.count) Characters • \(editor.workingBible.relationships.count) Pronoun Pairs")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("Cancel") {
                viewModel.showCharacterBibleSheet = false
            }

            Button("Save & Apply") {
                viewModel.saveCharacterBible(editor.workingBible)
                viewModel.showCharacterBibleSheet = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }
}
