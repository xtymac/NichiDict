import Foundation
@preconcurrency import GRDB

public struct DictionaryEntry: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let headword: String
    public let readingHiragana: String
    public let readingRomaji: String
    public let frequencyRank: Int?
    public let pitchAccent: String?
    public let jlptLevel: String?
    public let createdAt: Int
    
    // Related data (not stored in table, loaded separately)
    public var senses: [WordSense] = []

    // Computed property: Check if this is a rare kanji variant that's usually written in kana
    // Examples: 漸と (usually やっと), 為る (usually する), 直ぐ (usually すぐ)
    public var isRareKanji: Bool {
        // List of words that are usually written in kana (uk = usually kana)
        let usuallyKanaWords = [
            "する", "やっと", "すぐ", "まだ", "もう", "ずっと",
            "たくさん", "とても", "ちょっと", "どうぞ", "ちゃんと",
            "きっと", "そっと", "はっきり", "しっかり", "ゆっくり",
            "やっぱり", "やはり"
        ]

        // Check if:
        // 1. This entry's reading is in the usually-kana list
        // 2. The headword is NOT the pure kana form (i.e., it's a kanji variant)
        return usuallyKanaWords.contains(readingHiragana) && headword != readingHiragana
    }

    // GRDB column mapping
    public enum Columns: String, ColumnExpression {
        case id, headword
        case readingHiragana = "reading_hiragana"
        case readingRomaji = "reading_romaji"
        case frequencyRank = "frequency_rank"
        case pitchAccent = "pitch_accent"
        case jlptLevel = "jlpt_level"
        case createdAt = "created_at"
    }

    // CodingKeys for Codable conformance
    public enum CodingKeys: String, CodingKey {
        case id, headword
        case readingHiragana = "reading_hiragana"
        case readingRomaji = "reading_romaji"
        case frequencyRank = "frequency_rank"
        case pitchAccent = "pitch_accent"
        case jlptLevel = "jlpt_level"
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
        jlptLevel: String? = nil,
        createdAt: Int,
        senses: [WordSense] = []
    ) {
        self.id = id
        self.headword = headword
        self.readingHiragana = readingHiragana
        self.readingRomaji = readingRomaji
        self.frequencyRank = frequencyRank
        self.pitchAccent = pitchAccent
        self.jlptLevel = jlptLevel
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
        jlptLevel = try container.decodeIfPresent(String.self, forKey: .jlptLevel)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        senses = (try? container.decode([WordSense].self, forKey: .senses)) ?? []
    }
}
