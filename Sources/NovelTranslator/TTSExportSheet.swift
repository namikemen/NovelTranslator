import SwiftUI
import AppKit

public struct TTSExportSheet: View {
    @ObservedObject var viewModel: TranslationViewModel

    public init(viewModel: TranslationViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Audiobook Chapters")
                        .font(.headline)
                    Text("Synthesize chapters to .wav audio using Vieneu neural TTS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !viewModel.isBatchExportingAudio {
                    Button("Close") {
                        viewModel.showTTSExportSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }

            Divider()

            if let book = viewModel.currentEPUB {
                // Book Overview
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("📖 \(book.title)")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text("\(book.chapters.count) total chapters • \(book.chapters.filter(\.isTranslated).count) translated • \(book.totalWords) words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                if viewModel.isBatchExportingAudio, let progress = viewModel.batchExportProgress {
                    // Export In Progress View
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Processing: \(progress.chapterTitle)")
                                .font(.callout.bold())
                                .lineLimit(1)
                            Spacer()
                            Text("\(progress.currentChapterIndex) of \(progress.totalChapters)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }

                        ProgressView(
                            value: Double(progress.currentChapterIndex),
                            total: Double(max(progress.totalChapters, 1))
                        )

                        Text(progress.message)
                            .font(.caption)
                            .foregroundColor(progress.isError ? .red : .secondary)

                        HStack {
                            Spacer()
                            Button("Cancel Export", role: .destructive) {
                                viewModel.cancelBatchAudioExport()
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                } else if viewModel.ttsExportCompleted || viewModel.batchExportProgress?.isCompleted == true {
                    // Completed View
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)

                        Text("Audiobook Export Complete!")
                            .font(.headline)

                        if let dest = viewModel.ttsExportOutputDir {
                            Text("Audio files saved to:\n\(dest.path)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.open(dest)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Done") {
                                    viewModel.showTTSExportSheet = false
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
                } else {
                    // Export Configuration Form
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // 1. Text Source (Untranslated / Native Vietnamese vs Translated)
                            HStack(alignment: .center) {
                                Text("Text Source:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Picker("", selection: $viewModel.ttsExportTextSource) {
                                    ForEach(TranslationViewModel.TTSTextSource.allCases) { src in
                                        Text(src.rawValue).tag(src)
                                    }
                                }
                                .labelsHidden()
                            }

                            // 2. Chapter Selection Scope
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Chapters:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Picker("", selection: $viewModel.ttsExportScope) {
                                        ForEach(TranslationViewModel.TTSExportScope.allCases) { scope in
                                            Text(scope.rawValue).tag(scope)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                }

                                // Quick chapter selection buttons
                                HStack(spacing: 8) {
                                    Button("Select All (\(book.chapters.count))") {
                                        viewModel.selectAllChaptersForExport()
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption2)

                                    Text("•").foregroundColor(.secondary)

                                    Button("Deselect All") {
                                        viewModel.deselectAllChaptersForExport()
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption2)

                                    if book.chapters.contains(where: \.isTranslated) {
                                        Text("•").foregroundColor(.secondary)
                                        Button("Translated Only (\(book.chapters.filter(\.isTranslated).count))") {
                                            viewModel.selectTranslatedChaptersOnlyForExport()
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption2)
                                    }

                                    Spacer()

                                    Text("Selected: \(currentEffectiveChapters(book: book).count) chapters")
                                        .font(.caption2.bold())
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.leading, 124)

                                // Chapter Checkbox List (Scrollable)
                                if viewModel.ttsExportScope == .selected {
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 4) {
                                            ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                                                HStack {
                                                    Toggle(isOn: Binding(
                                                        get: { viewModel.ttsExportSelectedChapters.contains(index) },
                                                        set: { _ in viewModel.toggleChapterExportSelection(index) }
                                                    )) {
                                                        HStack(spacing: 6) {
                                                            Text("\(index + 1).")
                                                                .font(.caption.monospacedDigit())
                                                                .foregroundColor(.secondary)
                                                            Text(chapter.title)
                                                                .font(.caption)
                                                                .lineLimit(1)
                                                            Spacer()
                                                            if chapter.isTranslated {
                                                                Text("Translated")
                                                                    .font(.caption2)
                                                                    .foregroundColor(.green)
                                                            } else {
                                                                Text("Original")
                                                                    .font(.caption2)
                                                                    .foregroundColor(.secondary)
                                                            }
                                                            Text("(\(chapter.wordCount)w)")
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }
                                                    .toggleStyle(.checkbox)
                                                }
                                                .padding(.vertical, 2)
                                                .padding(.horizontal, 6)
                                            }
                                        }
                                        .padding(4)
                                    }
                                    .frame(height: 120)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                    )
                                }
                            }

                            Divider()

                            // 3. Voice & Test Voice Button
                            HStack {
                                Text("Voice:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Picker("", selection: $viewModel.ttsExportVoiceId) {
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

                            // 4. Speech Speed
                            HStack {
                                Text("Speed Multiplier:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Picker("", selection: $viewModel.ttsExportSpeed) {
                                    Text("0.75x").tag(0.75)
                                    Text("1.0x (Normal)").tag(1.0)
                                    Text("1.25x").tag(1.25)
                                    Text("1.5x").tag(1.5)
                                }
                                .labelsHidden()
                            }

                            // 5. Output Directory
                            HStack {
                                Text("Output Directory:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)

                                if let dest = viewModel.ttsExportOutputDir {
                                    Text(dest.path)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } else {
                                    Text("Choose folder...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button("Choose...") {
                                    chooseOutputFolder()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    if let err = viewModel.ttsErrorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // Start Action Button
                    HStack {
                        Button("Cancel") {
                            viewModel.showTTSExportSheet = false
                        }
                        Spacer()
                        Button(action: {
                            startExport()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                Text("Export \(currentEffectiveChapters(book: book).count) Chapters (.wav)")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.ttsExportOutputDir == nil || currentEffectiveChapters(book: book).isEmpty)
                    }
                }
            } else {
                Text("No eBook currently loaded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(18)
        .frame(width: 540, height: 480)
        .onAppear {
            viewModel.ttsExportCompleted = false
            if let defaultVoice = viewModel.availableTTSVoices.first?.id {
                viewModel.ttsExportVoiceId = viewModel.selectedTTSVoiceId.isEmpty ? defaultVoice : viewModel.selectedTTSVoiceId
            }
            if let book = viewModel.currentEPUB {
                if viewModel.ttsExportSelectedChapters.isEmpty {
                    viewModel.ttsExportSelectedChapters = Set(0..<book.chapters.count)
                }
                // If book has no translations yet (e.g. given directly in Vietnamese), default text source to original
                let hasTranslations = book.chapters.contains(where: \.isTranslated)
                if !hasTranslations {
                    viewModel.ttsExportTextSource = .original
                    viewModel.ttsExportScope = .allChapters
                }
                if viewModel.ttsExportOutputDir == nil {
                    let safeName = book.title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
                    let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    viewModel.ttsExportOutputDir = downloads?.appendingPathComponent("\(safeName)_audio", isDirectory: true)
                }
            }
        }
    }

    private func currentEffectiveChapters(book: EPUBBook) -> [Int] {
        switch viewModel.ttsExportScope {
        case .allChapters:
            return Array(book.chapters.indices)
        case .translatedOnly:
            return book.chapters.enumerated().compactMap { idx, ch in
                ch.isTranslated ? idx : nil
            }
        case .selected:
            return book.chapters.indices.filter { viewModel.ttsExportSelectedChapters.contains($0) }
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.ttsExportOutputDir = url
        }
    }

    private func startExport() {
        guard let dest = viewModel.ttsExportOutputDir, let book = viewModel.currentEPUB else { return }

        let indices = currentEffectiveChapters(book: book)
        guard !indices.isEmpty else {
            viewModel.ttsErrorMessage = "Please select at least one chapter to export."
            return
        }

        Task {
            await viewModel.startBatchAudioExport(
                outputDirectory: dest,
                selectedVoiceId: viewModel.ttsExportVoiceId,
                speed: viewModel.ttsExportSpeed,
                textSource: viewModel.ttsExportTextSource,
                chapterIndices: indices
            )
            viewModel.ttsExportCompleted = true
        }
    }
}
