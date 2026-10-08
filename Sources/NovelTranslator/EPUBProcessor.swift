import Foundation

public struct TranslatableNode: Identifiable, Sendable, Codable {
    public let id: Int
    public let originalText: String
    public var translatedText: String
    public let fullMatch: String
    public let tagOpen: String
    public let tagClose: String

    public init(id: Int, originalText: String, translatedText: String = "", fullMatch: String, tagOpen: String, tagClose: String) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.fullMatch = fullMatch
        self.tagOpen = tagOpen
        self.tagClose = tagClose
    }
}

public struct EPUBChapter: Identifiable, Sendable, Codable {
    public let id: String
    public var title: String
    public let relativePath: String
    public var originalContent: String
    public var translatedContent: String
    public var nodes: [TranslatableNode]
    public var isTranslated: Bool

    public var wordCount: Int {
        nodes.reduce(0) { $0 + $1.originalText.split { $0.isWhitespace || $0.isNewline }.count }
    }

    public init(id: String, title: String, relativePath: String, originalContent: String, nodes: [TranslatableNode] = []) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.originalContent = originalContent
        self.translatedContent = originalContent
        self.nodes = nodes
        self.isTranslated = false
    }
}

public struct EPUBBook: Sendable, Codable {
    public var title: String
    public var author: String
    public var language: String
    public let rootDirectory: URL
    public let opfRelativePath: String
    public var chapters: [EPUBChapter]
    public var characterBible: CharacterBible?

    public init(
        title: String,
        author: String,
        language: String,
        rootDirectory: URL,
        opfRelativePath: String,
        chapters: [EPUBChapter],
        characterBible: CharacterBible? = nil
    ) {
        self.title = title
        self.author = author
        self.language = language
        self.rootDirectory = rootDirectory
        self.opfRelativePath = opfRelativePath
        self.chapters = chapters
        self.characterBible = characterBible
    }

    public var totalNodes: Int {
        chapters.reduce(0) { $0 + $1.nodes.count }
    }

    public var totalWords: Int {
        chapters.reduce(0) { $0 + $1.wordCount }
    }
}

public enum EPUBError: LocalizedError {
    case zipExecutionFailed(String)
    case containerMissing
    case opfMissing
    case invalidChapter(String)

    public var errorDescription: String? {
        switch self {
        case .zipExecutionFailed(let msg): return "Archive error: \(msg)"
        case .containerMissing: return "Invalid EPUB: META-INF/container.xml not found."
        case .opfMissing: return "Invalid EPUB: Root OPF file not found."
        case .invalidChapter(let name): return "Could not parse chapter: \(name)"
        }
    }
}

public final class EPUBProcessor: Sendable {

    /// Unpacks an .epub file to a temporary directory and parses chapters in spine order
    public static func unpack(epubURL: URL) throws -> EPUBBook {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUB_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Run /usr/bin/unzip -q <epubURL> -d <tempDir>
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", epubURL.path, "-d", tempDir.path]

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        // Status 0: normal success; Status 1: warning (e.g. timestamp or zip quirks), often still extracted fine
        if process.terminationStatus != 0 && process.terminationStatus != 1 {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown unzip error"
            throw EPUBError.zipExecutionFailed("Unzip failed (status \(process.terminationStatus)): \(errMsg)")
        }

        // 1. Locate rootfile from META-INF/container.xml
        let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
        let containerContent: String? = {
            if let str = try? String(contentsOf: containerURL, encoding: .utf8) { return str }
            if let data = try? Data(contentsOf: containerURL) { return String(decoding: data, as: UTF8.self) }
            return nil
        }()
        guard let containerContent else {
            throw EPUBError.containerMissing
        }

        guard let opfPath = extractAttribute(named: "full-path", in: containerContent) else {
            throw EPUBError.opfMissing
        }

        let cleanOpfPath = (opfPath.components(separatedBy: "#").first ?? opfPath).removingPercentEncoding ?? opfPath
        let opfURL = tempDir.appendingPathComponent(cleanOpfPath)
        let opfContent: String? = {
            if let str = try? String(contentsOf: opfURL, encoding: .utf8) { return str }
            if let str = try? String(contentsOf: opfURL, encoding: .utf16) { return str }
            if let str = try? String(contentsOf: opfURL, encoding: .isoLatin1) { return str }
            if let data = try? Data(contentsOf: opfURL) { return String(decoding: data, as: UTF8.self) }
            return nil
        }()
        guard let opfContent else {
            throw EPUBError.opfMissing
        }

        let opfFolderURL = opfURL.deletingLastPathComponent()

        // 2. Parse metadata
        let title = extractTagContent(named: "dc:title", in: opfContent) ?? "Untitled eBook"
        let author = extractTagContent(named: "dc:creator", in: opfContent) ?? "Unknown Author"
        let language = extractTagContent(named: "dc:language", in: opfContent) ?? "en"

        // 3. Parse manifest items: id -> href (order-independent)
        var manifest: [String: String] = [:]
        let itemPattern = "<item\\b[^>]*>"
        if let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive]) {
            let ns = opfContent as NSString
            let matches = itemRegex.matches(in: opfContent, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                let tag = ns.substring(with: m.range)
                if let id = extractAttribute(named: "id", in: tag),
                   let href = extractAttribute(named: "href", in: tag) {
                    manifest[id] = href
                }
            }
        }

        // 4. Parse spine: order of itemrefs
        var spineIds: [String] = []
        let spinePattern = "<itemref\\b[^>]*>"
        if let spineRegex = try? NSRegularExpression(pattern: spinePattern, options: [.caseInsensitive]) {
            let ns = opfContent as NSString
            let matches = spineRegex.matches(in: opfContent, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                let tag = ns.substring(with: m.range)
                if let idref = extractAttribute(named: "idref", in: tag) {
                    spineIds.append(idref)
                }
            }
        }

        var chapters: [EPUBChapter] = []
        var globalNodeId = 0
        for (index, idref) in spineIds.enumerated() {
            guard let href = manifest[idref] else { continue }

            let cleanHref = href.components(separatedBy: "#").first ?? href
            let decodedHref = cleanHref.removingPercentEncoding ?? cleanHref
            let chapterURL = opfFolderURL.appendingPathComponent(decodedHref)

            let chapterContent: String? = {
                if let str = try? String(contentsOf: chapterURL, encoding: .utf8) { return str }
                if let str = try? String(contentsOf: chapterURL, encoding: .utf16) { return str }
                if let str = try? String(contentsOf: chapterURL, encoding: .isoLatin1) { return str }
                if let data = try? Data(contentsOf: chapterURL) {
                    return String(decoding: data, as: UTF8.self)
                }
                return nil
            }()

            guard let chapterContent else { continue }

            let chapterTitle = extractTagContent(named: "title", in: chapterContent)
                ?? extractTagContent(named: "h1", in: chapterContent)
                ?? extractTagContent(named: "h2", in: chapterContent)
                ?? "Chapter \(index + 1)"

            let relativePathFromRoot = chapterURL.path.replacingOccurrences(of: tempDir.path + "/", with: "")
            let nodes = extractTranslatableNodes(from: chapterContent, startingId: globalNodeId)
            globalNodeId += nodes.count

            let chapter = EPUBChapter(
                id: idref,
                title: chapterTitle,
                relativePath: relativePathFromRoot,
                originalContent: chapterContent,
                nodes: nodes
            )
            chapters.append(chapter)
        }

        guard !chapters.isEmpty else {
            throw EPUBError.invalidChapter("No readable chapters found in eBook manifest.")
        }

        return EPUBBook(
            title: title,
            author: author,
            language: language,
            rootDirectory: tempDir,
            opfRelativePath: opfPath,
            chapters: chapters
        )
    }

    /// Extracts translatable text from HTML/XHTML tags (<p>, <h1>..<h6>, <li>, <blockquote>, etc.)
    public static func extractTranslatableNodes(from html: String, startingId: Int) -> [TranslatableNode] {
        var nodes: [TranslatableNode] = []
        var nextId = startingId

        // Match content inside translatable block elements
        let pattern = #"(<(p|h[1-6]|li|blockquote|figcaption|title)[^>]*>)([\s\S]*?)(<\/\2>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsString = html as NSString
        let results = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in results {
            guard match.numberOfRanges >= 5 else { continue }
            let fullMatch = nsString.substring(with: match.range(at: 0))
            let tagOpen = nsString.substring(with: match.range(at: 1))
            let innerText = nsString.substring(with: match.range(at: 3))
            let tagClose = nsString.substring(with: match.range(at: 4))

            // Strip inner HTML tags to get raw translatable text
            let rawText = innerText.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !rawText.isEmpty {
                nodes.append(TranslatableNode(
                    id: nextId,
                    originalText: rawText,
                    translatedText: "",
                    fullMatch: fullMatch,
                    tagOpen: tagOpen,
                    tagClose: tagClose
                ))
                nextId += 1
            }
        }

        return nodes
    }

    /// Extracts clean sample text from a single chapter up to maxCharacters
    public static func extractChapterSampleText(from chapter: EPUBChapter, maxCharacters: Int = 20_000) -> String {
        var collected = ""
        for node in chapter.nodes {
            let trimmed = node.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if collected.isEmpty {
                collected = trimmed
            } else {
                collected += "\n\n" + trimmed
            }
            if collected.count >= maxCharacters {
                return String(collected.prefix(maxCharacters))
            }
        }
        return collected
    }

    /// Extracts clean sample text from initial chapter nodes up to maxCharacters
    public static func extractSampleText(from book: EPUBBook, maxCharacters: Int = 25_000) -> String {
        var collected = ""
        for chapter in book.chapters {
            for node in chapter.nodes {
                let trimmed = node.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if collected.isEmpty {
                    collected = trimmed
                } else {
                    collected += "\n\n" + trimmed
                }
                if collected.count >= maxCharacters {
                    return String(collected.prefix(maxCharacters))
                }
            }
        }
        return collected
    }

    /// Extracts stratified, cross-book sample text to capture major characters and characters appearing in later chapters
    public static func extractStratifiedSampleText(from book: EPUBBook, maxCharacters: Int = 30_000) -> String {
        guard !book.chapters.isEmpty else { return "" }

        // For books with 2 or fewer chapters, sequential extraction is sufficient
        if book.chapters.count <= 2 {
            return extractSampleText(from: book, maxCharacters: maxCharacters)
        }

        var sections: [String] = []
        var totalBudgetUsed = 0

        // 1. Cast / Dramatis Personae Check
        let castKeywords = ["character", "dramatis personae", "cast", "nhân vật", "danh sách nhân vật", "bảng nhân vật"]
        var castChapterIndices = Set<Int>()

        for (idx, ch) in book.chapters.enumerated() {
            let titleLower = ch.title.lowercased()
            let relLower = ch.relativePath.lowercased()
            if castKeywords.contains(where: { titleLower.contains($0) || relLower.contains($0) }) {
                castChapterIndices.insert(idx)
                let castSample = extractChapterSampleText(from: ch, maxCharacters: 4_000)
                if !castSample.isEmpty {
                    sections.append("[CAST / CHARACTERS LIST - \(ch.title)]:\n" + castSample)
                    totalBudgetUsed += castSample.count
                    if totalBudgetUsed >= maxCharacters / 3 {
                        break
                    }
                }
            }
        }

        let remainingBudget = maxCharacters - totalBudgetUsed
        // 2. Opening Anchor: 40% of remaining budget from early non-cast chapters
        let openingBudget = Int(Double(remainingBudget) * 0.40)
        var openingUsed = 0
        var earlyProcessedCount = 0

        for (idx, ch) in book.chapters.enumerated() {
            guard !castChapterIndices.contains(idx) else { continue }
            let sample = extractChapterSampleText(from: ch, maxCharacters: openingBudget - openingUsed)
            guard !sample.isEmpty else { continue }
            sections.append("--- [Opening Chapter: \(ch.title)] ---\n" + sample)
            openingUsed += sample.count
            earlyProcessedCount += 1
            if openingUsed >= openingBudget || earlyProcessedCount >= 2 {
                break
            }
        }
        totalBudgetUsed += openingUsed

        // 3. Distributed Milestone Slices: Remaining budget distributed across later chapters
        let distributedBudget = maxCharacters - totalBudgetUsed
        let remainingChapters = book.chapters.enumerated().filter { idx, _ in
            idx >= earlyProcessedCount && !castChapterIndices.contains(idx)
        }

        if !remainingChapters.isEmpty && distributedBudget > 1_000 {
            // Pick up to 8 milestone chapters evenly spaced
            let targetCount = min(8, remainingChapters.count)
            let step = Double(remainingChapters.count) / Double(targetCount)
            let perChapterBudget = max(800, distributedBudget / targetCount)

            var distributedUsed = 0
            for i in 0..<targetCount {
                let chosenIdx = Int(Double(i) * step)
                guard chosenIdx < remainingChapters.count else { break }
                let (chIndex, chapter) = remainingChapters[chosenIdx]

                let sample = extractChapterSampleText(from: chapter, maxCharacters: perChapterBudget)
                guard !sample.isEmpty else { continue }
                sections.append("--- [Milestone Chapter \(chIndex + 1): \(chapter.title)] ---\n" + sample)
                distributedUsed += sample.count
                if distributedUsed >= distributedBudget {
                    break
                }
            }
        }

        let result = sections.joined(separator: "\n\n")
        if result.count > maxCharacters {
            return String(result.prefix(maxCharacters))
        }
        return result
    }

    /// Injects translated nodes back into chapter XHTML
    public static func applyTranslations(to chapter: inout EPUBChapter) {
        var updatedHtml = chapter.originalContent
        for node in chapter.nodes {
            guard !node.translatedText.isEmpty else { continue }
            let replacement = "\(node.tagOpen)\(node.translatedText)\(node.tagClose)"
            updatedHtml = updatedHtml.replacingOccurrences(of: node.fullMatch, with: replacement)
        }
        chapter.translatedContent = updatedHtml
        chapter.isTranslated = true
    }

    /// Repackages the book directory into a standard .epub file
    public static func repack(book: EPUBBook, targetURL: URL, targetLanguageCode: String) throws {
        // 1. Write translated chapter files back to disk
        for chapter in book.chapters {
            let fileURL = book.rootDirectory.appendingPathComponent(chapter.relativePath)
            let folderURL = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try chapter.translatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // 2. Update dc:language in the OPF file
        let opfURL = book.rootDirectory.appendingPathComponent(book.opfRelativePath)
        if var opfContent = try? String(contentsOf: opfURL, encoding: .utf8) {
            opfContent = opfContent.replacingOccurrences(
                of: #"<dc:language>[^<]*<\/dc:language>"#,
                with: "<dc:language>\(targetLanguageCode)</dc:language>",
                options: .regularExpression
            )
            try? opfContent.write(to: opfURL, atomically: true, encoding: .utf8)
        }

        // 3. Remove existing target file if present
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        // 4. Repack using zip:
        // First zip the mimetype uncompressed
        let zipMime = Process()
        zipMime.currentDirectoryURL = book.rootDirectory
        zipMime.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipMime.arguments = ["-X0", targetURL.path, "mimetype"]
        try zipMime.run()
        zipMime.waitUntilExit()

        // Then zip everything else with compression
        let zipAll = Process()
        zipAll.currentDirectoryURL = book.rootDirectory
        zipAll.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipAll.arguments = ["-r9", targetURL.path, ".", "-x", "mimetype", "-x", "*.DS_Store"]
        try zipAll.run()
        zipAll.waitUntilExit()

        guard zipAll.terminationStatus == 0 else {
            throw EPUBError.zipExecutionFailed("Failed to repack EPUB archive.")
        }
    }

    /// Creates a complete, valid sample EPUB ebook for testing
    public static func createSampleEPUB(at targetURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SampleEPUB_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // mimetype
        try "application/epub+zip".write(to: tempDir.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)

        // META-INF/container.xml
        let metaDir = tempDir.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
        </container>
        """
        try containerXML.write(to: metaDir.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        // OEBPS
        let oebpsDir = tempDir.appendingPathComponent("OEBPS")
        try FileManager.default.createDirectory(at: oebpsDir, withIntermediateDirectories: true)

        let ch1 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
            <title>Chapter 1: The Cosmic Frontier</title>
        </head>
        <body>
            <h1>The Cosmic Frontier</h1>
            <p>From the dawn of human civilization, humanity has looked up at the night sky with wonder and curiosity.</p>
            <p>The universe stretches across billions of light-years, harboring hundreds of billions of galaxies, each containing trillions of celestial worlds.</p>
            <p>In this chapter, we explore how ancient stargazers mapped constellations and laid the groundwork for modern astrophysics.</p>
        </body>
        </html>
        """
        try ch1.write(to: oebpsDir.appendingPathComponent("chapter1.xhtml"), atomically: true, encoding: .utf8)

        let ch2 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
            <title>Chapter 2: Voyages to the Stars</title>
        </head>
        <body>
            <h1>Voyages to the Stars</h1>
            <p>Robotic spacecraft like Voyager, Cassini, and New Horizons have expanded our senses far beyond the comfort of Earth's atmosphere.</p>
            <p>We have witnessed cryovolcanoes on Enceladus, towering methane lakes on Titan, and the turbulent storms swirling across the face of Jupiter.</p>
            <p>As propulsion technologies evolve, interstellar missions to neighboring stars like Proxima Centauri are transforming from science fiction into achievable engineering.</p>
        </body>
        </html>
        """
        try ch2.write(to: oebpsDir.appendingPathComponent("chapter2.xhtml"), atomically: true, encoding: .utf8)

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookID" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Voyage to the Cosmos</dc:title>
                <dc:creator>Dr. Elena Rostova</dc:creator>
                <dc:language>en</dc:language>
                <dc:identifier id="BookID">urn:uuid:12345678-space-sample</dc:identifier>
            </metadata>
            <manifest>
                <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
            </manifest>
            <spine>
                <itemref idref="ch1"/>
                <itemref idref="ch2"/>
            </spine>
        </package>
        """
        try opf.write(to: oebpsDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        // Zip into targetURL
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        let zipMime = Process()
        zipMime.currentDirectoryURL = tempDir
        zipMime.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipMime.arguments = ["-X0", targetURL.path, "mimetype"]
        try zipMime.run()
        zipMime.waitUntilExit()

        let zipAll = Process()
        zipAll.currentDirectoryURL = tempDir
        zipAll.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipAll.arguments = ["-r9", targetURL.path, ".", "-x", "mimetype", "-x", "*.DS_Store"]
        try zipAll.run()
        zipAll.waitUntilExit()
    }

    // MARK: - XML / Regex Helpers
    private static func extractAttribute(named attr: String, in text: String) -> String? {
        let pattern = "\(attr)=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    private static func extractTagContent(named tag: String, in text: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)<\\/\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return (text as NSString).substring(with: match.range(at: 1))
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(for regexPattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        return results.map { match in
            (0..<match.numberOfRanges).map { rangeIdx in
                let r = match.range(at: rangeIdx)
                return r.location != NSNotFound ? nsString.substring(with: r) : ""
            }
        }
    }
}
