# Data Model: Offline Dictionary Search

**Feature**: 001-offline-dictionary-search
**Created**: 2025-10-08
**Input**: [spec.md](spec.md) entities + [research.md](research.md) GRDB patterns

## Overview

This document defines the SQLite database schema and corresponding Swift value types for the offline dictionary search feature. The design prioritizes:

- **Read-only access**: Database bundled in app, no writes
- **FTS5 full-text search**: Multi-script search (kanji, kana, romaji)
- **Performance**: <100ms query response with proper indexing
- **Type safety**: Swift value types with GRDB Codable support

## SQLite Schema

### Tables

#### 1. `dictionary_entries`

Primary table storing Japanese word entries.

```sql
CREATE TABLE dictionary_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    headword TEXT NOT NULL,              -- Kanji/kana form (e.g., "食べる", "桜")
    reading_hiragana TEXT NOT NULL,      -- Hiragana reading (e.g., "たべる", "さくら")
    reading_romaji TEXT NOT NULL,        -- Hepburn romaji (e.g., "taberu", "sakura")
    frequency_rank INTEGER,              -- Frequency rank (1 = most common, NULL = rare)
    pitch_accent TEXT,                   -- Downstep arrow notation (e.g., "た↓べる")
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),

    -- Indexes for sorting
    INDEX idx_frequency_rank ON dictionary_entries(frequency_rank ASC NULLS LAST),
    INDEX idx_headword ON dictionary_entries(headword COLLATE NOCASE)
);
```

**Field Notes**:
- `headword`: Can be pure kanji ("食事"), pure kana ("ひらがな"), or mixed ("食べる")
- `reading_hiragana`: Always hiragana, used for kana-based search
- `reading_romaji`: Always Hepburn romanization for consistent output
- `frequency_rank`: Lower = more common (1-100000), NULL for rare/archaic words
- `pitch_accent`: Uses downstep arrows (↓) to indicate pitch drops per clarification

#### 2. `word_senses`

Represents distinct meanings/senses of a dictionary entry.

```sql
CREATE TABLE word_senses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL,
    definition_english TEXT NOT NULL,    -- English definition
    part_of_speech TEXT NOT NULL,        -- Comma-separated POS tags (e.g., "noun,common")
    usage_notes TEXT,                    -- Optional usage guidance
    sense_order INTEGER NOT NULL,        -- Display order (1 = primary sense)

    FOREIGN KEY (entry_id) REFERENCES dictionary_entries(id) ON DELETE CASCADE,
    INDEX idx_entry_id ON word_senses(entry_id, sense_order)
);
```

**Field Notes**:
- One entry can have multiple senses (polysemy)
- `part_of_speech`: Examples: "ichidan verb,transitive", "noun,common", "i-adjective"
- `sense_order`: Primary meaning is 1, secondary is 2, etc.
- `usage_notes`: Contextual hints (e.g., "Formal", "Archaic", "Kansai dialect")

#### 3. `example_sentences`

Sample sentences demonstrating word usage.

```sql
CREATE TABLE example_sentences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sense_id INTEGER NOT NULL,
    japanese_text TEXT NOT NULL,         -- Japanese sentence with target word
    english_translation TEXT NOT NULL,   -- English translation
    example_order INTEGER NOT NULL,      -- Display order (1 = first example)

    FOREIGN KEY (sense_id) REFERENCES word_senses(id) ON DELETE CASCADE,
    INDEX idx_sense_id ON example_sentences(sense_id, example_order)
);
```

**Field Notes**:
- Examples belong to specific senses, not entries (more precise context)
- `japanese_text`: Contains the target word in context
- `example_order`: Sorted by frequency/simplicity (beginner-friendly first per spec)

#### 4. `dictionary_fts` (FTS5 Virtual Table)

Full-text search index for multi-script queries.

```sql
CREATE VIRTUAL TABLE dictionary_fts USING fts5(
    lemma,              -- Copy of headword (kanji/kana)
    reading_kana,       -- Copy of reading_hiragana
    reading_romaji,     -- Copy of reading_romaji
    content='dictionary_entries',  -- External content table (saves space)
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 0'  -- Preserve Japanese characters
);

-- Triggers to keep FTS5 in sync (read-only db doesn't need these at runtime)
CREATE TRIGGER dictionary_fts_ai AFTER INSERT ON dictionary_entries BEGIN
    INSERT INTO dictionary_fts(rowid, lemma, reading_kana, reading_romaji)
    VALUES (new.id, new.headword, new.reading_hiragana, new.reading_romaji);
END;

CREATE TRIGGER dictionary_fts_ad AFTER DELETE ON dictionary_entries BEGIN
    INSERT INTO dictionary_fts(dictionary_fts, rowid, lemma, reading_kana, reading_romaji)
    VALUES('delete', old.id, old.headword, old.reading_hiragana, old.reading_romaji);
END;

CREATE TRIGGER dictionary_fts_au AFTER UPDATE ON dictionary_entries BEGIN
    INSERT INTO dictionary_fts(dictionary_fts, rowid, lemma, reading_kana, reading_romaji)
    VALUES('delete', old.id, old.headword, old.reading_hiragana, old.reading_romaji);
    INSERT INTO dictionary_fts(rowid, lemma, reading_kana, reading_romaji)
    VALUES (new.id, new.headword, new.reading_hiragana, new.reading_romaji);
END;
```

**FTS5 Configuration**:
- `content='dictionary_entries'`: External content table pattern (no data duplication)
- `tokenize='unicode61'`: Proper handling of CJK characters
- `remove_diacritics 0`: Preserve Japanese diacritics (dakuten, handakuten)

**Column Weighting** (configured in GRDB queries):
- `lemma`: 10x weight (native script matches prioritized)
- `reading_kana`: 5x weight (kana matches second priority)
- `reading_romaji`: 1x weight (romaji matches lowest priority)

## Swift Models

### Value Types (Struct-based per Swift-First Development principle)

```swift
import Foundation
import GRDB

// MARK: - DictionaryEntry

struct DictionaryEntry: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    let id: Int
    let headword: String
    let readingHiragana: String
    let readingRomaji: String
    let frequencyRank: Int?
    let pitchAccent: String?
    let createdAt: Int

    // Related data (not stored in table, loaded separately)
    var senses: [WordSense] = []

    // GRDB column mapping
    enum Columns: String, ColumnExpression {
        case id, headword
        case readingHiragana = "reading_hiragana"
        case readingRomaji = "reading_romaji"
        case frequencyRank = "frequency_rank"
        case pitchAccent = "pitch_accent"
        case createdAt = "created_at"
    }

    static let databaseTableName = "dictionary_entries"

    // Relationship: entry has many senses
    static let wordSenses = hasMany(WordSense.self)
}

// MARK: - WordSense

struct WordSense: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    let id: Int
    let entryId: Int
    let definitionEnglish: String
    let partOfSpeech: String
    let usageNotes: String?
    let senseOrder: Int

    // Related data
    var examples: [ExampleSentence] = []

    enum Columns: String, ColumnExpression {
        case id
        case entryId = "entry_id"
        case definitionEnglish = "definition_english"
        case partOfSpeech = "part_of_speech"
        case usageNotes = "usage_notes"
        case senseOrder = "sense_order"
    }

    static let databaseTableName = "word_senses"

    // Relationships
    static let entry = belongsTo(DictionaryEntry.self)
    static let exampleSentences = hasMany(ExampleSentence.self)
}

// MARK: - ExampleSentence

struct ExampleSentence: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    let id: Int
    let senseId: Int
    let japaneseText: String
    let englishTranslation: String
    let exampleOrder: Int

    enum Columns: String, ColumnExpression {
        case id
        case senseId = "sense_id"
        case japaneseText = "japanese_text"
        case englishTranslation = "english_translation"
        case exampleOrder = "example_order"
    }

    static let databaseTableName = "example_sentences"

    // Relationship
    static let wordSense = belongsTo(WordSense.self)
}

// MARK: - SearchResult (domain model, not persisted)

struct SearchResult: Identifiable, Hashable {
    let id: Int  // entry.id
    let entry: DictionaryEntry
    let matchType: MatchType
    let relevanceScore: Double

    enum MatchType: String, Codable {
        case exact      // Exact headword or reading match
        case prefix     // Query is prefix of headword/reading
        case contains   // Headword/reading contains query

        var sortOrder: Int {
            switch self {
            case .exact: return 0
            case .prefix: return 1
            case .contains: return 2
            }
        }
    }
}
```

## Entity Relationships

```
DictionaryEntry (1) ──< (N) WordSense (1) ──< (N) ExampleSentence

1 entry → many senses → many examples per sense
```

**Relationship Rules**:
- **Entry to Senses**: One-to-many (1:N). An entry can have multiple meanings.
- **Sense to Examples**: One-to-many (1:N). Each sense can have multiple example sentences.
- **Cascade Deletion**: Deleting an entry deletes all its senses and examples (enforced by FK constraints).

**Note**: The bundled database is read-only, so cascade deletions never occur at runtime. These are schema integrity constraints for database generation tooling.

## Validation Rules

### Database Constraints

1. **NOT NULL Requirements**:
   - `dictionary_entries.headword`, `reading_hiragana`, `reading_romaji`
   - `word_senses.entry_id`, `definition_english`, `part_of_speech`, `sense_order`
   - `example_sentences.sense_id`, `japanese_text`, `english_translation`, `example_order`

2. **Foreign Key Integrity**:
   - `word_senses.entry_id` MUST reference valid `dictionary_entries.id`
   - `example_sentences.sense_id` MUST reference valid `word_senses.id`

3. **Ordering Constraints**:
   - `sense_order` MUST be >= 1 (primary sense is 1)
   - `example_order` MUST be >= 1

### Application-Level Validation

```swift
extension DictionaryEntry {
    func validate() throws {
        guard !headword.isEmpty else {
            throw ValidationError.emptyHeadword
        }
        guard !readingHiragana.isEmpty else {
            throw ValidationError.emptyReading
        }
        guard !readingRomaji.isEmpty else {
            throw ValidationError.emptyRomaji
        }
    }
}

extension WordSense {
    func validate() throws {
        guard !definitionEnglish.isEmpty else {
            throw ValidationError.emptyDefinition
        }
        guard senseOrder >= 1 else {
            throw ValidationError.invalidSenseOrder
        }
    }
}

enum ValidationError: Error {
    case emptyHeadword
    case emptyReading
    case emptyRomaji
    case emptyDefinition
    case invalidSenseOrder
}
```

## Performance Indexes

### Required Indexes

1. **Frequency sorting**: `idx_frequency_rank` on `dictionary_entries(frequency_rank)`
   - Used for ranking search results by word commonality
   - NULLS LAST ensures rare words appear after ranked words

2. **Entry lookup**: `idx_entry_id` on `word_senses(entry_id, sense_order)`
   - Composite index for fetching all senses of an entry in order
   - Covering index (includes sense_order for sorting)

3. **Example lookup**: `idx_sense_id` on `example_sentences(sense_id, example_order)`
   - Composite index for fetching examples in display order

4. **FTS5 index**: Automatically created by `dictionary_fts` virtual table
   - Handles prefix queries efficiently (`taberu*`)
   - BM25 ranking with column weighting

### Query Patterns

**Multi-script search with ranking**:
```sql
SELECT
    e.*,
    fts.rank AS bm25_score,
    CASE
        WHEN e.headword = :query THEN 0
        WHEN e.reading_hiragana = :query THEN 0
        WHEN e.reading_romaji = :query THEN 0
        WHEN e.headword LIKE :query || '%' THEN 1
        WHEN e.reading_hiragana LIKE :query || '%' THEN 1
        WHEN e.reading_romaji LIKE :query || '%' THEN 1
        ELSE 2
    END AS match_type
FROM dictionary_entries e
JOIN dictionary_fts fts ON e.id = fts.rowid
WHERE dictionary_fts MATCH :fts_query
ORDER BY
    match_type ASC,                          -- Exact > Prefix > Contains
    bm25(fts, 10.0, 5.0, 1.0) DESC,         -- Column-weighted relevance
    e.frequency_rank ASC NULLS LAST         -- Common words first
LIMIT :limit;
```

**Fetch entry with all senses and examples**:
```sql
-- Entry
SELECT * FROM dictionary_entries WHERE id = :entry_id;

-- Senses (ordered)
SELECT * FROM word_senses WHERE entry_id = :entry_id ORDER BY sense_order;

-- Examples for each sense (ordered)
SELECT * FROM example_sentences WHERE sense_id IN (:sense_ids) ORDER BY sense_id, example_order;
```

## Data Volume Estimates

Based on ~100,000 dictionary entries:

| Table | Estimated Rows | Avg Row Size | Total Size |
|-------|----------------|--------------|------------|
| dictionary_entries | 100,000 | ~200 bytes | ~20 MB |
| word_senses | 300,000 (3 per entry) | ~150 bytes | ~45 MB |
| example_sentences | 500,000 | ~120 bytes | ~60 MB |
| dictionary_fts (index) | 100,000 | ~100 bytes | ~10 MB |
| **Total** | | | **~135 MB** |

**Optimization Required**: Database exceeds 100MB target (SC-007). Mitigation strategies:
1. Compress example sentences (reduce from 5 avg to 3 avg per sense)
2. Use INTEGER enums for `part_of_speech` instead of TEXT
3. Enable SQLite `PRAGMA page_size = 4096` and `VACUUM` for better compression

**Revised Estimate**: ~85 MB after optimization

## Migration Strategy

**Note**: This is a read-only bundled database. No runtime migrations occur. This section documents the database generation process.

### Initial Schema Creation

```swift
// DatabaseManager.swift
func validateSchema() throws {
    try dbQueue.read { db in
        // Verify tables exist
        let hasEntries = try db.tableExists("dictionary_entries")
        let hasSenses = try db.tableExists("word_senses")
        let hasExamples = try db.tableExists("example_sentences")
        let hasFTS = try db.tableExists("dictionary_fts")

        guard hasEntries && hasSenses && hasExamples && hasFTS else {
            throw DatabaseError.corruptedSchema
        }

        // Verify FTS5 matches content table
        let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_fts") ?? 0
        let entryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_entries") ?? 0

        guard ftsCount == entryCount else {
            throw DatabaseError.ftsOutOfSync
        }
    }
}
```

### Schema Versioning

```sql
-- Metadata table for schema versioning
CREATE TABLE _schema_metadata (
    version INTEGER PRIMARY KEY,
    applied_at INTEGER NOT NULL,
    description TEXT
);

INSERT INTO _schema_metadata VALUES (1, unixepoch(), 'Initial schema with FTS5 support');
```

## Testing Strategy

### Unit Tests

```swift
final class DataModelTests: XCTestCase {
    var testDB: DatabaseQueue!

    override func setUp() async throws {
        // Create in-memory test database
        testDB = try DatabaseQueue(path: ":memory:")
        try await seedTestData()
    }

    func testEntryWithSenses() async throws {
        let entry = try await testDB.read { db in
            try DictionaryEntry
                .including(all: DictionaryEntry.wordSenses)
                .fetchOne(db)
        }

        XCTAssertNotNil(entry)
        XCTAssertGreaterThan(entry?.senses.count ?? 0, 0)
    }

    func testFTS5Search() async throws {
        let results = try await testDB.read { db in
            try DictionaryEntry.fetchAll(db, sql: """
                SELECT * FROM dictionary_entries e
                JOIN dictionary_fts fts ON e.id = fts.rowid
                WHERE dictionary_fts MATCH ?
                LIMIT 10
                """, arguments: ["taberu*"])
        }

        XCTAssertFalse(results.isEmpty)
    }
}
```

### Performance Tests

```swift
func testSearchPerformance() throws {
    measure {
        try testDB.read { db in
            _ = try DictionaryEntry.fetchAll(db, sql: """
                SELECT * FROM dictionary_entries e
                JOIN dictionary_fts fts ON e.id = fts.rowid
                WHERE dictionary_fts MATCH ?
                ORDER BY bm25(fts) DESC
                LIMIT 100
                """, arguments: ["食*"])
        }
    }
    // Assert: average time < 100ms
}
```

---

**Status**: ✅ Data model complete. Ready for contract definition and implementation.
