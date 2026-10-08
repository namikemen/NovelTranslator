import Foundation

public struct TranslationCheckpointSummary: Identifiable, Codable, Sendable {
    public var id: String
    public var title: String
    public var appMode: AppMode
    public var engine: TranslationEngine
    public var sourceLanguageId: String
    public var targetLanguageId: String
    public var timestamp: Date
    public var completedItems: Int
    public var totalItems: Int

    public var progressFraction: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }

    public var progressPercentString: String {
        return "\(Int(progressFraction * 100))%"
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

public struct TranslationCheckpoint: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var timestamp: Date
    public var appMode: AppMode
    public var engine: TranslationEngine
    public var sourceLanguageId: String
    public var targetLanguageId: String

    // Document Mode
    public var sourceDocument: String
    public var translatedDocument: String
    public var activeChunks: [DocumentChunk]
    public var completedChunks: Int
    public var totalTranslatableChunks: Int

    // EPUB Mode
    public var epubBook: EPUBBook?
    public var selectedChapterIndex: Int
    public var completedEPUBChapters: Int
    public var completedEPUBNodes: Int
    public var totalEPUBNodes: Int

    // Character Bible
    public var characterBible: CharacterBible?

    public init(
        id: String = UUID().uuidString,
        title: String = "",
        appMode: AppMode,
        engine: TranslationEngine,
        sourceLanguageId: String,
        targetLanguageId: String,
        sourceDocument: String = "",
        translatedDocument: String = "",
        activeChunks: [DocumentChunk] = [],
        completedChunks: Int = 0,
        totalTranslatableChunks: Int = 0,
        epubBook: EPUBBook? = nil,
        selectedChapterIndex: Int = 0,
        completedEPUBChapters: Int = 0,
        completedEPUBNodes: Int = 0,
        totalEPUBNodes: Int = 0,
        characterBible: CharacterBible? = nil
    ) {
        self.id = id
        if !title.isEmpty {
            self.title = title
        } else if appMode == .epub, let book = epubBook, !book.title.isEmpty {
            self.title = book.title
        } else if appMode == .document, !sourceDocument.isEmpty {
            let firstLine = sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? "Text Document"
            self.title = String(firstLine.prefix(40))
        } else {
            self.title = (appMode == .epub) ? "Untitled eBook" : "Text Document"
        }
        self.timestamp = Date()
        self.appMode = appMode
        self.engine = engine
        self.sourceLanguageId = sourceLanguageId
        self.targetLanguageId = targetLanguageId
        self.sourceDocument = sourceDocument
        self.translatedDocument = translatedDocument
        self.activeChunks = activeChunks
        self.completedChunks = completedChunks
        self.totalTranslatableChunks = totalTranslatableChunks
        self.epubBook = epubBook
        self.selectedChapterIndex = selectedChapterIndex
        self.completedEPUBChapters = completedEPUBChapters
        self.completedEPUBNodes = completedEPUBNodes
        self.totalEPUBNodes = totalEPUBNodes
        self.characterBible = characterBible ?? epubBook?.characterBible
    }

    public var summary: TranslationCheckpointSummary {
        let (completed, total): (Int, Int) = {
            if appMode == .document {
                return (completedChunks, totalTranslatableChunks)
            } else {
                return (completedEPUBNodes, totalEPUBNodes)
            }
        }()
        return TranslationCheckpointSummary(
            id: id,
            title: title,
            appMode: appMode,
            engine: engine,
            sourceLanguageId: sourceLanguageId,
            targetLanguageId: targetLanguageId,
            timestamp: timestamp,
            completedItems: completed,
            totalItems: total
        )
    }
}

public struct CheckpointManager: Sendable {
    private static let lock = NSLock()
    private static nonisolated(unsafe) var _customBaseDirectory: URL? = nil

    public static var customBaseDirectory: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _customBaseDirectory
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _customBaseDirectory = newValue
        }
    }

    public static var baseDirectory: URL {
        if let custom = customBaseDirectory {
            if !FileManager.default.fileExists(atPath: custom.path) {
                try? FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
            }
            return custom
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NovelTranslator", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("DocTranslateApp", isDirectory: true)

        let targetDir: URL
        if !FileManager.default.fileExists(atPath: dir.path) && FileManager.default.fileExists(atPath: legacyDir.path) {
            targetDir = legacyDir
        } else {
            targetDir = dir
            if !FileManager.default.fileExists(atPath: targetDir.path) {
                try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            }
        }
        return targetDir
    }

    public static var checkpointsDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("Checkpoints", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // Legacy single checkpoint URL for migration
    public static var legacyCheckpointFileURL: URL {
        baseDirectory.appendingPathComponent("checkpoint.json")
    }

    public static var legacySavedEPUBDirectory: URL {
        baseDirectory.appendingPathComponent("SavedEPUB", isDirectory: true)
    }

    // MARK: - Save Checkpoint
    @discardableResult
    public static func save(checkpoint: TranslationCheckpoint) -> String {
        migrateLegacyIfNeeded()

        var mutableCheckpoint = checkpoint
        let checkpointId = mutableCheckpoint.id
        let sessionEPUBDir = checkpointsDirectory.appendingPathComponent("\(checkpointId)_EPUB", isDirectory: true)

        // If EPUB mode, preserve unpacked book directory in its dedicated session folder
        if mutableCheckpoint.appMode == .epub, var book = mutableCheckpoint.epubBook {
            if book.rootDirectory != sessionEPUBDir {
                try? FileManager.default.removeItem(at: sessionEPUBDir)
                try? FileManager.default.copyItem(at: book.rootDirectory, to: sessionEPUBDir)
                book = EPUBBook(
                    title: book.title,
                    author: book.author,
                    language: book.language,
                    rootDirectory: sessionEPUBDir,
                    opfRelativePath: book.opfRelativePath,
                    chapters: book.chapters
                )
                mutableCheckpoint.epubBook = book
            }
        }

        let dir = checkpointsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(checkpointId).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(mutableCheckpoint)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save checkpoint \(checkpointId): \(error)")
        }

        return checkpointId
    }

    // MARK: - List Checkpoints
    public static func listCheckpoints() -> [TranslationCheckpointSummary] {
        migrateLegacyIfNeeded()

        guard let files = try? FileManager.default.contentsOfDirectory(at: checkpointsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        var summaries: [TranslationCheckpointSummary] = []
        let decoder = JSONDecoder()

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let checkpoint = try? decoder.decode(TranslationCheckpoint.self, from: data) {
                // Include checkpoints with saved progress or configured Character Bible
                if checkpoint.appMode == .document {
                    if checkpoint.completedChunks > 0 {
                        summaries.append(checkpoint.summary)
                    }
                } else {
                    if let book = checkpoint.epubBook {
                        let doneNodes = book.chapters.reduce(0) { $0 + $1.nodes.filter { !$0.translatedText.isEmpty }.count }
                        if doneNodes > 0 || checkpoint.characterBible != nil {
                            summaries.append(checkpoint.summary)
                        }
                    }
                }
            }
        }

        return summaries.sorted(by: { $0.timestamp > $1.timestamp })
    }

    // MARK: - Load Checkpoint
    public static func load(id: String) -> TranslationCheckpoint? {
        let fileURL = checkpointsDirectory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(TranslationCheckpoint.self, from: data)
        } catch {
            print("Failed to load checkpoint \(id): \(error)")
            return nil
        }
    }

    public static func loadLatest() -> TranslationCheckpoint? {
        guard let latestSummary = listCheckpoints().first else { return nil }
        return load(id: latestSummary.id)
    }

    // MARK: - Delete Checkpoint
    public static func delete(id: String) {
        let fileURL = checkpointsDirectory.appendingPathComponent("\(id).json")
        let epubDir = checkpointsDirectory.appendingPathComponent("\(id)_EPUB", isDirectory: true)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: epubDir)
    }

    public static func clearAll() {
        try? FileManager.default.removeItem(at: checkpointsDirectory)
        try? FileManager.default.createDirectory(at: checkpointsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: legacyCheckpointFileURL)
        try? FileManager.default.removeItem(at: legacySavedEPUBDirectory)
    }

    public static var hasSavedCheckpoint: Bool {
        !listCheckpoints().isEmpty
    }

    // MARK: - Legacy Migration
    private static func migrateLegacyIfNeeded() {
        guard FileManager.default.fileExists(atPath: legacyCheckpointFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: legacyCheckpointFileURL)
            let decoder = JSONDecoder()
            if var legacy = try? decoder.decode(TranslationCheckpoint.self, from: data) {
                let newId = UUID().uuidString
                legacy.id = newId
                let destEPUBDir = checkpointsDirectory.appendingPathComponent("\(newId)_EPUB", isDirectory: true)
                if FileManager.default.fileExists(atPath: legacySavedEPUBDirectory.path) {
                    try? FileManager.default.copyItem(at: legacySavedEPUBDirectory, to: destEPUBDir)
                    if var book = legacy.epubBook {
                        book = EPUBBook(
                            title: book.title,
                            author: book.author,
                            language: book.language,
                            rootDirectory: destEPUBDir,
                            opfRelativePath: book.opfRelativePath,
                            chapters: book.chapters
                        )
                        legacy.epubBook = book
                    }
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                let newData = try encoder.encode(legacy)
                let newFileURL = checkpointsDirectory.appendingPathComponent("\(newId).json")
                try newData.write(to: newFileURL, options: .atomic)
            }
            try? FileManager.default.removeItem(at: legacyCheckpointFileURL)
            try? FileManager.default.removeItem(at: legacySavedEPUBDirectory)
        } catch {
            print("Error migrating legacy checkpoint: \(error)")
        }
    }
}
