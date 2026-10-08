import Foundation

public struct TranslationBatch: Identifiable, Sendable {
    public let id: Int
    public let chapterIndex: Int
    public let nodes: [TranslatableNode]
    public let targetWordCount: Int

    public var wordCount: Int {
        nodes.reduce(0) { $0 + max(1, $1.originalText.split { $0.isWhitespace || $0.isNewline }.count) }
    }

    public init(id: Int, chapterIndex: Int, nodes: [TranslatableNode], targetWordCount: Int) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.nodes = nodes
        self.targetWordCount = targetWordCount
    }
}

public struct BatchTranslationResult: Sendable {
    public let completedTranslations: [Int: String]
    public let missingNodeIds: [Int]
    public let rawResponse: String

    public init(completedTranslations: [Int: String], missingNodeIds: [Int], rawResponse: String) {
        self.completedTranslations = completedTranslations
        self.missingNodeIds = missingNodeIds
        self.rawResponse = rawResponse
    }
}

public struct BatchChunker: Sendable {
    public static let defaultTargetWordCount = 1200
    public static let maxNodesPerBatch = 30

    public static func createBatches(
        from nodes: [TranslatableNode],
        chapterIndex: Int,
        targetWordCount: Int = defaultTargetWordCount
    ) -> [TranslationBatch] {
        guard !nodes.isEmpty else { return [] }

        let safeTargetWords = max(200, targetWordCount)
        var batches: [TranslationBatch] = []
        var currentNodes: [TranslatableNode] = []
        var currentWords = 0
        var batchId = 0

        for node in nodes {
            if !node.translatedText.isEmpty {
                if !currentNodes.isEmpty {
                    batches.append(TranslationBatch(
                        id: batchId,
                        chapterIndex: chapterIndex,
                        nodes: currentNodes,
                        targetWordCount: safeTargetWords
                    ))
                    batchId += 1
                    currentNodes = []
                    currentWords = 0
                }
                continue
            }

            let nodeWords = max(1, node.originalText.split { $0.isWhitespace || $0.isNewline }.count)
            let isHeading = node.tagOpen.range(of: #"<h[1-6]\b"#, options: [.regularExpression, .caseInsensitive]) != nil

            let shouldSplit = (isHeading && currentWords >= 200)
                || (currentWords + nodeWords > safeTargetWords)
                || (currentNodes.count >= maxNodesPerBatch)

            if shouldSplit && !currentNodes.isEmpty {
                batches.append(TranslationBatch(
                    id: batchId,
                    chapterIndex: chapterIndex,
                    nodes: currentNodes,
                    targetWordCount: safeTargetWords
                ))
                batchId += 1
                currentNodes = []
                currentWords = 0
            }

            currentNodes.append(node)
            currentWords += nodeWords
        }

        if !currentNodes.isEmpty {
            batches.append(TranslationBatch(
                id: batchId,
                chapterIndex: chapterIndex,
                nodes: currentNodes,
                targetWordCount: safeTargetWords
            ))
        }

        return batches
    }

    /// Converts translatable DocumentChunks into TranslationBatches for batched document translation
    public static func createBatches(
        from chunks: [DocumentChunk],
        targetWordCount: Int = defaultTargetWordCount
    ) -> [TranslationBatch] {
        let translatableNodes = chunks.compactMap { chunk -> TranslatableNode? in
            guard chunk.isTranslatable else { return nil }
            return TranslatableNode(
                id: chunk.id,
                originalText: chunk.text,
                translatedText: chunk.translatedText,
                fullMatch: chunk.text,
                tagOpen: "<p>",
                tagClose: "</p>"
            )
        }
        return createBatches(from: translatableNodes, chapterIndex: 0, targetWordCount: targetWordCount)
    }
}
