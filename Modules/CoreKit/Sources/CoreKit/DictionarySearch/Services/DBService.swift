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

            // Collect all readings to find variants
            var allReadings = Set<String>()
            for entry in entries {
                allReadings.insert(entry.readingHiragana)
            }

            // Find all variants with the same readings, with proper ordering
            if !allReadings.isEmpty {
                let placeholders = allReadings.map { _ in "?" }.joined(separator: ",")
                let variantsSql = """
                SELECT DISTINCT e.*,
                    CASE
                        WHEN e.headword = ? THEN 0
                        WHEN e.reading_hiragana = ? THEN 1
                        ELSE 2
                    END AS variant_priority
                FROM dictionary_entries e
                WHERE e.reading_hiragana IN (\(placeholders))
                ORDER BY
                    variant_priority ASC,
                    COALESCE(e.frequency_rank, 999999) ASC,
                    LENGTH(e.headword) ASC
                """

                // Build arguments: query twice for priority check, then all readings
                var variantArgs: [DatabaseValueConvertible] = [query, query]
                variantArgs.append(contentsOf: allReadings.map { $0 as DatabaseValueConvertible })

                let variantEntries = try DictionaryEntry.fetchAll(db, sql: variantsSql, arguments: StatementArguments(variantArgs))

                // Replace entries with sorted variants (maintains proper order)
                let existingIds = Set(entries.map { $0.id })
                var allEntries = entries
                for variant in variantEntries where !existingIds.contains(variant.id) {
                    allEntries.append(variant)
                }
                entries = allEntries
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
