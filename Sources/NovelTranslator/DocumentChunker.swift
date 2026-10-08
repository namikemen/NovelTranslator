import Foundation

public struct DocumentChunk: Identifiable, Sendable, Codable {
    public let id: Int
    public let text: String
    public let isTranslatable: Bool
    public var translatedText: String
    public let delimiter: String

    public init(id: Int, text: String, isTranslatable: Bool = true, translatedText: String = "", delimiter: String = "\n\n") {
        self.id = id
        self.text = text
        self.isTranslatable = isTranslatable
        self.translatedText = translatedText
        self.delimiter = delimiter
    }
}

public struct DocumentChunker {
    /// Maximum character length per chunk to ensure reliable on-device translation
    public static let maxChunkLength = 1200

    /// Splits document into chunks separated by paragraphs, preserving formatting
    public static func chunk(document: String) -> [DocumentChunk] {
        guard !document.isEmpty else { return [] }

        // Split primarily by double newlines (paragraphs)
        let rawParagraphs = document.components(separatedBy: "\n\n")
        var chunks: [DocumentChunk] = []
        var nextId = 0

        for (pIndex, rawP) in rawParagraphs.enumerated() {
            let isLastParagraph = (pIndex == rawParagraphs.count - 1)
            let delimiter = isLastParagraph ? "" : "\n\n"

            let trimmed = rawP.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Preserved empty paragraph / whitespace
                chunks.append(DocumentChunk(
                    id: nextId,
                    text: rawP,
                    isTranslatable: false,
                    translatedText: rawP,
                    delimiter: delimiter
                ))
                nextId += 1
                continue
            }

            // If the paragraph is reasonably sized, keep it intact
            if rawP.count <= maxChunkLength {
                chunks.append(DocumentChunk(
                    id: nextId,
                    text: rawP,
                    isTranslatable: true,
                    translatedText: "",
                    delimiter: delimiter
                ))
                nextId += 1
            } else {
                // Split large paragraphs by single newlines or sentences
                let subLines = rawP.components(separatedBy: "\n")
                for (sIndex, subLine) in subLines.enumerated() {
                    let isLastSubLine = (sIndex == subLines.count - 1)
                    let subDelimiter = isLastSubLine ? delimiter : "\n"
                    let subTrimmed = subLine.trimmingCharacters(in: .whitespacesAndNewlines)

                    if subTrimmed.isEmpty {
                        chunks.append(DocumentChunk(
                            id: nextId,
                            text: subLine,
                            isTranslatable: false,
                            translatedText: subLine,
                            delimiter: subDelimiter
                        ))
                    } else if subLine.count <= maxChunkLength {
                        chunks.append(DocumentChunk(
                            id: nextId,
                            text: subLine,
                            isTranslatable: true,
                            translatedText: "",
                            delimiter: subDelimiter
                        ))
                    } else {
                        // Sentence or character window split
                        let subChunks = splitBySentences(subLine, maxLength: maxChunkLength)
                        for (scIndex, sc) in subChunks.enumerated() {
                            let isLastSc = (scIndex == subChunks.count - 1)
                            let scDelim = isLastSc ? subDelimiter : " "
                            chunks.append(DocumentChunk(
                                id: nextId,
                                text: sc,
                                isTranslatable: true,
                                translatedText: "",
                                delimiter: scDelim
                            ))
                            nextId += 1
                        }
                        continue
                    }
                    nextId += 1
                }
            }
        }

        return chunks
    }

    /// Reassembles chunks into full document text
    public static func assemble(chunks: [DocumentChunk], useTranslated: Bool = true) -> String {
        var output = ""
        for chunk in chunks {
            if useTranslated {
                if chunk.isTranslatable {
                    output += chunk.translatedText.isEmpty ? chunk.text : chunk.translatedText
                } else {
                    output += chunk.text
                }
            } else {
                output += chunk.text
            }
            output += chunk.delimiter
        }
        return output
    }

    private static func splitBySentences(_ text: String, maxLength: Int) -> [String] {
        var results: [String] = []

        // Break on sentence endings (. ! ?) followed by whitespace or quotes
        let pattern = #"(?<=[.!?]["'”]?)\s+"#
        var rawSentences: [String] = []
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = text as NSString
            var lastIdx = 0
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let sentenceRange = NSRange(location: lastIdx, length: match.range.location - lastIdx)
                let sentence = ns.substring(with: sentenceRange)
                if !sentence.isEmpty { rawSentences.append(sentence) }
                lastIdx = match.range.location + match.range.length
            }
            if lastIdx < ns.length {
                let remaining = ns.substring(with: NSRange(location: lastIdx, length: ns.length - lastIdx))
                if !remaining.isEmpty { rawSentences.append(remaining) }
            }
        }
        if rawSentences.isEmpty {
            rawSentences = [text]
        }

        var current = ""
        for sentence in rawSentences {
            if (current.isEmpty ? sentence : "\(current) \(sentence)").count <= maxLength {
                current = current.isEmpty ? sentence : "\(current) \(sentence)"
            } else {
                if !current.isEmpty {
                    results.append(current)
                    current = ""
                }
                // If a single sentence exceeds maxLength, fall back to word boundaries
                if sentence.count > maxLength {
                    let words = sentence.components(separatedBy: " ")
                    var subCurrent = ""
                    for word in words {
                        if (subCurrent.isEmpty ? word : "\(subCurrent) \(word)").count <= maxLength {
                            subCurrent = subCurrent.isEmpty ? word : "\(subCurrent) \(word)"
                        } else {
                            if !subCurrent.isEmpty { results.append(subCurrent) }
                            subCurrent = word
                        }
                    }
                    if !subCurrent.isEmpty {
                        current = subCurrent
                    }
                } else {
                    current = sentence
                }
            }
        }
        if !current.isEmpty {
            results.append(current)
        }
        return results
    }
}
