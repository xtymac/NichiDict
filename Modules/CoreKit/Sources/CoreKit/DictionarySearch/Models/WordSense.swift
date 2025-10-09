import Foundation
@preconcurrency import GRDB

public struct WordSense: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let entryId: Int
    public let definitionEnglish: String
    public let partOfSpeech: String
    public let usageNotes: String?
    public let senseOrder: Int
    
    // Related data
    public var examples: [ExampleSentence] = []
    
    public enum Columns: String, ColumnExpression {
        case id
        case entryId = "entry_id"
        case definitionEnglish = "definition_english"
        case partOfSpeech = "part_of_speech"
        case usageNotes = "usage_notes"
        case senseOrder = "sense_order"
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case definitionEnglish = "definition_english"
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
        partOfSpeech: String,
        usageNotes: String?,
        senseOrder: Int,
        examples: [ExampleSentence] = []
    ) {
        self.id = id
        self.entryId = entryId
        self.definitionEnglish = definitionEnglish
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
        partOfSpeech = try container.decode(String.self, forKey: .partOfSpeech)
        usageNotes = try container.decodeIfPresent(String.self, forKey: .usageNotes)
        senseOrder = try container.decode(Int.self, forKey: .senseOrder)
        examples = (try? container.decode([ExampleSentence].self, forKey: .examples)) ?? []
    }
}
