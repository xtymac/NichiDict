import Foundation
@preconcurrency import GRDB

public actor DatabaseManager {
    private var _dbQueue: DatabaseQueue?
    
    public static let shared = DatabaseManager()
    
    private init() {}
    
    public var dbQueue: DatabaseQueue {
        get async throws {
            if let queue = _dbQueue {
                return queue
            }
            
            // Locate seed.sqlite in app bundle
            guard let dbURL = Bundle.main.url(forResource: "seed", withExtension: "sqlite") else {
                throw DatabaseError.seedDatabaseNotFound
            }
            
            // Verify file is readable
            guard FileManager.default.isReadableFile(atPath: dbURL.path) else {
                throw DatabaseError.seedDatabaseNotReadable
            }
            
            // Configure for read-only access
            var config = Configuration()
            config.readonly = true
            config.label = "DictionaryDatabase"
            
            config.prepareDatabase { db in
                // Enforce read-only at SQLite level
                try db.execute(sql: "PRAGMA query_only = ON")
                
                // Optimize for read-heavy workload
                try db.execute(sql: "PRAGMA temp_store = MEMORY")
                try db.execute(sql: "PRAGMA cache_size = -8000") // 8MB
                try db.execute(sql: "PRAGMA mmap_size = 268435456") // 256MB
            }
            
            let queue = try DatabaseQueue(path: dbURL.path, configuration: config)

            // Edge case: Verify database integrity on first open
            try await verifyDatabaseIntegrity(queue)

            _dbQueue = queue
            return queue
        }
    }
    
    /// Verify database integrity (corruption check)
    private func verifyDatabaseIntegrity(_ queue: DatabaseQueue) async throws {
        try await queue.read { db in
            // SQLite integrity check
            let integrityResult = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            guard integrityResult == "ok" else {
                throw DatabaseError.corruptedDatabase(integrityResult ?? "Unknown error")
            }

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

            // Verify FTS sync
            let entryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_entries") ?? 0
            let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_fts") ?? 0

            guard entryCount == ftsCount else {
                throw DatabaseError.ftsOutOfSync
            }
        }
    }

    public func validateDatabaseIntegrity() async throws -> Bool {
        let queue = try await dbQueue
        try await verifyDatabaseIntegrity(queue)
        return true
    }
    
    // Test helper
    public static func test() throws -> DatabaseManager {
        let manager = DatabaseManager()
        return manager
    }
}

public enum DatabaseError: Error, LocalizedError {
    case seedDatabaseNotFound
    case seedDatabaseNotReadable
    case corruptedDatabase(String)
    case schemaMismatch(String)
    case ftsOutOfSync
    case invalidConfiguration
    case unsupportedSchemaVersion(Int)
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .seedDatabaseNotFound:
            return "Dictionary database not found. Please reinstall the app."
        case .seedDatabaseNotReadable:
            return "Dictionary database is not readable."
        case .corruptedDatabase(let details):
            return "Dictionary database is corrupted: \(details). Please reinstall the app."
        case .schemaMismatch(let message):
            return "Database schema mismatch: \(message). Please reinstall the app."
        case .ftsOutOfSync:
            return "Search index is out of sync. Please reinstall the app."
        case .invalidConfiguration:
            return "Database configuration is invalid."
        case .unsupportedSchemaVersion(let version):
            return "Database schema version \(version) is not supported."
        case .queryFailed(let message):
            return "Database query failed: \(message)"
        }
    }
}

// Extension for test database
extension DatabaseManager {
    public static func testQueue(at path: String) throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true

        return try DatabaseQueue(path: path, configuration: config)
    }
}
