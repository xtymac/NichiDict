import Foundation
@preconcurrency import GRDB

public protocol DBServiceProtocol: Sendable {
    func searchEntries(query: String, limit: Int) async throws -> [DictionaryEntry]
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
            // Simple FTS5 search query
            let sql = """
            SELECT e.*
            FROM dictionary_entries e
            JOIN dictionary_fts fts ON e.id = fts.rowid
            WHERE dictionary_fts MATCH ?
            ORDER BY 
                CASE 
                    WHEN e.headword = ? THEN 0
                    WHEN e.reading_hiragana = ? THEN 0
                    WHEN e.reading_romaji = ? THEN 0
                    ELSE 1
                END,
                e.frequency_rank ASC
            LIMIT ?
            """
            
            return try DictionaryEntry.fetchAll(db, sql: sql, arguments: [query, query, query, query, limit])
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
                .filter(Column("entry_id") == id)
                .order(Column("sense_order"))
                .fetchAll(db)
            
            // For each sense, fetch examples
            var sensesWithExamples: [WordSense] = []
            for var sense in senses {
                let examples = try ExampleSentence
                    .filter(Column("sense_id") == sense.id)
                    .order(Column("example_order"))
                    .fetchAll(db)
                
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
