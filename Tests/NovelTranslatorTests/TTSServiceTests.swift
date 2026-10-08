import Testing
import Foundation
@testable import NovelTranslator

@Suite("TTS Service & Player Tests")
struct TTSServiceTests {

    @Test("Text cleaning removes HTML/XHTML tags")
    func testCleanHTMLTags() {
        let input = "<p class=\"calibre1\">Đây là đoạn văn <strong>rất quan trọng</strong> trong sách.</p>"
        let cleaned = TTSService.cleanTextForSpeech(input)
        #expect(cleaned == "Đây là đoạn văn rất quan trọng trong sách.")
    }

    @Test("Text cleaning strips Markdown links, headers, and images")
    func testCleanMarkdownFormatting() {
        let input = """
        # Chương 1: Bắt Đầu

        ![Ảnh minh họa](cover.jpg)
        Xem thêm thông tin tại [trang tác giả](https://example.com/author).
        Đây là văn bản **in đậm** và *in nghiêng*.
        """
        let cleaned = TTSService.cleanTextForSpeech(input)
        #expect(!cleaned.contains("#"))
        #expect(!cleaned.contains("![Ảnh minh họa]"))
        #expect(!cleaned.contains("https://example.com/author"))
        #expect(cleaned.contains("trang tác giả"))
        #expect(cleaned.contains("in đậm"))
        #expect(cleaned.contains("in nghiêng"))
    }

    @Test("Text cleaning removes page numbers and inline footnote references")
    func testCleanFootnotesAndPageNumbers() {
        let input = """
        247 / 448
        Các nhà khoa học phát hiện 146 , bộ gen có cấu trúc đặc biệt) .
        """
        let cleaned = TTSService.cleanTextForSpeech(input)
        #expect(!cleaned.contains("247 / 448"))
        #expect(!cleaned.contains("146 ,"))
    }

    @Test("Format time utility formats seconds into mm:ss string")
    func testFormatTime() {
        #expect(AudioPlayerManager.formatTime(0) == "00:00")
        #expect(AudioPlayerManager.formatTime(45) == "00:45")
        #expect(AudioPlayerManager.formatTime(65) == "01:05")
        #expect(AudioPlayerManager.formatTime(600) == "10:00")
    }

    @Test("Cached audio URL generates expected filename and path")
    @MainActor
    func testCachedAudioURL() {
        let manager = AudioPlayerManager.shared
        let url = manager.cachedAudioURL(for: "Test Book", chapterIndex: 2, voiceId: "Trúc Ly")
        #expect(url.pathExtension == "wav")
        #expect(url.lastPathComponent.contains("Test_Book"))
        #expect(url.lastPathComponent.contains("ch2"))
        #expect(url.lastPathComponent.contains("Tr_c_Ly"))
    }

    @Test("Vieneu default voices list contains Trúc Ly and preset voices")
    func testVieneuVoicesAvailable() async {
        let service = TTSService()
        let voices = await service.getAvailableVoices(engine: .vieneu)
        #expect(!voices.isEmpty)
        #expect(voices.contains(where: { $0.id == "Trúc Ly" }))
    }

    @Test("TTSBatchManifest correctly encodes and decodes JSON")
    func testManifestJSONCodable() throws {
        let manifest = TTSBatchManifest(
            voice: "Trúc Ly",
            speed: 1.25,
            output_dir: "/tmp/audio",
            chapters: [
                TTSChapterManifestItem(id: "ch1", title: "Chương 1", text: "Xin chào.", output_filename: "001_ch1.wav")
            ]
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TTSBatchManifest.self, from: data)
        #expect(decoded.voice == "Trúc Ly")
        #expect(decoded.speed == 1.25)
        #expect(decoded.chapters.count == 1)
        #expect(decoded.chapters[0].title == "Chương 1")
    }
}
