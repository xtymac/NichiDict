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

        // Detect if this looks like English/Chinese query BEFORE normalization
        // This is important because English words shouldn't go through romaji conversion
        let useReverseSearch = shouldTryReverseSearch(query: sanitizedQuery, scriptType: scriptType)
        let isEnglishQuery = isLikelyEnglishQuery(query: sanitizedQuery, scriptType: scriptType)

        // Step 3: Normalize query
        let normalizedQuery: String
        switch scriptType {
        case .romaji:
            // IMPORTANT: Don't normalize English queries as romaji
            // e.g., "six" should stay "six", not be converted to "shix"
            if isEnglishQuery {
                normalizedQuery = sanitizedQuery
            } else {
                normalizedQuery = RomajiConverter.normalizeForSearch(sanitizedQuery)
            }
        default:
            // Convert katakana to hiragana for better matching
            // データ → でーた
            normalizedQuery = sanitizedQuery.katakanaToHiragana()
        }

        // Step 4: Execute database search
        let searchLimit = min(maxResults, 100)
        var dbResults: [DictionaryEntry] = []
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

            // If no results and query ends with "する", try searching without "する"
            // This handles suru-verbs like "勉強する" → "勉強"
            if dbResults.isEmpty && normalizedQuery.hasSuffix("する") {
                let baseQuery = String(normalizedQuery.dropLast(2)) // Remove "する"
                if !baseQuery.isEmpty {
                    print("🔍 SearchService: No results for '\(normalizedQuery)', trying base form '\(baseQuery)'")
                    dbResults = try await dbService.searchEntries(
                        query: baseQuery,
                        limit: searchLimit
                    )
                    print("🔍 SearchService: Base form search returned \(dbResults.count) results")
                }
            }
        }
        
        // Step 5: Classify match types and create SearchResults
        print("🔍 DEBUG SearchService: dbResults order before map:")
        for (index, entry) in dbResults.enumerated() {
            print("  \(index + 1). \(entry.headword)")
        }

        let searchResults = dbResults.map { entry in
            let matchType = classifyMatchType(
                entry: entry,
                query: normalizedQuery,
                scriptType: scriptType,
                useReverseSearch: useReverseSearch
            )
            let (relevance, bucket) = calculateRelevanceAndBucket(
                entry: entry,
                matchType: matchType,
                query: normalizedQuery,
                useReverseSearch: useReverseSearch
            )
            let groupType = determineGroupType(
                entry: entry,
                matchType: matchType
            )
            return SearchResult(
                id: entry.id,
                entry: entry,
                matchType: matchType,
                relevanceScore: relevance,
                bucket: bucket,
                groupType: groupType
            )
        }

        print("🔍 DEBUG SearchService: searchResults order after map:")
        for (index, result) in searchResults.enumerated() {
            print("  \(index + 1). \(result.entry.headword) (bucket: \(result.bucket), score: \(result.relevanceScore))")
        }

        // Step 6: Rank results
        // IMPORTANT: Both forward and reverse search now use SQL-based ordering
        // SQL ORDER BY provides comprehensive ranking:
        //   Forward: match_priority → JLPT existence → JLPT level → frequency → length
        //   Reverse: core native → main verb boost → JLPT existence → semantic → sense order → idiom → frequency → POS → parenthetical → katakana → match quality
        let ranked: [SearchResult]
        ranked = searchResults
        if useReverseSearch {
            print("🔍 DEBUG SearchService: Reverse search - using SQL ordering (no client-side sort)")
        } else {
            print("🔍 DEBUG SearchService: Forward search - using SQL ordering (no client-side sort)")
        }

        // Old code (disabled): Client-side sorting that was overriding SQL's JLPT prioritization
        /*
        if useReverseSearch {
            ranked = searchResults
        } else {
            ranked = searchResults.sorted { lhs, rhs in
                // Primary: Bucket (A → B → C → D)
                if lhs.bucket != rhs.bucket {
                    return lhs.bucket < rhs.bucket
                }

                // Secondary: Relevance score (within bucket, descending)
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
        */

        // Step 7: Limit to maxResults
        let finalResults = Array(ranked.prefix(maxResults))
        print("🔍 DEBUG SearchService: Final results order being returned:")
        for (index, result) in finalResults.enumerated() {
            print("  \(index + 1). \(result.entry.headword)")
        }
        return finalResults
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
    
    /// Calculate relevance score and bucket using gentler scoring system (-20 to +100)
    /// Returns: (relevanceScore, bucket)
    private func calculateRelevanceAndBucket(
        entry: DictionaryEntry,
        matchType: SearchResult.MatchType,
        query: String,
        useReverseSearch: Bool
    ) -> (Double, SearchResult.ResultBucket) {
        var score: Double = 0
        let lowercaseQuery = query.lowercased()
        let lowercaseHeadword = entry.headword.lowercased()
        let lowercaseReading = entry.readingHiragana.lowercased()

        // 1. Match type scoring (exact +80, prefix +15, contains +4)
        let isExactHeadword = lowercaseHeadword == lowercaseQuery
        let isLemmaMatch = lowercaseReading == lowercaseQuery && !isExactHeadword

        if isExactHeadword {
            score += 80
        } else if isLemmaMatch {
            score += 40
        } else if matchType == .prefix {
            score += 15
        } else if matchType == .contains {
            score += 4
        }

        // 2. JLPT scoring (N5 +10, N4 +7, N3 +4, N2 +2)
        switch entry.jlptLevel {
        case "N5": score += 10
        case "N4": score += 7
        case "N3": score += 4
        case "N2": score += 2
        default: break
        }

        // 3. Frequency scoring (JMdict frequency ranks + Wikipedia)
        // IMPORTANT: Frequency scores must be high enough to prioritize ANY word with frequency
        // over words without frequency (which might get +2 from noun POS or +5 from adjective POS)
        // Minimum frequency bonus is +3 to ensure it beats noun(+2) and adjective(+5) bonuses
        if let frequencyRank = entry.frequencyRank {
            if frequencyRank <= 10 {
                score += 12  // news1/ichi1 equivalent (highest priority)
            } else if frequencyRank <= 30 {
                score += 9  // nf11-30
            } else if frequencyRank <= 50 {
                score += 7  // nf31-50
            } else if frequencyRank <= 200 {
                score += 5  // Medium frequency (JMdict tier 2 + Wikipedia high freq)
            } else if frequencyRank <= 1000 {
                score += 4  // Low frequency
            } else if frequencyRank <= 5000 {
                score += 3  // Very low frequency (still beats noun/adjective bonuses)
            }
        }

        // 4. Part of speech bonus
        // Basic adjectives/verbs: +5, Common noun phrases: +2
        if let pos = entry.senses.first?.partOfSpeech {
            if pos.contains("adj-i") || pos.contains("v1") || pos.contains("v5") {
                score += 5  // Basic adjectives and verbs
            } else if pos.contains("n") && !pos.contains("n-pr") {
                score += 2  // Common nouns (not proper nouns)
            }
        }

        // 4.5. Suffix pattern bonus: X+嫌い, X+好き (common suffix compounds)
        // e.g., 大嫌い, 人嫌い, 本好き, etc.
        // These are natural compound nouns that should rank higher than grammar forms
        var hasSuffixPattern = false
        if !isExactHeadword && !isLemmaMatch {
            // Check if entry ends with common adjective suffixes
            let commonSuffixes = ["嫌い", "ぎらい", "好き", "ずき"]
            for suffix in commonSuffixes {
                if entry.headword.hasSuffix(suffix) && entry.headword != suffix && entry.headword.count > suffix.count {
                    score += 8  // Suffix pattern bonus (increased to prioritize compounds over grammar forms)
                    hasSuffixPattern = true
                    break
                }
            }
        }

        // 4.6. Common word whitelist (high-frequency suffix compounds)
        // Priority order: 大嫌い > 人嫌い > others
        // These boost common compounds above grammar forms like 嫌いなく
        if entry.headword == "大嫌い" {
            score += 8  // Highest priority (most common in textbooks)
        } else if entry.headword == "人嫌い" {
            score += 6  // High priority
        } else {
            let commonWords = ["食わず嫌い", "大好き", "読書好き"]
            if commonWords.contains(entry.headword) {
                score += 6  // Extra boost for other common compounds
            }
        }

        // 4.7. Rare single-kanji prefix penalty
        // Single kanji + 嫌い compounds without frequency data are likely uncommon
        // e.g., "出嫌い" should rank lower than "大嫌い"
        if hasSuffixPattern && entry.frequencyRank == nil {
            // Check if it's a single-kanji prefix (e.g., "出嫌い" = 1 kanji + 嫌い)
            let kanjiCount = entry.headword.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
            if kanjiCount == 1 {
                score -= 6  // Penalize rare single-kanji compounds
            }
        }

        // 8. Common pattern bonus: 「〜の好き」「〜もの好き」etc. (+5, applied early)
        // This helps natural phrases like「新しいもの好き」rank higher than specialized terms
        let commonPatternBonus = detectCommonPatternBonus(
            headword: entry.headword,
            reading: entry.readingHiragana
        )
        let hasCommonPattern = commonPatternBonus > 0
        score += commonPatternBonus

        // 5. Length penalty: max(0, lenRatio-1)*(-4), capped at -8
        // For common patterns (〜好き) or high-frequency words, apply reduced penalty
        // For contains matches, apply STRONGER penalty to suppress compound words
        let lengthRatio = Double(entry.headword.count) / Double(max(query.count, 1))
        if lengthRatio > 1.0 {
            let basePenaltyMultiplier: Double
            if matchType == .contains {
                // Contains matches get 2x stronger length penalty
                // e.g., searching "嫌い" (2 chars), "嫌い箸" (3 chars) gets -4 instead of -2
                basePenaltyMultiplier = 8.0
            } else {
                basePenaltyMultiplier = 4.0
            }

            let basePenalty = min((lengthRatio - 1.0) * basePenaltyMultiplier, 16.0)

            // Reduce penalty for high-frequency words (they're verified common phrases)
            let isHighFrequency = (entry.frequencyRank ?? Int.max) <= 500
            let shouldReducePenalty = hasCommonPattern || isHighFrequency
            let penalty = shouldReducePenalty ? basePenalty * 0.5 : basePenalty
            score -= penalty
        }

        // 6. Phrase penalty: Only for [noun]+[particle]+[verb] patterns (-10)
        // Note: 名詞+の+名詞 (noun+no+noun) is NOT penalized
        // IMPORTANT: Skip phrase penalty for reverse search - phrases like "目を覚ます" are exactly what we want!
        let phrasePenalty = detectPhrasePenalty(
            headword: entry.headword,
            partOfSpeech: entry.senses.first?.partOfSpeech,
            useReverseSearch: useReverseSearch
        )
        score += phrasePenalty

        // 7. Proper noun penalty: -12 if proper noun and not exact/lemma
        if let pos = entry.senses.first?.partOfSpeech,
           pos.contains("n-pr") && !isExactHeadword && !isLemmaMatch {
            score -= 12
        }

        // 8. Intent-aware compound word penalty (CRITICAL for filtering unrelated compounds)
        // Detect query intent and apply stricter penalties for compounds
        let queryIsAdjective = query.hasSuffix("い") && query.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }

        if !isExactHeadword && !isLemmaMatch && entry.headword.count > query.count && !hasCommonPattern {
            // Check if entry starts with query (e.g., "嫌い箸" starts with "嫌い")
            if lowercaseHeadword.hasPrefix(lowercaseQuery) {
                let suffixStartIndex = entry.headword.index(entry.headword.startIndex, offsetBy: query.count)
                let suffix = String(entry.headword[suffixStartIndex...])

                if !suffix.isEmpty {
                    let firstChar = suffix.first!
                    let firstScalar = firstChar.unicodeScalars.first!

                    // Valid grammar suffixes for adjectives (な-adjectives)
                    let validSuffixes = ["な", "に", "だ", "です", "じゃ", "じゃない", "でも", "だった", "では", "なら", "さ", "なく"]
                    let isValidSuffix = validSuffixes.contains { suffix.hasPrefix($0) }

                    // Rule 2: Heavy penalty if query is followed by kanji (compound noun)
                    // e.g., "嫌い箸" - the "箸" is a separate word
                    // BUT: Skip penalty for entries with frequency data (they're verified real words)
                    if (0x4E00...0x9FFF).contains(firstScalar.value) {
                        // Kanji after query = compound noun, NOT a grammatical variant
                        let hasFrequency = entry.frequencyRank != nil
                        if !hasFrequency {
                            score -= 15  // Heavy penalty only for unverified compounds
                        }
                    }
                    // Rule 3: Light penalty if followed by hiragana but NOT a valid suffix
                    // BUT: Skip penalty for entries with frequency data (they're verified real words)
                    else if (0x3040...0x309F).contains(firstScalar.value) && !isValidSuffix {
                        let hasFrequency = entry.frequencyRank != nil
                        if !hasFrequency {
                            score -= 8  // Medium penalty only for unverified compounds
                        }
                    }
                    // Valid suffix: give grammar bonus (reduced to prioritize common compounds)
                    else if isValidSuffix {
                        score += 2  // Grammar variant bonus (reduced from 3 to let compounds rank higher)
                    }
                }
            }

            // Rule 4: Kanji match bonus/penalty
            // If query contains kanji, prioritize entries with same kanji
            let queryKanji = Set(query.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) })
            if !queryKanji.isEmpty {
                let entryKanji = Set(entry.headword.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) })
                let sharedKanji = queryKanji.intersection(entryKanji)

                if sharedKanji == queryKanji {
                    // Entry contains all query kanji: bonus
                    score += 6
                } else if sharedKanji.isEmpty {
                    // No shared kanji (e.g., 機雷 vs 嫌い): heavy penalty
                    score -= 12
                }
            }
        }

        // Determine bucket
        let bucket = determineBucket(
            entry: entry,
            matchType: matchType,
            isExactHeadword: isExactHeadword,
            isLemmaMatch: isLemmaMatch,
            query: query
        )

        // Debug logging for ranking issues
        if entry.headword.contains("新しい") && entry.headword != "新しい" {
            print("📊 Scoring '\(entry.headword)': score=\(score), bucket=\(bucket), bonus=\(commonPatternBonus), len=\(entry.headword.count)")
        }
        if entry.headword.contains("嫌い") {
            print("📊 嫌い Scoring '\(entry.headword)': score=\(score), bucket=\(bucket), matchType=\(matchType)")
        }

        // DEBUG: Log scores for 今日 searches
        if entry.headword.hasPrefix("今日") {
            print("📊 今日 DEBUG '\(entry.headword)' (reading: \(entry.readingHiragana)): score=\(String(format: "%.1f", score)), bucket=\(bucket), freq=\(entry.frequencyRank?.description ?? "nil"), jlpt=\(entry.jlptLevel ?? "nil"), matchType=\(matchType)")
        }

        return (score, bucket)
    }

    /// Detect phrase patterns and return penalty
    /// Only penalize [noun]+[particle]+[verb/suru-verb] patterns
    /// For reverse search (English→Japanese), we WANT phrases, so skip penalty
    private func detectPhrasePenalty(headword: String, partOfSpeech: String?, useReverseSearch: Bool) -> Double {
        // Skip phrase penalty for reverse search - expressions like "目を覚ます" are core translations!
        if useReverseSearch {
            return 0
        }

        // Check for particles: を、に、で、が、と、へ、から、まで
        let particles = ["を", "に", "で", "が", "へ", "から", "まで"]

        for particle in particles {
            if headword.contains(particle) {
                // Check if this looks like [noun]+[particle]+[verb] pattern
                // Simple heuristic: if headword contains particle and has verb-like ending
                // This is a conservative check to avoid false positives
                let verbEndings = ["る", "く", "す", "つ", "ぬ", "ぶ", "む", "う"]
                if verbEndings.contains(where: { headword.hasSuffix($0) }) {
                    return -10
                }
            }
        }

        // "と" particle needs special handling (can be part of quotations)
        if headword.contains("と") {
            // If it contains と and looks like a verb phrase
            if headword.hasSuffix("する") || headword.hasSuffix("言う") {
                return -10
            }
        }

        return 0
    }

    /// Detect common natural patterns that should rank higher
    /// Examples: 新しいもの好き、読書好き (patterns ending in 好き/zuki)
    private func detectCommonPatternBonus(headword: String, reading: String) -> Double {
        // Pattern 1: 〜の好き (explicit の particle)
        if headword.contains("の") && headword.hasSuffix("好き") {
            return 5
        }

        // Pattern 2: 〜もの好き / 物好き / 者好き (implicit の, common writings)
        if headword.hasSuffix("もの好き") || headword.hasSuffix("物好き") || headword.hasSuffix("者好き") {
            return 5
        }

        // Pattern 3: Reading-based fallback for 〜ずき (…zuki)
        // This catches variants where kanji is used for the modified noun
        // e.g., 新しいもの好き might have reading ending in ずき
        if reading.hasSuffix("ずき") && !headword.contains("の") {
            // Only apply if it's likely a compound (longer than just the standalone 好き)
            if headword.count > 2 && headword.hasSuffix("好き") {
                return 5
            }
        }

        return 0
    }

    /// Determine which bucket this result belongs to
    private func determineBucket(
        entry: DictionaryEntry,
        matchType: SearchResult.MatchType,
        isExactHeadword: Bool,
        isLemmaMatch: Bool,
        query: String
    ) -> SearchResult.ResultBucket {
        // A bucket: Exact match or lemma match
        if isExactHeadword || isLemmaMatch {
            return .exactMatch
        }

        // B bucket: Prefix match + high frequency
        // High frequency = JMdict news1|ichi1|nf≤30 OR has JLPT level
        if matchType == .prefix {
            let hasHighFrequency = (entry.frequencyRank ?? Int.max) <= 30
            let hasJLPT = entry.jlptLevel != nil

            if hasHighFrequency || hasJLPT {
                return .commonPrefixMatch
            }
        }

        // Check if this is a common pattern (〜の好き, 〜もの好き, etc.)
        // These should be in C bucket, not D bucket (specialized terms)
        let hasCommonPattern = detectCommonPatternBonus(
            headword: entry.headword,
            reading: entry.readingHiragana
        ) > 0

        // D bucket: Specialized terms (proper nouns, no JLPT, long)
        // BUT: Exclude common patterns like 〜もの好き
        let isProperNoun = entry.senses.first?.partOfSpeech.contains("n-pr") ?? false
        let isSpecialized = entry.jlptLevel == nil &&
                           entry.frequencyRank == nil &&
                           entry.headword.count > 4

        if !hasCommonPattern && (isProperNoun || isSpecialized) {
            return .specializedTerm
        }

        // C bucket: Everything else (general match + common patterns)
        return .generalMatch
    }

    /// Determine decorative group type for visual organization (does not affect sorting)
    /// - 基本词: Exact match results
    /// - 常用表达: Has JLPT level or frequency rank ≤ 200
    /// - 衍生词: Has frequency but rank > 200
    /// - 其他: No frequency data
    private func determineGroupType(
        entry: DictionaryEntry,
        matchType: SearchResult.MatchType
    ) -> SearchResult.GroupType {
        // 基本词: Exact match
        if matchType == .exact {
            return .basicWord
        }

        // 常用表达: JLPT level or high frequency (≤200)
        let hasJLPT = entry.jlptLevel != nil
        let hasHighFrequency = (entry.frequencyRank ?? Int.max) <= 200

        if hasJLPT || hasHighFrequency {
            return .commonPhrase
        }

        // 衍生词: Has frequency but lower rank (>200)
        if entry.frequencyRank != nil {
            return .derivative
        }

        // 其他: No frequency data
        return .other
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
