import Foundation

/// Categorizes search results into semantic groups for better UI organization
public enum SearchResultCategory: Int, Sendable, Comparable {
    case basicVocabulary = 0      // 基本词汇：核心词、基本形
    case derivativeForms = 1      // 派生形式：形容动词的各种形态
    case compoundWords = 2        // 复合词：由查询词构成的复合词
    case idioms = 3               // 惯用句、谚语
    case specialized = 4          // 专有名词、百科词条

    public var displayTitle: String {
        switch self {
        case .basicVocabulary:
            return "基本词汇"
        case .derivativeForms:
            return "派生形式"
        case .compoundWords:
            return "复合词"
        case .idioms:
            return "惯用句・谚语"
        case .specialized:
            return "专有名词"
        }
    }

    public var englishTitle: String {
        switch self {
        case .basicVocabulary:
            return "Basic Vocabulary"
        case .derivativeForms:
            return "Derivative Forms"
        case .compoundWords:
            return "Compound Words"
        case .idioms:
            return "Idioms & Proverbs"
        case .specialized:
            return "Specialized Terms"
        }
    }

    public static func < (lhs: SearchResultCategory, rhs: SearchResultCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Groups search results by category for organized display
public struct SearchResultGroup: Identifiable, Sendable {
    public let id: String
    public let category: SearchResultCategory
    public let results: [SearchResult]

    public init(category: SearchResultCategory, results: [SearchResult]) {
        self.id = "\(category.rawValue)"
        self.category = category
        self.results = results
    }
}

/// Helper to categorize search results
public struct SearchResultCategorizer {

    /// Categorize a single search result based on its characteristics
    public static func categorize(_ result: SearchResult, query: String) -> SearchResultCategory {
        let entry = result.entry
        let headword = entry.headword
        let headwordLength = headword.count
        let queryLength = query.count

        // 1. Check for idioms/proverbs (long phrases, expressions)
        if isIdiomOrProverb(entry) {
            return .idioms
        }

        // 2. Check for specialized terms (encyclopedic, proper nouns)
        if isSpecializedTerm(entry) {
            return .specialized
        }

        // 3. Check for derivative forms (形容动词派生形)
        if isDerivativeForm(entry, query: query) {
            return .derivativeForms
        }

        // 4. Check for compound words (contains query but longer)
        // 复合词：包含查询词但明显更长的词
        if headwordLength > queryLength + 1 {
            return .compoundWords
        }

        // 5. Default: basic vocabulary
        return .basicVocabulary
    }

    /// Group search results by category
    public static func groupResults(_ results: [SearchResult], query: String) -> [SearchResultGroup] {
        // Categorize each result
        var categorized: [SearchResultCategory: [SearchResult]] = [:]

        for result in results {
            let category = categorize(result, query: query)
            categorized[category, default: []].append(result)
        }

        // Convert to groups and sort by category priority
        let groups = categorized.map { category, results in
            SearchResultGroup(category: category, results: results)
        }.sorted { $0.category < $1.category }

        return groups
    }

    // MARK: - Private Helper Methods

    /// Check if entry is an idiom or proverb
    private static func isIdiomOrProverb(_ entry: DictionaryEntry) -> Bool {
        // 1. Check part of speech for "expressions" or "phrases"
        let hasExpressionPOS = entry.senses.contains { sense in
            sense.partOfSpeech.lowercased().contains("expression") ||
            sense.partOfSpeech.lowercased().contains("phrases") ||
            sense.partOfSpeech.lowercased().contains("clauses")
        }

        // 2. Check headword length (idioms are usually long)
        let isLongPhrase = entry.headword.count > 6

        // 3. Check for common idiom patterns (contains particles/grammar markers)
        let hasGrammarMarkers = entry.headword.contains("は") ||
                                entry.headword.contains("が") ||
                                entry.headword.contains("を") ||
                                entry.headword.contains("に") ||
                                entry.headword.contains("で")

        return hasExpressionPOS || (isLongPhrase && hasGrammarMarkers)
    }

    /// Check if entry is a specialized/encyclopedic term
    private static func isSpecializedTerm(_ entry: DictionaryEntry) -> Bool {
        // Check for specialized POS tags
        let hasSpecializedPOS = entry.senses.contains { sense in
            sense.partOfSpeech.lowercased().contains("wikipedia") ||
            sense.partOfSpeech.lowercased().contains("place") ||
            sense.partOfSpeech.lowercased().contains("person") ||
            sense.partOfSpeech.lowercased().contains("organization")
        }

        // Check for very low frequency (uncommon words)
        let isUncommon = entry.frequencyRank ?? Int.max > 10000

        return hasSpecializedPOS || isUncommon
    }

    /// Check if entry is a derivative form of the query
    private static func isDerivativeForm(_ entry: DictionaryEntry, query: String) -> Bool {
        let headword = entry.headword

        // Common adjectival noun derivatives
        // 静か → 静かな、静かに、静かさ、静かだ
        if headword.hasPrefix(query) && headword.count <= query.count + 2 {
            let suffix = String(headword.dropFirst(query.count))
            let derivativeSuffixes = ["な", "に", "さ", "だ", "で", "であり"]
            return derivativeSuffixes.contains { suffix.hasPrefix($0) }
        }

        return false
    }
}