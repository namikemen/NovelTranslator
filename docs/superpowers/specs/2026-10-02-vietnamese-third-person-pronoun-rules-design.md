# Design Spec: Vietnamese Third-Person Pronoun Resolution (Author Narration vs. Character Dialogue)

- **Date:** 2026-10-02
- **Status:** Approved
- **Target Platform:** macOS 15.0+ (Sequoia), Swift 6 Concurrency
- **Module:** DocTranslateApp

---

## 1. Problem Statement & Motivation

### 1.1 The Linguistic Distinction in Vietnamese Literature
In English literature, third-person singular pronouns (`he`, `she`, `him`, `her`) are uniform across all contexts. In Vietnamese literature, third-person references depend heavily on **who is speaking or thinking**:

1. **Author Narration (Lời kể của tác giả / Người dẫn chuyện):**
   - The narrator maintains an objective, detached, storytelling distance.
   - Using *anh ấy / cô ấy* in narration sounds like translationese (dịch thô / văn phong máy dịch) and quickly becomes repetitive and unnatural.
   - Instead, Vietnamese literature uses:
     - **Elderly (Người cao tuổi):** *ông ta*, *bà ta* (or concise *ông*, *bà*).
     - **Adults / Peers (Người bình thường / thanh niên):** *anh ta*, *cô ta* (or concise *anh*, *cô*).
     - **Children (Trẻ em):** *thằng bé*, *cô bé* (or *bé*).
     - **Subject Omission (Ẩn chủ ngữ):** When the subject was identified in the previous sentence.

2. **Character Dialogue & Thoughts (Lời thoại và dòng suy nghĩ của nhân vật nhắc về người thứ ba):**
   - When a character speaks or thinks about someone else, the pronoun reflects interpersonal respect, age gap, and social standing:
     - **Referring to someone older:** *anh ấy*, *cô ấy* (or *chị ấy*) conveys natural respect and polite distance without being stiff.
     - **Referring to someone much older (elderly / grandparent tier):** *ông ấy* / *ông ta*, *bà ấy* / *bà ta*.
     - **Referring to someone younger:** *cô ta*, *cậu ta* (or *thằng bé*, *cô bé* for children).

### 1.2 Current System Limitations
In the current implementation of `PronounPromptBuilder` and `CharacterProfile`:
- A single `resolvedThirdPersonPronoun` (e.g. *cô*, *anh*, *bà*, *ông*) is generated per character.
- The prompt instructs the LLM generally to avoid *cô ấy / anh ấy*, but does not distinguish between **Author Narration** vs **Character Dialogue / Thoughts**, leading the LLM to either:
  1. Ban *anh ấy / cô ấy* even inside dialogue where it would sound most natural when referring to an older peer.
  2. Default to *anh ấy / cô ấy* in narrative prose where *anh ta / cô ta* or *thằng bé / cô bé* should be used.

### 1.3 Goals
1. Formalize age tiers in `CharacterProfile` (`child`, `adult`, `elderly`) to automatically map to natural third-person pronouns.
2. Establish distinct dual pronoun resolution:
   - **Narration Third-Person Pronouns** (*ông ta / bà ta*, *anh ta / cô ta*, *thằng bé / cô bé*).
   - **Dialogue/Thought Third-Person Pronouns** (*anh ấy / cô ấy* for older, *cô ta / cậu ta* for younger, *ông ấy / ông ta* or *bà ấy / bà ta* for elderly).
3. Enhance `PronounPromptBuilder` with structured, unambiguous directives for both narration and character speech, while preserving strict separation from non-fiction translation.
4. Support manual overrides in `CharacterBibleSheet` while maintaining backward compatibility with existing saved checkpoints.

---

## 2. Architecture & Data Models

### 2.1 Age Tier Formalization

We introduce a normalized `AgeTier` enum with exhaustive display names and robust age parsing:

```swift
public enum AgeTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case child = "Child"         // Trẻ em: thằng bé, cô bé
    case adult = "Adult"         // Người lớn / Thanh niên / Bình thường: anh ta, cô ta
    case elderly = "Elderly"     // Người cao tuổi / Già hẳn: ông ta, bà ta
    
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .child: return "Trẻ em"
        case .adult: return "Người lớn"
        case .elderly: return "Cao tuổi"
        }
    }
    
    public static func from(relativeAge: String) -> AgeTier {
        let trimmed = relativeAge.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return .adult }

        // 0. Explicit exclusion of unknown or neutral markers
        if trimmed == "unknown" || trimmed == "không rõ" || trimmed == "n/a" || trimmed == "neutral" {
            return .adult
        }

        // 1. Explicit middle-aged check before elderly/aged check
        if trimmed.contains("middle-aged") || trimmed.contains("middle aged") || trimmed.contains("trung niên") || trimmed.contains("u40") || trimmed.contains("u50") {
            return .adult
        }

        // 2. Numeric age check (supports "25", "25 years old", "70s", "age 80")
        if let regex = try? NSRegularExpression(pattern: "\\b(\\d{1,3})s?\\b"),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed),
           let ageValue = Int(trimmed[range]) {
            if ageValue < 16 {
                return .child
            } else if ageValue >= 60 {
                return .elderly
            } else {
                return .adult
            }
        }

        // 3. Elderly keywords with word boundaries & kin terms
        let elderlyPattern = "\\b(elder|elderly|senior|old man|old woman|old person|grandfather|grandmother|grandpa|grandma|già|cụ|ông lão|bà lão|ông cụ|bà cụ)\\b"
        if let regex = try? NSRegularExpression(pattern: elderlyPattern),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return .elderly
        }
        // Direct standalone Vietnamese pronoun checks without matching "không"
        if trimmed == "ông" || trimmed == "bà" || trimmed.hasPrefix("ông ") || trimmed.hasPrefix("bà ") {
            return .elderly
        }

        // 4. Child keywords with word boundaries
        let childPattern = "\\b(child|kid|baby|toddler|teen|teenager|teenaged|youth|little boy|little girl|con nít|trẻ con|bé con|cậu bé|cô bé)\\b"
        if let regex = try? NSRegularExpression(pattern: childPattern),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return .child
        }
        if trimmed == "bé" || trimmed == "trẻ" || trimmed.hasPrefix("bé ") {
            return .child
        }

        // 5. Default fallback
        return .adult
    }
}
```

### 2.2 Character Profile Enhancements

`CharacterProfile` is updated with a stored `explicitAgeTier: AgeTier?`, an updated designated initializer, custom Codable decoding for backward compatibility, and deterministic pronoun accessors:

```swift
public struct CharacterProfile: Identifiable, Sendable, Codable, Hashable, Equatable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var gender: CharacterGender
    public var relativeAge: String
    public var roleOrStatus: String
    public var thirdPersonPronoun: String?
    public var explicitAgeTier: AgeTier?

    public var ageTier: AgeTier {
        get { explicitAgeTier ?? AgeTier.from(relativeAge: relativeAge) }
        set { explicitAgeTier = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        aliases: [String] = [],
        gender: CharacterGender = .unknown,
        relativeAge: String = "adult",
        roleOrStatus: String = "",
        thirdPersonPronoun: String? = nil,
        explicitAgeTier: AgeTier? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.gender = gender
        self.relativeAge = relativeAge
        self.roleOrStatus = roleOrStatus
        self.thirdPersonPronoun = thirdPersonPronoun
        self.explicitAgeTier = explicitAgeTier
    }

    /// Pronoun used by the 3rd-person narrator (Author narration).
    public var narrativeThirdPersonPronoun: String {
        if let explicit = thirdPersonPronoun, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch gender {
        case .female:
            switch ageTier {
            case .elderly: return "bà ta"
            case .adult: return "cô ta"
            case .child: return "cô bé"
            }
        case .male:
            switch ageTier {
            case .elderly: return "ông ta"
            case .adult: return "anh ta"
            case .child: return "thằng bé"
            }
        case .neutral, .unknown:
            switch ageTier {
            case .elderly: return "người già đó"
            case .adult: return "người đó"
            case .child: return "đứa bé"
            }
        }
    }

    /// Pronoun used in dialogue when referring to this character who is older than the speaker.
    public var dialogueOlderThirdPersonPronoun: String {
        switch gender {
        case .female:
            switch ageTier {
            case .elderly: return "bà ấy"
            case .adult: return "cô ấy"
            case .child: return "cô bé"
            }
        case .male:
            switch ageTier {
            case .elderly: return "ông ấy"
            case .adult: return "anh ấy"
            case .child: return "thằng bé"
            }
        case .neutral, .unknown:
            switch ageTier {
            case .elderly: return "người lớn tuổi đó"
            case .adult: return "người ấy"
            case .child: return "đứa bé"
            }
        }
    }

    /// Pronoun used in dialogue when referring to this character who is younger than the speaker.
    public var dialogueYoungerThirdPersonPronoun: String {
        switch gender {
        case .female:
            switch ageTier {
            case .elderly: return "bà ta"
            case .adult: return "cô ta"
            case .child: return "cô bé"
            }
        case .male:
            switch ageTier {
            case .elderly: return "ông ta"
            case .adult: return "cậu ta"
            case .child: return "thằng bé"
            }
        case .neutral, .unknown:
            switch ageTier {
            case .elderly: return "người già đó"
            case .adult: return "người đó"
            case .child: return "đứa bé"
            }
        }
    }

    /// Maintained for full backward compatibility; forwards to narrativeThirdPersonPronoun.
    public var resolvedThirdPersonPronoun: String {
        return narrativeThirdPersonPronoun
    }

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, gender, relativeAge, roleOrStatus, thirdPersonPronoun, explicitAgeTier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        self.gender = try container.decodeIfPresent(CharacterGender.self, forKey: .gender) ?? .unknown
        self.relativeAge = try container.decodeIfPresent(String.self, forKey: .relativeAge) ?? "adult"
        self.roleOrStatus = try container.decodeIfPresent(String.self, forKey: .roleOrStatus) ?? ""
        self.thirdPersonPronoun = try container.decodeIfPresent(String.self, forKey: .thirdPersonPronoun)
        self.explicitAgeTier = try container.decodeIfPresent(AgeTier.self, forKey: .explicitAgeTier)
    }
}
```

### 2.3 System Prompt Directives (`PronounPromptBuilder`)

`PronounPromptBuilder` injects clear, deterministic guidelines only when `bookGenre != .nonFiction`. Non-fiction books bypass Contexts A and B and keep their factual academic guidelines.

For fiction, Directive 3 is updated and the prompt anchors branch cleanly based on `ageTier`:

```swift
if bible.bookGenre != .nonFiction {
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
    directives.append("")

    if !activeChars.isEmpty {
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
```

Updated Directives block:
```swift
directives.append("Directives:")
directives.append("1. Strictly maintain these reciprocal pronouns in dialogues between these characters.")
directives.append("2. Do NOT default to generic or sterile \"tôi / bạn\" in dialogue when character relationships dictate intimacy or seniority.")
if bible.bookGenre != .nonFiction {
    directives.append("3. THIRD-PERSON USAGE: In narrative prose (Context A), avoid generic/repetitive \"anh ấy / cô ấy\", strictly following Context A rules (\"anh ta\", \"cô ta\", \"ông ta\", \"bà ta\", \"thằng bé\", \"cô bé\", direct names, or subject omission). In dialogue (Context B), use \"anh ấy / cô ấy\" ONLY when a character refers to an older peer, and use \"cô ta / cậu ta / ông ta / bà ta\" or \"thằng bé / cô bé\" as specified in Context B.")
}
directives.append("4. Keep narrative description natural and consistent with the identified perspective.")
```

---

## 3. Component Details & Data Flow

### 3.1 Data Flow
1. **Extraction / Configuration:** When a Character Bible is generated (via AI extraction or manual user entry), `relativeAge` is parsed by `AgeTier.from(relativeAge:)` to compute `ageTier`.
2. **Filtering:** Per chapter, active characters are selected by `CharacterBibleFilter`.
3. **Prompt Composition:** `PronounPromptBuilder` inspects active characters, builds the two-context rule set (Context A and Context B), and appends the character reference anchors. If `bookGenre == .nonFiction`, this section is completely bypassed.
4. **Translation Engine:** The LLM receives the system prompt with clear contextual boundaries between author narration (`"He walked into the bar..."` -> `"Anh ta bước vào quán..."`) and dialogue references (`"Do you know where he went?"` -> `"Cậu có biết anh ấy đi đâu không?"`).

### 3.2 UI Integration in `CharacterBibleSheet`
In `CharacterBibleSheet.swift`, within the `charactersTabView` List:
- In the row for each character, add a Menu Picker for `AgeTier` right next to the Age text field:
  ```swift
  Picker("", selection: Binding(
      get: { char.ageTier },
      set: { char.ageTier = $0 }
  )) {
      ForEach(AgeTier.allCases) { tier in
          Text(tier.displayName).tag(tier)
      }
  }
  .frame(width: 100)
  ```
- Keep the `TextField("3rd person", text: ...)` which allows overriding `thirdPersonPronoun` manually if a user wants a special pronoun (e.g. `gã`, `hắn`, `nàng`).

---

## 4. Testing & Validation Strategy

1. **Unit Tests in `DocTranslateAppTests`**:
   - `testAgeTierInference`: Verify mapping for:
     - `"25 years old"` -> `.adult`
     - `"72 years old"` -> `.elderly`
     - `"70s"` -> `.elderly`
     - `"10 years old"` -> `.child`
     - `"middle-aged man"` -> `.adult`
     - `"middle aged woman"` -> `.adult`
     - `"không rõ"` -> `.adult`
     - `"elderly retired teacher"` -> `.elderly`
     - `"grandpa"` -> `.elderly`
     - `"little kid"` -> `.child`
     - `"young adult"` -> `.adult`
   - `testNarrativePronounResolution`:
     - Male child -> `thằng bé`
     - Female child -> `cô bé`
     - Male adult -> `anh ta`
     - Female adult -> `cô ta`
     - Male elderly -> `ông ta`
     - Female elderly -> `bà ta`
   - `testDialoguePronounResolution`:
     - Male adult (older) -> `anh ấy`
     - Female adult (older) -> `cô ấy`
     - Male adult (younger) -> `cậu ta`
     - Female adult (younger) -> `cô ta`
     - Male elderly -> `ông ấy` (polite) / `ông ta`
     - Female elderly -> `bà ấy` (polite) / `bà ta`
     - Child -> `thằng bé` / `cô bé`
   - `testPromptBuilderDirectives`: Verify `PronounPromptBuilder` produces both Context A and Context B with active character anchors, branching for elderly, child, and adult.
   - Update existing `testThirdPersonNarrativeAndAntiRepetitionDirectives` to match the enriched prompt anchor format.
2. **Build & Bundle Verification**:
   - Run `swift test`.
   - Run `./bundle.sh` to ensure macOS application bundle builds cleanly.

---

## 5. Security & Compatibility

- **Backward Compatibility:** All existing `CharacterBible` models and checkpoint files remain valid without schema breakage. Existing JSON without `explicitAgeTier` will decode with `explicitAgeTier = nil` and compute `ageTier` from `relativeAge`.
- **Thread Safety:** All new models and enums conform to `Sendable`.
