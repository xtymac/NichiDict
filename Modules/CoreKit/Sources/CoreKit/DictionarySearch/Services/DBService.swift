import Foundation
@preconcurrency import GRDB

public protocol DBServiceProtocol: Sendable {
    func searchEntries(query: String, limit: Int) async throws -> [DictionaryEntry]
    func searchReverse(query: String, limit: Int) async throws -> [DictionaryEntry]
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

    public func searchReverse(query: String, limit: Int) async throws -> [DictionaryEntry] {
        // Reverse search: English/Chinese → Japanese
        print("🗄️ DBService.searchReverse: query='\(query)' limit=\(limit)")
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

            let sql: String
            let arguments: [DatabaseValueConvertible]

            if hasChineseColumns {
                // Multilingual database with Chinese support
                sql = """
                SELECT DISTINCT e.*,
                    CASE
                        -- Exact match to whole definition (highest priority)
                        WHEN LOWER(ws.definition_english) = ? THEN 0
                        -- "to X" pattern (e.g., "to go", "to be")
                        WHEN LOWER(ws.definition_english) = 'to ' || ? THEN 1
                        WHEN LOWER(ws.definition_english) LIKE 'to ' || ? || ';%' THEN 1
                        -- Starts with word followed by clarifying parentheses (e.g., "japanese (language)")
                        WHEN LOWER(ws.definition_english) LIKE ? || ' (%' THEN 1
                        -- Exact word match at start
                        WHEN LOWER(ws.definition_english) LIKE ? || ' %' THEN 2
                        WHEN LOWER(ws.definition_english) LIKE ? || ';%' THEN 2
                        -- Exact word match in middle/end with word boundaries
                        WHEN LOWER(ws.definition_english) LIKE '% ' || ? || ' %' THEN 3
                        WHEN LOWER(ws.definition_english) LIKE '%; ' || ? || ';%' THEN 3
                        WHEN LOWER(ws.definition_english) LIKE '% ' || ? THEN 3
                        WHEN LOWER(ws.definition_english) LIKE '%; ' || ? || '; %' THEN 3
                        -- Contains (lowest priority)
                        ELSE 4
                    END AS match_priority
                FROM dictionary_entries e
                JOIN word_senses ws ON e.id = ws.entry_id
                WHERE (
                    LOWER(ws.definition_english) LIKE '%' || ? || '%'
                    OR COALESCE(ws.definition_chinese_simplified, '') LIKE '%' || ? || '%'
                    OR COALESCE(ws.definition_chinese_traditional, '') LIKE '%' || ? || '%'
                )
                ORDER BY
                    match_priority ASC,
                    COALESCE(e.frequency_rank, 999999) ASC,
                    e.created_at ASC,
                    LENGTH(e.headword) ASC
                LIMIT ?
                """
                arguments = [
                    lowerQuery,      // exact match
                    lowerQuery,      // "to X" exact
                    lowerQuery,      // "to X;" pattern
                    lowerQuery,      // query followed by parentheses
                    lowerQuery,      // start with space
                    lowerQuery,      // start with semicolon
                    lowerQuery,      // middle with spaces (1)
                    lowerQuery,      // middle with semicolons
                    lowerQuery,      // end with space
                    lowerQuery,      // "; X; " pattern
                    lowerQuery,      // english LIKE
                    query,           // chinese simplified
                    query,           // chinese traditional
                    limit * 2        // Get more for filtering
                ]
            } else {
                // English-only database (test fixtures)
                sql = """
                SELECT DISTINCT e.*,
                    CASE
                        -- Exact match to whole definition (highest priority)
                        WHEN LOWER(ws.definition_english) = ? THEN 0
                        -- "to X" pattern (e.g., "to go", "to be")
                        WHEN LOWER(ws.definition_english) = 'to ' || ? THEN 1
                        WHEN LOWER(ws.definition_english) LIKE 'to ' || ? || ';%' THEN 1
                        -- Starts with word followed by clarifying parentheses (e.g., "japanese (language)")
                        WHEN LOWER(ws.definition_english) LIKE ? || ' (%' THEN 1
                        -- Exact word match at start
                        WHEN LOWER(ws.definition_english) LIKE ? || ' %' THEN 2
                        WHEN LOWER(ws.definition_english) LIKE ? || ';%' THEN 2
                        -- Exact word match in middle/end with word boundaries
                        WHEN LOWER(ws.definition_english) LIKE '% ' || ? || ' %' THEN 3
                        WHEN LOWER(ws.definition_english) LIKE '%; ' || ? || ';%' THEN 3
                        WHEN LOWER(ws.definition_english) LIKE '% ' || ? THEN 3
                        WHEN LOWER(ws.definition_english) LIKE '%; ' || ? || '; %' THEN 3
                        -- Contains (lowest priority)
                        ELSE 4
                    END AS match_priority
                FROM dictionary_entries e
                JOIN word_senses ws ON e.id = ws.entry_id
                WHERE LOWER(ws.definition_english) LIKE '%' || ? || '%'
                ORDER BY
                    match_priority ASC,
                    COALESCE(e.frequency_rank, 999999) ASC,
                    e.created_at ASC,
                    LENGTH(e.headword) ASC
                LIMIT ?
                """
                arguments = [
                    lowerQuery,      // exact match
                    lowerQuery,      // "to X" exact
                    lowerQuery,      // "to X;" pattern
                    lowerQuery,      // query followed by parentheses
                    lowerQuery,      // start with space
                    lowerQuery,      // start with semicolon
                    lowerQuery,      // middle with spaces (1)
                    lowerQuery,      // middle with semicolons
                    lowerQuery,      // end with space
                    lowerQuery,      // "; X; " pattern
                    lowerQuery,      // english LIKE
                    limit * 2        // Get more for filtering
                ]
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
