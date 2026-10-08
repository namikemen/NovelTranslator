import Testing
import Foundation
@testable import NovelTranslator

@Suite("Batch Chunker Tests")
struct BatchChunkerTests {

    @Test("Empty node list produces no batches")
    func testEmptyNodes() {
        let batches = BatchChunker.createBatches(from: [], chapterIndex: 0)
        #expect(batches.isEmpty)
    }

    @Test("Nodes under target word count form a single batch")
    func testSingleBatch() {
        let nodes = [
            TranslatableNode(id: 1, originalText: "Paragraph one with some text.", fullMatch: "<p>Paragraph one with some text.</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 2, originalText: "Paragraph two with another sentence.", fullMatch: "<p>Paragraph two with another sentence.</p>", tagOpen: "<p>", tagClose: "</p>")
        ]
        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 0, targetWordCount: 1200)

        #expect(batches.count == 1)
        #expect(batches[0].id == 0)
        #expect(batches[0].chapterIndex == 0)
        #expect(batches[0].nodes.count == 2)
        #expect(batches[0].wordCount == 10)
    }

    @Test("Nodes exceeding target word count split into multiple contiguous batches without mutating node text")
    func testWordLimitSplitting() {
        let text50Words = Array(repeating: "word", count: 50).joined(separator: " ")
        var nodes: [TranslatableNode] = []
        for i in 1...10 {
            nodes.append(TranslatableNode(
                id: i,
                originalText: "Node \(i) \(text50Words)",
                fullMatch: "<p>Node \(i) \(text50Words)</p>",
                tagOpen: "<p>",
                tagClose: "</p>"
            ))
        }

        // Each node is ~52 words. With target 150 words, each batch should hold ~3 nodes.
        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 1, targetWordCount: 150)

        #expect(batches.count > 1)
        let totalBatchedNodes = batches.reduce(0) { $0 + $1.nodes.count }
        #expect(totalBatchedNodes == 10)
        #expect(batches[0].nodes.first?.originalText.hasPrefix("Node 1") == true)
    }

    @Test("Heading boundary with substantial accumulated words triggers batch split")
    func testHeadingSplits() {
        let text250Words = Array(repeating: "word", count: 250).joined(separator: " ")
        let nodes = [
            TranslatableNode(id: 1, originalText: text250Words, fullMatch: "<p>\(text250Words)</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 2, originalText: "Section Two Title", fullMatch: "<h2>Section Two Title</h2>", tagOpen: "<h2>", tagClose: "</h2>"),
            TranslatableNode(id: 3, originalText: "Content of section two.", fullMatch: "<p>Content of section two.</p>", tagOpen: "<p>", tagClose: "</p>")
        ]

        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 0, targetWordCount: 1200)

        #expect(batches.count == 2)
        #expect(batches[0].nodes.count == 1)
        #expect(batches[0].nodes[0].id == 1)
        #expect(batches[1].nodes.count == 2)
        #expect(batches[1].nodes[0].id == 2)
    }

    @Test("Consecutive headings do not create single-word micro batches")
    func testConsecutiveHeadingsDoNotMicroSplit() {
        let nodes = [
            TranslatableNode(id: 1, originalText: "Chapter 1", fullMatch: "<h1>Chapter 1</h1>", tagOpen: "<h1>", tagClose: "</h1>"),
            TranslatableNode(id: 2, originalText: "The Departure", fullMatch: "<h2>The Departure</h2>", tagOpen: "<h2>", tagClose: "</h2>"),
            TranslatableNode(id: 3, originalText: "The sun was rising over the distant hills.", fullMatch: "<p>The sun was rising...</p>", tagOpen: "<p>", tagClose: "</p>")
        ]

        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 0, targetWordCount: 1200)

        #expect(batches.count == 1)
        #expect(batches[0].nodes.count == 3)
    }

    @Test("Already translated nodes preserve contiguity and are omitted from batches")
    func testOmitsAlreadyTranslatedNodes() {
        var node1 = TranslatableNode(id: 1, originalText: "First", fullMatch: "<p>First</p>", tagOpen: "<p>", tagClose: "</p>")
        node1.translatedText = "Đầu tiên"
        let node2 = TranslatableNode(id: 2, originalText: "Second", fullMatch: "<p>Second</p>", tagOpen: "<p>", tagClose: "</p>")

        let batches = BatchChunker.createBatches(from: [node1, node2], chapterIndex: 0)

        #expect(batches.count == 1)
        #expect(batches[0].nodes.count == 1)
        #expect(batches[0].nodes[0].id == 2)
    }

    @Test("Max node ceiling of 30 prevents infinite batch size on zero-space languages")
    func testMaxNodeCeiling() {
        var nodes: [TranslatableNode] = []
        for i in 1...65 {
            nodes.append(TranslatableNode(id: i, originalText: "测试段落\(i)", fullMatch: "<p>测试段落\(i)</p>", tagOpen: "<p>", tagClose: "</p>"))
        }

        let batches = BatchChunker.createBatches(from: nodes, chapterIndex: 0, targetWordCount: 5000)

        #expect(batches.count >= 3)
        #expect(batches[0].nodes.count <= 30)
        #expect(batches[1].nodes.count <= 30)
    }
}
