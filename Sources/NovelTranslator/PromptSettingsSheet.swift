import SwiftUI
import AppKit

// MARK: - Prompt Preset Model
public struct PromptPreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let description: String
    public let template: String

    public init(id: String, name: String, category: String, description: String, template: String) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.template = template
    }
}

public struct PromptPresets: Sendable {
    // MARK: - Translation Presets
    public static let translationPresets: [PromptPreset] = [
        PromptPreset(
            id: "trans-default",
            name: "Direct & Accurate (Default)",
            category: "General",
            description: "Dịch trực tiếp, trung thành với nguyên tác, giữ nguyên định dạng, không thêm bớt.",
            template: LLMTranslationService.defaultTranslationPromptTemplate
        ),
        PromptPreset(
            id: "trans-literary",
            name: "Literary Fiction (Văn h��c mượt mà)",
            category: "Fiction",
            description: "Hành văn trau chuốt, tự nhiên, giàu cảm xúc, chuyển ngữ mượt mà cho tiểu thuyết và truyện ngắn.",
            template: """
            You are an expert literary book translator specializing in {sourceLang} to {targetLang} literature.
            Translate the provided text into natural, fluent, and expressive {targetLang}.
            Preserve the author's tone, pacing, imagery, emotions, and subtle nuances.
            Keep dialogue lively and authentic; translate descriptions smoothly without awkward literal phrasing.
            Preserve all original formatting, paragraphs, indentation, and markdown/HTML tags.
            Return ONLY the translated text.
            CRITICAL: Do NOT output any thinking process, reasoning, internal monologue, analysis, or draft steps. Do NOT wrap output in <think> tags. Output ONLY the raw final translated text directly.
            """
        ),
        PromptPreset(
            id: "trans-lightnovel",
            name: "Light Novel & Modern (Hiện đại, tự nhiên)",
            category: "Fiction",
            description: "Nhịp điệu nhanh, đối thoại gần gũi, phù hợp tiểu thuyết thanh thiếu niên, Light Novel, Web Novel.",
            template: """
            You are a skilled translator specializing in modern light novels and contemporary fiction from {sourceLang} to {targetLang}.
            Translate with an engaging, rhythmic, and natural style that appeals to modern novel readers.
            Make spoken dialogues snappy, natural, and expressive with appropriate colloquial cadence in {targetLang}.
            Avoid stiff Sino-Vietnamese jargon where simple, vivid words sound more natural.
            Preserve all original formatting, paragraphs, indentation, and markdown/HTML tags.
            Return ONLY the translated text.
            CRITICAL: Do NOT output any thinking process, reasoning, internal monologue, or draft steps. Do NOT wrap output in <think> tags. Output ONLY the raw translated text directly.
            """
        ),
        PromptPreset(
            id: "trans-nonfiction",
            name: "Non-Fiction & Technical (Học thuật, chính xác)",
            category: "Academic",
            description: "Khách quan, chính xác, sử dụng thuật ngữ chuẩn xác cho sách khoa học, kỹ thuật, kinh tế.",
            template: """
            You are a professional non-fiction and academic translator translating from {sourceLang} to {targetLang}.
            Maintain an objective, formal, precise, and intellectually rigorous tone.
            Use standard recognized terminology in {targetLang} for concepts, economics, philosophy, science, or technology.
            Keep sentence logic crisp, clear, and academically sound.
            Preserve all original formatting, citations, code blocks, and markdown/HTML tags.
            Return ONLY the translated text.
            CRITICAL: Do NOT output any thinking process, reasoning, internal monologue, or analysis. Do NOT wrap output in <think> tags. Output ONLY the raw translated text directly.
            """
        ),
        PromptPreset(
            id: "trans-wuxia",
            name: "Wuxia & Classical Fantasy (Kiếm hiệp, Cổ trang)",
            category: "Fiction",
            description: "Hành văn cổ điển, từ Hán Việt phù hợp cho kiếm hiệp, tiên hiệp, huyền huyễn cổ trang.",
            template: """
            You are an expert literary translator specializing in Eastern fantasy, historical fiction, and wuxia literature from {sourceLang} to {targetLang}.
            Translate using evocative, atmospheric prose with appropriate classical and martial-arts undertones in {targetLang}.
            Preserve names of martial techniques, sects, weapons, and honorific forms of address in their conventional Sino-Vietnamese forms.
            Preserve all original formatting, paragraphs, and markdown/HTML tags.
            Return ONLY the translated text.
            CRITICAL: Do NOT output any thinking process, reasoning, internal monologue, or draft steps. Do NOT wrap output in <think> tags. Output ONLY the raw translated text directly.
            """
        )
    ]

    // MARK: - Character Analysis Presets
    public static let characterAnalysisPresets: [PromptPreset] = [
        PromptPreset(
            id: "char-default",
            name: "Comprehensive Book-Wide (Mặc định)",
            category: "General",
            description: "Phân tích đầy đủ nhân vật, tuổi tác, vai trò, xưng hô đối thoại và ngôi thứ 3 dựa trên toàn bộ sách.",
            template: LLMTranslationService.defaultCharacterAnalysisPromptTemplate
        ),
        PromptPreset(
            id: "char-japanese",
            name: "Japanese Fiction (Truyện Nhật Bản)",
            category: "Fiction",
            description: "Tập trung phân tích kính ngữ Nhật (-san, -kun, -chan, tiền bối) và phân biệt rõ họ/tên Nhật.",
            template: """
            You are an expert literary translator and linguist specializing in Japanese literature and East Asian fiction translated into Vietnamese.
            Analyze the confirmed character entities identified across the book, along with the background sample text.

            {entitiesSection}

            EXTRACTION RULES:
            1. Distinguish Japanese family names (surnames) from given names, keeping canonical full names or commonly used given names.
            2. Note Japanese honorific dynamics (-san, -kun, -chan, senpai, sensei) and map them accurately to Vietnamese reciprocal pronouns (anh/em, chị/em, bạn/mình, tiền bối/hậu bối, thầy/em).
            3. Exclude any place names, schools, shrines, train stations, or organizations.
            4. For all valid characters:
               - "name": Canonical character name
               - "aliases": Nicknames, surnames, or titles
               - "gender": "Male" | "Female" | "Neutral" | "Unknown"
               - "relativeAge": Approximate age description (e.g. "teenager", "20s", "elderly")
               - "roleOrStatus": School grade, profession, or status
               - "thirdPersonPronoun": Narrative 3rd pronoun (cô ta, anh ta, cậu ta, cô bé, thằng bé, ông ta...)
            5. Map reciprocal dialogue pronoun pairs (xưng hô) accurately based on seniority and intimacy.

            Return ONLY a valid JSON object matching this schema:
            {
              "narrativePOV": "First Person" | "Third Person",
              "narratorName": "string or null",
              "characters": [
                { "name": "Name", "aliases": ["alias1"], "gender": "Male"|"Female"|"Neutral"|"Unknown", "relativeAge": "string", "roleOrStatus": "string", "thirdPersonPronoun": "string" }
              ],
              "relationships": [
                { "source": "CharA", "target": "CharB", "selfPronoun": "string", "addressingPronoun": "string", "contextNote": "string" }
              ],
              "generalNotes": "string"
            }
            {contextAppendix}
            CRITICAL: Do NOT wrap output in any thinking tags. Return ONLY the raw JSON object.
            """
        ),
        PromptPreset(
            id: "char-fast",
            name: "Compact & Fast (Rút gọn cho model nhẹ)",
            category: "Performance",
            description: "Prompt súc tích, tối ưu tốc độ và giảm token cho Ollama hoặc các model API nhỏ/nhẹ.",
            template: """
            You are an English-to-Vietnamese translation assistant.
            Extract characters and dialogue pronouns from the confirmed candidates and sample text:

            {entitiesSection}

            Rules:
            1. Ignore cities, buildings, companies, or inanimate objects.
            2. For each real person, determine name, gender, age, role, and natural Vietnamese narrative pronoun (anh ta, cô ta, ông ta, bà ta, thằng bé, cô bé).
            3. Identify reciprocal dialogue pronoun pairs (xưng hô) between interacting characters.

            Return ONLY a valid JSON object:
            {
              "narrativePOV": "First Person" | "Third Person",
              "narratorName": "string or null",
              "characters": [
                { "name": "Name", "aliases": [], "gender": "Male"|"Female"|"Neutral"|"Unknown", "relativeAge": "string", "roleOrStatus": "string", "thirdPersonPronoun": "string" }
              ],
              "relationships": [
                { "source": "CharA", "target": "CharB", "selfPronoun": "string", "addressingPronoun": "string", "contextNote": "string" }
              ],
              "generalNotes": "string"
            }
            {contextAppendix}
            CRITICAL: Return ONLY valid JSON without thinking tags or markdown fences.
            """
        )
    ]
}

// MARK: - Prompt Settings Editor View Model
@MainActor
public class PromptSettingsEditorViewModel: ObservableObject {
    @Published public var selectedTab: TranslationViewModel.PromptTab = .translation
    @Published public var showResetAllAlert: Bool = false
    @Published public var showSavedToast: Bool = false
    @Published public var isPreviewExpanded: Bool = true
    @Published public var previewWithKnowledgeBase: Bool = true

    public init(initialTab: TranslationViewModel.PromptTab = .translation) {
        self.selectedTab = initialTab
    }

    public func showToast() {
        withAnimation {
            showSavedToast = true
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    self?.showSavedToast = false
                }
            }
        }
    }
}

// MARK: - Prompt Settings Sheet
public struct PromptSettingsSheet: View {
    @ObservedObject var viewModel: TranslationViewModel
    @StateObject private var editor: PromptSettingsEditorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: TranslationViewModel) {
        self.viewModel = viewModel
        _editor = StateObject(wrappedValue: PromptSettingsEditorViewModel(initialTab: viewModel.selectedPromptTab))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Segmented Tab Picker
            Picker("", selection: $editor.selectedTab) {
                Label("Translation Prompt", systemImage: "character.book.closed").tag(TranslationViewModel.PromptTab.translation)
                Label("Character Analysis", systemImage: "person.2.badge.gearshape").tag(TranslationViewModel.PromptTab.characterAnalysis)
                Label("Knowledge Base Rules", systemImage: "person.text.rectangle").tag(TranslationViewModel.PromptTab.knowledgeBase)
                Label("Presets & Tips", systemImage: "wand.and.stars").tag(TranslationViewModel.PromptTab.presetsAndTips)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Content
            Group {
                switch editor.selectedTab {
                case .translation:
                    translationPromptView
                case .characterAnalysis:
                    characterAnalysisPromptView
                case .knowledgeBase:
                    knowledgeBaseDirectivesView
                case .presetsAndTips:
                    presetsAndTipsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer
            footerView
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 620)
        .alert("Reset All Prompts to Defaults?", isPresented: $editor.showResetAllAlert) {
            Button("Reset Everything", role: .destructive) {
                viewModel.resetAllPromptsToDefaults()
                editor.showToast()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore both the Translation Prompt and Character Analysis Prompt back to their original default factory templates.")
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Model Prompts Configuration")
                        .font(.headline)
                    if viewModel.hasCustomPrompts {
                        Text("Custom Active")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    } else {
                        Text("Default Factory")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                    }
                }
                Text("Customize system instructions sent to AI models for document translation and character extraction.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Done") {
                viewModel.savePrompts()
                viewModel.showPromptSettingsSheet = false
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Tab 1: Translation Prompt View
    private var translationPromptView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Description & Variables Banner
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("System prompt used for translating paragraphs and chapters.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()

                    // Presets Quick Menu
                    Menu {
                        ForEach(PromptPresets.translationPresets) { preset in
                            Button(action: {
                                viewModel.customTranslationPrompt = preset.template
                                editor.showToast()
                            }) {
                                Text(preset.name)
                            }
                        }
                    } label: {
                        Label("Apply Preset", systemImage: "sparkles")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Button("Reset to Default") {
                        viewModel.resetTranslationPromptToDefault()
                        editor.showToast()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Placeholders Helper Row
                HStack(spacing: 8) {
                    Text("Placeholders:")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)

                    Button(action: {
                        insertIntoTranslationPrompt("{sourceLang}")
                    }) {
                        Text("{sourceLang}")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Click to insert active source language (e.g. English)")

                    Button(action: {
                        insertIntoTranslationPrompt("{targetLang}")
                    }) {
                        Text("{targetLang}")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Click to insert active target language (e.g. Vietnamese)")

                    Button(action: {
                        insertIntoTranslationPrompt("{knowledgeBase}")
                    }) {
                        Text("{knowledgeBase}")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Click to specify position of Character Bible Knowledge Base guidelines (if omitted, guidelines append automatically)")

                    Spacer()

                    Text("Active: \(viewModel.sourceLanguage.name) → \(viewModel.targetLanguage.name)")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Prompt TextEditor
            ZStack(alignment: .topTrailing) {
                TextEditor(text: $viewModel.customTranslationPrompt)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal)

            // Live Preview Disclosure
            DisclosureGroup(
                isExpanded: $editor.isPreviewExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle("Include Character Bible Knowledge Base in Preview", isOn: $editor.previewWithKnowledgeBase)
                                .font(.caption2)
                            Spacer()
                            if editor.previewWithKnowledgeBase {
                                Text("Showing full prompt sent to LLM")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            } else {
                                Text("Showing base prompt only")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        ScrollView {
                            Text(viewModel.currentFullTranslationSystemInstruction(
                                from: viewModel.sourceLanguage.name,
                                to: viewModel.targetLanguage.name,
                                includeKnowledgeBase: editor.previewWithKnowledgeBase
                            ))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .frame(height: 150)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                },
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.caption2)
                        Text("Live Rendered Preview (\(viewModel.sourceLanguage.name) → \(viewModel.targetLanguage.name))")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(.secondary)
                }
            )
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Tab 2: Character Analysis Prompt View
    private var characterAnalysisPromptView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Description & Variables Banner
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("System prompt used for scanning all chapters and extracting characters & pronouns.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()

                    // Presets Quick Menu
                    Menu {
                        ForEach(PromptPresets.characterAnalysisPresets) { preset in
                            Button(action: {
                                viewModel.customCharacterAnalysisPrompt = preset.template
                                editor.showToast()
                            }) {
                                Text(preset.name)
                            }
                        }
                    } label: {
                        Label("Apply Preset", systemImage: "sparkles")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Button("Reset to Default") {
                        viewModel.resetCharacterAnalysisPromptToDefault()
                        editor.showToast()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Placeholders Helper Row
                HStack(spacing: 8) {
                    Text("Placeholders:")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)

                    Button(action: {
                        insertIntoCharacterPrompt("{entitiesSection}")
                    }) {
                        Text("{entitiesSection}")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Inserts confirmed candidates scanned from all chapters")

                    Button(action: {
                        insertIntoCharacterPrompt("{contextAppendix}")
                    }) {
                        Text("{contextAppendix}")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Inserts previously established global character bible anchors")

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("Model must output valid JSON schema")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Prompt TextEditor
            ZStack(alignment: .topTrailing) {
                TextEditor(text: $viewModel.customCharacterAnalysisPrompt)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal)

            // Live Preview Disclosure
            DisclosureGroup(
                isExpanded: $editor.isPreviewExpanded,
                content: {
                    ScrollView {
                        Text(viewModel.currentCharacterAnalysisSystemInstruction(
                            entitiesSection: "CONFIRMED ENTITY ANCHORS:\n- Sherlock Holmes (142 occurrences)\n- Dr. John Watson (98 occurrences)",
                            contextAppendix: "ALREADY ESTABLISHED GLOBAL KNOWLEDGE BASE:\n- Sherlock Holmes [Male, Adult] (3rd pronoun: anh ta)"
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(height: 100)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                },
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.caption2)
                        Text("Live Rendered Preview (Sample Book Entities & Context)")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(.secondary)
                }
            )
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Tab 3: Knowledge Base Directives View
    private var knowledgeBaseDirectivesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Info Banner
                VStack(alignment: .leading, spacing: 6) {
                    Label("Character Bible Knowledge Base Directives", systemImage: "person.text.rectangle")
                        .font(.headline)

                    Text("Khi dịch sách sang tiếng Việt, toàn bộ thông tin từ Character Bible được tự động chuyển đổi thành khối chỉ thị dịch thuật (Knowledge Base Directives) dưới đây và kết hợp với System Prompt.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Text("Active Source:")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text(viewModel.characterBible != nil || viewModel.currentEPUB?.characterBible != nil ? "📖 Active Book Knowledge Base" : "✨ Sample Detective Novel")
                            .font(.caption2)
                            .foregroundColor(.accentColor)

                        Spacer()

                        Button(action: {
                            viewModel.showCharacterBibleSheet = true
                        }) {
                            Label("Open Character Bible", systemImage: "person.2.badge.gearshape")
                                .font(.caption2)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                // Knowledge Base Live Render Box
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Generated Knowledge Base Prompt Block:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Copy Block") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            let activeBible = viewModel.characterBible ?? viewModel.currentEPUB?.characterBible ?? viewModel.sampleBibleForPreview
                            let directives = PronounPromptBuilder.buildKnowledgeBaseDirectives(bible: activeBible)
                            pasteboard.setString(directives, forType: .string)
                        }
                        .controlSize(.mini)
                    }

                    ScrollView {
                        let activeBible = viewModel.characterBible ?? viewModel.currentEPUB?.characterBible ?? viewModel.sampleBibleForPreview
                        Text(PronounPromptBuilder.buildKnowledgeBaseDirectives(bible: activeBible))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 220)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }

                Divider()

                // Explanation of the 4 Pillars
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cấu trúc của Knowledge Base trong Prompt:")
                        .font(.subheadline.bold())

                    VStack(alignment: .leading, spacing: 6) {
                        tipRow(
                            title: "1. Thể loại sách & Ngôi kể (Genre & Narrative Perspective):",
                            detail: "Xác định phong cách dịch (Hư cấu / Phi hư cấu) và ngôi kể chính (Ngôi thứ nhất / Ngôi thứ ba) để định hình giọng văn trần thuật."
                        )
                        tipRow(
                            title: "2. Cặp đại từ xưng hô đối thoại (Pronoun Pairs):",
                            detail: "Định nghĩa chính xác cách từng nhân vật xưng (selfPronoun) và gọi nhân vật đối diện (addressingPronoun) trong hội thoại theo quan hệ tuổi tác, tôn ti, và mức độ thân mật."
                        )
                        tipRow(
                            title: "3. Quy tắc ngôi thứ 3 (Narration vs Dialogue):",
                            detail: "Phân biệt rõ: Lời kể tác giả (dùng anh ta, cô ta, ông ta, bà ta, thằng bé, cô bé - tuyệt đối tránh lạm dụng 'anh ấy/cô ấy') so với lời nhân vật nhắc tới người thứ ba trong đối thoại."
                        )
                        tipRow(
                            title: "4. Chỉ thị bắt buộc (Directives):",
                            detail: "Yêu cầu mô hình giữ nguyên tính nhất quán của các đại từ xưng hô xuyên suốt toàn bộ các chương sách, không tự ý suy diễn sang 'tôi / bạn' chung chung."
                        )
                    }
                    .padding(10)
                    .background(Color.blue.opacity(0.06))
                    .cornerRadius(6)
                }
            }
            .padding()
        }
    }

    // MARK: - Tab 4: Presets & Tips View
    private var presetsAndTipsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Translation Presets Card
                VStack(alignment: .leading, spacing: 10) {
                    Label("Translation Style Presets", systemImage: "text.book.closed")
                        .font(.headline)

                    ForEach(PromptPresets.translationPresets) { preset in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(preset.name)
                                        .font(.subheadline.bold())
                                    Text(preset.category)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(4)
                                }
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Apply") {
                                viewModel.customTranslationPrompt = preset.template
                                editor.selectedTab = .translation
                                editor.showToast()
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }

                Divider()

                // Character Analysis Presets Card
                VStack(alignment: .leading, spacing: 10) {
                    Label("Character Analysis Presets", systemImage: "person.2")
                        .font(.headline)

                    ForEach(PromptPresets.characterAnalysisPresets) { preset in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(preset.name)
                                        .font(.subheadline.bold())
                                    Text(preset.category)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.1))
                                        .foregroundColor(.purple)
                                        .cornerRadius(4)
                                }
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Apply") {
                                viewModel.customCharacterAnalysisPrompt = preset.template
                                editor.selectedTab = .characterAnalysis
                                editor.showToast()
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }

                Divider()

                // Best Practices & Guidance Callout
                VStack(alignment: .leading, spacing: 8) {
                    Label("Prompt Engineering Tips for Translating eBooks", systemImage: "lightbulb.fill")
                        .font(.headline)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 6) {
                        tipRow(
                            title: "Prevent Reasoning / <think> Leakage:",
                            detail: "When using DeepSeek R1, Qwen 2.5 Coder, or reasoning models, always keep the directive: 'Do NOT wrap output in <think> tags. Output ONLY the raw final translated text directly.'"
                        )
                        tipRow(
                            title: "Reciprocal Dialogue Pronouns (Xưng hô):",
                            detail: "For Vietnamese translation, reciprocal pronouns (anh/em, cô/cháu, bố/con) are automatically injected from your Character Bible. You do not need to hardcode specific character names into this base translation prompt."
                        )
                        tipRow(
                            title: "Entity & Context Safety:",
                            detail: "In Character Analysis, the placeholders {entitiesSection} and {contextAppendix} supply scanned names across all chapters. If you omit them, the app will automatically inject them safely so entity scanning never breaks."
                        )
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(6)
                }
            }
            .padding()
        }
    }

    private func tipRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button(role: .destructive, action: {
                editor.showResetAllAlert = true
            }) {
                Label("Reset All to Defaults", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)

            Spacer()

            if editor.showSavedToast || viewModel.promptSaveFeedback != nil {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Prompts saved to disk")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .transition(.opacity)
            }

            Button(action: {
                viewModel.savePrompts()
                editor.showToast()
            }) {
                Label("Save Prompts", systemImage: "arrow.down.doc")
            }
            .controlSize(.small)

            Button("Done") {
                viewModel.savePrompts()
                viewModel.showPromptSettingsSheet = false
                dismiss()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Helpers
    private func insertIntoTranslationPrompt(_ text: String) {
        if !viewModel.customTranslationPrompt.contains(text) {
            viewModel.customTranslationPrompt += " " + text
        }
    }

    private func insertIntoCharacterPrompt(_ text: String) {
        if !viewModel.customCharacterAnalysisPrompt.contains(text) {
            viewModel.customCharacterAnalysisPrompt += "\n" + text
        }
    }
}
