import Foundation

public struct CharacterBibleFilter: Sendable {
    /// Resolves the effective characters, relationships, and notes for a chapter (merging global and local scope)
    public static func effectiveScope(
        forChapterId chapterId: String?,
        in bible: CharacterBible
    ) -> (characters: [CharacterProfile], relationships: [RelationshipPair], notes: String) {
        guard let chapterId, let local = bible.chapterScopes[chapterId] else {
            return (bible.characters, bible.relationships, bible.generalNotes)
        }

        // Merge characters: local characters override matching global by id or lowercase name
        var charMap: [String: CharacterProfile] = [:]
        for c in bible.characters {
            charMap[c.id] = c
            charMap[c.name.lowercased()] = c
        }
        for c in local.characters {
            charMap[c.id] = c
            charMap[c.name.lowercased()] = c
        }
        var uniqueChars: [CharacterProfile] = []
        var seenIds = Set<String>()
        for c in local.characters + bible.characters {
            if !seenIds.contains(c.id) {
                seenIds.insert(c.id)
                uniqueChars.append(c)
            }
        }

        // Merge relationships: local relationship overrides matching source->target pair
        var relMap: [String: RelationshipPair] = [:]
        for r in bible.relationships {
            relMap["\(r.sourceCharacterId)->\(r.targetCharacterId)"] = r
        }
        for r in local.relationships {
            relMap["\(r.sourceCharacterId)->\(r.targetCharacterId)"] = r
        }
        let mergedRelationships = Array(relMap.values)

        var mergedNotes = bible.generalNotes
        if !local.notes.isEmpty {
            mergedNotes = mergedNotes.isEmpty ? local.notes : "\(mergedNotes)\n[Chapter Note]: \(local.notes)"
        }

        return (uniqueChars, mergedRelationships, mergedNotes)
    }

    /// Filters the character bible to return only relationship pairs active in the specified chapter text.
    public static func filterRelationships(
        in bible: CharacterBible,
        forChapterText chapterText: String,
        chapterId: String? = nil
    ) -> [RelationshipPair] {
        guard !chapterText.isEmpty else { return [] }

        let (effectiveChars, effectiveRels, _) = effectiveScope(forChapterId: chapterId, in: bible)

        // Find which characters are present in the chapter text using word boundaries
        var presentCharacterIds = Set<String>()

        for character in effectiveChars {
            if isCharacterPresent(character, in: chapterText) {
                presentCharacterIds.insert(character.id)
            }
        }

        let isFirstPerson = (bible.narrativePOV == .firstPerson)
        let narratorId = bible.narratorCharacterId

        return effectiveRels.filter { pair in
            let sourcePresent = presentCharacterIds.contains(pair.sourceCharacterId)
            let targetPresent = presentCharacterIds.contains(pair.targetCharacterId)

            if sourcePresent && targetPresent {
                return true
            }

            // In first-person POV, narrator is always present in scene even if not speaking their own name
            if isFirstPerson, let narratorId {
                if pair.sourceCharacterId == narratorId && targetPresent {
                    return true
                }
                if pair.targetCharacterId == narratorId && sourcePresent {
                    return true
                }
            }

            return false
        }
    }

    private static func isCharacterPresent(_ character: CharacterProfile, in text: String) -> Bool {
        let tokens = [character.name] + character.aliases
        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: trimmed))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: (text as NSString).length)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - JIT Candidate Discovery Heuristic
    public struct CandidateEntity: Identifiable, Sendable, Codable, Equatable, Hashable {
        public var id: String { name }
        public let name: String
        public let occurrenceCount: Int
        public let sampleExcerpts: [String]

        public init(name: String, occurrenceCount: Int, sampleExcerpts: [String] = []) {
            self.name = name
            self.occurrenceCount = occurrenceCount
            self.sampleExcerpts = sampleExcerpts
        }
    }

    public static let commonStopwords: Set<String> = [
        // Days & Months
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
        // Book structure
        "Chapter", "Book", "Volume", "Section", "Part", "Page", "Title", "Prologue", "Epilogue",
        // Pronouns & Determiners
        "The", "They", "There", "This", "That", "These", "Those", "Then", "Thus", "Therefore",
        "Here", "Where", "When", "Why", "What", "How", "Who", "Whom", "Whose", "Which",
        "He", "She", "It", "You", "We", "I", "His", "Her", "My", "Our", "Your", "Their", "Its",
        "Him", "Them", "Us", "Me", "Mine", "Yours", "Hers", "Ours", "Theirs",
        // Prepositions & Conjunctions
        "And", "But", "For", "Nor", "So", "Yet", "In", "On", "At", "To", "With", "From", "By", "As", "If",
        "Because", "Although", "Since", "After", "Before", "While", "Even", "Just", "Only", "Until", "Unless",
        "Through", "Across", "Behind", "Between", "Among", "Against", "About", "Around", "Over", "Under",
        "Into", "Onto", "Upon", "Within", "Without", "Toward", "Towards",
        // Common Adverbs & Discourse
        "Now", "Well", "Yes", "No", "Not", "Oh", "Ah", "One", "Two", "First", "Second",
        "Once", "Suddenly", "Meanwhile", "However", "Instead", "Perhaps", "Maybe", "Indeed",
        "Every", "Each", "All", "Some", "Any", "Many", "Much", "Few", "Several", "Both",
        "Other", "Another", "Such", "Nothing", "Something", "Anything", "Everything",
        "Someone", "Anyone", "Everyone", "Nobody", "Somebody", "Anybody",
        // Verbs & Auxiliaries
        "Please", "Could", "Would", "Should", "Can", "Might", "Must", "Will", "Won",
        "Do", "Did", "Does", "Don", "Doesn", "Didn", "Wouldn", "Couldn", "Shouldn",
        "Is", "Are", "Was", "Were", "Am", "Been", "Being", "Be",
        "Have", "Has", "Had", "Having", "Let", "Okay", "Thank", "Thanks", "Huh", "Um", "Uh",
        // Numbers
        "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Twenty", "Thirty", "Hundred", "Thousand",
        // Generic / Common Conversational Words
        "Besides", "According", "Soon", "Later", "Again", "Still", "Already", "Always", "Never",
        "Sure", "Right", "Really", "Actually", "Finally", "Slowly", "Quickly", "Instantly",
        "Tell", "Excuse", "Look", "Listen", "Wait", "Come", "Of", "Next", "Back", "Looking",
        "Mom", "Dad", "Mother", "Father", "Brother", "Sister", "Son", "Daughter"
    ]

    /// Scans text for recurring capitalized entity names that do not match existing known characters in the Bible.
    public static func scanUnknownEntities(
        in text: String,
        existingBible: CharacterBible,
        chapterId: String? = nil,
        minOccurrences: Int = 3
    ) -> [CandidateEntity] {
        guard !text.isEmpty else { return [] }

        let (effectiveChars, _, _) = effectiveScope(forChapterId: chapterId, in: existingBible)
        var knownTokens = Set<String>()
        for char in effectiveChars {
            knownTokens.insert(char.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            for alias in char.aliases {
                knownTokens.insert(alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        let leadingStopwordsRegex = "(?:The|A|An|They|There|This|That|These|Those|Then|Thus|Therefore|Here|Where|When|Why|What|How|Who|Whom|Whose|Which|And|But|For|Nor|So|Yet|In|On|At|To|With|From|By|As|If|Because|Although|Since|After|Before|While|Even|Just|Only|Now|Well|Yes|No|Not|Oh|Ah|Once|Suddenly|Meanwhile|However|Instead|Perhaps|Maybe|Indeed|Every|Each|All|Some|Any|Many|Much|Few|Several|Both|Other|Another|Such|Nothing|Something|Anything|Everything|Someone|Anyone|Everyone|Nobody|Somebody|Anybody)"

        let twoWordPattern = "\\b(?!" + leadingStopwordsRegex + "\\b)[A-Z][a-z]{1,20}\\s+[A-Z][a-z]{1,20}\\b"
        let oneWordPattern = "\\b(?!" + leadingStopwordsRegex + "\\b)[A-Z][a-z]{1,20}\\b"

        var counts: [String: Int] = [:]
        var excerpts: [String: [String]] = [:]

        var sentenceRanges: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences]) { _, range, _, _ in
            sentenceRanges.append(NSRange(range, in: text))
        }

        func addCandidate(_ candidate: String, matchRange: NSRange) {
            let words = candidate.split(separator: " ").map(String.init)
            if words.contains(where: { commonStopwords.contains($0) }) { return }
            if knownTokens.contains(candidate.lowercased()) { return }

            counts[candidate, default: 0] += 1
            if excerpts[candidate] == nil {
                excerpts[candidate] = []
            }
            if let list = excerpts[candidate], list.count < 3 {
                if let sRange = sentenceRanges.first(where: { NSIntersectionRange($0, matchRange).length > 0 }) {
                    let sentence = nsText.substring(with: sRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !list.contains(sentence) {
                        excerpts[candidate]?.append(sentence)
                    }
                }
            }
        }

        // 1. Two-word pass
        if let regex2 = try? NSRegularExpression(pattern: twoWordPattern) {
            let matches = regex2.matches(in: text, options: [], range: fullRange)
            for m in matches {
                let candidate = nsText.substring(with: m.range)
                addCandidate(candidate, matchRange: m.range)
            }
        }

        // 2. Single-word pass for standalone names
        let twoWordCandidates = Set(counts.keys)
        if let regex1 = try? NSRegularExpression(pattern: oneWordPattern) {
            let matches = regex1.matches(in: text, options: [], range: fullRange)
            for m in matches {
                let candidate = nsText.substring(with: m.range)
                let isPartOfTwoWord = twoWordCandidates.contains(where: { $0.contains(candidate) })
                if !isPartOfTwoWord {
                    addCandidate(candidate, matchRange: m.range)
                }
            }
        }

        var results: [CandidateEntity] = []
        for (name, count) in counts {
            if count >= minOccurrences {
                results.append(CandidateEntity(name: name, occurrenceCount: count, sampleExcerpts: excerpts[name] ?? []))
            }
        }

        return results.sorted { $0.occurrenceCount > $1.occurrenceCount }
    }

    /// Scans all chapters across the entire EPUB book to identify top recurring character entities deterministically.
    /// Guarantees that characters from any chapter (early, middle, or late) are accounted for without sampling gaps.
    public static func scanBookEntities(
        in book: EPUBBook,
        existingBible: CharacterBible? = nil,
        minOccurrences: Int = 2,
        maxCandidates: Int = 30
    ) -> [CandidateEntity] {
        guard !book.chapters.isEmpty else { return [] }

        var knownTokens = Set<String>()
        if let existing = existingBible {
            for char in existing.characters {
                knownTokens.insert(char.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                for alias in char.aliases {
                    knownTokens.insert(alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                }
            }
        }

        let titlePattern = "(?:Mr\\.?|Mrs\\.?|Miss|Ms\\.?|Dr\\.?|Lord|Lady|Sir|Captain|Colonel|Major|General|Father|Mother|Uncle|Aunt|Professor|Detective|Inspector|Officer)\\s+[A-Z][a-z]{1,20}"
        let twoWordPattern = "\\b[A-Z][a-z]{1,20}\\s+[A-Z][a-z]{1,20}\\b"
        let oneWordPattern = "\\b[A-Z][a-z]{1,20}\\b"

        var twoWordCounts: [String: Int] = [:]
        var titleCounts: [String: Int] = [:]
        var singleWordCounts: [String: Int] = [:]
        var tokenExcerpts: [String: [String]] = [:]

        for chapter in book.chapters {
            let chapterText = chapter.nodes.map(\.originalText).joined(separator: "\n\n")
            guard !chapterText.isEmpty else { continue }

            let nsText = chapterText as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            var sentenceRanges: [NSRange] = []
            chapterText.enumerateSubstrings(in: chapterText.startIndex..., options: [.bySentences]) { _, range, _, _ in
                sentenceRanges.append(NSRange(range, in: chapterText))
            }

            func recordExcerpt(for token: String, matchRange: NSRange) {
                if tokenExcerpts[token] == nil {
                    tokenExcerpts[token] = []
                }
                if let list = tokenExcerpts[token], list.count < 3 {
                    if let sRange = sentenceRanges.first(where: { NSIntersectionRange($0, matchRange).length > 0 }) {
                        let sentence = nsText.substring(with: sRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !list.contains(sentence) && sentence.count <= 220 {
                            tokenExcerpts[token]?.append(sentence)
                        }
                    }
                }
            }

            // A. Title pass
            if let regexTitle = try? NSRegularExpression(pattern: titlePattern) {
                for m in regexTitle.matches(in: chapterText, options: [], range: fullRange) {
                    let name = nsText.substring(with: m.range).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    let words = name.split(separator: " ").map(String.init)
                    if words.count == 2 && !commonStopwords.contains(words[1]) {
                        titleCounts[name, default: 0] += 1
                        recordExcerpt(for: name, matchRange: m.range)
                    }
                }
            }

            // B. Two-word pass
            if let regex2 = try? NSRegularExpression(pattern: twoWordPattern) {
                for m in regex2.matches(in: chapterText, options: [], range: fullRange) {
                    let name = nsText.substring(with: m.range)
                    let words = name.split(separator: " ").map(String.init)
                    if words.count == 2 && !commonStopwords.contains(words[0]) && !commonStopwords.contains(words[1]) {
                        twoWordCounts[name, default: 0] += 1
                        recordExcerpt(for: name, matchRange: m.range)
                    }
                }
            }

            // C. Single-word pass
            if let regex1 = try? NSRegularExpression(pattern: oneWordPattern) {
                for m in regex1.matches(in: chapterText, options: [], range: fullRange) {
                    let word = nsText.substring(with: m.range)
                    if !commonStopwords.contains(word) && !knownTokens.contains(word.lowercased()) {
                        singleWordCounts[word, default: 0] += 1
                        recordExcerpt(for: word, matchRange: m.range)
                    }
                }
            }
        }

        // Normalize two-word name variations (e.g. "Fujimura Saho" and "Saho Fujimura")
        var normalizedTwoWords: [String: Int] = [:]
        for (name, count) in twoWordCounts where count >= 2 {
            let words = Set(name.split(separator: " ").map(String.init))
            var merged = false
            for (existing, exCount) in normalizedTwoWords {
                let exWords = Set(existing.split(separator: " ").map(String.init))
                if words == exWords {
                    normalizedTwoWords[existing] = exCount + count
                    merged = true
                    break
                }
            }
            if !merged {
                normalizedTwoWords[name] = count
            }
        }

        // Candidate grouping
        struct CandData {
            var count: Int
            var parts: Set<String>
            var aliases: Set<String>
            var excerpts: [String]
        }
        var candidateMap: [String: CandData] = [:]

        for (name, count) in normalizedTwoWords {
            let words = Set(name.split(separator: " ").map(String.init))
            var excs = tokenExcerpts[name] ?? []
            for w in words {
                if let more = tokenExcerpts[w] {
                    for e in more where !excs.contains(e) && excs.count < 3 {
                        excs.append(e)
                    }
                }
            }
            candidateMap[name] = CandData(count: count, parts: words, aliases: words, excerpts: excs)
        }

        // Integrate title names
        for (tname, count) in titleCounts where count >= 2 {
            let words = tname.split(separator: " ").map(String.init)
            let p = words.count > 1 ? words[1] : words[0]
            var matched = false
            for (cname, cdata) in candidateMap {
                if cdata.parts.contains(p) {
                    candidateMap[cname]?.count += count
                    candidateMap[cname]?.aliases.insert(tname)
                    matched = true
                    break
                }
            }
            if !matched {
                candidateMap[tname] = CandData(count: count, parts: [p], aliases: [p, tname], excerpts: tokenExcerpts[tname] ?? [])
            }
        }

        // Distribute single words
        for (word, count) in singleWordCounts where count >= 2 {
            let matches = candidateMap.keys.filter { candidateMap[$0]?.parts.contains(word) == true }
            if !matches.isEmpty {
                // Assign to highest count candidate
                if let best = matches.max(by: { (candidateMap[$0]?.count ?? 0) < (candidateMap[$1]?.count ?? 0) }) {
                    candidateMap[best]?.count += count
                    candidateMap[best]?.aliases.insert(word)
                }
            } else if count >= minOccurrences {
                candidateMap[word] = CandData(count: count, parts: [word], aliases: [], excerpts: tokenExcerpts[word] ?? [])
            }
        }

        var results: [CandidateEntity] = []
        for (name, data) in candidateMap {
            if data.count >= minOccurrences {
                results.append(CandidateEntity(name: name, occurrenceCount: data.count, sampleExcerpts: data.excerpts))
            }
        }

        return Array(results.sorted { $0.occurrenceCount > $1.occurrenceCount }.prefix(maxCandidates))
    }
}
