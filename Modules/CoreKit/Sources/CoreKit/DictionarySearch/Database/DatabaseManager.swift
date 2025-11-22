import Foundation
@preconcurrency import GRDB

public actor DatabaseManager {
    private var _dbQueue: DatabaseQueue?
    
    public static let shared = DatabaseManager()
    
    private init() {}
    
    public var dbQueue: DatabaseQueue {
        get async throws {
            let totalStartTime = CFAbsoluteTimeGetCurrent()

            if let queue = _dbQueue {
                return queue
            }

            print("⏱️ [DB Init] Starting database initialization...")

            // Locate seed.sqlite in app bundle
            let step1Start = CFAbsoluteTimeGetCurrent()
            guard let dbURL = Bundle.main.url(forResource: "seed", withExtension: "sqlite") else {
                throw DatabaseError.seedDatabaseNotFound
            }
            print("⏱️ [DB Init] Step 1: Locate database file - \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - step1Start) * 1000))ms")

            // Verify file is readable
            let step2Start = CFAbsoluteTimeGetCurrent()
            guard FileManager.default.isReadableFile(atPath: dbURL.path) else {
                throw DatabaseError.seedDatabaseNotReadable
            }
            print("⏱️ [DB Init] Step 2: Verify file readable - \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - step2Start) * 1000))ms")

            // Configure for read-only access
            let step3Start = CFAbsoluteTimeGetCurrent()
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
            print("⏱️ [DB Init] Step 3: Configure database - \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - step3Start) * 1000))ms")

            let step4Start = CFAbsoluteTimeGetCurrent()
            let queue = try DatabaseQueue(path: dbURL.path, configuration: config)
            print("⏱️ [DB Init] Step 4: Open database connection - \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - step4Start) * 1000))ms")

            // OPTIMIZATION: Skip integrity check for bundled read-only database
            // The database is validated during build and bundled with the app.
            // Integrity check adds ~2 seconds to first search with no practical benefit.
            // If needed for debugging, use validateDatabaseIntegrity() manually.

            _dbQueue = queue

            let totalTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            print("⏱️ [DB Init] ✅ Database initialized successfully - Total: \(String(format: "%.3f", totalTime))ms")

            return queue
        }
    }
    
    /// Verify database integrity (corruption check)
    private func verifyDatabaseIntegrity(_ queue: DatabaseQueue) async throws {
        try await queue.read { db in
            print("⏱️ [DB Verify] Starting integrity verification...")

            // SQLite integrity check
            let check1Start = CFAbsoluteTimeGetCurrent()
            let integrityResult = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            guard integrityResult == "ok" else {
                throw DatabaseError.corruptedDatabase(integrityResult ?? "Unknown error")
            }
            print("⏱️ [DB Verify] - PRAGMA integrity_check: \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - check1Start) * 1000))ms")

            // Verify required tables exist
            let check2Start = CFAbsoluteTimeGetCurrent()
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
            print("⏱️ [DB Verify] - Verify tables exist: \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - check2Start) * 1000))ms")

            // Verify FTS sync
            let check3Start = CFAbsoluteTimeGetCurrent()
            let entryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_entries") ?? 0
            let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_fts") ?? 0

            guard entryCount == ftsCount else {
                throw DatabaseError.ftsOutOfSync
            }
            print("⏱️ [DB Verify] - Verify FTS sync (entries: \(entryCount), fts: \(ftsCount)): \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - check3Start) * 1000))ms")
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
