import Foundation
@preconcurrency import GRDB

/// Variant type classification from JMDict ke_inf tags
/// Determines how the entry should be displayed and ranked in search results
public enum VariantType: String, Codable, Sendable {
    case primary = "primary"    // Normal/common spelling (has ke_pri or no special tags)
    case uk = "uk"              // Usually kana (from sense misc tag)
    case rK = "rK"              // Rarely used kanji form
    case oK = "oK"              // Outdated/old kanji
    case sK = "sK"              // Search-only kanji (don't show in results)
    case iK = "iK"              // Irregular kanji usage
    case io = "io"              // Irregular okurigana
    case ateji = "ateji"        // Ateji (phonetic kanji)

    /// Display priority for sorting (lower = higher priority)
    public var displayPriority: Int {
        switch self {
        case .uk: return 1          // Usually kana - most preferred
        case .primary: return 2      // Normal spelling
        case .ateji: return 3        // Ateji - occasionally used
        case .rK: return 4           // Rare kanji
        case .oK: return 5           // Old kanji
        case .iK, .io: return 6      // Irregular usage
        case .sK: return 7           // Search-only - never display
        }
    }

    /// Human-readable label for UI display
    public var label: String {
        switch self {
        case .primary: return ""
        case .uk: return "usually kana"
        case .rK: return "rare kanji"
        case .oK: return "old kanji"
        case .sK: return "search-only"
        case .ateji: return "ateji"
        case .iK: return "irregular kanji"
        case .io: return "irregular okurigana"
        }
    }

    /// Whether this variant should appear in search results
    public var shouldShowInResults: Bool {
        return self != .sK
    }
}

public struct DictionaryEntry: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let headword: String
    public let readingHiragana: String
    public let readingRomaji: String
    public let frequencyRank: Int?
    public let pitchAccent: String?
    public let jlptLevel: String?
    public let createdAt: Int
    public let variantType: VariantType?  // NEW: JMDict variant classification

    // Related data (not stored in table, loaded separately)
    public var senses: [WordSense] = []

    // MARK: - Computed Properties for Variant Handling

    /// Check if this is a rare kanji variant that should display as kana
    /// Uses database variant_type if available, falls back to hardcoded list for backward compatibility
    public var isRareKanji: Bool {
        // Prefer database-driven detection
        if let variant = variantType {
            return variant == .rK || variant == .oK
        }

        // Backward compatibility: fallback to hardcoded list for old data without variant_type
        let usuallyKanaWords = [
            "する", "やっと", "すぐ", "まだ", "もう", "ずっと",
            "たくさん", "とても", "ちょっと", "どうぞ", "ちゃんと",
            "きっと", "そっと", "はっきり", "しっかり", "ゆっくり",
            "やっぱり", "やはり", "それで"
        ]
        return usuallyKanaWords.contains(readingHiragana) && headword != readingHiragana
    }

    /// Check if this entry is usually written in kana
    public var isUsuallyKana: Bool {
        return variantType == .uk
    }

    /// Whether this entry should appear in search results
    public var shouldShowInResults: Bool {
        return variantType?.shouldShowInResults ?? true
    }

    /// The headword to display (uses kana for rare kanji variants)
    public var displayHeadword: String {
        switch variantType {
        case .uk, .rK, .oK, .sK:
            return readingHiragana  // Show kana form
        default:
            return headword         // Show original form
        }
    }

    /// Display priority for sorting variants (lower = higher priority)
    public var displayPriority: Int {
        return variantType?.displayPriority ?? 2  // Default to normal priority
    }

    /// Human-readable variant label (empty for primary forms)
    public var variantLabel: String {
        return variantType?.label ?? ""
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
        case variantType = "variant_type"  // NEW
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
        case variantType = "variant_type"  // NEW
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
        variantType: VariantType? = nil,  // NEW
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
        self.variantType = variantType
        self.senses = senses
    }

    // Custom decoder to handle optional senses and variantType
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
        variantType = try? container.decodeIfPresent(VariantType.self, forKey: .variantType)
        senses = (try? container.decode([WordSense].self, forKey: .senses)) ?? []
    }
}
