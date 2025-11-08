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
            // Add wildcard for prefix matching in FTS5
            let ftsQuery = query + "*"

            // Simple FTS5 search query with precise ranking
            let sql = """
            SELECT e.*,
                CASE
                    WHEN e.headword = ? THEN 0
                    WHEN e.reading_hiragana = ? THEN 1
                    WHEN e.reading_romaji = ? THEN 2
                    WHEN e.headword LIKE ? || '%' THEN 3
                    WHEN e.reading_hiragana LIKE ? || '%' THEN 4
                    ELSE 5
                END AS match_priority
            FROM dictionary_entries e
            JOIN dictionary_fts fts ON e.id = fts.rowid
            WHERE dictionary_fts MATCH ?
            ORDER BY
                match_priority ASC,
                COALESCE(e.frequency_rank, 999999) ASC,
                LENGTH(e.headword) ASC
            LIMIT ?
            """

            var entries = try DictionaryEntry.fetchAll(db, sql: sql, arguments: [query, query, query, query, query, ftsQuery, limit])

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

            return entries
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

            // Build core headwords filter if provided
            let coreHeadwordsArray = coreHeadwords.map { Array($0) } ?? []

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
                        -- Match priority: exact > prefix > word boundary > contains
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
                        -- Parenthetical priority: "word (hint)" gets boost
                        CASE
                            WHEN LOWER(ws.definition_english) = ? THEN 0
                            WHEN LOWER(ws.definition_english) LIKE ? || ' (%' THEN 0
                            ELSE 1
                        END AS parenthetical_priority,
                        -- Part-of-speech weight: verb=0, noun=1, other=2
                        CASE
                            WHEN ws.part_of_speech LIKE '%verb%' THEN 0
                            WHEN ws.part_of_speech LIKE '%noun%' THEN 1
                            ELSE 2
                        END AS pos_weight
                    FROM dictionary_entries e
                    JOIN word_senses ws ON e.id = ws.entry_id
                    WHERE (
                        LOWER(ws.definition_english) LIKE '%' || ? || '%'
                        OR COALESCE(ws.definition_chinese_simplified, '') LIKE '%' || ? || '%'
                        OR COALESCE(ws.definition_chinese_traditional, '') LIKE '%' || ? || '%'
                    )
                ),
                aggregated AS (
                    SELECT
                        c.id,
                        MIN(c.match_priority) AS match_priority,
                        MIN(c.parenthetical_priority) AS parenthetical_priority,
                        MIN(c.pos_weight) AS pos_weight
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
                    -- Priority 2: Parenthetical semantic match
                    agg.parenthetical_priority,
                    -- Priority 3: Part-of-speech (verbs > nouns > other)
                    agg.pos_weight,
                    -- Priority 4: Common words
                    CASE
                        WHEN e.frequency_rank IS NOT NULL AND e.frequency_rank <= 5000 THEN 0
                        ELSE 1
                    END,
                    -- Priority 5: DEMOTE pure katakana (reverse of old logic)
                    CASE
                        WHEN ? = 1
                             AND e.headword != ''
                             AND e.headword GLOB '[ァ-ヶー]*'
                             AND e.headword NOT GLOB '*[ぁ-ん一-龯]*'
                        THEN 1
                        ELSE 0
                    END,
                    -- Priority 6: Match quality
                    agg.match_priority,
                    -- Priority 7: Frequency
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
                    lowerQuery, lowerQuery,              // parenthetical_priority
                    lowerQuery, query, query,            // WHERE clause
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
                        -- Parenthetical priority
                        CASE
                            WHEN LOWER(ws.definition_english) = ? THEN 0
                            WHEN LOWER(ws.definition_english) LIKE ? || ' (%' THEN 0
                            ELSE 1
                        END AS parenthetical_priority,
                        -- Part-of-speech weight
                        CASE
                            WHEN ws.part_of_speech LIKE '%verb%' THEN 0
                            WHEN ws.part_of_speech LIKE '%noun%' THEN 1
                            ELSE 2
                        END AS pos_weight
                    FROM dictionary_entries e
                    JOIN word_senses ws ON e.id = ws.entry_id
                    WHERE LOWER(ws.definition_english) LIKE '%' || ? || '%'
                ),
                aggregated AS (
                    SELECT
                        c.id,
                        MIN(c.match_priority) AS match_priority,
                        MIN(c.parenthetical_priority) AS parenthetical_priority,
                        MIN(c.pos_weight) AS pos_weight
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
                    -- Priority 2: Parenthetical semantic match
                    agg.parenthetical_priority,
                    -- Priority 3: Part-of-speech
                    agg.pos_weight,
                    -- Priority 4: Common words
                    CASE
                        WHEN e.frequency_rank IS NOT NULL AND e.frequency_rank <= 5000 THEN 0
                        ELSE 1
                    END,
                    -- Priority 5: DEMOTE pure katakana
                    CASE
                        WHEN ? = 1
                             AND e.headword != ''
                             AND e.headword GLOB '[ァ-ヶー]*'
                             AND e.headword NOT GLOB '*[ぁ-ん一-龯]*'
                        THEN 1
                        ELSE 0
                    END,
                    -- Priority 6: Match quality
                    agg.match_priority,
                    -- Priority 7: Frequency
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
                    lowerQuery, lowerQuery,              // parenthetical_priority
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

            // If no results, return empty
            guard !entries.isEmpty else {
                print("🗄️ DBService.searchReverse: No results from SQL, returning []")
                return []
            }

            // Load senses and filter STRICTLY to only relevant ones
            var filteredEntries: [DictionaryEntry] = []

            for var entry in entries {
                let allSenses = try WordSense
                    .filter(Column("entry_id") == entry.id)
                    .order(Column("sense_order"))
                    .fetchAll(db)

                // STRICT filtering: only exact word matches
                let lowerQuery = query.lowercased()
                let relevantSenses = allSenses.filter { sense in
                    let englishDef = sense.definitionEnglish.lowercased()
                    let chineseSimp = sense.definitionChineseSimplified ?? ""

                    // English: must be exact word match (with word boundaries)
                    let englishWords = englishDef.components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { !$0.isEmpty }
                    let exactEnglishMatch = englishWords.contains { $0 == lowerQuery }

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
                }
            }

            print("🗄️ DBService.searchReverse: Returning \(filteredEntries.count) filtered entries")
            return filteredEntries
        }
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
