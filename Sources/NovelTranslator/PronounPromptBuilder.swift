import Foundation

public struct PronounPromptBuilder: Sendable {
    /// Generates standalone Vietnamese Character Bible / Knowledge Base directives.
    public static func buildKnowledgeBaseDirectives(
        bible: CharacterBible?,
        chapterText: String? = nil,
        chapterId: String? = nil
    ) -> String {
        guard let bible else { return "" }

        let (effectiveChars, effectiveRels, effectiveNotes) = CharacterBibleFilter.effectiveScope(forChapterId: chapterId, in: bible)

        let relationships: [RelationshipPair] = {
            if let text = chapterText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CharacterBibleFilter.filterRelationships(in: bible, forChapterText: text, chapterId: chapterId)
            } else {
                return effectiveRels
            }
        }()

        var directives: [String] = []
        directives.append("VIETNAMESE PRONOUN & CHARACTER GUIDELINES (KNOWLEDGE BASE):")
        directives.append("Book Genre: \(bible.bookGenre.rawValue)")
        directives.append("Narrative Perspective: \(bible.narrativePOV.rawValue)")

        // Non-Fiction specific translation directives
        if bible.bookGenre == .nonFiction {
            directives.append("")
            directives.append("NON-FICTION & TECHNICAL TRANSLATION GUIDELINES:")
            directives.append("- Style: Factual, objective, academically accurate, and clear.")
            directives.append("- Tone: Professional and impersonal. Avoid literary romantic/fiction pronouns (do NOT use 'chàng', 'nàng', 'anh/em', 'hắn', 'gã').")
            directives.append("- Pronouns: Translate author self-references ('I', 'we') as 'tôi', 'chúng ta' (inclusive of readers) or 'tác giả'; translate 'you' as 'bạn' or 'bạn đọc'. Use character or researcher full titles where appropriate.")
        }

        if !relationships.isEmpty {
            directives.append("")
            directives.append("Active Character Pronoun Pairs:")
            let charMap = Dictionary(uniqueKeysWithValues: effectiveChars.map { ($0.id, $0.name) })
            for pair in relationships {
                let sourceName = charMap[pair.sourceCharacterId] ?? pair.sourceCharacterId
                let targetName = charMap[pair.targetCharacterId] ?? pair.targetCharacterId
                var line = "- \(sourceName) -> \(targetName): Calls self \"\(pair.selfPronoun)\", addresses \(targetName) as \"\(pair.addressingPronoun)\""
                if let note = pair.contextNote, !note.isEmpty {
                    line += " (Context: \(note))"
                }
                directives.append(line)
            }
        }

        // Third-Person Pronoun Guidelines (Narration vs Dialogue)
        if !effectiveChars.isEmpty && bible.bookGenre != .nonFiction {
            directives.append("")
            directives.append("THIRD-PERSON PRONOUN GUIDELINES (NARRATION VS DIALOGUE):")
            directives.append("1. Context A - Author Narration (Lời văn trần thuật / Kể chuyện của tác giả):")
            directives.append("   - Khi tác giả kể về hành động/suy nghĩ của nhân vật bằng \"he / she\", TUYỆT ĐỐI TRÁNH lạm dụng \"anh ấy / cô ấy\".")
            directives.append("   - Người cao tuổi: dùng \"ông ta\", \"bà ta\" (hoặc vắn tắt \"ông\", \"bà\").")
            directives.append("   - Người bình thường / thanh niên: dùng \"anh ta\", \"cô ta\" (hoặc vắn tắt \"anh\", \"cô\").")
            directives.append("   - Trẻ em: dùng \"thằng bé\", \"cô bé\" (hoặc \"bé\").")
            directives.append("   - Ưu tiên gọi tên nhân vật hoặc ẩn chủ ngữ (subject omission) khi ngữ cảnh đã rõ.")
            directives.append("")
            directives.append("2. Context B - In Dialogue & Character Thoughts (Nhân vật nhắc tới người khác trong lời thoại hoặc suy nghĩ):")
            directives.append("   - Khi nhân vật nói hoặc nghĩ về người thứ ba (\"he / she\"):")
            directives.append("     * Nếu người được nhắc LỚN TUỔI HƠN nhân vật đang nói: dùng \"anh ấy\", \"cô ấy\" (hoặc \"chị ấy\") để thể hiện sự tự nhiên, lịch sự.")
            directives.append("     * Nếu người được nhắc GIÀ HẲN (bậc ông bà / cao niên): dùng \"ông ấy\" / \"ông ta\", \"bà ấy\" / \"bà ta\".")
            directives.append("     * Nếu người được nhắc NHỎ TUỔI HƠN nhân vật đang nói: dùng \"cô ta\", \"cậu ta\" (nếu là người lớn/thanh niên) hoặc \"thằng bé\", \"cô bé\" (nếu là trẻ em).")

            let activeChars: [CharacterProfile] = {
                if let text = chapterText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let chars = effectiveChars.filter { char in
                        let tokens = [char.name] + char.aliases
                        return tokens.contains { t in !t.isEmpty && text.localizedCaseInsensitiveContains(t) }
                    }
                    return chars.isEmpty ? effectiveChars : chars
                }
                return effectiveChars
            }()

            if !activeChars.isEmpty {
                directives.append("")
                directives.append("Active Character 3rd-Person Reference Anchors:")
                for char in activeChars {
                    var lines: [String] = []
                    lines.append("- \(char.name) (\(char.gender.rawValue), \(char.ageTier.rawValue)):")
                    lines.append("  * Narration: \"\(char.narrativeThirdPersonPronoun)\" / direct name / subject omission (DO NOT use \"anh ấy/cô ấy\" in narrative prose)")
                    switch char.ageTier {
                    case .elderly:
                        lines.append("  * In Dialogue: \"\(char.dialogueOlderThirdPersonPronoun)\" / \"\(char.narrativeThirdPersonPronoun)\"")
                    case .child:
                        lines.append("  * In Dialogue: \"\(char.narrativeThirdPersonPronoun)\"")
                    case .adult:
                        lines.append("  * In Dialogue (ref by younger): \"\(char.dialogueOlderThirdPersonPronoun)\"")
                        lines.append("  * In Dialogue (ref by older): \"\(char.dialogueYoungerThirdPersonPronoun)\"")
                    }
                    directives.append(lines.joined(separator: "\n"))
                }
            }
        }

        if !effectiveNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            directives.append("")
            directives.append("General Notes: \(effectiveNotes)")
        }

        directives.append("")
        directives.append("Directives:")
        directives.append("1. Strictly maintain these reciprocal pronouns in dialogues between these characters.")
        directives.append("2. Do NOT default to generic or sterile \"tôi / bạn\" in dialogue when character relationships dictate intimacy or seniority.")
        if bible.bookGenre != .nonFiction {
            directives.append("3. THIRD-PERSON USAGE: In narrative prose (Context A), avoid generic/repetitive \"anh ấy / cô ấy\", strictly following Context A rules (\"anh ta\", \"cô ta\", \"ông ta\", \"bà ta\", \"thằng bé\", \"cô bé\", direct names, or subject omission). In dialogue (Context B), use \"anh ấy / cô ấy\" ONLY when a character refers to an older peer, and use \"cô ta / cậu ta / ông ta / bà ta\" or \"thằng bé / cô bé\" as specified in Context B.")
        }
        directives.append("4. Keep narrative description natural and consistent with the identified perspective.")

        return directives.joined(separator: "\n")
    }

    /// Enriches the base system instruction with Vietnamese pronoun directives if target is Vietnamese and a bible is available.
    public static func buildSystemInstruction(
        baseInstruction: String,
        targetLanguageCode: String,
        bible: CharacterBible?,
        chapterText: String?,
        chapterId: String? = nil
    ) -> String {
        guard let bible else { return baseInstruction }
        let cleanTarget = targetLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanTarget == "vi" || cleanTarget.hasPrefix("vi-") else {
            return baseInstruction
        }

        let kbDirectives = buildKnowledgeBaseDirectives(bible: bible, chapterText: chapterText, chapterId: chapterId)
        guard !kbDirectives.isEmpty else { return baseInstruction }

        if baseInstruction.contains("{knowledgeBase}") {
            return baseInstruction.replacingOccurrences(of: "{knowledgeBase}", with: kbDirectives)
        } else if baseInstruction.contains("{characterBibleGuidelines}") {
            return baseInstruction.replacingOccurrences(of: "{characterBibleGuidelines}", with: kbDirectives)
        } else {
            return baseInstruction + "\n\n" + kbDirectives
        }
    }
}
