import Foundation

public struct BatchXMLParser: Sendable {

    /// Formats batch nodes and optional rolling context into a parameterized LLM user prompt
    public static func buildUserPrompt(
        nodes: [TranslatableNode],
        from sourceLang: String,
        to targetLang: String,
        previousContext: String? = nil
    ) -> String {
        var sections: [String] = []

        if let context = previousContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            let boundedContext = context.count > 3000 ? String(context.suffix(3000)) : context
            sections.append("""
            [PREVIOUS CONTEXT - For reference only to maintain narrative continuity, tone, and pronoun consistency. DO NOT translate this section]:
            <prev_context>
            \(boundedContext)
            </prev_context>
            """)
        }

        let paragraphsBlock = nodes.map { "<p id=\"\($0.id)\">\($0.originalText)</p>" }.joined(separator: "\n")
        sections.append("""
        [PARAGRAPHS TO TRANSLATE]:
        Translate the following paragraphs from \(sourceLang) into \(targetLang). Preserve each paragraph inside its exact <p id="X">...</p> tag. Do not omit, combine, or change any ID:

        \(paragraphsBlock)
        """)

        return sections.joined(separator: "\n\n")
    }

    /// Parses LLM response into a dictionary of [nodeId: translatedText] and reports missing IDs
    public static func parse(
        response: String,
        expectedNodeIds: [Int]
    ) -> BatchTranslationResult {
        // 1. Clean thinking tags and markdown code blocks
        var cleaned = LLMTranslationService.cleanAndValidateTranslation(rawResponse: response, originalText: "")

        if cleaned.hasPrefix("```xml") {
            cleaned = String(cleaned.dropFirst(6))
        } else if cleaned.hasPrefix("```markdown") {
            cleaned = String(cleaned.dropFirst(11))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        var completed: [Int: String] = [:]
        let expectedSet = Set(expectedNodeIds)

        // 2. Defensive regex preventing unclosed tags from swallowing following tags, with flexible attribute matching
        let pattern = #"(?i)<(?:p|h[1-6]|blockquote|li|div)\b[^>]*?\bid\s*=\s*["']?(\d+)["']?[^>]*>((?:(?!<(?:p|h[1-6]|blockquote|li|div)\b)[\s\S])*?)<\/(?:p|h[1-6]|blockquote|li|div)>"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let ns = cleaned as NSString
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let idString = ns.substring(with: match.range(at: 1))
                let content = ns.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let nodeId = Int(idString), expectedSet.contains(nodeId), !content.isEmpty {
                    completed[nodeId] = content
                }
            }
        }

        // 2b. Secondary Fallback for unclosed final tag: if an expected tag appears near the end without closing tag, or formatted as "[id] text"
        if completed.count < expectedNodeIds.count {
            let linePattern = #"(?mi)^\s*(?:\[(\d+)\]|p?id\s*[:=]\s*(\d+)\s*[:\-\.]?)\s*(.+?)$"#
            if let lineRegex = try? NSRegularExpression(pattern: linePattern, options: []) {
                let ns = cleaned as NSString
                let lineMatches = lineRegex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
                for match in lineMatches {
                    let idRange1 = match.range(at: 1)
                    let idRange2 = match.range(at: 2)
                    let textRange = match.range(at: 3)

                    let idStr = (idRange1.location != NSNotFound) ? ns.substring(with: idRange1) : ns.substring(with: idRange2)
                    if let nodeId = Int(idStr), expectedSet.contains(nodeId), completed[nodeId] == nil {
                        let text = ns.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            completed[nodeId] = text
                        }
                    }
                }
            }
        }

        // 3. Audit missing IDs
        let missing = expectedNodeIds.filter { completed[$0] == nil }

        return BatchTranslationResult(
            completedTranslations: completed,
            missingNodeIds: missing,
            rawResponse: response
        )
    }
}
