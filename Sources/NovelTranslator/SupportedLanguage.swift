import Foundation

public struct SupportedLanguage: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let code: String?

    public var language: Locale.Language? {
        guard let code else { return nil }
        return Locale.Language(identifier: code)
    }

    public static let autoDetect = SupportedLanguage(id: "auto", name: "Auto-Detect", code: nil)

    public static let allTargets: [SupportedLanguage] = [
        SupportedLanguage(id: "en", name: "English (US)", code: "en-US"),
        SupportedLanguage(id: "es", name: "Spanish", code: "es-ES"),
        SupportedLanguage(id: "fr", name: "French", code: "fr-FR"),
        SupportedLanguage(id: "de", name: "German", code: "de-DE"),
        SupportedLanguage(id: "it", name: "Italian", code: "it-IT"),
        SupportedLanguage(id: "ja", name: "Japanese", code: "ja-JP"),
        SupportedLanguage(id: "zh-Hans", name: "Chinese (Simplified)", code: "zh-Hans"),
        SupportedLanguage(id: "zh-Hant", name: "Chinese (Traditional)", code: "zh-Hant"),
        SupportedLanguage(id: "ko", name: "Korean", code: "ko-KR"),
        SupportedLanguage(id: "pt-BR", name: "Portuguese (Brazil)", code: "pt-BR"),
        SupportedLanguage(id: "ru", name: "Russian", code: "ru-RU"),
        SupportedLanguage(id: "ar", name: "Arabic", code: "ar-SA"),
        SupportedLanguage(id: "nl", name: "Dutch", code: "nl-NL"),
        SupportedLanguage(id: "pl", name: "Polish", code: "pl-PL"),
        SupportedLanguage(id: "tr", name: "Turkish", code: "tr-TR"),
        SupportedLanguage(id: "vi", name: "Vietnamese", code: "vi-VN"),
        SupportedLanguage(id: "id", name: "Indonesian", code: "id-ID"),
        SupportedLanguage(id: "th", name: "Thai", code: "th-TH"),
        SupportedLanguage(id: "uk", name: "Ukrainian", code: "uk-UA")
    ]

    public static var allSources: [SupportedLanguage] {
        [autoDetect] + allTargets
    }
}
