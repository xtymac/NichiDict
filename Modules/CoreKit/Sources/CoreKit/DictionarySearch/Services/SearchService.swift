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

        // Edge case: Query too long
        guard trimmedQuery.count <= 100 else {
            throw SearchError.queryTooLong(trimmedQuery.count)
        }

        // Edge case: Sanitize special characters that could break SQL/FTS
        let sanitizedQuery = sanitizeQuery(trimmedQuery)
        guard !sanitizedQuery.isEmpty else {
            throw SearchError.invalidCharacters
        }

        // Step 2: Detect script type
        let scriptType = ScriptDetector.detect(sanitizedQuery)
        print("🔍 SearchService: query='\(sanitizedQuery)' scriptType=\(scriptType)")

        // Step 3: Normalize query
        let normalizedQuery: String
        switch scriptType {
        case .romaji:
            normalizedQuery = RomajiConverter.normalizeForSearch(sanitizedQuery)
        default:
            // Convert katakana to hiragana for better matching
            // データ → でーた
            normalizedQuery = sanitizedQuery.katakanaToHiragana()
        }

        // Step 4: Execute database search
        let searchLimit = min(maxResults, 100)
        var dbResults: [DictionaryEntry] = []

        // Detect if this looks like English/Chinese query for reverse search
        let useReverseSearch = shouldTryReverseSearch(query: sanitizedQuery, scriptType: scriptType)
        let isEnglishQuery = isLikelyEnglishQuery(query: sanitizedQuery, scriptType: scriptType)
        print("🔍 SearchService: useReverseSearch=\(useReverseSearch) for query='\(sanitizedQuery)'")
        if useReverseSearch {
            print("🔍 SearchService: isEnglishQuery=\(isEnglishQuery)")
        }

        await ScriptDetectionMonitor.shared.record(
            query: sanitizedQuery,
            scriptType: scriptType,
            useReverseSearch: useReverseSearch
        )

        if useReverseSearch {
            // For English/Chinese queries, ONLY use reverse search
            // This prevents incorrect matches from forward search
            print("🔍 SearchService: Using REVERSE search for '\(normalizedQuery)'")

            // Extract semantic hints and core mappings for better ranking
            var semanticHint: String? = nil
            var searchQuery = normalizedQuery
            var coreHeadwords: Set<String>? = nil

            if isEnglishQuery {
                // Check for parenthetical hints like "japanese (language)"
                if EnglishJapaneseMapping.hasParenthetical(normalizedQuery) {
                    semanticHint = EnglishJapaneseMapping.extractSemanticHint(from: normalizedQuery)
                    searchQuery = EnglishJapaneseMapping.extractBaseWord(from: normalizedQuery)
                    print("🔍 SearchService: Extracted hint='\(semanticHint ?? "")' baseWord='\(searchQuery)'")

                    // If we have a semantic hint, try to get core mapping for it too
                    if let hint = semanticHint {
                        coreHeadwords = EnglishJapaneseMapping.canonicalHeadwords(forEnglishWord: hint)
                    }
                }

                // Get core native equivalents for the base word
                if coreHeadwords == nil {
                    coreHeadwords = EnglishJapaneseMapping.canonicalHeadwords(forEnglishWord: searchQuery)
                }

                if let coreHeadwords = coreHeadwords {
                    print("🔍 SearchService: Core native headwords: \(coreHeadwords)")
                }
            }

            dbResults = try await dbService.searchReverse(
                query: searchQuery,
                limit: searchLimit,
                isEnglishQuery: isEnglishQuery,
                semanticHint: semanticHint,
                coreHeadwords: coreHeadwords
            )
            print("🔍 SearchService: Reverse search returned \(dbResults.count) results")
        } else {
            // For Japanese queries, use forward search
            print("🔍 SearchService: Using FORWARD search for '\(normalizedQuery)'")
            dbResults = try await dbService.searchEntries(
                query: normalizedQuery,
                limit: searchLimit
            )
            print("🔍 SearchService: Forward search returned \(dbResults.count) results")
        }
        
        // Step 5: Classify match types and create SearchResults
        let searchResults = dbResults.map { entry in
            let matchType = classifyMatchType(
                entry: entry,
                query: normalizedQuery,
                scriptType: scriptType,
                useReverseSearch: useReverseSearch
            )
            return SearchResult(
                id: entry.id,
                entry: entry,
                matchType: matchType,
                relevanceScore: calculateRelevance(entry: entry, matchType: matchType, query: normalizedQuery)
            )
        }
        
        // Step 6: Rank results
        let ranked: [SearchResult]
        if useReverseSearch {
            ranked = searchResults
        } else {
            ranked = searchResults.sorted { lhs, rhs in
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
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }

                // Quaternary: Preserve database ordering by created_at
                if lhs.entry.createdAt != rhs.entry.createdAt {
                    return lhs.entry.createdAt < rhs.entry.createdAt
                }

                // Final fallback: stable ordering by id
                return lhs.entry.id < rhs.entry.id
            }
        }
        
        // Step 7: Limit to maxResults
        return Array(ranked.prefix(maxResults))
    }
    
    private func classifyMatchType(
        entry: DictionaryEntry,
        query: String,
        scriptType: ScriptType,
        useReverseSearch: Bool
    ) -> SearchResult.MatchType {
        if useReverseSearch {
            if let definitionMatch = bestDefinitionMatchQuality(for: entry, query: query) {
                switch definitionMatch {
                case .exact:
                    return .exact
                case .prefix:
                    return .prefix
                case .contains:
                    return .contains
                case .none:
                    break
                }
            }

            // Fallback: treat reverse-search hits without clear definition match as contains
            return .contains
        }

        let lowercaseQuery = query.lowercased()

        // Exact match check based on detected script
        switch scriptType {
        case .romaji:
            if entry.readingRomaji.lowercased() == lowercaseQuery {
                return .exact
            }
        default:
            // Headword exact match is the highest priority
            if entry.headword.lowercased() == lowercaseQuery {
                return .exact
            }

            // Reading-only match (homograph like 掏る when searching する)
            // Treated as prefix to allow headword-prefix matches to rank higher
            if entry.readingHiragana.lowercased() == lowercaseQuery ||
               entry.readingRomaji.lowercased() == lowercaseQuery {
                // If reading matches but headword doesn't, treat as prefix match
                // This allows "すると" to potentially rank higher than "掏る"
                return entry.headword.lowercased() == lowercaseQuery ? .exact : .prefix
            }
        }

        // Prefix match check
        switch scriptType {
        case .romaji:
            if entry.readingRomaji.lowercased().hasPrefix(lowercaseQuery) {
                return .prefix
            }
        default:
            if entry.headword.lowercased().hasPrefix(lowercaseQuery) ||
               entry.readingHiragana.lowercased().hasPrefix(lowercaseQuery) ||
               entry.readingRomaji.lowercased().hasPrefix(lowercaseQuery) {
                return .prefix
            }
        }

        // Contains match (default)
        return .contains
    }
    
    private func calculateRelevance(entry: DictionaryEntry, matchType: SearchResult.MatchType, query: String) -> Double {
        let matchScore = Double(matchType.sortOrder * 1000)
        let freqScore = Double(10000 - (entry.frequencyRank ?? 9999))

        // JLPT bonus: prioritize common words (N5 > N4 > N3 > N2 > N1)
        let jlptBonus: Double
        switch entry.jlptLevel {
        case "N5": jlptBonus = 5000  // Highest priority for beginner words
        case "N4": jlptBonus = 4000
        case "N3": jlptBonus = 3000
        case "N2": jlptBonus = 2000
        case "N1": jlptBonus = 1000
        default: jlptBonus = 0
        }

        // Exact character match bonus: headword exactly matches query
        // This prioritizes "する" (if it exists) over "掏る" when searching "する"
        let exactHeadwordBonus: Double = (entry.headword.lowercased() == query.lowercased()) ? 10000 : 0

        // Homograph penalty: reading matches but headword doesn't (同音異字)
        // Balanced penalty: preserves JLPT/frequency weight while discouraging homographs
        // Changed from -2000 to -1000 to maintain natural ranking (N5 > N4 for same match type)
        let homographPenalty: Double = (entry.readingHiragana.lowercased() == query.lowercased() &&
                                        entry.headword.lowercased() != query.lowercased()) ? -1000 : 0

        // Prefix match bonus: headword starts with query
        // Small bonus to distinguish grammar-type derivatives from reduplication
        // Reduced from 500 to 200 to preserve JLPT ranking (N5 掏る > N4 すると)
        let prefixBonus: Double = (entry.headword.lowercased().hasPrefix(query.lowercased()) &&
                                   entry.headword.lowercased() != query.lowercased()) ? 200 : 0

        // Length penalty: shorter words are more fundamental
        // Penalize longer words to prioritize "する" over "すると"
        let lengthPenalty = Double(entry.headword.count + entry.readingHiragana.count) * -10

        // TODO: Multi-sense penalty (future optimization)
        // Penalize entries with too many senses to avoid encyclopedia entries dominating results
        // Example: "する（為る／為す）" with 50+ senses should rank lower than simple words
        // Implementation note: Need to ensure senses are loaded or add sense_count field to DB
        // let sensePenalty = Double(entry.senses.count > 10 ? -100 : 0)

        return matchScore + freqScore + jlptBonus + exactHeadwordBonus + homographPenalty + prefixBonus + lengthPenalty
    }

    /// Sanitize query to prevent SQL injection and FTS5 syntax errors
    /// Removes or escapes characters that could break the search
    private func sanitizeQuery(_ query: String) -> String {
        // Remove FTS5 special characters that could cause syntax errors
        // Keep: letters, numbers, Japanese characters (hiragana, katakana, kanji), spaces
        // Note: We exclude hyphens as they can cause FTS5 syntax errors in certain contexts
        let allowedCharacterSet = CharacterSet.alphanumerics
            .union(CharacterSet.whitespaces)
            .union(CharacterSet(charactersIn: "ー")) // Japanese long vowel mark only
            // Japanese character ranges
            .union(CharacterSet(charactersIn: "\u{3040}"..."\u{309F}")) // Hiragana
            .union(CharacterSet(charactersIn: "\u{30A0}"..."\u{30FF}")) // Katakana
            .union(CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")) // Kanji (CJK Unified Ideographs)

        // Filter out disallowed characters
        let sanitized = query.unicodeScalars.filter { scalar in
            allowedCharacterSet.contains(scalar)
        }

        return String(String.UnicodeScalarView(sanitized))
    }

    /// Determine if we should try reverse search (English/Chinese → Japanese)
    private func shouldTryReverseSearch(query: String, scriptType: ScriptType) -> Bool {
        switch scriptType {
        case .romaji:
            return isLikelyEnglishQuery(query: query, scriptType: scriptType)

        case .kanji:
            // Pure kanji (4+ characters) is more likely Chinese input
            // Japanese text usually has kana mixed in
            return true  // Treat as Chinese for reverse search

        case .japaneseKanji:
            // Short kanji words (1-3 characters) are likely Japanese vocabulary
            // Examples: 行く, 見る, 食べる, 飲む, 本, 人
            return false  // Use forward search (Japanese)

        case .hiragana, .katakana, .mixed:
            // Contains Japanese kana - definitely Japanese
            return false
        }
    }

    private func isLikelyEnglishQuery(query: String, scriptType: ScriptType) -> Bool {
        guard scriptType == .romaji else { return false }

        let lowerQuery = query.lowercased()

        let commonEnglishWords = [
            "go", "do", "be", "am", "is", "are", "was", "were",
            "eat", "run", "see", "get", "make", "take", "come",
            "know", "think", "look", "want", "give", "use", "find",
            "tell", "ask", "work", "feel", "try", "leave", "call",
            "star", "car", "bus", "train", "game", "play", "phone",
            "music", "movie"
        ]

        if commonEnglishWords.contains(lowerQuery) {
            return true
        }

        let japaneseParticles = ["wa", "ga", "wo", "o", "ni", "de", "to", "ya", "ka", "ne", "yo"]
        if japaneseParticles.contains(lowerQuery) {
            return false
        }

        guard query.count > 1 else {
            return false
        }

        let japaneseRomajiPrefixes = ["ta", "ka", "sa", "na", "ha", "ma", "ya", "ra"]
        if japaneseRomajiPrefixes.contains(where: { prefix in
            lowerQuery.hasPrefix(prefix + "be") || lowerQuery.hasPrefix(prefix + "ku")
        }) {
            return false
        }

        return true
    }

    private func bestDefinitionMatchQuality(for entry: DictionaryEntry, query: String) -> DefinitionMatchQuality? {
        guard !entry.senses.isEmpty else {
            return nil
        }

        var bestMatch: DefinitionMatchQuality = .none
        let lowerQuery = query.lowercased()
        let whitespaceSet = CharacterSet.whitespacesAndNewlines

        for sense in entry.senses {
            let english = sense.definitionEnglish.lowercased()
            let englishSegments = english.split(separator: ";")

            for segment in englishSegments {
                let trimmed = segment.trimmingCharacters(in: whitespaceSet)
                if trimmed.isEmpty { continue }

                if trimmed == lowerQuery || trimmed == "to \(lowerQuery)" {
                    return .exact
                }

                // Treat clarifying punctuation (e.g., "japanese (language)") as exact
                if trimmed.hasPrefix(lowerQuery) {
                    let remainder = trimmed.dropFirst(lowerQuery.count)
                    let remainderTrimmed = remainder.trimmingCharacters(in: whitespaceSet)
                    if remainderTrimmed.isEmpty {
                        return .exact
                    }
                    if let firstScalar = remainderTrimmed.unicodeScalars.first,
                       !CharacterSet.alphanumerics.contains(firstScalar) {
                        return .exact
                    }
                }

                if trimmed.hasPrefix("to \(lowerQuery)") {
                    bestMatch = bestMatch.upgrading(to: .exact)
                    continue
                }

                if trimmed.hasPrefix(lowerQuery + " ") ||
                    trimmed.hasPrefix(lowerQuery + "-") ||
                    trimmed.hasPrefix(lowerQuery + "(") {
                    bestMatch = bestMatch.upgrading(to: .prefix)
                    continue
                }

                let tokens = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                if tokens.contains(lowerQuery) {
                    bestMatch = bestMatch.upgrading(to: .contains)
                }
            }

            let chineseCandidates = [
                sense.definitionChineseSimplified,
                sense.definitionChineseTraditional
            ]

            for candidate in chineseCandidates {
                guard let candidate, !candidate.isEmpty else { continue }
                let segments = candidate.split(separator: ";")

                for rawSegment in segments {
                    let trimmed = rawSegment.trimmingCharacters(in: whitespaceSet)
                    if trimmed.isEmpty { continue }

                    if trimmed == query {
                        return .exact
                    }

                    if trimmed.hasPrefix(query) {
                        bestMatch = bestMatch.upgrading(to: .prefix)
                        continue
                    }

                    if trimmed.contains(query) {
                        bestMatch = bestMatch.upgrading(to: .contains)
                    }
                }
            }
        }

        return bestMatch == .none ? nil : bestMatch
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

private enum DefinitionMatchQuality: Int {
    case exact = 0
    case prefix = 1
    case contains = 2
    case none = 3

    func upgrading(to newQuality: DefinitionMatchQuality) -> DefinitionMatchQuality {
        return rawValue < newQuality.rawValue ? self : newQuality
    }
}
