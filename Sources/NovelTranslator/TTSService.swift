import Foundation
import AVFoundation

public enum TTSEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case vieneu = "Vieneu Neural (Vietnamese)"
    case apple = "Apple System Speech"

    public var id: String { rawValue }
}

public struct TTSVoice: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let engine: TTSEngine
    public let language: String?

    public init(id: String, name: String, engine: TTSEngine, language: String? = nil) {
        self.id = id
        self.name = name
        self.engine = engine
        self.language = language
    }
}

public struct TTSChapterManifestItem: Codable, Sendable {
    public let id: String
    public let title: String
    public let text: String
    public let output_filename: String

    public init(id: String, title: String, text: String, output_filename: String) {
        self.id = id
        self.title = title
        self.text = text
        self.output_filename = output_filename
    }
}

public struct TTSBatchManifest: Codable, Sendable {
    public let voice: String
    public let speed: Double
    public let output_dir: String
    public let chapters: [TTSChapterManifestItem]

    public init(voice: String, speed: Double = 1.0, output_dir: String, chapters: [TTSChapterManifestItem]) {
        self.voice = voice
        self.speed = speed
        self.output_dir = output_dir
        self.chapters = chapters
    }
}

public struct TTSBatchProgress: Sendable {
    public let event: String
    public let currentChapterIndex: Int
    public let totalChapters: Int
    public let chapterTitle: String
    public let message: String
    public let isCompleted: Bool
    public let isError: Bool

    public init(
        event: String,
        currentChapterIndex: Int,
        totalChapters: Int,
        chapterTitle: String,
        message: String,
        isCompleted: Bool = false,
        isError: Bool = false
    ) {
        self.event = event
        self.currentChapterIndex = currentChapterIndex
        self.totalChapters = totalChapters
        self.chapterTitle = chapterTitle
        self.message = message
        self.isCompleted = isCompleted
        self.isError = isError
    }
}

public enum TTSError: LocalizedError, Equatable {
    case pythonNotFound
    case bridgeScriptNotFound
    case executionFailed(String)
    case cancelled
    case invalidManifest
    case audioGenerationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python environment with Vieneu was not found. Please verify the mlx conda environment."
        case .bridgeScriptNotFound:
            return "Vieneu TTS bridge script could not be located."
        case .executionFailed(let msg):
            return "TTS execution failed: \(msg)"
        case .cancelled:
            return "TTS operation was cancelled."
        case .invalidManifest:
            return "Invalid chapter manifest for batch synthesis."
        case .audioGenerationFailed(let msg):
            return "Audio generation error: \(msg)"
        }
    }
}

public final class TTSService: Sendable {
    public static let shared = TTSService()

    public init() {}

    // MARK: - Process Environment Helper

    public static func defaultProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let condaBin = "/Users/namotaku/miniconda3/envs/mlx/bin:/Users/namotaku/miniconda3/condabin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = env["PATH"] {
            env["PATH"] = "\(condaBin):\(existing)"
        } else {
            env["PATH"] = condaBin
        }
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    // MARK: - Voice Discovery

    public func getAvailableVoices(engine: TTSEngine, targetLanguageCode: String? = nil) async -> [TTSVoice] {
        switch engine {
        case .vieneu:
            return await getVieneuVoices()
        case .apple:
            return getAppleVoices(targetLanguageCode: targetLanguageCode)
        }
    }

    private static nonisolated(unsafe) var cachedVieneuVoices: [TTSVoice]? = nil

    private func getVieneuVoices() async -> [TTSVoice] {
        if let cached = Self.cachedVieneuVoices {
            return cached
        }

        // In test environments, avoid spawning Python MLX runtimes to ensure tests remain ultra fast
        if CommandLine.arguments.contains(where: { $0.contains("test") }) ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
            ProcessInfo.processInfo.processName.contains("test") {
            let defaults = defaultVieneuVoices()
            Self.cachedVieneuVoices = defaults
            return defaults
        }

        guard let pythonLaunch = resolvePythonCommand(),
              let scriptURL = resolveBridgeScriptURL() else {
            let defaults = defaultVieneuVoices()
            Self.cachedVieneuVoices = defaults
            return defaults
        }

        var arguments = pythonLaunch.arguments
        arguments.append(scriptURL.path)
        arguments.append("list-voices")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonLaunch.executable)
        process.arguments = arguments
        process.environment = Self.defaultProcessEnvironment()

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let stdoutHandle = stdoutPipe.fileHandleForReading
            let data = stdoutHandle.readDataToEndOfFile()
            process.waitUntilExit()

            if let jsonString = String(data: data, encoding: .utf8) {
                // Find json line
                let lines = jsonString.split(separator: "\n")
                for line in lines {
                    if let lineData = line.data(using: .utf8),
                       let jsonObj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                       let rawVoices = jsonObj["voices"] as? [[String: Any]] {
                        let parsed: [TTSVoice] = rawVoices.compactMap { v in
                            guard let id = v["id"] as? String else { return nil }
                            let name = (v["name"] as? String) ?? id
                            return TTSVoice(id: id, name: name, engine: .vieneu, language: "vi-VN")
                        }
                        if !parsed.isEmpty {
                            Self.cachedVieneuVoices = parsed
                            return parsed
                        }
                    }
                }
            }
        } catch {
            // Fall back to preset list
        }

        let defaults = defaultVieneuVoices()
        Self.cachedVieneuVoices = defaults
        return defaults
    }

    private func defaultVieneuVoices() -> [TTSVoice] {
        [
            TTSVoice(id: "Trúc Ly", name: "Trúc Ly — Nữ · Bắc · Tự nhiên (Default)", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Phạm Tuyên", name: "Phạm Tuyên — Nam · Bắc", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Bích Ngọc", name: "Bích Ngọc — Nữ · Bắc", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Mỹ Duyên", name: "Mỹ Duyên — Nữ · Bắc · Đọc truyện", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Đức Trí", name: "Đức Trí — Nam · Bắc · Đọc truyện", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Hữu Quân", name: "Hữu Quân — Nam · Bắc · Tin tức", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Xuân Tiên", name: "Xuân Tiên — Nữ · Bắc · Tin tức", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Mai Anh", name: "Mai Anh — Nữ · Bắc · Tin tức", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Anh Khôi", name: "Anh Khôi — Nam · Bắc · Kể chuyện", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Minh Quân", name: "Minh Quân — Nam · Bắc · Tự nhiên", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Mạnh Dũng", name: "Mạnh Dũng — Nam · Bắc · Tự nhiên", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Adam", name: "Adam — Nam · Nam · Tự nhiên", engine: .vieneu, language: "vi-VN"),
            TTSVoice(id: "Ái Hân", name: "Ái Hân — Nữ · Nam · Tin tức", engine: .vieneu, language: "vi-VN"),
        ]
    }

    private func getAppleVoices(targetLanguageCode: String?) -> [TTSVoice] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let filtered: [AVSpeechSynthesisVoice]
        if let targetCode = targetLanguageCode, !targetCode.isEmpty {
            let prefix = targetCode.components(separatedBy: "-")[0]
            let matches = allVoices.filter { $0.language.lowercased().hasPrefix(prefix.lowercased()) }
            filtered = matches.isEmpty ? allVoices : matches
        } else {
            filtered = allVoices
        }

        return filtered.map { v in
            TTSVoice(id: v.identifier, name: "\(v.name) (\(v.language))", engine: .apple, language: v.language)
        }
    }

    // MARK: - Single Chapter / Text Synthesis

    public func synthesize(
        text: String,
        voiceId: String,
        speed: Double = 1.0,
        engine: TTSEngine = .vieneu,
        outputURL: URL
    ) async throws {
        let cleanText = Self.cleanTextForSpeech(text)
        guard !cleanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSError.audioGenerationFailed("Text content is empty.")
        }

        switch engine {
        case .vieneu:
            try await synthesizeVieneu(text: cleanText, voiceId: voiceId, speed: speed, outputURL: outputURL)
        case .apple:
            // For Apple, we can render via AVSpeechSynthesizer buffer if needed or live
            try await synthesizeApple(text: cleanText, voiceIdentifier: voiceId, outputURL: outputURL)
        }
    }

    private func synthesizeVieneu(
        text: String,
        voiceId: String,
        speed: Double,
        outputURL: URL
    ) async throws {
        guard let pythonLaunch = resolvePythonCommand() else {
            throw TTSError.pythonNotFound
        }
        guard let scriptURL = resolveBridgeScriptURL() else {
            throw TTSError.bridgeScriptNotFound
        }

        // Write text to a temporary file to handle long multi-page chapters safely without CLI argument length limits
        let tempTextURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_input_\(UUID().uuidString).txt")
        try cleanTextForTemporaryFile(text).write(to: tempTextURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempTextURL) }

        var arguments = pythonLaunch.arguments
        arguments.append(scriptURL.path)
        arguments.append("synthesize")
        arguments.append("--voice")
        arguments.append(voiceId)
        arguments.append("--speed")
        arguments.append(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), speed))
        arguments.append("--text-file")
        arguments.append(tempTextURL.path)
        arguments.append("--output")
        arguments.append(outputURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonLaunch.executable)
        process.arguments = arguments
        process.environment = Self.defaultProcessEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let _ = stdoutHandle.readDataToEndOfFile()
        let stderrData = stderrHandle.readDataToEndOfFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errMsg = String(data: stderrData, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
            throw TTSError.executionFailed(errMsg)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw TTSError.audioGenerationFailed("Output audio file was not created at \(outputURL.path)")
        }
    }

    private func synthesizeApple(text: String, voiceIdentifier: String, outputURL: URL) async throws {
        // Render AVSpeechUtterance to audio file using AVSpeechSynthesizer.write
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var audioFile: AVAudioFile?
            var hasFinished = false

            synth.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                if pcmBuffer.frameLength == 0 {
                    if !hasFinished {
                        hasFinished = true
                        continuation.resume(returning: ())
                    }
                    return
                }

                if audioFile == nil {
                    do {
                        audioFile = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
                    } catch {
                        if !hasFinished {
                            hasFinished = true
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                }

                do {
                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    if !hasFinished {
                        hasFinished = true
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Batch Synthesis (for Audiobook Export)

    public func batchSynthesize(
        manifest: TTSBatchManifest,
        activeProcessReceiver: (@Sendable (Process) -> Void)? = nil,
        progressHandler: @escaping @Sendable (TTSBatchProgress) -> Void
    ) async throws {
        guard let pythonLaunch = resolvePythonCommand() else {
            throw TTSError.pythonNotFound
        }
        guard let scriptURL = resolveBridgeScriptURL() else {
            throw TTSError.bridgeScriptNotFound
        }

        // Clean texts in manifest
        let cleanedChapters = manifest.chapters.map { ch in
            TTSChapterManifestItem(
                id: ch.id,
                title: ch.title,
                text: Self.cleanTextForSpeech(ch.text),
                output_filename: ch.output_filename
            )
        }
        let cleanManifest = TTSBatchManifest(
            voice: manifest.voice,
            speed: manifest.speed,
            output_dir: manifest.output_dir,
            chapters: cleanedChapters
        )

        let manifestURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_manifest_\(UUID().uuidString).json")
        let manifestData = try JSONEncoder().encode(cleanManifest)
        try manifestData.write(to: manifestURL)
        defer { try? FileManager.default.removeItem(at: manifestURL) }

        var arguments = pythonLaunch.arguments
        arguments.append(scriptURL.path)
        arguments.append("batch-synthesize")
        arguments.append("--manifest")
        arguments.append(manifestURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonLaunch.executable)
        process.arguments = arguments
        process.environment = Self.defaultProcessEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        activeProcessReceiver?(process)

        // Read stream lines
        let stdoutHandle = stdoutPipe.fileHandleForReading

        try process.run()

        var buffer = Data()
        var total = manifest.chapters.count
        var currentIndex = 0

        while process.isRunning || stdoutHandle.availableData.count > 0 {
            let data = stdoutHandle.availableData
            if data.isEmpty {
                if !process.isRunning { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }

            buffer.append(data)
            while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0...newlineRange.lowerBound)

                if (try? JSONSerialization.jsonObject(with: lineData)) != nil,
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    let event = (json["event"] as? String) ?? ""
                    let idx = (json["index"] as? Int) ?? currentIndex
                    let title = (json["title"] as? String) ?? "Chapter"

                    if let t = json["total"] as? Int {
                        total = t
                    }
                    currentIndex = idx

                    switch event {
                    case "start":
                        progressHandler(TTSBatchProgress(
                            event: "start",
                            currentChapterIndex: 0,
                            totalChapters: total,
                            chapterTitle: "Initializing TTS engine...",
                            message: "Loaded Vieneu model"
                        ))
                    case "chapter_start":
                        progressHandler(TTSBatchProgress(
                            event: "chapter_start",
                            currentChapterIndex: idx,
                            totalChapters: total,
                            chapterTitle: title,
                            message: "Synthesizing '\(title)'..."
                        ))
                    case "chapter_skip":
                        progressHandler(TTSBatchProgress(
                            event: "chapter_skip",
                            currentChapterIndex: idx,
                            totalChapters: total,
                            chapterTitle: title,
                            message: "Audio already exists for '\(title)' (Skipped)"
                        ))
                    case "chapter_done":
                        let dur = json["duration_seconds"] as? Double ?? 0
                        progressHandler(TTSBatchProgress(
                            event: "chapter_done",
                            currentChapterIndex: idx + 1,
                            totalChapters: total,
                            chapterTitle: title,
                            message: "Completed '\(title)' in \(String(format: "%.1f", dur))s"
                        ))
                    case "chapter_error":
                        let err = (json["error"] as? String) ?? "Unknown error"
                        progressHandler(TTSBatchProgress(
                            event: "chapter_error",
                            currentChapterIndex: idx,
                            totalChapters: total,
                            chapterTitle: title,
                            message: "Failed '\(title)': \(err)",
                            isError: true
                        ))
                    case "completed":
                        let processed = json["processed"] as? Int ?? 0
                        let skipped = json["skipped"] as? Int ?? 0
                        progressHandler(TTSBatchProgress(
                            event: "completed",
                            currentChapterIndex: total,
                            totalChapters: total,
                            chapterTitle: "Done",
                            message: "Batch completed: \(processed) generated, \(skipped) skipped.",
                            isCompleted: true
                        ))
                    default:
                        break
                    }
                }
            }
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Process exited with code \(process.terminationStatus)"
            throw TTSError.executionFailed(errMsg)
        }
    }

    // MARK: - Text Cleaning for Speech

    public static func cleanTextForSpeech(_ rawText: String) -> String {
        var text = rawText

        // 1. Strip XHTML / HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // 2. Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // 3. Strip Markdown images and links: ![alt](url) -> "", [text](url) -> text
        text = text.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]+\\)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)

        // 4. Strip Markdown headers: # Header -> Header
        text = text.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)

        // 5. Strip Markdown formatting asterisks and underscores: **bold**, *italic*
        text = text.replacingOccurrences(of: "\\*\\*|__|\\*|_", with: "", options: .regularExpression)

        // 6. Strip page numbers like "247 / 448" or "12/50"
        text = text.replacingOccurrences(of: "(?m)^\\d+\\s*/\\s*\\d+$", with: "", options: .regularExpression)

        // 7. Strip inline footnote reference numbers: e.g. "nhân 146 , bộ" -> "nhân, bộ"
        text = text.replacingOccurrences(of: "(?<=\\w)\\s+(\\d+)\\s*([,\\.!;:])", with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?<=\\w)\\s+(\\d+)\\s*\\)", with: ")", options: .regularExpression)

        // 8. Collapse whitespace and excess newlines
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanTextForTemporaryFile(_ text: String) -> String {
        Self.cleanTextForSpeech(text)
    }

    // MARK: - Python Environment & Bridge Path Resolution

    public struct PythonLaunchConfiguration: Sendable {
        public let executable: String
        public let arguments: [String]
    }

    public func resolvePythonCommand() -> PythonLaunchConfiguration? {
        let fm = FileManager.default

        // 1. User defaults or custom configuration
        if let customPython = UserDefaults.standard.string(forKey: "VieneuPythonPath"),
           !customPython.isEmpty, fm.fileExists(atPath: customPython) {
            return PythonLaunchConfiguration(executable: customPython, arguments: [])
        }

        // 2. Direct mlx conda environment python path
        let mlxPython = "/Users/namotaku/miniconda3/envs/mlx/bin/python"
        if fm.fileExists(atPath: mlxPython) {
            return PythonLaunchConfiguration(executable: mlxPython, arguments: [])
        }

        // 3. User home relative conda mlx path
        let homeDir = fm.homeDirectoryForCurrentUser.path
        let homeMlx = "\(homeDir)/miniconda3/envs/mlx/bin/python"
        if fm.fileExists(atPath: homeMlx) {
            return PythonLaunchConfiguration(executable: homeMlx, arguments: [])
        }

        let homeAnacondaMlx = "\(homeDir)/anaconda3/envs/mlx/bin/python"
        if fm.fileExists(atPath: homeAnacondaMlx) {
            return PythonLaunchConfiguration(executable: homeAnacondaMlx, arguments: [])
        }

        // 4. Check conda runner
        let condaPath = "/Users/namotaku/miniconda3/condabin/conda"
        if fm.fileExists(atPath: condaPath) {
            return PythonLaunchConfiguration(executable: condaPath, arguments: ["run", "-n", "mlx", "python"])
        }

        // 5. General fallback python
        for fallback in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            if fm.fileExists(atPath: fallback) {
                return PythonLaunchConfiguration(executable: fallback, arguments: [])
            }
        }

        return nil
    }

    public func resolveBridgeScriptURL() -> URL? {
        let fm = FileManager.default

        // 1. Main Bundle Resources
        if let resURL = Bundle.main.url(forResource: "vieneu_tts_bridge", withExtension: "py"),
           fm.fileExists(atPath: resURL.path) {
            return resURL
        }

        // 2. Main Bundle directory contents
        let bundleRes = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/vieneu_tts_bridge.py")
        if fm.fileExists(atPath: bundleRes.path) {
            return bundleRes
        }

        // 3. Executable relative resources
        if let exeURL = Bundle.main.executableURL {
            let exeRes = exeURL.deletingLastPathComponent().appendingPathComponent("../Resources/vieneu_tts_bridge.py").standardized
            if fm.fileExists(atPath: exeRes.path) {
                return exeRes
            }
        }

        // 4. Project scripts directory
        let scriptRelative = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("scripts/vieneu_tts_bridge.py")
        if fm.fileExists(atPath: scriptRelative.path) {
            return scriptRelative
        }

        // 5. Hardcoded development project path
        let devProjectScript = URL(fileURLWithPath: "/Users/namotaku/.gemini/antigravity/scratch/DocTranslateApp/scripts/vieneu_tts_bridge.py")
        if fm.fileExists(atPath: devProjectScript.path) {
            return devProjectScript
        }

        // 6. App Support / caches scripts directory
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let scriptNovel = appSupport.appendingPathComponent("NovelTranslator/scripts/vieneu_tts_bridge.py")
            if fm.fileExists(atPath: scriptNovel.path) {
                return scriptNovel
            }
            let scriptAppSupport = appSupport.appendingPathComponent("DocTranslateApp/scripts/vieneu_tts_bridge.py")
            if fm.fileExists(atPath: scriptAppSupport.path) {
                return scriptAppSupport
            }
        }

        return nil
    }
}
