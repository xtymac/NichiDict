# DBService Contract

**Feature**: 001-offline-dictionary-search
**Created**: 2025-10-08
**Purpose**: Read-only database access layer for bundled SQLite dictionary

## Protocol Definition

```swift
import Foundation
import GRDB

/// Read-only database service for accessing bundled dictionary data
/// Thread-safe via GRDB's DatabaseQueue (Sendable)
protocol DBServiceProtocol: Sendable {
    /// Search dictionary entries using FTS5 full-text search
    /// - Parameters:
    ///   - query: User's search query (multi-script: kanji, kana, or romaji)
    ///   - limit: Maximum number of results to return (default: 100)
    /// - Returns: Array of matching entries WITHOUT senses/examples (shallow fetch)
    /// - Throws: DatabaseError if query fails or database is corrupted
    /// - Performance: Must complete in <100ms for queries with <3 characters
    func searchEntries(
        query: String,
        limit: Int
    ) async throws -> [DictionaryEntry]

    /// Fetch complete entry with all senses and example sentences
    /// - Parameter id: Entry ID from search results
    /// - Returns: Complete entry with nested senses and examples, or nil if not found
    /// - Throws: DatabaseError if fetch fails
    /// - Note: Used for detail view (User Story 2 & 3)
    func fetchEntry(id: Int) async throws -> DictionaryEntry?

    /// Validate database integrity on app launch
    /// - Returns: true if database schema is valid and FTS index is in sync
    /// - Throws: DatabaseError.corruptedSchema or DatabaseError.ftsOutOfSync
    /// - Note: Called once at app startup; throws if database is corrupted
    func validateDatabaseIntegrity() async throws -> Bool
}
```

## Implementation Contract

### 1. `searchEntries(query:limit:)`

**Purpose**: Multi-script search with FTS5, returns shallow entries (no senses/examples).

**Algorithm**:
1. Detect script type (kanji, kana, romaji, or mixed)
2. Normalize query (convert katakana→hiragana for kana queries)
3. Build FTS5 MATCH expression with column restriction
4. Execute query with BM25 ranking
5. Return results ordered by: match type > BM25 score > frequency rank

**SQL Template**:
```sql
SELECT
    e.id, e.headword, e.reading_hiragana, e.reading_romaji,
    e.frequency_rank, e.pitch_accent, e.created_at,
    CASE
        WHEN e.headword = :query THEN 0
        WHEN e.reading_hiragana = :query THEN 0
        WHEN e.reading_romaji = :query THEN 0
        WHEN e.headword LIKE :prefix THEN 1
        WHEN e.reading_hiragana LIKE :prefix THEN 1
        WHEN e.reading_romaji LIKE :prefix THEN 1
        ELSE 2
    END AS match_type
FROM dictionary_entries e
JOIN dictionary_fts fts ON e.id = fts.rowid
WHERE dictionary_fts MATCH :fts_query
ORDER BY
    match_type ASC,
    bm25(fts, 10.0, 5.0, 1.0) DESC,  -- Column weights: lemma=10x, kana=5x, romaji=1x
    e.frequency_rank ASC NULLS LAST
LIMIT :limit;
```

**FTS5 Query Building**:
```swift
// Kanji/Hiragana: Search lemma + reading_kana columns
"{lemma reading_kana} : (\"\(query)\" OR \(query)*)"

// Romaji: Search reading_romaji column only
"{reading_romaji} : \(query)*"

// Mixed/Unknown: Search all columns
"\"\(query)\" OR \(query)*"
```

**Performance Contract**:
- <100ms for queries with <3 characters (constitution requirement)
- <200ms for all queries (spec relaxed requirement)
- Must use prepared statements (GRDB caching)
- Must execute on database queue (background thread)

**Edge Cases**:
- Empty query: Return empty array (no error)
- Query >100 chars: Truncate to 100 before searching
- Special characters (!@#$%): Sanitize by escaping FTS5 special chars (", *, :)
- No results: Return empty array (no error)

### 2. `fetchEntry(id:)`

**Purpose**: Deep fetch of entry with all related data for detail view.

**Algorithm**:
1. Fetch entry by ID
2. Fetch all senses for entry (ordered by sense_order)
3. For each sense, fetch example sentences (ordered by example_order)
4. Construct nested DictionaryEntry with senses and examples

**SQL Templates**:
```sql
-- 1. Fetch entry
SELECT * FROM dictionary_entries WHERE id = :id;

-- 2. Fetch senses
SELECT * FROM word_senses WHERE entry_id = :entry_id ORDER BY sense_order ASC;

-- 3. Fetch examples (batch query)
SELECT * FROM example_sentences
WHERE sense_id IN (:sense_ids)
ORDER BY sense_id ASC, example_order ASC;
```

**GRDB Pattern** (using associations):
```swift
let entry = try await dbQueue.read { db in
    try DictionaryEntry
        .including(all: DictionaryEntry.wordSenses
            .including(all: WordSense.exampleSentences))
        .fetchOne(db, id: id)
}
```

**Performance**:
- Single entry fetch: <50ms
- Entry + 3 senses + 10 examples: <80ms

**Edge Cases**:
- Entry not found: Return nil (not an error)
- Entry exists but has no senses: Return entry with empty senses array
- Sense exists but has no examples: Return sense with empty examples array

### 3. `validateDatabaseIntegrity()`

**Purpose**: Verify database schema and FTS index integrity at app launch.

**Algorithm**:
1. Check tables exist: `dictionary_entries`, `word_senses`, `example_sentences`, `dictionary_fts`
2. Verify FTS5 row count matches entries row count
3. Verify foreign key constraints are enabled
4. Check schema version matches expected version

**SQL Queries**:
```sql
-- Check table existence
SELECT name FROM sqlite_master WHERE type='table' AND name IN (
    'dictionary_entries', 'word_senses', 'example_sentences', 'dictionary_fts'
);

-- Verify FTS sync
SELECT
    (SELECT COUNT(*) FROM dictionary_entries) AS entry_count,
    (SELECT COUNT(*) FROM dictionary_fts) AS fts_count;

-- Check foreign keys enabled
PRAGMA foreign_keys;

-- Check schema version
SELECT version FROM _schema_metadata ORDER BY version DESC LIMIT 1;
```

**Success Criteria**:
- All 4 tables exist
- `entry_count == fts_count`
- `PRAGMA foreign_keys = 1`
- Schema version >= 1

**Error Handling**:
- Missing table: Throw `DatabaseError.corruptedSchema`
- FTS out of sync: Throw `DatabaseError.ftsOutOfSync`
- Foreign keys disabled: Throw `DatabaseError.invalidConfiguration`
- Schema version mismatch: Throw `DatabaseError.unsupportedSchemaVersion`

## Error Handling

### Custom Errors

```swift
enum DatabaseError: Error, LocalizedError {
    case corruptedSchema
    case ftsOutOfSync
    case invalidConfiguration
    case unsupportedSchemaVersion(Int)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .corruptedSchema:
            return "Dictionary database is missing or corrupted. Please reinstall the app."
        case .ftsOutOfSync:
            return "Search index is out of sync. Please reinstall the app."
        case .invalidConfiguration:
            return "Database configuration is invalid."
        case .unsupportedSchemaVersion(let version):
            return "Database schema version \(version) is not supported by this app version."
        case .queryFailed(let message):
            return "Database query failed: \(message)"
        }
    }
}
```

### Error Propagation

All methods use Swift structured concurrency (`async throws`):
- Errors thrown from GRDB propagate as-is
- Custom validation errors thrown explicitly
- UI layer catches and displays user-friendly messages

## Thread Safety

**GRDB DatabaseQueue** provides thread safety:
- Read operations use `.read { db in }` closure
- All database access serialized through queue
- Protocol marked `Sendable` for Swift 6 concurrency safety
- Async methods dispatch to GRDB's database queue automatically

## Testing Contract

### Unit Tests Required

```swift
final class DBServiceTests: XCTestCase {
    var dbService: DBServiceProtocol!
    var testDB: DatabaseQueue!

    // MARK: - Search Tests

    func testSearchEntriesKanjiQuery() async throws {
        let results = try await dbService.searchEntries(query: "食", limit: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.allSatisfy { $0.headword.contains("食") })
    }

    func testSearchEntriesRomajiQuery() async throws {
        let results = try await dbService.searchEntries(query: "taberu", limit: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.contains { $0.readingRomaji.hasPrefix("taberu") })
    }

    func testSearchEntriesEmptyQuery() async throws {
        let results = try await dbService.searchEntries(query: "", limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchEntriesNoResults() async throws {
        let results = try await dbService.searchEntries(query: "xyzabc", limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchEntriesRanking() async throws {
        let results = try await dbService.searchEntries(query: "ta", limit: 10)
        // Verify exact match appears before prefix matches
        if let exactMatch = results.first(where: { $0.headword == "た" || $0.readingRomaji == "ta" }) {
            let exactIndex = results.firstIndex(of: exactMatch)!
            let prefixMatches = results.filter { $0.readingRomaji.hasPrefix("ta") && $0.readingRomaji != "ta" }
            for prefixMatch in prefixMatches {
                let prefixIndex = results.firstIndex(of: prefixMatch)!
                XCTAssertLessThan(exactIndex, prefixIndex, "Exact match should rank before prefix match")
            }
        }
    }

    // MARK: - Fetch Tests

    func testFetchEntryWithSensesAndExamples() async throws {
        // Insert test entry with senses and examples
        let entryId = 1
        let entry = try await dbService.fetchEntry(id: entryId)

        XCTAssertNotNil(entry)
        XCTAssertFalse(entry!.senses.isEmpty)
        XCTAssertFalse(entry!.senses[0].examples.isEmpty)
    }

    func testFetchEntryNotFound() async throws {
        let entry = try await dbService.fetchEntry(id: 999999)
        XCTAssertNil(entry)
    }

    // MARK: - Validation Tests

    func testValidateDatabaseIntegrity() async throws {
        let isValid = try await dbService.validateDatabaseIntegrity()
        XCTAssertTrue(isValid)
    }

    func testValidateDatabaseIntegrityCorrupted() async throws {
        // Drop FTS table to simulate corruption
        try await testDB.write { db in
            try db.execute(sql: "DROP TABLE dictionary_fts")
        }

        await assertThrowsError(try await dbService.validateDatabaseIntegrity()) { error in
            XCTAssertEqual(error as? DatabaseError, .corruptedSchema)
        }
    }
}
```

### Performance Tests

```swift
func testSearchPerformanceSmallQuery() throws {
    measure {
        _ = try dbService.searchEntries(query: "食", limit: 100)
    }
    // Assert: average < 100ms (constitution requirement)
}

func testSearchPerformanceLongerQuery() throws {
    measure {
        _ = try dbService.searchEntries(query: "taberu", limit: 100)
    }
    // Assert: average < 200ms (spec requirement)
}

func testFetchEntryPerformance() throws {
    measure {
        _ = try dbService.fetchEntry(id: 1)
    }
    // Assert: average < 50ms
}
```

## Dependencies

- **GRDB.swift 6.x**: SQLite wrapper with type-safe queries
- **Foundation**: Swift standard library
- **Swift Concurrency**: async/await, Sendable

## Implementation Notes

1. **Read-Only Configuration**: Use `Configuration.readonly = true` to prevent accidental writes
2. **Database Path**: Bundle.main.path(forResource: "seed", ofType: "sqlite")
3. **Query Caching**: Enable prepared statement caching for performance
4. **Background Queue**: All database operations on GRDB's queue (not main thread)
5. **Script Detection**: Use Unicode ranges to detect kanji/kana/romaji
6. **Romaji Normalization**: Support both Hepburn and Kunrei-shiki input (convert to Hepburn for output)

---

**Status**: ✅ Contract defined. Ready for implementation in CoreKit/DictionarySearch/Services/DBService.swift
