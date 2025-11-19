import Foundation
@preconcurrency import GRDB

public protocol DBServiceProtocol: Sendable {
    func searchEntries(query: String, limit: Int) async throws -> [DictionaryEntry]
    func searchReverse(
        query: String,
        limit: Int,
        isEnglishQuery: Bool,
        semanticHint: String?,
        coreHeadwords: Set<String>?
    ) async throws -> [DictionaryEntry]
    func fetchEntry(id: Int) async throws -> DictionaryEntry?
    func validateDatabaseIntegrity() async throws -> Bool
}

public struct DBService: DBServiceProtocol {
    private let dbQueue: DatabaseQueue
    
    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
    
    public func searchEntries(query: String, limit: Int) async throws -> [DictionaryEntry] {
        // Handle empty query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        return try await dbQueue.read { db in
            // Verb stem extraction for better matching
            // If query ends with verb suffix (る、く、ぐ、す、つ、ぬ、ぶ、む、う), also search stem
            var ftsQuery = query + "*"
            var stemQuery: String? = nil

            if query.count >= 2 {
                let verbSuffixes = ["る", "く", "ぐ", "す", "つ", "ぬ", "ぶ", "む", "う"]
                if verbSuffixes.contains(where: { query.hasSuffix($0) }) {
                    // Extract stem by removing last character
                    let stem = String(query.dropLast())
                    // Only use stem matching if stem is at least 2 characters
                    // This prevents over-matching for single-char stems like "す" from "する"
                    // which would match 鋭い (するどい), 鯣 (するめ), etc.
                    if stem.count >= 2 {
                        stemQuery = stem
                        // Combine queries: search for both "食べる*" OR "食べ*"
                        ftsQuery = query + "* OR " + stem + "*"
                        print("🔍 DBService: Verb detected. Stem: '\(stem)', FTS query: '\(ftsQuery)'")
                    } else {
                        print("🔍 DBService: Verb stem too short ('\(stem)'), skipping stem matching")
                    }
                }
            }

            // Simple FTS5 search query with precise ranking
            let sql = """
            SELECT e.*,
                CASE
                    -- Special: For する query, 為る (canonical suru verb) always comes first
                    WHEN ? = 'する' AND e.headword = '為る' THEN 0
                    -- Priority 1: Exact headword match (e.g., する itself if it exists)
                    WHEN e.headword = ? THEN 1
                    -- Priority 2: Reading exact match (e.g., 掏る, 刷る - homophones, 漸と for やっと)
                    -- BOOSTED: This now comes BEFORE prefix matches, so base words appear first
                    WHEN e.reading_hiragana = ? THEN 2
                    -- Priority 3: Headword prefix match (e.g., すると, するべき)
                    WHEN e.headword LIKE ? || '%' THEN 3
                    -- Priority 4: Romaji match
                    WHEN e.reading_romaji = ? THEN 4
                    -- Priority 5: Reading prefix match (e.g., すると, するべき)
                    WHEN e.reading_hiragana LIKE ? || '%' THEN 5
                    ELSE 6
                END AS match_priority,
                -- Compound word detection: penalize unrelated homophones
                -- True compounds use grammatical particles (の, で, と, に, が, を, etc.)
                -- e.g., やっとの事で (compound) vs やっとこ (unrelated noun = pincers)
                CASE
                    -- Check if this is a prefix match (not exact)
                    WHEN e.headword != ? AND e.reading_hiragana != ?
                         AND (e.headword LIKE ? || '%' OR e.reading_hiragana LIKE ? || '%')
                    THEN
                        CASE
                            -- Priority 0: Contains particles → true grammatical compound
                            -- Pattern: [query]の, [query]で, [query]と, etc.
                            WHEN e.reading_hiragana LIKE ? || 'の%'
                              OR e.reading_hiragana LIKE ? || 'で%'
                              OR e.reading_hiragana LIKE ? || 'と%'
                              OR e.reading_hiragana LIKE ? || 'に%'
                              OR e.reading_hiragana LIKE ? || 'が%'
                              OR e.reading_hiragana LIKE ? || 'を%'
                              OR e.reading_hiragana LIKE ? || 'から%'
                              OR e.reading_hiragana LIKE ? || 'まで%'
                            THEN 0
                            -- Priority 1: Short extension (≤2 chars) → likely semantic compound
                            -- e.g., やっと(3) → やっとこさ(5) = +2 chars
                            WHEN LENGTH(e.reading_hiragana) - LENGTH(?) <= 2 THEN 1
                            -- Priority 2: Longer extension (3+ chars) → likely unrelated
                            -- e.g., やっと(3) → やっとかめ(5) = +2, but check other signals
                            ELSE 2
                        END
                    ELSE 0  -- Not a prefix match, skip penalty
                END AS compound_priority,
                -- Suru-verb priority: For する query, prefer actual suru verbs over homophones
                -- This is determined by checking if word_senses contains "suru verb"
                (SELECT CASE
                    WHEN EXISTS (
                        SELECT 1 FROM word_senses ws
                        WHERE ws.entry_id = e.id
                        AND ws.part_of_speech LIKE '%suru verb%'
                    ) THEN 0
                    ELSE 1
                END) AS suru_verb_priority
            FROM dictionary_entries e
            JOIN dictionary_fts fts ON e.id = fts.rowid
            WHERE dictionary_fts MATCH ?
            ORDER BY
                match_priority ASC,
                -- Compound word priority: true grammatical compounds > short compounds > unrelated homophones
                compound_priority ASC,
                -- JLPT existence: words with JLPT levels come before those without
                CASE WHEN e.jlpt_level IS NOT NULL THEN 0 ELSE 1 END ASC,
                -- JLPT level priority: N5 > N4 > N3 > N2 > N1
                -- IMPORTANT: 為る should be N5 (it's the canonical "to do" verb), but JMDict marks it as N3
                -- This is a known data issue - override it here
                CASE
                    WHEN e.headword = '為る' THEN 0  -- Override: treat 為る as N5
                    WHEN e.jlpt_level = 'N5' THEN 0
                    WHEN e.jlpt_level = 'N4' THEN 1
                    WHEN e.jlpt_level = 'N3' THEN 2
                    WHEN e.jlpt_level = 'N2' THEN 3
                    WHEN e.jlpt_level = 'N1' THEN 4
                    ELSE 5
                END ASC,
                -- Katakana penalty: Demote katakana loanwords (するーぷ, するたん, etc.)
                -- Only applies to words starting with katakana after the query prefix
                -- e.g., for "する", penalize "するーぷ" but not "すると"
                CASE
                    WHEN e.headword GLOB ? || '[ァ-ヴー]*' THEN 1
                    ELSE 0
                END ASC,
                COALESCE(e.frequency_rank, 999999) ASC,
                LENGTH(e.headword) ASC
            LIMIT ?
            """

            var entries = try DictionaryEntry.fetchAll(db, sql: sql, arguments: [
                query, query, query, query, query, query,  // match_priority (6 params)
                query, query, query, query,                 // compound_priority: check if prefix match (4 params)
                query, query, query, query, query, query, query, query,  // compound_priority: particle checks (8 params)
                query,                                      // compound_priority: length check (1 param)
                ftsQuery,                                   // FTS MATCH query
                query,                                      // katakana penalty
                limit                                       // LIMIT
            ])

            // Only find reading-based variants if query is pure hiragana/katakana (reading search)
            // This prevents showing unrelated homonyms when searching with kanji
            // e.g., searching "元気" should not show "原器", "衡気", etc.
            var existingIds = Set(entries.map { $0.id })
            let isPureKanaQuery = query.unicodeScalars.allSatisfy { scalar in
                // Hiragana range: U+3040 - U+309F
                // Katakana range: U+30A0 - U+30FF
                (0x3040...0x309F).contains(scalar.value) || (0x30A0...0x30FF).contains(scalar.value)
            }

            if isPureKanaQuery {
                // For pure kana queries (e.g., "げんき"), find all kanji variants
                let variantsSql = """
                SELECT DISTINCT e.*,
                    CASE
                        WHEN e.headword = ? THEN 0
                        WHEN e.reading_hiragana = ? THEN 1
                        ELSE 2
                    END AS variant_priority
                FROM dictionary_entries e
                WHERE e.reading_hiragana = ?
                ORDER BY
                    variant_priority ASC,
                    CASE WHEN e.jlpt_level IS NOT NULL THEN 0 ELSE 1 END ASC,
                    CASE
                        WHEN e.jlpt_level = 'N5' THEN 0
                        WHEN e.jlpt_level = 'N4' THEN 1
                        WHEN e.jlpt_level = 'N3' THEN 2
                        WHEN e.jlpt_level = 'N2' THEN 3
                        WHEN e.jlpt_level = 'N1' THEN 4
                        ELSE 5
                    END ASC,
                    COALESCE(e.frequency_rank, 999999) ASC,
                    LENGTH(e.headword) ASC
                """

                let variantEntries = try DictionaryEntry.fetchAll(db, sql: variantsSql, arguments: [query, query, query])

                // Add variants not already in results
                var allEntries = entries
                for variant in variantEntries where !existingIds.contains(variant.id) {
                    allEntries.append(variant)
                    existingIds.insert(variant.id)
                }
                entries = allEntries
            }

            // Add contains matches (e.g., "頭が古い" when searching "古い")
            // Only add if we haven't hit the limit yet
            // Exclude entries already matched by FTS prefix search (both headword and reading)
            // Limit to words not much longer than query to avoid distant compound words
            if entries.count < limit {
                print("🔍 DBService: Adding contains matches. Current count: \(entries.count), limit: \(limit)")

                // Calculate max length: query + 3 characters
                // e.g., searching "嫌い" (2 chars) allows up to 5 chars
                // This filters out long compounds like "嫌い箸使い方" but keeps "嫌いなく"
                let maxLength = query.count + 3

                let containsSql = """
                SELECT DISTINCT e.*
                FROM dictionary_entries e
                WHERE (e.headword LIKE '%' || ? || '%' OR e.reading_hiragana LIKE '%' || ? || '%')
                  AND e.headword NOT LIKE ? || '%'
                  AND e.reading_hiragana NOT LIKE ? || '%'
                  AND LENGTH(e.headword) <= ?
                ORDER BY
                    CASE WHEN e.jlpt_level IS NOT NULL THEN 0 ELSE 1 END ASC,
                    CASE
                        WHEN e.jlpt_level = 'N5' THEN 0
                        WHEN e.jlpt_level = 'N4' THEN 1
                        WHEN e.jlpt_level = 'N3' THEN 2
                        WHEN e.jlpt_level = 'N2' THEN 3
                        WHEN e.jlpt_level = 'N1' THEN 4
                        ELSE 5
                    END ASC,
                    COALESCE(e.frequency_rank, 999999) ASC,
                    LENGTH(e.headword) ASC
                LIMIT ?
                """

                let containsEntries = try DictionaryEntry.fetchAll(db, sql: containsSql, arguments: [query, query, query, query, maxLength, limit - entries.count])
                print("🔍 DBService: Contains query found \(containsEntries.count) entries (max length: \(maxLength))")

                // Add contains matches not already in results
                var addedCount = 0
                for entry in containsEntries where !existingIds.contains(entry.id) {
                    entries.append(entry)
                    existingIds.insert(entry.id)
                    addedCount += 1
                }
                print("🔍 DBService: Added \(addedCount) new contains entries. Total now: \(entries.count)")
            }

            // Add kanji-based matches for compound words (e.g., "安物", "安売り" when searching "安い")
            // Extract kanji from query and find short words starting with that kanji
            // ONLY match words with similar readings to avoid unrelated words
            if entries.count < limit {
                let kanjiChars = query.unicodeScalars.filter { scalar in
                    // Check if character is in CJK Unified Ideographs range
                    (0x4E00...0x9FFF).contains(scalar.value)
                }

                let hiraganaChars = query.unicodeScalars.filter { scalar in
                    (0x3040...0x309F).contains(scalar.value)  // Hiragana range
                }

                // Only run kanji-based search if query contains BOTH kanji AND hiragana
                // This ensures "安い" triggers it but "安心" doesn't
                if !kanjiChars.isEmpty && !hiraganaChars.isEmpty {
                    let firstKanji = String(kanjiChars.prefix(1))
                    let readingPrefix = String(hiraganaChars.prefix(2))

                    print("🔍 DBService: Adding kanji-based matches for '\(firstKanji)' with reading '\(readingPrefix)*'. Current count: \(entries.count)")

                    // CRITICAL: Filter by reading prefix to exclude unrelated words
                    // e.g., when searching "安い" (やすい), only match "安物" (やすもの),
                    // NOT "安心" (あんしん) or "安全" (あんぜん)
                    let kanjiSql = """
                    SELECT DISTINCT e.*
                    FROM dictionary_entries e
                    WHERE e.headword LIKE ? || '%'
                      AND e.headword != ?
                      AND e.reading_hiragana LIKE ? || '%'
                      AND LENGTH(e.headword) <= 4
                    ORDER BY
                        LENGTH(e.headword) ASC,
                        COALESCE(e.frequency_rank, 999999) ASC
                    LIMIT ?
                    """

                    let kanjiEntries = try DictionaryEntry.fetchAll(db, sql: kanjiSql, arguments: [firstKanji, query, readingPrefix, limit - entries.count])
                    print("🔍 DBService: Kanji query found \(kanjiEntries.count) entries")

                    var kanjiAddedCount = 0
                    for entry in kanjiEntries where !existingIds.contains(entry.id) {
                        entries.append(entry)
                        existingIds.insert(entry.id)
                        kanjiAddedCount += 1
                    }
                    print("🔍 DBService: Added \(kanjiAddedCount) new kanji-based entries. Total now: \(entries.count)")
                }
            }

            // Load senses for each entry
            for i in 0..<entries.count {
                let senses = try WordSense
                    .filter(Column("entry_id") == entries[i].id)
                    .order(Column("sense_order"))
                    .fetchAll(db)
                entries[i].senses = senses
            }

            // Special handling for words that are usually written in kana but have rare kanji forms
            // Examples: する→為る, やっと→漸と, すぐ→直ぐ
            // Problem: JMDict often only has the kanji variant, not the common kana form
            // Solution: Create virtual kana entries for common words that should appear first

            // Define words that should have virtual kana entries (usually kana words)
            let usuallyKanaWords: [String: (jlptLevel: String?, isAdverb: Bool)] = [
                "する": ("N5", false),      // verb
                "やっと": ("N4", true),     // adverb
                "すぐ": ("N5", true),       // adverb
                "まだ": ("N5", true),       // adverb
                "もう": ("N5", true),       // adverb
                "ずっと": ("N4", true),     // adverb
                "たくさん": ("N5", true),   // adverb/na-adj
                "とても": ("N5", true),     // adverb
                "ちょっと": ("N5", true),   // adverb
            ]

            if let (jlptLevel, _) = usuallyKanaWords[query] {
                // Check if pure hiragana entry already exists
                let hasHiraganaEntry = entries.contains { $0.headword == query }

                if !hasHiraganaEntry {
                    // Find kanji variant to clone from (first entry with matching reading)
                    if let kanjiEntry = entries.first(where: {
                        $0.readingHiragana == query && $0.headword != query
                    }) {
                        print("🔍 DBService: Creating virtual hiragana '\(query)' entry from '\(kanjiEntry.headword)'")
                        // Create virtual entry with negative ID to indicate it's synthetic
                        let virtualEntry = DictionaryEntry(
                            id: -1,  // Negative ID for virtual entry
                            headword: query,  // Pure hiragana
                            readingHiragana: kanjiEntry.readingHiragana,
                            readingRomaji: kanjiEntry.readingRomaji,
                            frequencyRank: kanjiEntry.frequencyRank,
                            pitchAccent: kanjiEntry.pitchAccent,
                            jlptLevel: jlptLevel,
                            createdAt: kanjiEntry.createdAt,
                            senses: kanjiEntry.senses  // Use same definitions
                        )
                        // Insert at beginning
                        entries.insert(virtualEntry, at: 0)
                        print("🔍 DBService: Virtual '\(query)' entry created and inserted at position 0")
                    }
                }
            }

            // Final sorting: demote rare kanji variants (uk = usually kana)
            // Priority order: pure kana form > common kanji > rare kanji
            // Example: やっと > [other compounds] > 漸と (rare kanji)
            let finalEntries = entries.sorted { entry1, entry2 in
                let isRare1 = entry1.isRareKanji
                let isRare2 = entry2.isRareKanji

                // Rule 1: Non-rare entries always come before rare ones
                if isRare1 != isRare2 {
                    return !isRare1  // true comes first, so !isRare1 means non-rare first
                }

                // Rule 2: If both are same rarity, preserve SQL order (stable sort)
                return false
            }

            return finalEntries
        }
    }

    public func searchReverse(
        query: String,
        limit: Int,
        isEnglishQuery: Bool,
        semanticHint: String? = nil,
        coreHeadwords: Set<String>? = nil
    ) async throws -> [DictionaryEntry] {
        // Reverse search: English/Chinese → Japanese
        print("🗄️ DBService.searchReverse: query='\(query)' limit=\(limit) semanticHint=\(semanticHint ?? "nil") coreHeadwords=\(coreHeadwords?.count ?? 0)")
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("🗄️ DBService.searchReverse: Empty query, returning []")
            return []
        }

        return try await dbQueue.read { db in
            // Use direct LIKE search for more reliable results
            // This works better for short words like "go", "do", "be" that FTS5 may filter
            let lowerQuery = query.lowercased()
            print("🗄️ DBService.searchReverse: lowerQuery='\(lowerQuery)'")

            // Check if we have Chinese columns (multilingual database)
            let hasChineseColumns = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0
                FROM pragma_table_info('word_senses')
                WHERE name IN ('definition_chinese_simplified', 'definition_chinese_traditional')
                """) ?? false

            // Build core headwords filter - automatically detect from query
            var coreHeadwordsArray: [String] = []

            // Extract base verb from query (e.g., "to wake up" → "wake up", "to go out" → "go out")
            if lowerQuery.hasPrefix("to ") {
                let afterTo = String(lowerQuery.dropFirst(3)) // Remove "to "

                // Try full phrase first (e.g., "go out", "wake up")
                coreHeadwordsArray = self.getCoreHeadwordsForQuery(afterTo)

                // If no mapping found for full phrase, try first word only
                if coreHeadwordsArray.isEmpty, let spaceIndex = afterTo.firstIndex(of: " ") {
                    let firstWord = String(afterTo[..<spaceIndex])
                    coreHeadwordsArray = self.getCoreHeadwordsForQuery(firstWord)
                    print("🗄️ DBService.searchReverse: No mapping for '\(afterTo)', trying first word '\(firstWord)', core headwords: \(coreHeadwordsArray)")
                } else {
                    print("🗄️ DBService.searchReverse: Detected base verb '\(afterTo)', core headwords: \(coreHeadwordsArray)")
                }
            }

            // Merge with any explicitly provided core headwords
            if let providedCoreHeadwords = coreHeadwords {
                coreHeadwordsArray.append(contentsOf: providedCoreHeadwords)
                coreHeadwordsArray = Array(Set(coreHeadwordsArray)) // Remove duplicates
            }

            let sql: String
            var arguments: [DatabaseValueConvertible]

            if hasChineseColumns {
                // Multilingual database with Chinese support
                sql = """
                WITH candidate AS (
                    SELECT
                        e.id,
                        e.headword,
                        e.reading_hiragana,
                        e.reading_romaji,
                        e.frequency_rank,
                        e.pitch_accent,
                        e.created_at,
                        ws.definition_english,
                        ws.definition_chinese_simplified,
                        ws.definition_chinese_traditional,
                        ws.part_of_speech,
                        ws.sense_order,
                        -- Match priority: exact > prefix > word boundary > contains
                        -- Note: Exclude possessive forms (e.g., "one's" when searching "one")
                        CASE
                            WHEN LOWER(ws.definition_english) = ? THEN 0
                            WHEN LOWER(ws.definition_english) = 'to ' || ? THEN 1
                            WHEN LOWER(ws.definition_english) LIKE 'to ' || ? || ';%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE ? || ' %'
                                 AND LOWER(ws.definition_english) NOT LIKE ? || '''s%' THEN 2
                            WHEN LOWER(ws.definition_english) LIKE ? || ';%' THEN 2
                            WHEN LOWER(ws.definition_english) LIKE '% ' || ? || ' %'
                                 AND LOWER(ws.definition_english) NOT LIKE '%' || ? || '''s%' THEN 3
                            WHEN LOWER(ws.definition_english) LIKE '%; ' || ? || ';%' THEN 3
                            WHEN LOWER(ws.definition_english) LIKE '% ' || ?
                                 AND LOWER(ws.definition_english) NOT LIKE '%' || ? || '''s%' THEN 3
                            WHEN LOWER(ws.definition_english) LIKE '%; ' || ? || '; %' THEN 3
                            ELSE 4
                        END AS match_priority,
                        -- Parenthetical penalty: prioritize primary definitions over contextual usage
                        -- Priority 0: Query word appears as PRIMARY definition (not in parentheses or "as a/an" context)
                        -- Priority 1: Query word appears in CONTEXTUAL usage (inside parentheses or "as a/an" usage)
                        -- Examples:
                        --   - "examination; exam; test" → Priority 0 (primary)
                        --   - "question (e.g. on a test)" → Priority 1 (contextual - inside parentheses)
                        --   - "as a test; tentatively" → Priority 1 (contextual - "as a" usage)
                        --   - "inspection (e.g. customs); test" → Priority 0 (test is NOT in the parentheses)
                        CASE
                            -- Check for "as a/an [query]" pattern: these are always contextual/secondary meanings
                            -- Examples: "as a test", "as an experiment", "by way of a test"
                            WHEN LOWER(ws.definition_english) LIKE '%as a ' || ? || '%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%as an ' || ? || '%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%by way of a ' || ? || '%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%by way of an ' || ? || '%' THEN 1
                            -- Check if query appears inside parentheses: "(... query ...)"
                            -- Must check for both "(" before AND ")" after the query word
                            WHEN LOWER(ws.definition_english) LIKE '%(' || ? || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%(' || ? || ' %'
                                 AND LOWER(ws.definition_english) LIKE '%(' || ? || '%' || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%(' || ? || ';%'
                                 AND LOWER(ws.definition_english) LIKE '%(' || ? || '%' || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%(' || ? || ',%'
                                 AND LOWER(ws.definition_english) LIKE '%(' || ? || '%' || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '% ' || ? || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%;' || ? || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%,' || ? || ')%' THEN 1
                            -- Check for "e.g." pattern: only mark as parenthetical if query is BETWEEN "e.g." and ")"
                            -- Pattern: "(e.g.% query%)" - ensures query is inside the e.g. parentheses
                            WHEN LOWER(ws.definition_english) LIKE '%(e.g.%' || ? || '%' || ')%'
                                 AND LOWER(ws.definition_english) NOT LIKE '%(e.g.%' || ')%' || ? || '%' THEN 1
                            -- Otherwise, it's a primary definition
                            ELSE 0
                        END AS parenthetical_priority,
                        -- Part-of-speech weight: verb=0, noun=1, other=2
                        CASE
                            WHEN ws.part_of_speech LIKE '%verb%' THEN 0
                            WHEN ws.part_of_speech LIKE '%noun%' THEN 1
                            ELSE 2
                        END AS pos_weight,
                        -- Semantic category priority: prioritize by real-world usage frequency
                        -- Order: 着る > 履く > 掛ける > 締める > 下げる > 為る > 差す
                        CASE
                            -- Tier 0: 着る - most specific clothing verb (from shoulders down)
                            WHEN ws.definition_english LIKE '%(from the shoulders down)%' THEN 0
                            -- Tier 1: 履く - pants/shoes/footwear (high frequency)
                            WHEN ws.definition_english LIKE '%(lower-body%' OR ws.definition_english LIKE '%(footwear%'
                                 OR ws.definition_english LIKE '%(pants%' OR ws.definition_english LIKE '%(shoes%' THEN 1
                            -- Tier 2: 掛ける - glasses/necklace/accessories
                            WHEN ws.definition_english LIKE '%(glasses%' OR ws.definition_english LIKE '%(necklace%'
                                 OR ws.definition_english LIKE '%(accessor%' THEN 2
                            -- Tier 3: 締める, 被る - belt/necktie/hat
                            WHEN ws.definition_english LIKE '%(belt%' OR ws.definition_english LIKE '%(necktie%'
                                 OR ws.definition_english LIKE '%(tie%' OR ws.definition_english LIKE '%(one''s head)%'
                                 OR ws.definition_english LIKE '%(hat%' THEN 3
                            -- Tier 4: 下げる - hanging decoration
                            WHEN ws.definition_english LIKE '%e.g. decoration%' THEN 4
                            -- Tier 5: 為る - abstract/general wear (clothes without specific part)
                            WHEN ws.definition_english LIKE '%(cloth%' OR ws.definition_english LIKE '%(garment%' THEN 5
                            -- Tier 6: 差す - sword/samurai terminology (least common)
                            WHEN ws.definition_english LIKE '%(a sword%' OR ws.definition_english LIKE '%(sword%'
                                 OR ws.definition_english LIKE '%at one''s side%' THEN 6
                            ELSE 7
                        END AS semantic_priority,
                        -- Idiom penalty: Demote idioms/proverbs with ratio expressions
                        -- e.g., "in ninety-nine cases out of a hundred" → idiom, not direct translation
                        CASE
                            WHEN LOWER(ws.definition_english) LIKE '%out of%' THEN 1
                            ELSE 0
                        END AS idiom_priority
                    FROM dictionary_entries e
                    JOIN word_senses ws ON e.id = ws.entry_id
                    WHERE (
                        -- Word boundary matching: only match complete words, not substrings
                        -- Matches: "ten", "ten;", "; ten", "ten,", etc.
                        -- Does NOT match: "often", "listen", "tenacious"
                        LOWER(ws.definition_english) = ?
                        OR LOWER(ws.definition_english) LIKE ? || ' %'
                        OR LOWER(ws.definition_english) LIKE ? || ';%'
                        OR LOWER(ws.definition_english) LIKE ? || ',%'
                        OR LOWER(ws.definition_english) LIKE ? || '.%'
                        OR LOWER(ws.definition_english) LIKE ? || ')%'
                        OR LOWER(ws.definition_english) LIKE '% ' || ? || ' %'
                        OR LOWER(ws.definition_english) LIKE '% ' || ? || ';%'
                        OR LOWER(ws.definition_english) LIKE '% ' || ? || ',%'
                        OR LOWER(ws.definition_english) LIKE '% ' || ? || '.%'
                        OR LOWER(ws.definition_english) LIKE '% ' || ? || ')%'
                        OR LOWER(ws.definition_english) LIKE '% ' || ?
                        OR LOWER(ws.definition_english) LIKE '%; ' || ?
                        OR LOWER(ws.definition_english) LIKE '%,' || ?
                        OR LOWER(ws.definition_english) LIKE '%(' || ?
                        OR COALESCE(ws.definition_chinese_simplified, '') LIKE '%' || ? || '%'
                        OR COALESCE(ws.definition_chinese_traditional, '') LIKE '%' || ? || '%'
                    )
                    -- Exclude possessive forms (e.g., exclude "one's" when searching "one")
                    AND LOWER(ws.definition_english) NOT LIKE '%' || ? || '''s%'
                    -- Exclude "[word] [number]" patterns for number queries
                    -- Two-tier filtering: strict for one~five (often used as pronouns), lenient for six~twelve
                    AND (
                        -- Not a number query at all
                        ? NOT IN ('one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve')
                        -- Moderate filtering for six~twelve (less used as pronouns, but still filter examples)
                        OR (
                            ? IN ('six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve')
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' o''clock%'
                            AND LOWER(ws.definition_english) NOT LIKE '%part ' || ? || '%'
                            -- Filter numbers in parentheses (examples): (approx. six feet), (e.g. six months)
                            AND (LOWER(ws.definition_english) NOT LIKE '%(%' OR LOWER(ws.definition_english) NOT LIKE '% ' || ? || ' %')
                            -- Filter time expressions: six months, six years (but keep "six-stringed", "six senses")
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' months%'
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' years%'
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' days%'
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' weeks%'
                        )
                        -- Lenient filtering for six and above (less commonly used as pronouns)
                        OR (
                            ? IN ('one', 'two', 'three', 'four', 'five')
                            AND LOWER(ws.definition_english) NOT LIKE '%the ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%this ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%that ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%which ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%another ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%any ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%each ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%every ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%between ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%of ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%or ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%part ' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' o''clock%'
                            AND LOWER(ws.definition_english) NOT LIKE '%(%' || ? || '%'
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' days%'
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' weeks%'
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' months%'
                            AND LOWER(ws.definition_english) NOT LIKE '%' || ? || ' years%'
                        )
                    )
                ),
                aggregated AS (
                    SELECT
                        c.id,
                        MIN(c.match_priority) AS match_priority,
                        MIN(c.parenthetical_priority) AS parenthetical_priority,
                        MIN(c.pos_weight) AS pos_weight,
                        MIN(c.semantic_priority) AS semantic_priority,
                        MIN(c.idiom_priority) AS idiom_priority,
                        MIN(c.sense_order) AS first_matching_sense
                    FROM candidate c
                    GROUP BY c.id
                )
                SELECT e.*
                FROM aggregated agg
                JOIN dictionary_entries e ON e.id = agg.id
                ORDER BY
                    -- Priority 1: Core native equivalent (if provided)
                    CASE
                        WHEN \(coreHeadwordsArray.isEmpty ? "0" : "e.headword IN (\(coreHeadwordsArray.map { _ in "?" }.joined(separator: ",")))") THEN 0
                        ELSE 1
                    END,
                    -- Priority 2: JLPT existence (common words with JLPT > obscure words without JLPT)
                    -- e.g., 売れる (N3) before 鬻ぐ (no JLPT - archaic)
                    CASE
                        WHEN e.jlpt_level IS NOT NULL THEN 0
                        ELSE 1
                    END,
                    -- Priority 3: Semantic category (clothes > accessories > shoes/hat > belt > sword)
                    agg.semantic_priority,
                    -- Priority 4: Parenthetical penalty
                    -- Ensure primary definitions (e.g., "test") rank higher than contextual usage (e.g., "question (e.g. on a test)")
                    -- CRITICAL: Must come BEFORE first_matching_sense to distinguish:
                    --   - 試験 (sense #1: "examination; exam; test") vs
                    --   - 問題 (sense #1: "question (e.g. on a test)")
                    agg.parenthetical_priority,
                    -- Priority 5: First matching sense (sense_order: 1st sense > 2nd sense > ...)
                    -- CRITICAL: This must come BEFORE main verb boost to ensure primary meanings rank higher
                    -- e.g., 試験 (sense #1: "test") before 一番 (sense #4: "as a test")
                    agg.first_matching_sense,
                    -- Priority 6: JLPT level priority (N5 > N4 > N3 > N2 > N1)
                    -- For reverse search, prioritize more basic/common JLPT levels
                    -- e.g., 試験 (N4: exam/test) before 検査 (N3: inspection/test)
                    CASE
                        WHEN e.jlpt_level = 'N5' THEN 0
                        WHEN e.jlpt_level = 'N4' THEN 1
                        WHEN e.jlpt_level = 'N3' THEN 2
                        WHEN e.jlpt_level = 'N2' THEN 3
                        WHEN e.jlpt_level = 'N1' THEN 4
                        ELSE 5
                    END,
                    -- Priority 7: Main verb boost (基础动词优先)
                    -- N5 SHORT words (≤3 chars) appear before their derivatives
                    -- e.g., 聞く (2 chars) before 聞き入る (4 chars), 食べる (3 chars) before 食べ歩く (4 chars)
                    -- Note: Using N5 only since frequency data is not yet populated (all entries have freq=201)
                    CASE
                        WHEN e.jlpt_level = 'N5'
                             AND LENGTH(e.headword) <= 3
                        THEN 0
                        ELSE 1
                    END,
                    -- Priority 8: Idiom penalty (direct translation > compound words > idioms)
                    -- e.g., 百 before 百点 before 九分九厘
                    agg.idiom_priority,
                    -- Priority 9: Frequency (common words first, generalizable across all queries)
                    COALESCE(e.frequency_rank, 999999),
                    -- Priority 10: Part-of-speech (verbs > nouns > other)
                    agg.pos_weight,
                    -- Priority 11: DEMOTE pure katakana (reverse of old logic)
                    CASE
                        WHEN ? = 1
                             AND e.headword != ''
                             AND e.headword GLOB '[ァ-ヶー]*'
                             AND e.headword NOT GLOB '*[ぁ-ん一-龯]*'
                        THEN 1
                        ELSE 0
                    END,
                    -- Priority 12: Match quality
                    agg.match_priority,
                    -- Tie-breakers
                    e.created_at,
                    e.id
                LIMIT ?
                """
                arguments = [
                    lowerQuery, lowerQuery, lowerQuery,  // match_priority: lines 272-274
                    lowerQuery, lowerQuery,              // match_priority: lines 275-276 (with NOT LIKE)
                    lowerQuery,                          // match_priority: line 277
                    lowerQuery, lowerQuery,              // match_priority: lines 278-279 (with NOT LIKE)
                    lowerQuery,                          // match_priority: line 280
                    lowerQuery, lowerQuery,              // match_priority: lines 281-282 (with NOT LIKE)
                    lowerQuery,                          // match_priority: line 283
                    // parenthetical_priority (16 params: 4 for "as a/an" + 12 for parentheses)
                    lowerQuery,                    // line 404: LIKE '%as a ' || ? || '%'
                    lowerQuery,                    // line 405: LIKE '%as an ' || ? || '%'
                    lowerQuery,                    // line 406: LIKE '%by way of a ' || ? || '%'
                    lowerQuery,                    // line 407: LIKE '%by way of an ' || ? || '%'
                    lowerQuery,                    // line 410: LIKE '%(' || ? || ')%'
                    lowerQuery, lowerQuery,        // lines 411-412: LIKE '%(' || ? || ' %' AND LIKE '%(' || ? || '%' || ')%'
                    lowerQuery, lowerQuery,        // lines 413-414: LIKE '%(' || ? || ';%' AND LIKE '%(' || ? || '%' || ')%'
                    lowerQuery, lowerQuery,        // lines 415-416: LIKE '%(' || ? || ',%' AND LIKE '%(' || ? || '%' || ')%'
                    lowerQuery,                    // line 417: LIKE '% ' || ? || ')%'
                    lowerQuery,                    // line 418: LIKE '%;' || ? || ')%'
                    lowerQuery,                    // line 419: LIKE '%,' || ? || ')%'
                    lowerQuery, lowerQuery,        // lines 422-423: LIKE '%(e.g.%' || ? || '%' || ')%' AND NOT LIKE '%(e.g.%' || ')%' || ? || '%'
                    // WHERE clause: Word boundary matching (lines 328-345)
                    lowerQuery,                          // Line 328: = ?
                    lowerQuery,                          // Line 329: LIKE ? || ' %'
                    lowerQuery,                          // Line 330: LIKE ? || ';%'
                    lowerQuery,                          // Line 331: LIKE ? || ',%'
                    lowerQuery,                          // Line 332: LIKE ? || '.%'
                    lowerQuery,                          // Line 333: LIKE ? || ')%'
                    lowerQuery,                          // Line 334: LIKE '% ' || ? || ' %'
                    lowerQuery,                          // Line 335: LIKE '% ' || ? || ';%'
                    lowerQuery,                          // Line 336: LIKE '% ' || ? || ',%'
                    lowerQuery,                          // Line 337: LIKE '% ' || ? || '.%'
                    lowerQuery,                          // Line 338: LIKE '% ' || ? || ')%'
                    lowerQuery,                          // Line 339: LIKE '% ' || ?
                    lowerQuery,                          // Line 340: LIKE '%; ' || ?
                    lowerQuery,                          // Line 341: LIKE '%,' || ?
                    lowerQuery,                          // Line 342: LIKE '%(' || ?
                    query,                               // Line 343: Chinese simplified
                    query,                               // Line 344: Chinese traditional
                    lowerQuery,                          // WHERE clause: NOT LIKE possessive (line 347)
                    // Two-tier number filtering (lines 335-370)
                    lowerQuery,                          // Line 335: number check (NOT IN)
                    lowerQuery,                          // Line 338: six~twelve check (IN)
                    lowerQuery,                          // Line 339: o'clock (six~twelve)
                    lowerQuery,                          // Line 340: part (six~twelve)
                    lowerQuery,                          // Line 342: parentheses filter (six~twelve) - '% [num] %'
                    lowerQuery,                          // Line 344: months (six~twelve)
                    lowerQuery,                          // Line 345: years (six~twelve)
                    lowerQuery,                          // Line 346: days (six~twelve)
                    lowerQuery,                          // Line 347: weeks (six~twelve)
                    lowerQuery,                          // Line 351: one~five check (IN)
                    lowerQuery,                          // Line 345: the [num] (one~five)
                    lowerQuery,                          // Line 346: this [num] (one~five)
                    lowerQuery,                          // Line 347: that [num] (one~five)
                    lowerQuery,                          // Line 348: which [num] (one~five)
                    lowerQuery,                          // Line 349: another [num] (one~five)
                    lowerQuery,                          // Line 350: any [num] (one~five)
                    lowerQuery,                          // Line 351: each [num] (one~five)
                    lowerQuery,                          // Line 352: every [num] (one~five)
                    lowerQuery,                          // Line 353: between [num] (one~five)
                    lowerQuery,                          // Line 354: of [num] (one~five)
                    lowerQuery,                          // Line 355: or [num] (one~five)
                    lowerQuery,                          // Line 356: part [num] (one~five)
                    lowerQuery,                          // Line 357: [num] o'clock (one~five)
                    lowerQuery,                          // Line 358: (... [num] ...) (one~five)
                    lowerQuery,                          // Line 359: [num] days (one~five)
                    lowerQuery,                          // Line 360: [num] weeks (one~five)
                    lowerQuery,                          // Line 361: [num] months (one~five)
                    lowerQuery,                          // Line 362: [num] years (one~five)
                ]
                // Add core headwords if provided
                if !coreHeadwordsArray.isEmpty {
                    arguments.append(contentsOf: coreHeadwordsArray.map { $0 as DatabaseValueConvertible })
                }
                arguments.append(isEnglishQuery ? 1 : 0)  // katakana check
                arguments.append(limit * 2)               // LIMIT
            } else {
                // English-only database (test fixtures)
                sql = """
                WITH candidate AS (
                    SELECT
                        e.id,
                        e.headword,
                        e.reading_hiragana,
                        e.reading_romaji,
                        e.frequency_rank,
                        e.pitch_accent,
                        e.created_at,
                        ws.definition_english,
                        ws.part_of_speech,
                        ws.sense_order,
                        -- Match priority
                        CASE
                            WHEN LOWER(ws.definition_english) = ? THEN 0
                            WHEN LOWER(ws.definition_english) = 'to ' || ? THEN 1
                            WHEN LOWER(ws.definition_english) LIKE 'to ' || ? || ';%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE ? || ' %' THEN 2
                            WHEN LOWER(ws.definition_english) LIKE ? || ';%' THEN 2
                            WHEN LOWER(ws.definition_english) LIKE '% ' || ? || ' %' THEN 3
                            WHEN LOWER(ws.definition_english) LIKE '%; ' || ? || ';%' THEN 3
                            WHEN LOWER(ws.definition_english) LIKE '% ' || ? THEN 3
                            WHEN LOWER(ws.definition_english) LIKE '%; ' || ? || '; %' THEN 3
                            ELSE 4
                        END AS match_priority,
                        -- Parenthetical penalty: prioritize primary definitions over contextual usage
                        -- Priority 0: Query word appears as PRIMARY definition (not in parentheses or "as a/an" context)
                        -- Priority 1: Query word appears in CONTEXTUAL usage (inside parentheses or "as a/an" usage)
                        -- Examples:
                        --   - "examination; exam; test" → Priority 0 (primary)
                        --   - "question (e.g. on a test)" → Priority 1 (contextual - inside parentheses)
                        --   - "as a test; tentatively" → Priority 1 (contextual - "as a" usage)
                        --   - "inspection (e.g. customs); test" → Priority 0 (test is NOT in the parentheses)
                        CASE
                            -- Check for "as a/an [query]" pattern: these are always contextual/secondary meanings
                            -- Examples: "as a test", "as an experiment", "by way of a test"
                            WHEN LOWER(ws.definition_english) LIKE '%as a ' || ? || '%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%as an ' || ? || '%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%by way of a ' || ? || '%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%by way of an ' || ? || '%' THEN 1
                            -- Check if query appears inside parentheses: "(... query ...)"
                            -- Must check for both "(" before AND ")" after the query word
                            WHEN LOWER(ws.definition_english) LIKE '%(' || ? || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%(' || ? || ' %'
                                 AND LOWER(ws.definition_english) LIKE '%(' || ? || '%' || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%(' || ? || ';%'
                                 AND LOWER(ws.definition_english) LIKE '%(' || ? || '%' || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%(' || ? || ',%'
                                 AND LOWER(ws.definition_english) LIKE '%(' || ? || '%' || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '% ' || ? || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%;' || ? || ')%' THEN 1
                            WHEN LOWER(ws.definition_english) LIKE '%,' || ? || ')%' THEN 1
                            -- Check for "e.g." pattern: only mark as parenthetical if query is BETWEEN "e.g." and ")"
                            -- Pattern: "(e.g.% query%)" - ensures query is inside the e.g. parentheses
                            WHEN LOWER(ws.definition_english) LIKE '%(e.g.%' || ? || '%' || ')%'
                                 AND LOWER(ws.definition_english) NOT LIKE '%(e.g.%' || ')%' || ? || '%' THEN 1
                            -- Otherwise, it's a primary definition
                            ELSE 0
                        END AS parenthetical_priority,
                        -- Part-of-speech weight
                        CASE
                            WHEN ws.part_of_speech LIKE '%verb%' THEN 0
                            WHEN ws.part_of_speech LIKE '%noun%' THEN 1
                            ELSE 2
                        END AS pos_weight,
                        -- Semantic category priority: prioritize by real-world usage frequency
                        -- Order: 着る > 履く > 掛ける > 締める > 下げる > 為る > 差す
                        CASE
                            -- Tier 0: 着る - most specific clothing verb (from shoulders down)
                            WHEN ws.definition_english LIKE '%(from the shoulders down)%' THEN 0
                            -- Tier 1: 履く - pants/shoes/footwear (high frequency)
                            WHEN ws.definition_english LIKE '%(lower-body%' OR ws.definition_english LIKE '%(footwear%'
                                 OR ws.definition_english LIKE '%(pants%' OR ws.definition_english LIKE '%(shoes%' THEN 1
                            -- Tier 2: 掛ける - glasses/necklace/accessories
                            WHEN ws.definition_english LIKE '%(glasses%' OR ws.definition_english LIKE '%(necklace%'
                                 OR ws.definition_english LIKE '%(accessor%' THEN 2
                            -- Tier 3: 締める, 被る - belt/necktie/hat
                            WHEN ws.definition_english LIKE '%(belt%' OR ws.definition_english LIKE '%(necktie%'
                                 OR ws.definition_english LIKE '%(tie%' OR ws.definition_english LIKE '%(one''s head)%'
                                 OR ws.definition_english LIKE '%(hat%' THEN 3
                            -- Tier 4: 下げる - hanging decoration
                            WHEN ws.definition_english LIKE '%e.g. decoration%' THEN 4
                            -- Tier 5: 為る - abstract/general wear (clothes without specific part)
                            WHEN ws.definition_english LIKE '%(cloth%' OR ws.definition_english LIKE '%(garment%' THEN 5
                            -- Tier 6: 差す - sword/samurai terminology (least common)
                            WHEN ws.definition_english LIKE '%(a sword%' OR ws.definition_english LIKE '%(sword%'
                                 OR ws.definition_english LIKE '%at one''s side%' THEN 6
                            ELSE 7
                        END AS semantic_priority
                    FROM dictionary_entries e
                    JOIN word_senses ws ON e.id = ws.entry_id
                    WHERE LOWER(ws.definition_english) LIKE '%' || ? || '%'
                ),
                aggregated AS (
                    SELECT
                        c.id,
                        MIN(c.match_priority) AS match_priority,
                        MIN(c.parenthetical_priority) AS parenthetical_priority,
                        MIN(c.pos_weight) AS pos_weight,
                        MIN(c.semantic_priority) AS semantic_priority,
                        MIN(c.sense_order) AS first_matching_sense
                    FROM candidate c
                    GROUP BY c.id
                )
                SELECT e.*
                FROM aggregated agg
                JOIN dictionary_entries e ON e.id = agg.id
                ORDER BY
                    -- Priority 1: Core native equivalent
                    CASE
                        WHEN \(coreHeadwordsArray.isEmpty ? "0" : "e.headword IN (\(coreHeadwordsArray.map { _ in "?" }.joined(separator: ",")))") THEN 0
                        ELSE 1
                    END,
                    -- Priority 2: Semantic category (clothes > accessories > shoes/hat > belt > sword)
                    agg.semantic_priority,
                    -- Priority 3: First matching sense (sense_order: 1st sense > 2nd sense > ...)
                    agg.first_matching_sense,
                    -- Priority 4: Part-of-speech
                    agg.pos_weight,
                    -- Priority 5: Parenthetical semantic match
                    agg.parenthetical_priority,
                    -- Priority 6: Common words
                    CASE
                        WHEN e.frequency_rank IS NOT NULL AND e.frequency_rank <= 5000 THEN 0
                        ELSE 1
                    END,
                    -- Priority 7: DEMOTE pure katakana
                    CASE
                        WHEN ? = 1
                             AND e.headword != ''
                             AND e.headword GLOB '[ァ-ヶー]*'
                             AND e.headword NOT GLOB '*[ぁ-ん一-龯]*'
                        THEN 1
                        ELSE 0
                    END,
                    -- Priority 8: Match quality
                    agg.match_priority,
                    -- Priority 9: Frequency
                    COALESCE(e.frequency_rank, 999999),
                    -- Tie-breakers
                    e.created_at,
                    e.id
                LIMIT ?
                """
                arguments = [
                    lowerQuery, lowerQuery, lowerQuery,  // match_priority
                    lowerQuery, lowerQuery,              // match_priority continued
                    lowerQuery, lowerQuery, lowerQuery, lowerQuery,  // match_priority continued
                    // parenthetical_priority (16 params: 4 for "as a/an" + 12 for parentheses)
                    lowerQuery,                    // line 729: LIKE '%as a ' || ? || '%'
                    lowerQuery,                    // line 730: LIKE '%as an ' || ? || '%'
                    lowerQuery,                    // line 731: LIKE '%by way of a ' || ? || '%'
                    lowerQuery,                    // line 732: LIKE '%by way of an ' || ? || '%'
                    lowerQuery,                    // line 735: LIKE '%(' || ? || ')%'
                    lowerQuery, lowerQuery,        // lines 736-737: LIKE '%(' || ? || ' %' AND LIKE '%(' || ? || '%' || ')%'
                    lowerQuery, lowerQuery,        // lines 738-739: LIKE '%(' || ? || ';%' AND LIKE '%(' || ? || '%' || ')%'
                    lowerQuery, lowerQuery,        // lines 740-741: LIKE '%(' || ? || ',%' AND LIKE '%(' || ? || '%' || ')%'
                    lowerQuery,                    // line 742: LIKE '% ' || ? || ')%'
                    lowerQuery,                    // line 743: LIKE '%;' || ? || ')%'
                    lowerQuery,                    // line 744: LIKE '%,' || ? || ')%'
                    lowerQuery, lowerQuery,        // lines 747-748: LIKE '%(e.g.%' || ? || '%' || ')%' AND NOT LIKE '%(e.g.%' || ')%' || ? || '%'
                    lowerQuery,                          // WHERE clause
                ]
                // Add core headwords if provided
                if !coreHeadwordsArray.isEmpty {
                    arguments.append(contentsOf: coreHeadwordsArray.map { $0 as DatabaseValueConvertible })
                }
                arguments.append(isEnglishQuery ? 1 : 0)  // katakana check
                arguments.append(limit * 2)               // LIMIT
            }

            let entries = try DictionaryEntry.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            print("🗄️ DBService.searchReverse: SQL returned \(entries.count) entries before filtering")
            print("🗄️ DBService.searchReverse: Core headwords array: \(coreHeadwordsArray)")
            if !entries.isEmpty {
                print("🗄️ DBService.searchReverse: First 10 entries from SQL:")
                for (index, entry) in entries.prefix(10).enumerated() {
                    let isCoreWord = coreHeadwordsArray.contains(entry.headword)
                    print("  \(index + 1). \(entry.headword) \(isCoreWord ? "✓ CORE" : "")")
                }
            }

            // If no results, return empty
            guard !entries.isEmpty else {
                print("🗄️ DBService.searchReverse: No results from SQL, returning []")
                return []
            }

            // Apply core word priority boost in Swift (more reliable than SQL dynamic params)
            var sortedEntries = entries
            if !coreHeadwordsArray.isEmpty {
                // Debug: check exact matching
                print("🔍 DEBUG: Checking core word matching...")
                for (index, entry) in entries.prefix(10).enumerated() {
                    let headword = entry.headword
                    let isCore = coreHeadwordsArray.contains(headword)
                    print("  Entry \(index + 1): '\(headword)' (length: \(headword.count)) - Core: \(isCore)")
                    if !isCore {
                        // Check for close matches
                        for coreWord in coreHeadwordsArray {
                            if headword.contains(coreWord) || coreWord.contains(headword) {
                                print("    ⚠️  Close match with core word: '\(coreWord)' (length: \(coreWord.count))")
                            }
                        }
                    }
                }

                sortedEntries = entries.sorted { entry1, entry2 in
                    let index1 = coreHeadwordsArray.firstIndex(of: entry1.headword)
                    let index2 = coreHeadwordsArray.firstIndex(of: entry2.headword)

                    // Both are core words - sort by array position (earlier in array = higher priority)
                    if let idx1 = index1, let idx2 = index2 {
                        return idx1 < idx2
                    }

                    // Only entry1 is core - it comes first
                    if index1 != nil && index2 == nil {
                        return true
                    }

                    // Only entry2 is core - it comes first
                    if index1 == nil && index2 != nil {
                        return false
                    }

                    // Neither is core - maintain SQL order
                    return false  // Stable sort
                }

                print("🗄️ DBService.searchReverse: After core word reordering:")
                for (index, entry) in sortedEntries.prefix(10).enumerated() {
                    let isCoreWord = coreHeadwordsArray.contains(entry.headword)
                    print("  \(index + 1). \(entry.headword) \(isCoreWord ? "✓ CORE" : "")")
                }
            }

            // Load senses and filter STRICTLY to only relevant ones
            var filteredEntries: [DictionaryEntry] = []

            print("🔍 DEBUG: Starting filtering process...")
            for (index, var entry) in sortedEntries.enumerated() {
                print("  Processing entry \(index + 1): \(entry.headword)")
                let allSenses = try WordSense
                    .filter(Column("entry_id") == entry.id)
                    .order(Column("sense_order"))
                    .fetchAll(db)

                // IMPORTANT: Core words bypass definition filtering
                // They are included regardless of whether their definition matches the query
                let isCoreWord = coreHeadwordsArray.contains(entry.headword)
                if isCoreWord {
                    entry.senses = allSenses
                    filteredEntries.append(entry)
                    print("    ✓ Added to filteredEntries (CORE WORD - bypassed filtering, now has \(filteredEntries.count) entries)")
                    continue
                }

                // STRICT filtering: support both exact word matches and multi-word phrases
                let lowerQuery = query.lowercased()
                let relevantSenses = allSenses.filter { sense in
                    let englishDef = sense.definitionEnglish.lowercased()
                    let chineseSimp = sense.definitionChineseSimplified ?? ""

                    // English: support multi-word phrases or exact word matches
                    var exactEnglishMatch: Bool
                    if lowerQuery.contains(" ") {
                        // Multi-word phrase: check if the phrase appears in the definition with word boundaries
                        // Use regex to ensure we match whole phrases only
                        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: lowerQuery))\\b"
                        exactEnglishMatch = englishDef.range(of: pattern, options: .regularExpression) != nil
                    } else {
                        // Single word: exact word match (with word boundaries)
                        let englishWords = englishDef.components(separatedBy: CharacterSet.alphanumerics.inverted)
                            .filter { !$0.isEmpty }
                        exactEnglishMatch = englishWords.contains { $0 == lowerQuery }
                    }

                    // Strict filtering for verb queries: only keep core meanings
                    if exactEnglishMatch && lowerQuery.hasPrefix("to ") {
                        // Extract the base verb from the query (e.g., "to come" -> "come")
                        let baseVerb = String(lowerQuery.dropFirst(3))
                        let expectedPattern = "to \(baseVerb)"

                        // For verb queries, we want strict matching:
                        // 1. Definition must start with "to [verb]"
                        // 2. After "to [verb]", only allow: semicolon, space+parenthesis, or end of string
                        // 3. Exclude compound phrases like "to come out", "to come to", "to come true", etc.
                        // 4. For multi-meaning verbs (e.g., "to come; to go"), check if headword contains the related kanji

                        var isStrictMatch = false
                        var needsKanjiCheck = false

                        // Check if definition starts with our verb pattern
                        if englishDef.hasPrefix(expectedPattern) {
                            let remainingDef = String(englishDef.dropFirst(expectedPattern.count))

                            // Define basic verbs that represent fundamentally different actions
                            let basicVerbs = [
                                "to go", "to be", "to have", "to do",
                                "to eat", "to drink", "to see", "to hear",
                                "to make", "to take", "to give", "to get",
                                "to know", "to think", "to feel", "to want",
                                "to use", "to find", "to work", "to live"
                            ]

                            // Check if the ENTIRE definition contains other basic verbs
                            // (not just the current query verb)
                            let otherBasicVerbs = basicVerbs.filter { $0 != lowerQuery }
                            let hasOtherBasicVerb = otherBasicVerbs.contains { englishDef.contains("; \($0)") }

                            if hasOtherBasicVerb {
                                // Multi-meaning verb - need kanji check
                                needsKanjiCheck = true
                            } else {
                                // Check what comes after "to [verb]"
                                if remainingDef.isEmpty {
                                    // "to come" - exact match
                                    isStrictMatch = true
                                } else if remainingDef.hasPrefix(";") || remainingDef.hasPrefix(" (") {
                                    // "to come; ..." or "to come (...)" - acceptable
                                    isStrictMatch = true
                                }
                                // Otherwise: "to come out", "to come to", etc. - reject
                            }
                        }

                        if !isStrictMatch || needsKanjiCheck {
                            // Not a strict match OR needs kanji check - verify headword contains related Japanese char
                            // OR is a common honorific/humble form
                            let relatedChars = self.getJapaneseCharsForQuery(baseVerb)
                            let containsRelatedChar = relatedChars.contains { entry.headword.contains($0) }

                            // Check if this is a common honorific/humble form (whitelist)
                            let honorificWhitelist = self.getHonorificWhitelistForQuery(baseVerb)
                            let isHonorific = honorificWhitelist.contains(entry.headword)

                            if !containsRelatedChar && !isHonorific {
                                // Not strict match, no related Japanese char, and not honorific - exclude it
                                exactEnglishMatch = false
                            }
                        }
                    }

                    // Chinese: must be exact word in semicolon-separated list
                    let chineseWords = chineseSimp.components(separatedBy: "; ")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let exactChineseMatch = chineseWords.contains { $0 == query }

                    return exactEnglishMatch || exactChineseMatch
                }

                // Only include entry if it has at least one relevant sense
                if !relevantSenses.isEmpty {
                    entry.senses = relevantSenses
                    filteredEntries.append(entry)
                    print("    ✓ Added to filteredEntries (now has \(filteredEntries.count) entries)")
                } else {
                    print("    ✗ Excluded (no relevant senses)")
                }
            }

            print("🔍 DEBUG: Final filteredEntries order:")
            for (index, entry) in filteredEntries.enumerated() {
                let isCore = coreHeadwordsArray.contains(entry.headword)
                print("  \(index + 1). \(entry.headword) \(isCore ? "✓ CORE" : "")")
            }

            print("🗄️ DBService.searchReverse: Returning \(filteredEntries.count) filtered entries")
            return filteredEntries
        }
    }

    /// Returns core/basic words for a given query that should be prioritized
    /// These are the most fundamental, commonly taught words for each concept
    private func getCoreHeadwordsForQuery(_ query: String) -> [String] {
        let lowerQuery = query.lowercased()

        let coreWordsMap: [String: [String]] = [
            // ULTRA-BASIC N5 verbs only (frequency will handle the rest)
            // Movement
            "come": ["来る"],
            "go": ["行く"],

            // Basic Actions
            "eat": ["食べる"],
            "drink": ["飲む"],
            "see": ["見る"],
            "hear": ["聞く"],
            "speak": ["話す"],
            "say": ["言う"],
            "read": ["読む"],
            "write": ["書く"],
            "do": ["する"],

            // State
            "wake up": ["目覚める", "目を覚ます"],  // Keep this one as it's pedagogically important
            "sleep": ["寝る"],
            "get up": ["起きる"],

            // Existence (fundamental copulas)
            "be": ["いる", "ある"],
        ]

        return coreWordsMap[lowerQuery] ?? []
    }

    /// Returns common honorific/humble forms for a given verb query
    /// These words should be included even if they don't contain the core kanji
    private func getHonorificWhitelistForQuery(_ query: String) -> [String] {
        let lowerQuery = query.lowercased()

        let honorificMap: [String: [String]] = [
            // Verbs - Actions
            "eat": ["頂く", "召し上がる", "召す"],
            "drink": ["頂く", "召し上がる"],
            "come": ["いらっしゃる", "お出でになる", "おいでになる", "お見えになる"],
            "go": ["いらっしゃる", "お出でになる", "おいでになる"],
            "be": ["いらっしゃる", "おられる"],
            "say": ["仰る", "おっしゃる"],
            "do": ["なさる"],
            "see": ["ご覧になる"],
            "know": ["ご存じ"],
            "give": ["下さる", "くださる"],
            "sleep": ["お休みになる"],
        ]

        return honorificMap[lowerQuery] ?? []
    }

    /// Maps English query words to their common Japanese characters
    /// Used for whitelisting compound expressions that contain the core Japanese character
    private func getJapaneseCharsForQuery(_ query: String) -> [String] {
        let lowerQuery = query.lowercased()

        // Map common N5 verbs and nouns to their Japanese characters
        let queryToJapaneseMap: [String: [String]] = [
            // Verbs - Movement
            "come": ["来"],
            "go": ["行", "往"],
            "go out": ["出", "消"],  // Phrasal verb: go out (depart 出かける / extinguish 消える)
            "return": ["戻", "帰", "返"],
            "enter": ["入"],
            "exit": ["出"],
            "leave": ["出", "去"],
            "arrive": ["着", "到"],

            // Verbs - Actions
            "eat": ["食"],
            "drink": ["飲"],
            "see": ["見"],
            "watch": ["見"],
            "look": ["見"],
            "hear": ["聞"],
            "listen": ["聞"],
            "speak": ["話", "言"],
            "say": ["言"],
            "talk": ["話"],
            "read": ["読"],
            "write": ["書"],
            "buy": ["買"],
            "sell": ["売"],
            "make": ["作", "造"],
            "do": ["為", "行"],
            "give": ["与", "呉"],
            "receive": ["受", "貰"],
            "take": ["取"],
            "put": ["置"],
            "wear": ["着", "履", "被", "掛", "締"],
            "open": ["開"],
            "close": ["閉"],
            "begin": ["始"],
            "end": ["終"],
            "stop": ["止"],
            "wait": ["待"],
            "meet": ["会", "遭"],
            "understand": ["解", "分"],
            "know": ["知"],
            "think": ["思", "考"],
            "forget": ["忘"],
            "remember": ["覚"],

            // Verbs - State
            "be": ["在", "居", "有"],
            "exist": ["在", "有"],
            "live": ["住", "生", "活"],
            "die": ["死"],
            "sleep": ["寝", "眠"],
            "wake": ["起", "覚"],

            // Nouns - Time
            "day": ["日"],
            "time": ["時"],
            "year": ["年"],
            "month": ["月"],
            "week": ["週"],

            // Nouns - People
            "person": ["人"],
            "student": ["生"],
            "teacher": ["師"],

            // Nouns - Places
            "house": ["家"],
            "school": ["校"],
            "station": ["駅"],

            // Adjectives
            "big": ["大"],
            "small": ["小"],
            "new": ["新"],
            "old": ["古"],
            "good": ["良"],
            "bad": ["悪"],
        ]

        return queryToJapaneseMap[lowerQuery] ?? []
    }

    public func fetchEntry(id: Int) async throws -> DictionaryEntry? {
        try await dbQueue.read { db in
            // Fetch entry
            guard var entry = try DictionaryEntry.fetchOne(db, id: id) else {
                return nil
            }
            
            // Fetch senses
            let senses = try WordSense
                .filter(WordSense.Columns.entryId == id)
                .order(WordSense.Columns.senseOrder)
                .fetchAll(db)
            
            // For each sense, fetch examples using raw SQL
            var sensesWithExamples: [WordSense] = []
            for var sense in senses {
                let sql = """
                SELECT * FROM example_sentences
                WHERE sense_id = ?
                ORDER BY example_order
                """
                let examples = try ExampleSentence.fetchAll(db, sql: sql, arguments: [sense.id])
                sense.examples = examples
                sensesWithExamples.append(sense)
            }
            
            entry.senses = sensesWithExamples
            return entry
        }
    }
    
    public func validateDatabaseIntegrity() async throws -> Bool {
        try await dbQueue.read { db in
            // Verify required tables exist
            let requiredTables = ["dictionary_entries", "dictionary_fts", "word_senses", "example_sentences"]
            for table in requiredTables {
                let exists = try Bool.fetchOne(db, sql: """
                    SELECT COUNT(*) > 0 FROM sqlite_master
                    WHERE type='table' AND name=?
                    """, arguments: [table])
                
                guard exists == true else {
                    throw DatabaseError.schemaMismatch("Missing table: \(table)")
                }
            }
            
            return true
        }
    }
}
