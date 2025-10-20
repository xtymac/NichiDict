import Foundation
@preconcurrency import GRDB

public struct WordSense: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let entryId: Int
    public let definitionEnglish: String
    public let definitionChineseSimplified: String?
    public let definitionChineseTraditional: String?
    public let partOfSpeech: String
    public let usageNotes: String?
    public let senseOrder: Int

    // Related data
    public var examples: [ExampleSentence] = []

    // Get localized definition based on user's locale
    public func localizedDefinition(locale: Locale = .current) -> String {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let scriptCode = locale.language.script?.identifier

        // Check for Chinese variants
        if languageCode == "zh" {
            // Determine if Traditional or Simplified
            if scriptCode == "Hant" {
                // Traditional Chinese (Hong Kong, Taiwan)
                if let traditionalDef = definitionChineseTraditional, !traditionalDef.isEmpty {
                    return traditionalDef
                }
            } else {
                // Simplified Chinese (Mainland China, Singapore) - default for "zh"
                if let simplifiedDef = definitionChineseSimplified, !simplifiedDef.isEmpty {
                    return simplifiedDef
                }
            }
            // Fallback: try the other Chinese variant
            if let simplifiedDef = definitionChineseSimplified, !simplifiedDef.isEmpty {
                return simplifiedDef
            }
            if let traditionalDef = definitionChineseTraditional, !traditionalDef.isEmpty {
                return traditionalDef
            }
        }

        // For Japanese locale, prefer Chinese (if available) over English
        if languageCode == "ja" {
            if let simplifiedDef = definitionChineseSimplified, !simplifiedDef.isEmpty {
                return simplifiedDef
            }
            if let traditionalDef = definitionChineseTraditional, !traditionalDef.isEmpty {
                return traditionalDef
            }
        }

        // Default to English
        return definitionEnglish
    }

    public enum Columns: String, ColumnExpression {
        case id
        case entryId = "entry_id"
        case definitionEnglish = "definition_english"
        case definitionChineseSimplified = "definition_chinese_simplified"
        case definitionChineseTraditional = "definition_chinese_traditional"
        case partOfSpeech = "part_of_speech"
        case usageNotes = "usage_notes"
        case senseOrder = "sense_order"
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case definitionEnglish = "definition_english"
        case definitionChineseSimplified = "definition_chinese_simplified"
        case definitionChineseTraditional = "definition_chinese_traditional"
        case partOfSpeech = "part_of_speech"
        case usageNotes = "usage_notes"
        case senseOrder = "sense_order"
        case examples
    }

    public static let databaseTableName = "word_senses"
    
    // Relationships
    public static let entry = belongsTo(DictionaryEntry.self)
    public static let exampleSentences = hasMany(ExampleSentence.self)
    
    public init(
        id: Int,
        entryId: Int,
        definitionEnglish: String,
        definitionChineseSimplified: String? = nil,
        definitionChineseTraditional: String? = nil,
        partOfSpeech: String,
        usageNotes: String?,
        senseOrder: Int,
        examples: [ExampleSentence] = []
    ) {
        self.id = id
        self.entryId = entryId
        self.definitionEnglish = definitionEnglish
        self.definitionChineseSimplified = definitionChineseSimplified
        self.definitionChineseTraditional = definitionChineseTraditional
        self.partOfSpeech = partOfSpeech
        self.usageNotes = usageNotes
        self.senseOrder = senseOrder
        self.examples = examples
    }

    // Custom decoder to handle optional examples
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        entryId = try container.decode(Int.self, forKey: .entryId)
        definitionEnglish = try container.decode(String.self, forKey: .definitionEnglish)
        definitionChineseSimplified = try container.decodeIfPresent(String.self, forKey: .definitionChineseSimplified)
        definitionChineseTraditional = try container.decodeIfPresent(String.self, forKey: .definitionChineseTraditional)
        partOfSpeech = try container.decode(String.self, forKey: .partOfSpeech)
        usageNotes = try container.decodeIfPresent(String.self, forKey: .usageNotes)
        senseOrder = try container.decode(Int.self, forKey: .senseOrder)
        examples = (try? container.decode([ExampleSentence].self, forKey: .examples)) ?? []
    }
}
