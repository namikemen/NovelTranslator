import Testing
import Foundation
@testable import NovelTranslator

@Suite("Batch XML Parser Tests")
struct BatchXMLParserTests {

    @Test("Builds user prompt with formatted paragraphs and no context")
    func testBuildUserPromptWithoutContext() {
        let nodes = [
            TranslatableNode(id: 101, originalText: "Hello world.", fullMatch: "<p>Hello world.</p>", tagOpen: "<p>", tagClose: "</p>"),
            TranslatableNode(id: 102, originalText: "Second line.", fullMatch: "<p>Second line.</p>", tagOpen: "<p>", tagClose: "</p>")
        ]

        let prompt = BatchXMLParser.buildUserPrompt(nodes: nodes, from: "English", to: "Vietnamese", previousContext: nil)

        #expect(!prompt.contains("<prev_context>"))
        #expect(prompt.contains("<p id=\"101\">Hello world.</p>"))
        #expect(prompt.contains("<p id=\"102\">Second line.</p>"))
        #expect(prompt.contains("from English into Vietnamese"))
    }

    @Test("Builds user prompt with bounded rolling context")
    func testBuildUserPromptWithContext() {
        let nodes = [
            TranslatableNode(id: 101, originalText: "Hello world.", fullMatch: "<p>Hello world.</p>", tagOpen: "<p>", tagClose: "</p>")
        ]
        let context = "Original: \"Prev\"\nTranslated: \"Trước\""

        let prompt = BatchXMLParser.buildUserPrompt(nodes: nodes, from: "English", to: "Vietnamese", previousContext: context)

        #expect(prompt.contains("<prev_context>"))
        #expect(prompt.contains("Original: \"Prev\""))
        #expect(prompt.contains("<p id=\"101\">Hello world.</p>"))
    }

    @Test("Parses standard XML paragraph tags and ignores thinking tags")
    func testStandardXMLParsing() {
        let rawResponse = """
        <think>Translating chapter content...</think>
        <p id="1">Xin chào thế giới.</p>
        <p id="2">Đoạn văn thứ hai.</p>
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [1, 2])

        #expect(result.missingNodeIds.isEmpty)
        #expect(result.completedTranslations[1] == "Xin chào thế giới.")
        #expect(result.completedTranslations[2] == "Đoạn văn thứ hai.")
    }

    @Test("Preserves dialogue quotation marks and inline formatting")
    func testPreservesQuotesAndInlineTags() {
        let rawResponse = """
        <p id="10">"Chúng ta không thể quay lại," chàng nói.</p>
        <p id="11">Cô ấy nhìn vào <em>ánh lửa</em> bập bùng.</p>
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [10, 11])

        #expect(result.completedTranslations[10] == "\"Chúng ta không thể quay lại,\" chàng nói.")
        #expect(result.completedTranslations[11] == "Cô ấy nhìn vào <em>ánh lửa</em> bập bùng.")
    }

    @Test("Parses attributes with varying quotes and non-p tag variants")
    func testAttributeAndTagVariants() {
        let rawResponse = """
        ```xml
        <h2 id='100'>Chương 1</h2>
        <p class="story" id=101>Nội dung câu chuyện.</p>
        <blockquote id="102">Một danh ngôn.</blockquote>
        ```
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [100, 101, 102])

        #expect(result.missingNodeIds.isEmpty)
        #expect(result.completedTranslations[100] == "Chương 1")
        #expect(result.completedTranslations[101] == "Nội dung câu chuyện.")
        #expect(result.completedTranslations[102] == "Một danh ngôn.")
    }

    @Test("Identifies missing node IDs and discards hallucinated IDs")
    func testMissingAndHallucinatedIDs() {
        let rawResponse = """
        <p id="1">Đoạn một.</p>
        <p id="999">Đoạn ảo hallucination.</p>
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [1, 2, 3])

        #expect(result.completedTranslations[1] == "Đoạn một.")
        #expect(result.completedTranslations[999] == nil)
        #expect(result.missingNodeIds == [2, 3])
    }

    @Test("Defensive regex prevents unclosed tags from swallowing subsequent paragraphs")
    func testUnclosedTagDoesNotSwallowNextNode() {
        let rawResponse = """
        <p id="1">Đoạn một không có đóng thẻ
        <p id="2">Đoạn hai có đóng thẻ.</p>
        """

        let result = BatchXMLParser.parse(response: rawResponse, expectedNodeIds: [1, 2])

        #expect(result.completedTranslations[2] == "Đoạn hai có đóng thẻ.")
        #expect(result.missingNodeIds == [1])
    }
}
