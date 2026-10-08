import SwiftUI
import UniformTypeIdentifiers
import AppKit
@preconcurrency import Translation

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct NovelTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = TranslationViewModel()

    var body: some Scene {
        WindowGroup { [viewModel] in
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1050, minHeight: 700)
                .onAppear {
                    appDelegate.onTerminate = {
                        viewModel.saveCheckpoint()
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Model Prompts...") {
                    viewModel.showPromptSettingsSheet = true
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: TranslationViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Control Toolbar (compact, sleek vertical footprint)
            toolbarView
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Progress Banner (displayed only when translating, can resume, or has active notice)
            if viewModel.isTranslating || viewModel.canResume || viewModel.fallbackNotice != nil {
                progressBannerView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                Divider()
            }

            // Error Banner
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.15))
                Divider()
            }

            // Apple Translator Character Bible notice
            if viewModel.engine == .apple && viewModel.appMode == .epub && (viewModel.targetLanguage.id == "vi" || viewModel.targetLanguage.id == "vi-VN") && (viewModel.characterBible != nil || viewModel.currentEPUB?.characterBible != nil) && !viewModel.isTranslating {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Apple Built-in Translator uses fixed on-device models and does not support custom Character Bibles. Switch to Ollama or OpenAI to apply your Vietnamese pronoun rules.")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                Divider()
            }

            // Main Content Area
            epubModeView

            Divider()

            // Status Bar
            statusBarView
        }
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            viewModel.loadFromFile(url: url)
                        }
                    }
                }
                return true
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    if let data = data,
                       let pathString = String(data: data, encoding: .utf8),
                       let url = URL(string: pathString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        DispatchQueue.main.async {
                            viewModel.loadFromFile(url: url)
                        }
                    }
                }
                return true
            }
        }
        .overlay {
            if viewModel.isTargetedForDrop {
                ZStack {
                    Color.black.opacity(0.35)
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor).opacity(0.92)))
                        .padding(40)
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        Text("Drop eBook (.epub) to Open")
                            .font(.title3.bold())
                        Text("Release to load eBook immediately into translator")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .translationTask(viewModel.configuration) { session in
            await viewModel.translate(using: session)
        }
        .popover(isPresented: $viewModel.showSettingsPopover, arrowEdge: .top) {
            engineSettingsView
                .frame(width: 420)
                .padding()
        }
        .sheet(isPresented: $viewModel.showSavedSessionsSheet) {
            SavedSessionsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showCharacterBibleSheet) {
            CharacterBibleSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showPromptSettingsSheet) {
            PromptSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showTTSExportSheet) {
            TTSExportSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showModelManagerSheet) {
            ModelManagerSheet(viewModel: viewModel)
        }
        .alert("Analyze Characters for Vietnamese?", isPresented: $viewModel.showUnanalyzedBibleAlert) {
            Button("Scan All Chapters (AI)") {
                Task {
                    await viewModel.scanAndAnalyzeAllChapters()
                }
            }
            Button("Translate Directly", role: .cancel) {
                viewModel.startTranslation(resume: false)
            }
        } message: {
            Text("Scanning all chapters ensures characters appearing in later chapters are identified and translated with proper Vietnamese pronouns (anh, em, chị, ông, bà...).")
        }
    }

    // MARK: - Toolbar View
    private var toolbarView: some View {
        HStack(alignment: .center, spacing: 8) {
            // Engine Picker & Settings Button
            HStack(spacing: 4) {
                Picker("Engine", selection: $viewModel.engine) {
                    ForEach(TranslationEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .labelsHidden()
                .fixedSize()

                if viewModel.engine != .apple {
                    if viewModel.engine == .openai {
                        Menu {
                            Section("Active Primary Model") {
                                ForEach(viewModel.modelProfiles) { profile in
                                    Button(action: {
                                        viewModel.selectModelProfile(id: profile.id)
                                    }) {
                                        HStack {
                                            Text(profile.name)
                                            if viewModel.activeProfileId == profile.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button(action: {
                                viewModel.showModelManagerSheet = true
                            }) {
                                Label("Manage Models & Fallbacks...", systemImage: "slider.horizontal.3")
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "cpu")
                                    .font(.caption2)
                                Text(viewModel.activeModelProfile?.name ?? "Model")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .cornerRadius(5)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Quick switch model profile or configure fallback models")
                    }

                    Button(action: { viewModel.showSettingsPopover.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Configure \(viewModel.engine.rawValue) settings and models")

                    Button(action: { viewModel.showPromptSettingsSheet = true }) {
                        HStack(spacing: 3) {
                            Image(systemName: "character.cursor.ibeam")
                                .foregroundColor(viewModel.hasCustomPrompts ? .accentColor : .secondary)
                            if viewModel.hasCustomPrompts {
                                Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Adjust Model Prompts (Translation & Character Analysis)")
                }
            }

            Divider()
                .frame(height: 18)

            // Source & Target Languages
            HStack(spacing: 5) {
                Picker("From", selection: $viewModel.sourceLanguage) {
                    ForEach(SupportedLanguage.allSources) { lang in
                        Text(lang.name).tag(lang)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Picker("To", selection: $viewModel.targetLanguage) {
                    ForEach(SupportedLanguage.allTargets) { lang in
                        Text(lang.name).tag(lang)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            // Character Bible (for Vietnamese target language in EPUB mode)
            if viewModel.targetLanguage.id == "vi" || viewModel.targetLanguage.id == "vi-VN" {
                Button(action: { viewModel.showCharacterBibleSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.badge.gearshape")
                        if let bible = viewModel.characterBible ?? viewModel.currentEPUB?.characterBible, !bible.characters.isEmpty {
                            Text("Bible (\(bible.characters.count))")
                                .font(.caption)
                        } else {
                            Text("Character Bible")
                                .font(.caption)
                        }
                    }
                }
                .help("Configure characters and Vietnamese pronoun pairs")
                .fixedSize()
            }

            // Translate Action Button with Resume Checkpoint Support
            if viewModel.isTranslating {
                Button(role: .cancel, action: { viewModel.cancelTranslation() }) {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .keyboardShortcut(".", modifiers: .command)
                .fixedSize()
            } else if viewModel.canResume {
                HStack(spacing: 4) {
                    Button(action: { viewModel.startTranslation(resume: true) }) {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .help("Resume translation from saved checkpoint")
                    .fixedSize()

                    Menu {
                        Button("Restart from Beginning", role: .destructive) {
                            viewModel.startTranslation(resume: false)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 16)
                    .help("More translation options")
                }
            } else {
                Button(action: {
                    if (viewModel.targetLanguage.id == "vi" || viewModel.targetLanguage.id == "vi-VN") && (viewModel.characterBible == nil && viewModel.currentEPUB?.characterBible == nil) {
                        viewModel.showUnanalyzedBibleAlert = true
                    } else {
                        viewModel.startTranslation(resume: false)
                    }
                }) {
                    Label("Translate eBook", systemImage: "translate")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isTranslateDisabled)
                .fixedSize()
            }

            // Save Progress (independent on-demand bookmarking)
            if viewModel.canResume || viewModel.isTranslating {
                Button(action: {
                    viewModel.saveCheckpoint()
                }) {
                    Label("Save", systemImage: "bookmark")
                }
                .help("Save current progress to checkpoint")
                .fixedSize()
            }

            if let saveMsg = viewModel.saveProgressFeedback {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(saveMsg)
                        .font(.caption2)
                        .foregroundColor(.green)
                        .lineLimit(1)
                }
                .fixedSize()
            }

            Spacer()

            // Utility File & Session Tools (Compact macOS Icon Buttons with Tooltips)
            HStack(spacing: 6) {
                // Saved Sessions Menu
                Menu {
                    if viewModel.savedSessions.isEmpty {
                        Text("No saved sessions").foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.savedSessions) { session in
                            Button(action: {
                                viewModel.resumeSession(withId: session.id)
                            }) {
                                Text("📖 \(session.title) (\(session.progressPercentString))")
                            }
                        }
                        Divider()
                        Button("Manage All Saved Sessions...") {
                            viewModel.showSavedSessionsSheet = true
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.arrow.circlepath")
                        if !viewModel.savedSessions.isEmpty {
                            Text("\(viewModel.savedSessions.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                    }
                }
                .help("Saved translation sessions (\(viewModel.savedSessions.count))")
                .fixedSize()

                // File Open Button
                Button(action: { showOpenPanel() }) {
                    Image(systemName: "folder")
                }
                .help("Open EPUB eBook (⌘O)")

                // Sample Book Button
                Button(action: { viewModel.loadSampleEPUB() }) {
                    Image(systemName: "book.pages")
                }
                .help("Load sample EPUB eBook")

                // Clear Button
                Button(action: { viewModel.clear() }) {
                    Image(systemName: "trash")
                }
                .help("Clear current eBook")
            }
        }
    }

    private var isTranslateDisabled: Bool {
        viewModel.currentEPUB == nil
    }

    // MARK: - Engine Settings Popover
    private var engineSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundColor(.accentColor)
                Text("\(viewModel.engine.rawValue) Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    viewModel.showSettingsPopover = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            Divider()

            if viewModel.engine == .ollama {
                ollamaSettingsForm
            } else {
                openAISettingsForm
            }

            Divider()

            // Batch Size Configuration
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundColor(.accentColor)
                    Text("Batch Size")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(viewModel.batchWordLimit) words/req")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.accentColor)
                }

                Stepper(
                    value: $viewModel.batchWordLimit,
                    in: 500...2500,
                    step: 100
                ) {
                    Text("Target words per request")
                        .font(.caption)
                }

                Text("Batches consecutive paragraphs using XML tags. 1,000–1,500 words is optimal for cloud models; 600–800 words for local Ollama.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Model Prompts Customization Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "character.cursor.ibeam")
                        .foregroundColor(.accentColor)
                    Text("Model Prompts")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Customize Prompts...") {
                        viewModel.showPromptSettingsSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Text("Adjust system prompt templates for translation quality and character analysis extraction.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if viewModel.hasCustomPrompts {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text("Custom prompts active")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Spacer()
                        Button("Reset to Defaults") {
                            viewModel.resetAllPromptsToDefaults()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Auto Fallback on Error (Ollama / Temporary Apple for 1–2 sentences)", isOn: $viewModel.autoFallback)
                    .font(.caption)
                    .foregroundColor(.primary)

                Text("Allows temporary Apple fallback for up to 2 sentences during transient API errors. If the API remains down, translation automatically stops.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Toggle("Auto-discover new characters per chapter (JIT)", isOn: $viewModel.autoDiscoverChapterCharacters)
                .font(.caption)
                .foregroundColor(.primary)

            Divider()

            // Text-to-Speech (TTS) Settings
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.accentColor)
                    Text("Text-to-Speech (TTS)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }

                HStack {
                    Text("Engine:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Picker("", selection: $viewModel.ttsEngine) {
                        ForEach(TTSEngine.allCases) { eng in
                            Text(eng.rawValue).tag(eng)
                        }
                    }
                    .labelsHidden()
                }

                HStack {
                    Text("Voice:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Picker("", selection: $viewModel.selectedTTSVoiceId) {
                        ForEach(viewModel.availableTTSVoices) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                    .labelsHidden()

                    Button(action: {
                        viewModel.testListeningCurrentVoice()
                    }) {
                        HStack(spacing: 3) {
                            if viewModel.isTestingTTSVoice {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "speaker.wave.2")
                            }
                            Text("Test Voice")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isTestingTTSVoice)
                    .help("Listen to a quick sample of this voice")
                }

                HStack {
                    Text("Speed:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Picker("", selection: $viewModel.ttsSpeed) {
                        Text("0.75x").tag(0.75)
                        Text("1.0x (Normal)").tag(1.0)
                        Text("1.25x").tag(1.25)
                        Text("1.5x").tag(1.5)
                    }
                    .labelsHidden()
                }
            }

            Divider()

            // Test Connection
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
            }

            if let result = viewModel.connectionTestResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.contains("Success") || result.contains("Found") ? .green : .orange)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
            }
        }
        .onDisappear {
            viewModel.saveOpenAIEnvConfig()
        }
    }

    private var ollamaSettingsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ollama Server URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("http://localhost:11434/v1", text: $viewModel.ollamaConfig.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
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

            HStack {
                Text("Concurrency (Parallel Chunks): \(viewModel.ollamaConfig.concurrency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("", value: $viewModel.ollamaConfig.concurrency, in: 1...8)
                    .labelsHidden()
            }
        }
    }

    private var openAISettingsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Model Profiles Quick Switcher & Manager
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Model Profile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Manage All Profiles...") {
                        viewModel.showSettingsPopover = false
                        viewModel.showModelManagerSheet = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }

                if !viewModel.modelProfiles.isEmpty {
                    Picker("", selection: Binding(
                        get: { viewModel.activeProfileId ?? viewModel.modelProfiles.first?.id ?? UUID() },
                        set: { newId in viewModel.selectModelProfile(id: newId) }
                    )) {
                        ForEach(viewModel.modelProfiles) { profile in
                            Text("\(profile.name) (\(profile.modelName))").tag(profile.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            // Fallback chain indicator if multiple models enabled
            if viewModel.activeFallbackConfigs.count > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fallback Sequence:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(viewModel.activeFallbackConfigs.map { $0.name }.joined(separator: " ➔ "))
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Base API Endpoint URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://api.openai.com/v1", text: $viewModel.openAIConfig.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("sk-...", text: $viewModel.openAIConfig.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
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
                    TextField("gpt-4o-mini", text: $viewModel.openAIConfig.modelName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Text("Concurrency (Parallel Requests): \(viewModel.openAIConfig.concurrency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("", value: $viewModel.openAIConfig.concurrency, in: 1...10)
                    .labelsHidden()
            }

            HStack(spacing: 8) {
                Button(action: {
                    viewModel.saveOpenAIEnvConfig()
                }) {
                    Label("Save to .env", systemImage: "arrow.down.doc")
                }
                .help("Saves settings to .env file and UserDefaults to use next time")

                if let status = viewModel.envSaveStatus {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - EPUB Mode View
    private var epubModeView: some View {
        HSplitView {
            // Chapter Sidebar
            VStack(alignment: .leading, spacing: 8) {
                if let book = viewModel.currentEPUB {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(book.chapters.count) chapters • \(book.totalWords) words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    Divider()

                    List(selection: $viewModel.selectedChapterIndex) {
                        ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                            HStack {
                                Image(systemName: chapter.isTranslated ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(chapter.isTranslated ? .green : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text("\(chapter.wordCount) words")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .tag(index)
                            .padding(.vertical, 2)
                            .contextMenu {
                                Button {
                                    viewModel.translateChapter(index: index, force: false)
                                } label: {
                                    Label("Translate Chapter \(index + 1)", systemImage: "play.fill")
                                }

                                Button(role: .destructive) {
                                    viewModel.translateChapter(index: index, force: true)
                                } label: {
                                    Label("Re-translate Chapter \(index + 1)", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)

                    Divider()

                    Button(action: { showSavePanel() }) {
                        HStack {
                            Image(systemName: "arrow.down.doc.fill")
                            Text("Export Translated EPUB...")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                    Button(action: { viewModel.showTTSExportSheet = true }) {
                        HStack {
                            Image(systemName: "waveform")
                            Text("Export Audiobook (.wav)...")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No EPUB eBook Loaded")
                            .font(.headline)
                        Text("Open an .epub file or load the sample book to start translating.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        Button("Load Sample EPUB") {
                            viewModel.loadSampleEPUB()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .frame(minWidth: 260, maxWidth: 320)

            // Chapter Content Split View
            if let book = viewModel.currentEPUB, !book.chapters.isEmpty {
                HSplitView {
                    // Original Chapter Text
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Original (\(selectedChapterTitle))", systemImage: "doc.text")
                                .font(.headline)
                            Spacer()

                            // Listen to Original Text directly (Great for native Vietnamese books)
                            Button(action: {
                                viewModel.playCurrentChapterAudio(source: .original)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "speaker.wave.2")
                                    Text("Listen")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(viewModel.isTranslating)
                            .help("Listen to original chapter text without translating (e.g. for native Vietnamese books)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)

                        ScrollView {
                            Text(viewModel.currentChapterOriginalText)
                                .font(.system(.body, design: .serif))
                                .lineSpacing(4)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    }
                    .frame(minWidth: 320)

                    // Translated Chapter Text
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Label("Translated (\(selectedChapterTitle))", systemImage: "character.book.closed")
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()

                            // Full Text vs Paragraph View Mode Switcher
                            Picker("", selection: $viewModel.epubReaderMode) {
                                ForEach(TranslationViewModel.EPUBReaderMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()

                            // Translate / Re-translate Chapter Button
                            if viewModel.selectedChapterIndex < book.chapters.count {
                                let chapter = book.chapters[viewModel.selectedChapterIndex]
                                Button {
                                    viewModel.translateChapter(index: viewModel.selectedChapterIndex, force: chapter.isTranslated)
                                } label: {
                                    Label(
                                        chapter.isTranslated ? "Re-translate" : "Translate",
                                        systemImage: chapter.isTranslated ? "arrow.clockwise" : "play.fill"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isTranslating)
                                .help(chapter.isTranslated ? "Re-translate this entire chapter" : "Translate this chapter")

                                // TTS Audio Button
                                Button(action: {
                                    viewModel.playCurrentChapterAudio(source: .translated)
                                }) {
                                    HStack(spacing: 4) {
                                        if viewModel.isSynthesizingAudio {
                                            ProgressView()
                                                .controlSize(.mini)
                                        } else {
                                            Image(systemName: viewModel.audioPlayer.isPlaying ? "pause.fill" : "speaker.wave.2.fill")
                                        }
                                        Text(viewModel.audioPlayer.isPlaying ? "Pause" : (viewModel.hasCachedAudioForChapter(chapterIndex: viewModel.selectedChapterIndex, source: .translated) ? "Listen" : "Listen (TTS)"))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isTranslating)
                                .help("Listen to chapter with \(viewModel.ttsEngine.rawValue) TTS")
                            }

                            Button(action: { viewModel.copyToClipboard() }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)

                        // Inline Audio Player Bar
                        if viewModel.audioPlayer.isPlaying || viewModel.audioPlayer.isPaused || viewModel.isSynthesizingAudio || viewModel.audioPlayer.currentAudioURL != nil {
                            TTSPlayerBarView(viewModel: viewModel)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 6)
                        }

                        if viewModel.epubReaderMode == .full {
                            ScrollView {
                                Text(viewModel.currentChapterTranslatedText)
                                    .font(.system(.body, design: .serif))
                                    .lineSpacing(4)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    if viewModel.selectedChapterIndex < book.chapters.count {
                                        let chapter = book.chapters[viewModel.selectedChapterIndex]
                                        ForEach(chapter.nodes) { node in
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text("Paragraph #\(node.id)")
                                                        .font(.caption2)
                                                        .fontWeight(.bold)
                                                        .foregroundColor(.secondary)
                                                    Spacer()
                                                    Button {
                                                        viewModel.retranslateEPUBNode(chapterIndex: viewModel.selectedChapterIndex, nodeId: node.id)
                                                    } label: {
                                                        HStack(spacing: 3) {
                                                            Image(systemName: "arrow.clockwise")
                                                            Text("Re-translate")
                                                        }
                                                        .font(.caption2)
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .disabled(viewModel.isTranslating)
                                                }

                                                if !node.translatedText.isEmpty {
                                                    Text(node.translatedText)
                                                        .font(.system(.body, design: .serif))
                                                        .foregroundColor(.primary)

                                                    Text(node.originalText)
                                                        .font(.system(.caption, design: .serif))
                                                        .foregroundColor(.secondary)
                                                        .padding(.top, 2)
                                                } else {
                                                    Text(node.originalText)
                                                        .font(.system(.body, design: .serif))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding(10)
                                            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                            )
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                        }
                    }
                    .frame(minWidth: 320)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No eBook Loaded")
                        .font(.title2.bold())
                    Text("Open an EPUB file to view chapters, configure Character Bible, and translate.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    HStack(spacing: 12) {
                        Button("Open EPUB File (⌘O)") {
                            showOpenPanel()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Load Sample eBook") {
                            viewModel.loadSampleEPUB()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selectedChapterTitle: String {
        guard let book = viewModel.currentEPUB, viewModel.selectedChapterIndex < book.chapters.count else { return "" }
        return book.chapters[viewModel.selectedChapterIndex].title
    }

    // MARK: - Progress Banner
    private var progressBannerView: some View {
        HStack(spacing: 12) {
            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 220)

            // Chapter & Paragraph Counter
            Text("Chapter \(viewModel.completedEPUBChapters)/\(viewModel.totalEPUBChapters) (\(Int(viewModel.progressFraction * 100))%) • Paragraphs \(viewModel.currentEPUBNodeProgress.completed)/\(viewModel.currentEPUBNodeProgress.total)")
                .font(.caption)
                .fontWeight(.medium)

            // ETA Badge
            if let eta = viewModel.estimatedTimeRemaining {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(eta)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            }

            // Speed Badge
            if let speed = viewModel.translationSpeed {
                Text(speed)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Checkpoint Badge when paused
            if viewModel.canResume {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(.green)
                    Text("Checkpoint Saved")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .cornerRadius(4)
            }

            // Fallback Notice Badge
            if let fallback = viewModel.fallbackNotice {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(.purple)
                    Text(fallback)
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(4)
            }

            Spacer()
        }
    }

    // MARK: - Status Bar View
    private var statusBarView: some View {
        HStack {
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            if viewModel.isTranslating {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helper Methods
    private func countWords(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "epub") ?? .data
        ]

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadFromFile(url: url)
        }
    }

    private func showSavePanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        let baseName = viewModel.currentEPUB?.title.replacingOccurrences(of: " ", with: "_") ?? "translated_book"
        panel.nameFieldStringValue = "\(baseName)_\(viewModel.targetLanguage.id).epub"
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveToFile(url: url)
        }
    }
}

// MARK: - Saved Sessions Management Sheet
struct SavedSessionsSheet: View {
    @ObservedObject var viewModel: TranslationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("Saved Translation Sessions")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    viewModel.showSavedSessionsSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            Divider()

            if viewModel.savedSessions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No saved translation sessions")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("When translating an eBook, use 'Save' or pause to resume anytime.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(viewModel.savedSessions) { session in
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "book.closed.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(session.title)
                                            .font(.system(.body, weight: .semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(session.progressPercentString)
                                            .font(.system(.caption, design: .monospaced, weight: .bold))
                                            .foregroundColor(.accentColor)
                                    }

                                    ProgressView(value: session.progressFraction)
                                        .tint(.accentColor)

                                    HStack(spacing: 6) {
                                        Text("\(session.completedItems) of \(session.totalItems) paragraphs")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(session.sourceLanguageId.uppercased()) ➔ \(session.targetLanguageId.uppercased())")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(session.formattedDate)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Button("Resume") {
                                        viewModel.resumeSession(withId: session.id)
                                        viewModel.showSavedSessionsSheet = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                    Button(role: .destructive, action: {
                                        viewModel.deleteSession(withId: session.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete this saved session")
                                }
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 380)
    }
}
