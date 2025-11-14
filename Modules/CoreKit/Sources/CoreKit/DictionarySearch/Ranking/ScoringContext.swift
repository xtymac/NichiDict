import Foundation

/// Context information passed to scoring features and hard rules
/// Contains all data needed to evaluate an entry's relevance
public struct ScoringContext: Sendable {
    /// Script type detection for query analysis
    public enum ScriptType: String, Codable, Sendable {
        case hiragana
        case katakana
        case kanji
        case romaji
        case mixed
    }

    /// The original search query (normalized)
    public let query: String

    /// Query script type (hiragana, katakana, kanji, romaji, mixed)
    public let scriptType: ScriptType

    /// Match type for this entry
    public let matchType: SearchResult.MatchType

    /// Whether this is an exact headword match
    public let isExactHeadword: Bool

    /// Whether this is a lemma (reading) match
    public let isLemmaMatch: Bool

    /// Whether using reverse search (English/Chinese → Japanese)
    public let useReverseSearch: Bool

    public init(
        query: String,
        scriptType: ScriptType,
        matchType: SearchResult.MatchType,
        isExactHeadword: Bool,
        isLemmaMatch: Bool,
        useReverseSearch: Bool
    ) {
        self.query = query
        self.scriptType = scriptType
        self.matchType = matchType
        self.isExactHeadword = isExactHeadword
        self.isLemmaMatch = isLemmaMatch
        self.useReverseSearch = useReverseSearch
    }
}
