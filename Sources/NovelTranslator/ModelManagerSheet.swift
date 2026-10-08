import SwiftUI
import AppKit

// MARK: - Model Manager Editor View Model
@MainActor
public class ModelManagerEditorViewModel: ObservableObject {
    @Published public var selectedProfileId: UUID? = nil
    @Published public var editingProfile: LLMConfig = .defaultOpenAI
    @Published public var isTestingCurrentConnection: Bool = false
    @Published public var connectionTestMessage: String? = nil
    @Published public var isFetchingModels: Bool = false
    @Published public var fetchedModels: [String] = []
    @Published public var showApiKey: Bool = false

    public init() {}
}

public struct ModelManagerSheet: View {
    @ObservedObject public var viewModel: TranslationViewModel
    @StateObject private var editor: ModelManagerEditorViewModel = ModelManagerEditorViewModel()
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: TranslationViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Main Two-Column Layout
            HSplitView {
                // Left Column: Profile List & Fallback Order
                profilesSidebar
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)

                // Right Column: Profile Detail Editor
                profileDetailView
                    .frame(minWidth: 420, idealWidth: 480)
            }

            Divider()

            // Footer Bar with Visual Fallback Chain
            fallbackChainFooter
        }
        .frame(minWidth: 760, idealWidth: 840, minHeight: 520, idealHeight: 580)
        .onAppear {
            if let activeId = viewModel.activeProfileId, viewModel.modelProfiles.contains(where: { $0.id == activeId }) {
                editor.selectedProfileId = activeId
                if let active = viewModel.modelProfiles.first(where: { $0.id == activeId }) {
                    editor.editingProfile = active
                }
            } else if let first = viewModel.modelProfiles.first {
                editor.selectedProfileId = first.id
                editor.editingProfile = first
            }
        }
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(alignment: .center) {
            Image(systemName: "cpu.fill")
                .foregroundColor(.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Model Profiles & Fallback Chain")
                    .font(.headline)
                Text("Configure multiple API models and automatic failover sequence when rate limits or server errors occur.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Done") {
                commitCurrentEditing()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sidebar: Profile List
    private var profilesSidebar: some View {
        VStack(spacing: 0) {
            // Toolbar above list
            HStack {
                Text("PROFILES (\(viewModel.modelProfiles.count))")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Menu {
                    Button("Custom API Profile") {
                        let newProf = LLMConfig(
                            name: "New Custom Model",
                            baseURL: "https://api.openai.com/v1",
                            apiKey: "",
                            modelName: "gpt-4o-mini",
                            temperature: 0.1,
                            concurrency: 4,
                            isEnabled: true
                        )
                        viewModel.addModelProfile(newProf)
                        selectProfile(newProf)
                    }

                    Divider()

                    Section("Add Provider Preset") {
                        ForEach(LLMConfig.allPresets) { preset in
                            Button(preset.name) {
                                viewModel.addPresetProfile(preset)
                                if let newlyAdded = viewModel.modelProfiles.last {
                                    selectProfile(newlyAdded)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Scrollable Profile List
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(viewModel.modelProfiles.enumerated()), id: \.element.id) { index, profile in
                        profileRow(profile: profile, index: index)
                    }
                }
                .padding(8)
            }

            Divider()

            // List controls
            HStack(spacing: 6) {
                Button(action: {
                    if let id = editor.selectedProfileId {
                        commitCurrentEditing()
                        viewModel.moveProfileUp(id: id)
                    }
                }) {
                    Image(systemName: "arrow.up")
                }
                .help("Move profile up in fallback priority")
                .disabled(editor.selectedProfileId == nil || viewModel.modelProfiles.first?.id == editor.selectedProfileId)

                Button(action: {
                    if let id = editor.selectedProfileId {
                        commitCurrentEditing()
                        viewModel.moveProfileDown(id: id)
                    }
                }) {
                    Image(systemName: "arrow.down")
                }
                .help("Move profile down in fallback priority")
                .disabled(editor.selectedProfileId == nil || viewModel.modelProfiles.last?.id == editor.selectedProfileId)

                Button(action: {
                    if let id = editor.selectedProfileId {
                        commitCurrentEditing()
                        viewModel.duplicateModelProfile(id: id)
                        if let dupe = viewModel.modelProfiles.first(where: { $0.id != id && $0.name.contains("(Copy)") }) {
                            selectProfile(dupe)
                        }
                    }
                }) {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicate selected profile")
                .disabled(editor.selectedProfileId == nil)

                Spacer()

                Button(role: .destructive, action: {
                    if let id = editor.selectedProfileId {
                        viewModel.deleteModelProfile(id: id)
                        if let first = viewModel.modelProfiles.first {
                            selectProfile(first)
                        }
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(viewModel.modelProfiles.count > 1 ? .red : .secondary)
                }
                .help("Delete profile")
                .disabled(viewModel.modelProfiles.count <= 1 || editor.selectedProfileId == nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func profileRow(profile: LLMConfig, index: Int) -> some View {
        let isSelected = editor.selectedProfileId == profile.id
        let isPrimary = viewModel.activeProfileId == profile.id
        let host = URL(string: profile.baseURL)?.host ?? profile.baseURL

        // Determine fallback priority among enabled items
        let enabledProfiles = viewModel.modelProfiles.filter { $0.isEnabled && $0.id != viewModel.activeProfileId }
        let fallbackIndex = enabledProfiles.firstIndex(where: { $0.id == profile.id })

        return Button(action: {
            commitCurrentEditing()
            selectProfile(profile)
        }) {
            HStack(alignment: .top, spacing: 8) {
                // Status Indicator
                VStack {
                    if isPrimary {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    } else if profile.isEnabled {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(.accentColor)
                            .font(.caption2)
                    } else {
                        Image(systemName: "circle.slash")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                }
                .frame(width: 14)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profile.name)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        if isPrimary {
                            Text("PRIMARY")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(3)
                        } else if let fbIdx = fallbackIndex {
                            Text("FALLBACK #\(fbIdx + 1)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(3)
                        } else {
                            Text("OFF")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.secondary)
                                .cornerRadius(3)
                        }
                    }

                    Text("\(profile.modelName) • \(host)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Editor
    private var profileDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Primary Action Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(editor.editingProfile.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(editor.editingProfile.modelName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if viewModel.activeProfileId != editor.editingProfile.id {
                        Button(action: {
                            commitCurrentEditing()
                            viewModel.selectModelProfile(id: editor.editingProfile.id)
                        }) {
                            Label("Set as Primary", systemImage: "star.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Active Primary Model")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }

                Divider()

                // Form Fields
                VStack(alignment: .leading, spacing: 10) {
                    // Profile Name
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Profile Label / Nickname")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. DeepSeek Chat or Primary API", text: $editor.editingProfile.name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: editor.editingProfile.name) {
                                autoSaveCurrent()
                            }
                    }

                    // Base URL
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Base Endpoint URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://api.openai.com/v1", text: $editor.editingProfile.baseURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: editor.editingProfile.baseURL) {
                                autoSaveCurrent()
                            }
                    }

                    // API Key
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(editor.showApiKey ? "Hide" : "Show") {
                                editor.showApiKey.toggle()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                        }

                        if editor.showApiKey {
                            TextField("sk-... (or leave empty for local Ollama/LM Studio)", text: $editor.editingProfile.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: editor.editingProfile.apiKey) {
                                    autoSaveCurrent()
                                }
                        } else {
                            SecureField("sk-... (or leave empty for local Ollama/LM Studio)", text: $editor.editingProfile.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: editor.editingProfile.apiKey) {
                                    autoSaveCurrent()
                                }
                        }
                    }

                    // Model Name & Fetch Models
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Model Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                Task { await fetchModelsForCurrent() }
                            }) {
                                if editor.isFetchingModels {
                                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                                } else {
                                    Text("Fetch Models")
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .disabled(editor.isFetchingModels || editor.editingProfile.baseURL.isEmpty)
                        }

                        if !editor.fetchedModels.isEmpty {
                            Picker("", selection: $editor.editingProfile.modelName) {
                                ForEach(editor.fetchedModels, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: editor.editingProfile.modelName) {
                                autoSaveCurrent()
                            }
                        } else {
                            TextField("e.g. gpt-4o-mini, deepseek-chat, translategemma:4b", text: $editor.editingProfile.modelName)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: editor.editingProfile.modelName) {
                                    autoSaveCurrent()
                                }
                        }
                    }

                    // Temperature & Concurrency
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Concurrency: \(editor.editingProfile.concurrency) requests")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper("", value: $editor.editingProfile.concurrency, in: 1...10)
                                .labelsHidden()
                                .onChange(of: editor.editingProfile.concurrency) {
                                    autoSaveCurrent()
                                }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Temperature: \(String(format: "%.1f", editor.editingProfile.temperature))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper("", value: $editor.editingProfile.temperature, in: 0.0...1.0, step: 0.1)
                                .labelsHidden()
                                .onChange(of: editor.editingProfile.temperature) {
                                    autoSaveCurrent()
                                }
                        }
                    }

                    // Enable in Fallback Chain Toggle
                    Toggle("Enable in Fallback Chain", isOn: $editor.editingProfile.isEnabled)
                        .font(.subheadline)
                        .padding(.top, 4)
                        .onChange(of: editor.editingProfile.isEnabled) {
                            autoSaveCurrent()
                        }

                    Text("When enabled, this model will automatically be used if earlier models encounter errors (HTTP 429, 503, network timeouts).")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Test Connection Button & Status
                HStack(spacing: 10) {
                    Button(action: {
                        Task { await testCurrentConnection() }
                    }) {
                        if editor.isTestingCurrentConnection {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                Text("Testing...")
                            }
                        } else {
                            Label("Test Connection", systemImage: "network")
                        }
                    }
                    .disabled(editor.isTestingCurrentConnection || editor.editingProfile.baseURL.isEmpty)

                    if let msg = editor.connectionTestMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(msg.contains("Success") || msg.contains("Found") ? .green : .orange)
                            .lineLimit(2)
                    }

                    Spacer()
                }
            }
            .padding(16)
        }
    }

    // MARK: - Footer: Fallback Chain Preview
    private var fallbackChainFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.swap")
                    .foregroundColor(.accentColor)
                    .font(.caption2)
                Text("Active Failover Execution Chain:")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Primary
                    if let primary = viewModel.activeModelProfile {
                        chainBadge(title: primary.name, subtitle: primary.modelName, tag: "1. Primary", color: .green)
                    }

                    // Fallbacks
                    ForEach(Array(viewModel.activeFallbackConfigs.enumerated()), id: \.element.id) { idx, fb in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        chainBadge(title: fb.name, subtitle: fb.modelName, tag: "Fallback #\(idx + 1)", color: .blue)
                    }

                    // Safety Fallback (Apple)
                    if viewModel.autoFallback {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        chainBadge(title: "Apple Built-in", subtitle: "Safety (2 sentences)", tag: "Final Safety", color: .purple)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func chainBadge(title: String, subtitle: String, tag: String, color: Color) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Circle().fill(color).frame(width: 5, height: 5)
                    Text(tag)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Actions
    private func selectProfile(_ profile: LLMConfig) {
        editor.selectedProfileId = profile.id
        editor.editingProfile = profile
        editor.connectionTestMessage = nil
        editor.fetchedModels = []
    }

    private func autoSaveCurrent() {
        guard let id = editor.selectedProfileId else { return }
        editor.editingProfile.id = id
        viewModel.updateModelProfile(editor.editingProfile)
    }

    private func commitCurrentEditing() {
        guard let id = editor.selectedProfileId else { return }
        editor.editingProfile.id = id
        viewModel.updateModelProfile(editor.editingProfile)
    }

    private func testCurrentConnection() async {
        editor.isTestingCurrentConnection = true
        editor.connectionTestMessage = nil
        let result = await viewModel.testConnection(for: editor.editingProfile)
        editor.isTestingCurrentConnection = false
        editor.connectionTestMessage = result
    }

    private func fetchModelsForCurrent() async {
        editor.isFetchingModels = true
        editor.fetchedModels = []
        let models = await viewModel.fetchAvailableModels(for: editor.editingProfile)
        editor.isFetchingModels = false
        if !models.isEmpty {
            editor.fetchedModels = models
            if !models.contains(editor.editingProfile.modelName), let first = models.first {
                editor.editingProfile.modelName = first
                autoSaveCurrent()
            }
            editor.connectionTestMessage = "Found \(models.count) models."
        } else {
            editor.connectionTestMessage = "No models returned from /models."
        }
    }
}

