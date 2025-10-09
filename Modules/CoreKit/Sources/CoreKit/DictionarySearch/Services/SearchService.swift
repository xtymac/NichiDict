import Foundation

public protocol SearchServiceProtocol: Sendable {
    func search(query: String, maxResults: Int) async throws -> [SearchResult]
}

public struct SearchService: SearchServiceProtocol {
    private let dbService: DBServiceProtocol
    
    public init(dbService: DBServiceProtocol) {
        self.dbService = dbService
    }
    
    public func search(query: String, maxResults: Int) async throws -> [SearchResult] {
        // Step 1: Validate and sanitize input
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else {
            return []
        }
        
        // Step 2: Detect script type
        let scriptType = ScriptDetector.detect(trimmedQuery)
        
        // Step 3: Normalize query
        let normalizedQuery: String
        switch scriptType {
        case .romaji:
            normalizedQuery = RomajiConverter.normalizeForSearch(trimmedQuery)
        default:
            normalizedQuery = trimmedQuery
        }
        
        // Step 4: Execute database search
        let dbResults = try await dbService.searchEntries(
            query: normalizedQuery,
            limit: maxResults
        )
        
        // Step 5: Classify match types and create SearchResults
        let searchResults = dbResults.map { entry in
            let matchType = classifyMatchType(entry: entry, query: normalizedQuery)
            return SearchResult(
                id: entry.id,
                entry: entry,
                matchType: matchType,
                relevanceScore: calculateRelevance(entry: entry, matchType: matchType)
            )
        }
        
        // Step 6: Rank results
        let ranked = searchResults.sorted { lhs, rhs in
            // Primary: Match type
            if lhs.matchType != rhs.matchType {
                return lhs.matchType < rhs.matchType
            }
            
            // Secondary: Relevance score
            if lhs.relevanceScore != rhs.relevanceScore {
                return lhs.relevanceScore > rhs.relevanceScore
            }
            
            // Tertiary: Frequency rank
            let lhsRank = lhs.entry.frequencyRank ?? Int.max
            let rhsRank = rhs.entry.frequencyRank ?? Int.max
            return lhsRank < rhsRank
        }
        
        // Step 7: Limit to maxResults
        return Array(ranked.prefix(maxResults))
    }
    
    private func classifyMatchType(entry: DictionaryEntry, query: String) -> SearchResult.MatchType {
        let lowercaseQuery = query.lowercased()
        
        // Exact match check
        if entry.headword.lowercased() == lowercaseQuery ||
           entry.readingHiragana.lowercased() == lowercaseQuery ||
           entry.readingRomaji.lowercased() == lowercaseQuery {
            return .exact
        }
        
        // Prefix match check
        if entry.headword.lowercased().hasPrefix(lowercaseQuery) ||
           entry.readingHiragana.lowercased().hasPrefix(lowercaseQuery) ||
           entry.readingRomaji.lowercased().hasPrefix(lowercaseQuery) {
            return .prefix
        }
        
        // Contains match (default)
        return .contains
    }
    
    private func calculateRelevance(entry: DictionaryEntry, matchType: SearchResult.MatchType) -> Double {
        let matchScore = Double(matchType.sortOrder * 1000)
        let freqScore = Double(10000 - (entry.frequencyRank ?? 9999))
        return matchScore + freqScore
    }
}

public enum SearchError: Error, LocalizedError {
    case emptyQuery
    case queryTooLong(Int)
    case invalidCharacters
    case databaseUnavailable
    case searchFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Please enter a search term."
        case .queryTooLong(let length):
            return "Search query too long (\(length) characters). Maximum is 100."
        case .invalidCharacters:
            return "Search contains invalid characters."
        case .databaseUnavailable:
            return "Dictionary database is unavailable. Please restart the app."
        case .searchFailed(let error):
            return "Search failed: \(error.localizedDescription)"
        }
    }
}
