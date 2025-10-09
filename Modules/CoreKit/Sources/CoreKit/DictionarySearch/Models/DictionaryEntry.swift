import Foundation
@preconcurrency import GRDB

public struct DictionaryEntry: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let headword: String
    public let readingHiragana: String
    public let readingRomaji: String
    public let frequencyRank: Int?
    public let pitchAccent: String?
    public let createdAt: Int
    
    // Related data (not stored in table, loaded separately)
    public var senses: [WordSense] = []
    
    // GRDB column mapping
    public enum Columns: String, ColumnExpression {
        case id, headword
        case readingHiragana = "reading_hiragana"
        case readingRomaji = "reading_romaji"
        case frequencyRank = "frequency_rank"
        case pitchAccent = "pitch_accent"
        case createdAt = "created_at"
    }

    // CodingKeys for Codable conformance
    public enum CodingKeys: String, CodingKey {
        case id, headword
        case readingHiragana = "reading_hiragana"
        case readingRomaji = "reading_romaji"
        case frequencyRank = "frequency_rank"
        case pitchAccent = "pitch_accent"
        case createdAt = "created_at"
        case senses
    }

    public static let databaseTableName = "dictionary_entries"
    
    // Relationship: entry has many senses
    public static let wordSenses = hasMany(WordSense.self)
    
    // Custom initializer for testing
    public init(
        id: Int,
        headword: String,
        readingHiragana: String,
        readingRomaji: String,
        frequencyRank: Int?,
        pitchAccent: String?,
        createdAt: Int,
        senses: [WordSense] = []
    ) {
        self.id = id
        self.headword = headword
        self.readingHiragana = readingHiragana
        self.readingRomaji = readingRomaji
        self.frequencyRank = frequencyRank
        self.pitchAccent = pitchAccent
        self.createdAt = createdAt
        self.senses = senses
    }

    // Custom decoder to handle optional senses
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        headword = try container.decode(String.self, forKey: .headword)
        readingHiragana = try container.decode(String.self, forKey: .readingHiragana)
        readingRomaji = try container.decode(String.self, forKey: .readingRomaji)
        frequencyRank = try container.decodeIfPresent(Int.self, forKey: .frequencyRank)
        pitchAccent = try container.decodeIfPresent(String.self, forKey: .pitchAccent)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        senses = (try? container.decode([WordSense].self, forKey: .senses)) ?? []
    }
}
