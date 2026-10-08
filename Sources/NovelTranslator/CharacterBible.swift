import Foundation

public enum CharacterGender: String, CaseIterable, Identifiable, Codable, Sendable {
    case male = "Male"
    case female = "Female"
    case neutral = "Neutral"
    case unknown = "Unknown"
    public var id: String { rawValue }
}

public enum NarrativePOV: String, CaseIterable, Identifiable, Codable, Sendable {
    case thirdPerson = "Third Person"
    case firstPerson = "First Person"
    public var id: String { rawValue }
}

public enum BookGenre: String, CaseIterable, Identifiable, Codable, Sendable {
    case fiction = "Fiction / Novel"
    case nonFiction = "Non-Fiction / Technical / Academic"
    public var id: String { rawValue }
}

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

public struct ChapterScope: Identifiable, Sendable, Codable, Equatable, Hashable {
    public var id: String // chapter relativePath or chapter id
    public var chapterIndex: Int
    public var chapterTitle: String
    public var characters: [CharacterProfile]
    public var relationships: [RelationshipPair]
    public var notes: String

    public init(
        id: String,
        chapterIndex: Int,
        chapterTitle: String,
        characters: [CharacterProfile] = [],
        relationships: [RelationshipPair] = [],
        notes: String = ""
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.characters = characters
        self.relationships = relationships
        self.notes = notes
    }
}

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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(gender, forKey: .gender)
        try container.encode(relativeAge, forKey: .relativeAge)
        try container.encode(roleOrStatus, forKey: .roleOrStatus)
        try container.encodeIfPresent(thirdPersonPronoun, forKey: .thirdPersonPronoun)
        try container.encodeIfPresent(explicitAgeTier, forKey: .explicitAgeTier)
    }
}

public struct RelationshipPair: Identifiable, Sendable, Codable, Hashable, Equatable {
    public var id: String
    public var sourceCharacterId: String
    public var targetCharacterId: String
    public var selfPronoun: String
    public var addressingPronoun: String
    public var contextNote: String?

    public init(
        id: String = UUID().uuidString,
        sourceCharacterId: String,
        targetCharacterId: String,
        selfPronoun: String,
        addressingPronoun: String,
        contextNote: String? = nil
    ) {
        self.id = id
        self.sourceCharacterId = sourceCharacterId
        self.targetCharacterId = targetCharacterId
        self.selfPronoun = selfPronoun
        self.addressingPronoun = addressingPronoun
        self.contextNote = contextNote
    }
}

public struct CharacterBible: Sendable, Codable, Equatable, Hashable {
    public var bookTitle: String
    public var bookGenre: BookGenre
    public var narrativePOV: NarrativePOV
    public var narratorCharacterId: String?
    public var characters: [CharacterProfile]
    public var relationships: [RelationshipPair]
    public var chapterScopes: [String: ChapterScope]
    public var generalNotes: String

    public init(
        bookTitle: String = "",
        bookGenre: BookGenre = .fiction,
        narrativePOV: NarrativePOV = .thirdPerson,
        narratorCharacterId: String? = nil,
        characters: [CharacterProfile] = [],
        relationships: [RelationshipPair] = [],
        chapterScopes: [String: ChapterScope] = [:],
        generalNotes: String = ""
    ) {
        self.bookTitle = bookTitle
        self.bookGenre = bookGenre
        self.narrativePOV = narrativePOV
        self.narratorCharacterId = narratorCharacterId
        self.characters = characters
        self.relationships = relationships
        self.chapterScopes = chapterScopes
        self.generalNotes = generalNotes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bookTitle = try container.decodeIfPresent(String.self, forKey: .bookTitle) ?? ""
        self.bookGenre = try container.decodeIfPresent(BookGenre.self, forKey: .bookGenre) ?? .fiction
        self.narrativePOV = try container.decodeIfPresent(NarrativePOV.self, forKey: .narrativePOV) ?? .thirdPerson
        self.narratorCharacterId = try container.decodeIfPresent(String.self, forKey: .narratorCharacterId)
        self.characters = try container.decodeIfPresent([CharacterProfile].self, forKey: .characters) ?? []
        self.relationships = try container.decodeIfPresent([RelationshipPair].self, forKey: .relationships) ?? []
        self.chapterScopes = try container.decodeIfPresent([String: ChapterScope].self, forKey: .chapterScopes) ?? [:]
        self.generalNotes = try container.decodeIfPresent(String.self, forKey: .generalNotes) ?? ""
    }
}
