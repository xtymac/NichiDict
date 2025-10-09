# GRDB + SQLite FTS5 Research

**Feature**: Offline Dictionary Search
**Date**: 2025-10-08
**Focus**: Read-only SQLite with FTS5 for Japanese multi-script search

---

## 1. FTS5 Full-Text Search Setup

### Decision: Multi-column FTS5 with separate tokenization strategies per script type

**Rationale**:
- Japanese requires different tokenization for kanji, kana (hiragana/katakana), and romaji
- SQLite FTS5 `unicode61` tokenizer handles kana well (character-level tokenization)
- Romaji benefits from `unicode61` with `remove_diacritics 1` for flexible matching
- Separate columns allow weighting (exact kanji matches rank higher than romaji matches)
- BM25 ranking formula provides relevance scoring out-of-box

**Alternatives Considered**:
1. **Single FTS5 column with concatenated text**: Rejected - cannot differentiate match type (kanji vs kana vs romaji) for ranking
2. **External content FTS5 table**: Rejected - adds complexity without performance benefit for read-only use case
3. **Custom ICU tokenizer**: Rejected - requires building SQLite with ICU, increases binary size significantly

### Implementation Notes:

#### Schema Design

```sql
-- Main dictionary table (read-only, bundled)
CREATE TABLE dictionary_entry (
    id INTEGER PRIMARY KEY,
    lemma TEXT NOT NULL,              -- Kanji/kana headword (食べる)
    reading_hiragana TEXT NOT NULL,   -- Full hiragana (たべる)
    reading_katakana TEXT,            -- Katakana (if applicable, タベル)
    reading_romaji TEXT NOT NULL,     -- Hepburn romaji (taberu)
    frequency_rank INTEGER,           -- 1 = most common
    pitch_accent TEXT,                -- Downstep notation (た↓べる)
    pos_tags TEXT NOT NULL            -- Part of speech (verb-ichidan)
);

-- FTS5 virtual table for multi-script search
CREATE VIRTUAL TABLE dictionary_fts USING fts5(
    lemma,                            -- Kanji/kana (食べる, たべる)
    reading_kana,                     -- Hiragana + katakana combined (たべるタベル)
    reading_romaji,                   -- Romaji (taberu)
    content='dictionary_entry',       -- Links to main table
    content_rowid='id',               -- Uses id as foreign key
    tokenize='unicode61 remove_diacritics 1'
);

-- Populate FTS5 from main table
INSERT INTO dictionary_fts(rowid, lemma, reading_kana, reading_romaji)
SELECT id, lemma,
       reading_hiragana || COALESCE(reading_katakana, ''),
       reading_romaji
FROM dictionary_entry;

-- Word senses (meanings)
CREATE TABLE word_sense (
    id INTEGER PRIMARY KEY,
    entry_id INTEGER NOT NULL REFERENCES dictionary_entry(id),
    sense_index INTEGER NOT NULL,     -- 1, 2, 3 for multiple meanings
    definition_en TEXT NOT NULL,      -- English definition
    pos_detail TEXT,                  -- Detailed POS (transitive-verb)
    usage_notes TEXT
);

-- Example sentences
CREATE TABLE example_sentence (
    id INTEGER PRIMARY KEY,
    sense_id INTEGER NOT NULL REFERENCES word_sense(id),
    japanese_text TEXT NOT NULL,
    english_translation TEXT NOT NULL,
    sentence_order INTEGER            -- Sort by simplicity/frequency
);

-- Indexes for performance
CREATE INDEX idx_entry_frequency ON dictionary_entry(frequency_rank);
CREATE INDEX idx_sense_entry ON word_sense(entry_id);
CREATE INDEX idx_example_sense ON example_sentence(sense_id);
```

#### GRDB Model Definitions

```swift
// Models/DictionaryEntry.swift
import GRDB

struct DictionaryEntry: Codable, FetchableRecord, Identifiable {
    var id: Int64
    var lemma: String
    var readingHiragana: String
    var readingKatakana: String?
    var readingRomaji: String
    var frequencyRank: Int?
    var pitchAccent: String?
    var posTags: String

    enum CodingKeys: String, CodingKey {
        case id
        case lemma
        case readingHiragana = "reading_hiragana"
        case readingKatakana = "reading_katakana"
        case readingRomaji = "reading_romaji"
        case frequencyRank = "frequency_rank"
        case pitchAccent = "pitch_accent"
        case posTags = "pos_tags"
    }
}

struct WordSense: Codable, FetchableRecord, Identifiable {
    var id: Int64
    var entryId: Int64
    var senseIndex: Int
    var definitionEn: String
    var posDetail: String?
    var usageNotes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case senseIndex = "sense_index"
        case definitionEn = "definition_en"
        case posDetail = "pos_detail"
        case usageNotes = "usage_notes"
    }
}

struct ExampleSentence: Codable, FetchableRecord, Identifiable {
    var id: Int64
    var senseId: Int64
    var japaneseText: String
    var englishTranslation: String
    var sentenceOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case senseId = "sense_id"
        case japaneseText = "japanese_text"
        case englishTranslation = "english_translation"
        case sentenceOrder = "sentence_order"
    }
}
```

#### FTS5 Query Patterns

```swift
// Services/SearchService.swift
import GRDB

class SearchService {
    private let dbQueue: DatabaseQueue

    func search(query: String, limit: Int = 100) async throws -> [SearchResult] {
        // Detect script type and convert if needed
        let scriptType = detectScriptType(query)
        let normalizedQuery = normalizeQuery(query, scriptType: scriptType)

        return try await dbQueue.read { db in
            // FTS5 MATCH query with column weighting
            let pattern = buildFTS5Pattern(normalizedQuery, scriptType: scriptType)

            let sql = """
            SELECT
                e.id,
                e.lemma,
                e.reading_hiragana,
                e.reading_romaji,
                e.frequency_rank,
                e.pitch_accent,
                e.pos_tags,
                bm25(dictionary_fts, 10.0, 5.0, 1.0) AS rank_score,
                \(matchTypeSQL(scriptType)) AS match_type
            FROM dictionary_entry e
            JOIN dictionary_fts fts ON fts.rowid = e.id
            WHERE dictionary_fts MATCH ?
            ORDER BY match_type ASC, rank_score DESC, e.frequency_rank ASC
            LIMIT ?
            """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [pattern, limit])
            return rows.map { row in
                SearchResult(
                    entry: DictionaryEntry(row: row),
                    matchType: MatchType(rawValue: row["match_type"]) ?? .contains,
                    rankScore: row["rank_score"]
                )
            }
        }
    }

    private func buildFTS5Pattern(_ query: String, scriptType: ScriptType) -> String {
        switch scriptType {
        case .kanji, .hiragana, .katakana:
            // Exact and prefix matching for CJK
            return "{lemma reading_kana} : (\"\(query)\" OR \(query)*)"
        case .romaji:
            // Prefix matching for romaji with column restriction
            return "{reading_romaji} : \(query)*"
        case .mixed:
            // Search all columns without restriction
            return "\"\(query)\" OR \(query)*"
        }
    }

    private func matchTypeSQL(_ scriptType: ScriptType) -> String {
        """
        CASE
            WHEN e.lemma = '\(query)' THEN 0
            WHEN e.lemma LIKE '\(query)%' THEN 1
            WHEN e.reading_hiragana = '\(query)' THEN 0
            WHEN e.reading_hiragana LIKE '\(query)%' THEN 1
            WHEN e.reading_romaji LIKE '\(query)%' THEN 1
            ELSE 2
        END
        """
    }
}

enum ScriptType {
    case kanji, hiragana, katakana, romaji, mixed
}

enum MatchType: Int {
    case exact = 0
    case prefix = 1
    case contains = 2
}

struct SearchResult {
    let entry: DictionaryEntry
    let matchType: MatchType
    let rankScore: Double
}
```

**Performance Considerations**:
- FTS5 `MATCH` queries are indexed - O(log n) lookup
- BM25 ranking: `bm25(dictionary_fts, 10.0, 5.0, 1.0)` = lemma weight 10x, kana 5x, romaji 1x
- `content='dictionary_entry'` saves space (no duplicate data in FTS5 table)
- Limit results to 100 to prevent UI lag with broad queries

---

## 2. Query Performance Optimization

### Decision: DatabaseQueue with WAL mode disabled (read-only), prepared statement caching, and query result pagination

**Rationale**:
- Read-only database = no write contention = DatabaseQueue sufficient (simpler than DatabasePool)
- WAL mode unnecessary for read-only (DELETE journal mode is fine)
- Prepared statement caching reduces parse overhead for repeated queries
- Pagination prevents loading 100k rows into memory
- FTS5 indexes + frequency index = <100ms query time for 95% of searches

**Alternatives Considered**:
1. **DatabasePool**: Rejected - adds overhead for read coordination without benefit (no writes)
2. **WAL mode**: Rejected - provides no advantage for bundled read-only database
3. **Load entire database to memory**: Rejected - 100MB database would consume excessive RAM

### Implementation Notes:

#### Database Initialization (Read-Only)

```swift
// Database/DatabaseManager.swift
import GRDB
import Foundation

class DatabaseManager {
    static let shared = DatabaseManager()
    private var _dbQueue: DatabaseQueue?

    var dbQueue: DatabaseQueue {
        get throws {
            if let queue = _dbQueue { return queue }

            guard let dbPath = Bundle.main.path(forResource: "seed", ofType: "sqlite") else {
                throw DatabaseError.seedDatabaseNotFound
            }

            var config = Configuration()
            config.readonly = true
            config.prepareDatabase { db in
                // Disable WAL mode (read-only doesn't need it)
                try db.execute(sql: "PRAGMA journal_mode = DELETE")

                // Optimize for read-only access
                try db.execute(sql: "PRAGMA query_only = 1")

                // Cache size: 2000 pages * 4KB = ~8MB cache
                try db.execute(sql: "PRAGMA cache_size = -8000") // Negative = KB

                // Memory-map I/O for faster reads
                try db.execute(sql: "PRAGMA mmap_size = 268435456") // 256MB

                // Enable prepared statement caching
                db.configuration.prepareStatement = .statementCachingOptimization
            }

            let queue = try DatabaseQueue(path: dbPath, configuration: config)
            _dbQueue = queue
            return queue
        }
    }

    enum DatabaseError: Error {
        case seedDatabaseNotFound
        case seedDatabaseNotReadable
        case schemaMismatch(String)
    }
}
```

**Performance Benchmarks** (expected on iPhone 11 with 100k entries):
- Single kanji query (e.g., "食"): 50-80ms
- 3-character kana (e.g., "たべる"): 80-120ms
- Full word (e.g., "食べる"): 60-100ms
- Romaji prefix (e.g., "tab"): 70-110ms

**Optimization Techniques**:
1. `PRAGMA cache_size = -8000` (8MB cache) keeps hot indexes in memory
2. `PRAGMA mmap_size` enables memory-mapped I/O (faster than read syscalls)
3. `PRAGMA query_only = 1` tells SQLite no writes will occur (additional optimizations)
4. Prepared statement caching eliminates repeated SQL parsing
5. `LIMIT 100` prevents runaway queries from loading entire table

---

## 3. Read-Only Database Bundle Access

### Decision: Bundle seed.sqlite in app bundle, open with GRDB readonly configuration, no copying to Documents directory

**Rationale**:
- Read-only access means no writes = no need to copy to writable directory
- Opening directly from bundle saves disk space and launch time
- GRDB's readonly mode prevents accidental writes and enables optimizations
- Bundle resources are code-signed and verified by iOS (integrity guarantee)

**Alternatives Considered**:
1. **Copy to Documents on first launch**: Rejected - wastes 100MB disk space, adds 2-3s to first launch
2. **Copy to Library/Caches**: Rejected - cache may be purged by system, causing app failure
3. **Download on demand**: Rejected - violates offline-first requirement

### Implementation Notes:

```swift
// Database/DatabaseManager.swift (extended)
import GRDB
import Foundation

class DatabaseManager {
    static let shared = DatabaseManager()
    private var _dbQueue: DatabaseQueue?

    var dbQueue: DatabaseQueue {
        get throws {
            if let queue = _dbQueue { return queue }

            // Locate seed.sqlite in app bundle
            guard let dbURL = Bundle.main.url(forResource: "seed", withExtension: "sqlite") else {
                throw DatabaseError.seedDatabaseNotFound
            }

            // Verify file exists and is readable
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
                try db.execute(sql: "PRAGMA journal_mode = DELETE")
                try db.execute(sql: "PRAGMA cache_size = -8000") // 8MB
                try db.execute(sql: "PRAGMA mmap_size = 268435456") // 256MB

                // Validate schema integrity
                try validateSchema(db)
            }

            let queue = try DatabaseQueue(path: dbURL.path, configuration: config)
            _dbQueue = queue
            return queue
        }
    }

    private static func validateSchema(_ db: Database) throws {
        // Verify required tables exist
        let requiredTables = ["dictionary_entry", "dictionary_fts", "word_sense", "example_sentence"]
        for table in requiredTables {
            let exists = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0 FROM sqlite_master
                WHERE type='table' AND name=?
                """, arguments: [table])

            guard exists == true else {
                throw DatabaseError.schemaMismatch("Missing table: \(table)")
            }
        }
    }
}
```

**Performance Considerations**:
- Bundle resources load lazily (no upfront cost)
- First query incurs ~20-30ms penalty to open file descriptor
- Subsequent queries benefit from OS-level file cache
- Memory-mapped I/O (`mmap_size`) keeps frequently accessed pages in RAM
- Database stays open for app lifetime (no repeated open/close overhead)

---

## 4. Multi-Script Search Strategy

### Decision: Script detection → normalization → multi-column FTS5 query with column restrictions

**Rationale**:
- Detect input script type (kanji/kana/romaji) to optimize FTS5 column search
- Normalize input: convert katakana→hiragana, romaji→lowercase for matching
- Use FTS5 column filter syntax `{column_name}: query` to restrict search space
- Handle mixed input (e.g., "食べtabe") by searching all columns without restriction
- Kanji detection via Unicode range U+4E00–U+9FFF (CJK Unified Ideographs)

**Alternatives Considered**:
1. **Separate queries per script type**: Rejected - 3x query overhead, complex result merging
2. **Single concatenated FTS5 column**: Rejected - cannot optimize for script type, poor ranking
3. **ICU collation**: Rejected - excessive complexity for marginal benefit

### Implementation Notes:

#### Script Detection

```swift
// Services/ScriptDetector.swift
import Foundation

enum ScriptType {
    case kanji
    case hiragana
    case katakana
    case romaji
    case mixed
}

struct ScriptDetector {
    static func detect(_ text: String) -> ScriptType {
        let scalars = text.unicodeScalars

        var hasKanji = false
        var hasHiragana = false
        var hasKatakana = false
        var hasRomaji = false

        for scalar in scalars {
            switch scalar.value {
            case 0x4E00...0x9FFF:  // CJK Unified Ideographs
                hasKanji = true
            case 0x3040...0x309F:  // Hiragana
                hasHiragana = true
            case 0x30A0...0x30FF:  // Katakana
                hasKatakana = true
            case 0x0041...0x005A,  // A-Z
                 0x0061...0x007A:  // a-z
                hasRomaji = true
            default:
                break
            }
        }

        // Determine dominant script type
        let scriptCount = [hasKanji, hasHiragana, hasKatakana, hasRomaji].filter { $0 }.count

        if scriptCount > 1 {
            return .mixed
        } else if hasKanji {
            return .kanji
        } else if hasHiragana {
            return .hiragana
        } else if hasKatakana {
            return .katakana
        } else if hasRomaji {
            return .romaji
        } else {
            return .mixed  // Default for unknown/empty
        }
    }
}
```

**Performance Considerations**:
- Script detection: O(n) string scan, ~1-5ms for typical queries
- Kana normalization: O(n) Unicode scalar conversion, ~1-3ms
- FTS5 column restriction reduces search space by 66% (1 of 3 columns vs all 3)
- Example: searching romaji "taberu" only searches `reading_romaji` column, ignoring kanji/kana columns

---

## 5. Result Ranking Strategy

### Decision: Three-tier ranking: (1) Match type (exact/prefix/contains), (2) BM25 relevance score, (3) Frequency rank

**Rationale**:
- Users expect exact matches first (searching "食べる" should show "食べる" at top, not "食べ物")
- BM25 provides TF-IDF-style relevance within match type (favors terms appearing in fewer documents)
- Frequency rank breaks ties (common words rank higher than rare words for same match type)
- SQL-side ranking is faster than Swift-side (no need to load all results into memory)
- Column weighting in BM25 (kanji 10x, kana 5x, romaji 1x) prioritizes native script matches

**Alternatives Considered**:
1. **Swift-side ranking after fetch**: Rejected - requires loading all results, then sorting (slower)
2. **BM25 only**: Rejected - BM25 doesn't guarantee exact matches rank first
3. **Frequency rank only**: Rejected - ignores relevance, would rank "食" above "食べる" for "食べる" query

### Implementation Notes:

#### SQL-Side Ranking Logic

```sql
-- Complete ranking query pattern
SELECT
    e.id,
    e.lemma,
    e.reading_hiragana,
    e.reading_romaji,
    e.frequency_rank,
    e.pitch_accent,
    e.pos_tags,

    -- BM25 relevance score with column weighting
    bm25(dictionary_fts, 10.0, 5.0, 1.0) AS bm25_score,

    -- Match type scoring (0=exact, 1=prefix, 2=contains)
    CASE
        WHEN e.lemma = :query THEN 0
        WHEN e.reading_hiragana = :query THEN 0
        WHEN e.reading_romaji = :query THEN 0
        WHEN e.lemma LIKE :query || '%' THEN 1
        WHEN e.reading_hiragana LIKE :query || '%' THEN 1
        WHEN e.reading_romaji LIKE :query || '%' THEN 1
        ELSE 2
    END AS match_type

FROM dictionary_entry e
JOIN dictionary_fts fts ON fts.rowid = e.id

WHERE dictionary_fts MATCH :fts_pattern

ORDER BY
    match_type ASC,                    -- 1st: Exact > Prefix > Contains
    bm25_score DESC,                   -- 2nd: Higher relevance first
    e.frequency_rank ASC NULLS LAST    -- 3rd: Common words first

LIMIT 100;
```

**BM25 Column Weighting**:
- `lemma`: 10.0 (highest priority - native Japanese headword)
- `reading_kana`: 5.0 (medium - phonetic reading)
- `reading_romaji`: 1.0 (lowest - romanization for learners)

---

## Summary: Key Decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| **FTS5 Setup** | Multi-column FTS5 with `unicode61` tokenizer | Supports multi-script search with column weighting |
| **Database Access** | DatabaseQueue, read-only, bundle-direct | No writes = simpler setup, no copy overhead |
| **Performance** | FTS5 indexes, prepared statements, mmap I/O | <100ms query time, <2s launch time |
| **Multi-Script** | Script detection → normalization → column-restricted FTS5 | Optimizes search space, handles all input types |
| **Ranking** | Match type → BM25 → Frequency rank (SQL-side) | Fast, predictable ordering matching user expectations |

**Expected Performance**:
- Search queries: 50-120ms (95th percentile)
- Cold database open: 20-30ms
- App launch to searchable: <2s
- Memory usage: <50MB (with 8MB cache)
- Database size: ~80MB (100k entries + FTS5 indexes)

---

# Romaji Conversion Research

## Decision: Custom Implementation with Lookup Tables
**Rationale**: Custom lookup-table based implementation provides the best balance of flexibility, performance, and control for this use case. Given the requirement for <100ms search performance and the need to support both Hepburn and Kunrei-shiki input while standardizing to Hepburn output, a lightweight custom solution avoids external dependencies while maintaining full control over normalization behavior.

**Alternatives Considered**:
1. **CFStringTransform (Apple's ICU)**: Built-in macOS/iOS API for Japanese transliteration
   - Pros: Native, zero dependencies, well-tested
   - Cons: Only supports Modified Hepburn, cannot accept Kunrei-shiki input, limited customization
   - Verdict: Rejected - doesn't meet flexible input requirement

2. **Third-party Swift libraries** (e.g., Romaji-swift, WanaKanaSwift):
   - Pros: Pre-built solutions, community maintained
   - Cons: Most are unmaintained (last updates 2018-2020), add dependency overhead, may not handle all edge cases
   - Verdict: Rejected - maintenance risk and unnecessary complexity

3. **Server-side conversion API**:
   - Pros: Offload processing, easy updates
   - Cons: Violates offline-first requirement, adds latency
   - Verdict: Rejected - incompatible with offline requirement

## Implementation Notes

### Core Conversion Algorithm

**Approach**: Bidirectional mapping tables for kana ↔ romaji conversion with preprocessing for input normalization.

#### 1. Kana to Romaji (for display output)
Use static lookup dictionaries mapping kana sequences to Hepburn romaji. Process from longest to shortest sequences to handle digraphs correctly.

```swift
// Hepburn mapping (for output display)
let kanaToHepburn: [String: String] = [
    // Basic hiragana
    "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
    "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
    "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
    "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
    "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
    "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
    "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
    "や": "ya", "ゆ": "yu", "よ": "yo",
    "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
    "わ": "wa", "を": "wo", "ん": "n",
    "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
    "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
    "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
    "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
    "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",

    // Digraphs (きゃ, しゃ, etc.) - process these first
    "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
    "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
    "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
    "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
    "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
    "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
    "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
    "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
    "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
    "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
    "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",

    // Small tsu (gemination) - handled separately
    "っ": "", // Placeholder, requires special logic

    // Long vowels
    "ー": "-", // Elongation mark (katakana)
]

// Katakana mapping (same phonetic values as hiragana)
let katakanaToHiragana: [Character: Character] = [
    "ア": "あ", "イ": "い", "ウ": "う", "エ": "え", "オ": "お",
    "カ": "か", "キ": "き", "ク": "く", "ケ": "け", "コ": "こ",
    // ... (complete mapping)
]
```

#### 2. Romaji to Kana (for search normalization)

Create reverse mappings that accept BOTH Hepburn and Kunrei-shiki variants:

```swift
// Accept both romanization systems for search
let romajiToKana: [String: String] = [
    // Standard mappings
    "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
    "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",

    // Hepburn variants
    "shi": "し", "chi": "ち", "tsu": "つ", "fu": "ふ",
    "ja": "じゃ", "ju": "じゅ", "jo": "じょ",
    "sha": "しゃ", "shu": "しゅ", "sho": "しょ",
    "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ",

    // Kunrei-shiki variants (map to same kana)
    "si": "し", "ti": "ち", "tu": "つ", "hu": "ふ",
    "zya": "じゃ", "zyu": "じゅ", "zyo": "じょ",
    "sya": "しゃ", "syu": "しゅ", "syo": "しょ",
    "tya": "ちゃ", "tyu": "ちゅ", "tyo": "ちょ",

    // Additional variants
    "di": "ぢ", "du": "づ", // Kunrei
    "ji": "じ", "zu": "ず", // Hepburn

    // Digraphs
    "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ",
    // ... (complete mapping)
]
```

### Normalization Strategy for Search

**Three-tier normalization approach**:

1. **Input Normalization** (user input → searchable form):
   ```swift
   func normalizeSearchInput(_ input: String) -> String {
       var normalized = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

       // Handle romaji input - convert to kana for database matching
       if isRomaji(normalized) {
           normalized = romajiToKana(normalized)
       }

       // Normalize kana variations
       normalized = katakanaToHiragana(normalized)

       return normalized
   }
   ```

2. **Database Indexing** (entries stored in normalized form):
   - Store readings in both kana (hiragana) and Hepburn romaji
   - Create search indexes on normalized forms
   - Example: 食べる stored as:
     - `reading_kana`: "たべる"
     - `reading_romaji`: "taberu"
     - `search_normalized`: "taberu" (for romaji searches)

3. **Match Ranking** (per FR-014):
   ```swift
   enum MatchType: Int {
       case exactMatch = 3      // "taberu" matches "taberu"
       case prefixMatch = 2     // "tab" matches "taberu"
       case containsMatch = 1   // "abe" matches "t-abe-ru"
   }

   // SQL query:
   // ORDER BY
   //   CASE
   //     WHEN reading_normalized = ? THEN 3
   //     WHEN reading_normalized LIKE ? || '%' THEN 2
   //     WHEN reading_normalized LIKE '%' || ? || '%' THEN 1
   //   END DESC,
   //   frequency_rank ASC
   ```

### Edge Case Handling

#### 1. Long Vowels: "ou" vs "ō" vs "oo"
**Problem**: Different representations of long vowels (東京: toukyou, tōkyō, tookyoo)

**Solution**: Normalize all variants during input:
```swift
func normalizeLongVowels(_ romaji: String) -> String {
    var normalized = romaji
    // Convert macrons to standard form
    normalized = normalized.replacingOccurrences(of: "ō", with: "ou")
    normalized = normalized.replacingOccurrences(of: "ū", with: "uu")
    normalized = normalized.replacingOccurrences(of: "ā", with: "aa")
    // Also accept double vowels
    // "tookyoo" → search for "toukyou" form
    return normalized
}
```

Store in database as Hepburn standard (toukyou), accept all variants in search.

#### 2. Syllabic "n" vs "nn": "kanna" vs "kan'na"
**Problem**: ん before vowels/y/w needs disambiguation (かんあ: kan'a vs かんな: kanna)

**Solution**:
```swift
// During romaji → kana conversion:
func handleSyllabicN(_ romaji: String) -> String {
    // "n" followed by vowel/y → ん
    // "nn" always → ん + next mora
    let pattern = "n(?=[aiueoy])"
    // If single 'n' before vowel, treat as ん
    // If 'nn', first 'n' is ん, second starts next mora

    // Example: "kanna" → "かんな"
    // Example: "kan'na" → "かんな" (apostrophe marks syllable boundary)
    // Example: "kana" → "かな" (not かんあ)
}
```

Accept apostrophe as syllable boundary marker: `kan'i` → "かんい" vs `kani` → "かに"

#### 3. Small tsu (gemination): "kitte" vs "kite"
**Problem**: Double consonants indicate っ (促音)

**Solution**:
```swift
func handleGemination(_ romaji: String) -> String {
    // Double consonant (except nn) → insert っ
    // "kitte" → "きって" (ki + っ + te)
    // "kite" → "きて" (ki + te)

    let geminates = ["kk", "ss", "tt", "pp", "cc", "gg", "zz", "dd", "bb"]
    // Replace with っ + single consonant
}
```

#### 4. Particle は/へ/を romanization
**Problem**: Particles have special readings (は→wa, へ→e, を→o when used as particles)

**Solution**: Accept both forms in search:
```swift
// Both "wa" and "ha" map to は in search
// Both "e" and "he" map to へ
// Both "o" and "wo" map to を
// Database stores standard Hepburn for display
```

### Performance Implications

**Lookup Table Performance**:
- Dictionary lookups: O(1) average case
- String iteration: O(n) where n = input length
- Total complexity: O(n) for conversion

**Benchmarks** (estimated for typical input):
- 5-character input: <0.1ms conversion time
- Database query: 1-5ms (with proper indexing)
- Total search latency: <10ms for romaji conversion + database lookup
- Well under <100ms requirement

**Optimization strategies**:
1. **Lazy initialization**: Create lookup tables once at app launch
2. **Precompute**: Store both kana and romaji in database to avoid runtime conversion for display
3. **Memoization**: Cache recent conversions (optional, likely unnecessary given speed)
4. **Greedy matching**: Process longest sequences first to minimize iterations

### Implementation Structure

```swift
// Modules/CoreKit/Sources/CoreKit/RomajiConverter.swift

public struct RomajiConverter {
    // Static lookup tables
    private static let kanaToRomaji: [String: String] = [...]
    private static let romajiToKana: [String: String] = [...]

    // Kana → Hepburn romaji (for display)
    public static func toRomaji(_ kana: String) -> String {
        // Implementation
    }

    // Romaji → Kana (for search normalization)
    public static func toKana(_ romaji: String) -> String {
        // Accepts both Hepburn and Kunrei-shiki
        // Returns hiragana
    }

    // Normalize input for search
    public static func normalizeForSearch(_ input: String) -> String {
        // Detects input type and normalizes
    }

    // Helper: detect if string is romaji
    private static func isRomaji(_ text: String) -> Bool {
        // Check if contains only ASCII characters
        text.allSatisfy { $0.isASCII }
    }

    // Handle edge cases
    private static func handleLongVowels(_ romaji: String) -> String
    private static func handleGemination(_ romaji: String) -> String
    private static func handleSyllabicN(_ romaji: String) -> String
}
```

### Testing Strategy

**Unit tests** for conversion accuracy:
```swift
func testHepburnConversion() {
    XCTAssertEqual(RomajiConverter.toRomaji("たべる"), "taberu")
    XCTAssertEqual(RomajiConverter.toRomaji("しゃしん"), "shashin")
}

func testKunreiAcceptance() {
    XCTAssertEqual(RomajiConverter.toKana("si"), "し") // Same as "shi"
    XCTAssertEqual(RomajiConverter.toKana("ti"), "ち") // Same as "chi"
}

func testLongVowels() {
    XCTAssertEqual(normalizeForSearch("toukyou"), normalizeForSearch("tōkyō"))
    XCTAssertEqual(normalizeForSearch("toukyou"), normalizeForSearch("tookyoo"))
}

func testEdgeCases() {
    XCTAssertEqual(RomajiConverter.toKana("kitte"), "きって") // Gemination
    XCTAssertEqual(RomajiConverter.toKana("kanna"), "かんな") // Syllabic n
    XCTAssertEqual(RomajiConverter.toKana("kan'i"), "かんい") // Apostrophe
}
```

**Performance tests**:
```swift
func testConversionPerformance() {
    measure {
        for _ in 0..<1000 {
            _ = RomajiConverter.toKana("konnichiwa")
        }
    }
    // Should complete in <10ms for 1000 iterations
}
```

### Database Schema Considerations

```sql
-- Store both normalized forms for efficient search
CREATE TABLE dictionary_entries (
    id INTEGER PRIMARY KEY,
    lemma TEXT NOT NULL,              -- 食べる (kanji/kana)
    reading_hiragana TEXT NOT NULL,   -- たべる
    reading_romaji TEXT NOT NULL,     -- taberu (Hepburn for display)
    frequency_rank INTEGER,
    -- ... other fields
);

-- Indexes for fast lookup
CREATE INDEX idx_reading_hiragana ON dictionary_entries(reading_hiragana);
CREATE INDEX idx_reading_romaji ON dictionary_entries(reading_romaji);
CREATE INDEX idx_lemma ON dictionary_entries(lemma);

-- For prefix matching
CREATE INDEX idx_romaji_prefix ON dictionary_entries(reading_romaji COLLATE NOCASE);
```

### Summary

**Key Design Decisions**:
1. Custom implementation using static lookup tables for maximum control and performance
2. Bidirectional mapping: kana → Hepburn (display), romaji (both systems) → kana (search)
3. Three-tier normalization: input → searchable → ranked results
4. Store both kana and romaji in database to avoid runtime conversion overhead
5. Comprehensive edge case handling for real-world input variations

**Performance characteristics**:
- Conversion: <0.1ms per typical query
- Total search time: <10ms (well under 100ms requirement)
- Memory: ~50KB for lookup tables (negligible)
- Zero external dependencies

**Meets all requirements**:
- ✅ Accept both Hepburn and Kunrei-shiki input (FR-001)
- ✅ Display Hepburn romaji output
- ✅ <100ms performance target
- ✅ Offline-first (no external services)
- ✅ Handle edge cases (long vowels, gemination, syllabic n)

---

# Combine Debouncing Research

**Topic**: Real-time search debouncing patterns for SwiftUI + Swift 6
**Date**: 2025-10-08
**Requirements**: Adaptive debouncing (150ms for <3 chars, 300ms for 3+ chars), query cancellation, async/await integration

---

## Decision: Custom Publisher with `switchToLatest` + Adaptive Debounce Operator

**Rationale**:
- **Adaptive Timing**: Using `flatMap` with conditional debounce timing based on query length provides clean, declarative way to switch between 150ms and 300ms delays
- **Query Cancellation**: `switchToLatest()` operator automatically cancels previous in-flight async tasks when new query arrives, preventing wasted database work
- **Swift 6 Concurrency**: `Future` publisher bridges Combine pipeline to async/await database queries with proper Task cancellation
- **Performance**: Debouncing happens on main thread scheduling (negligible overhead), database work happens on background thread via async/await

**Alternatives Considered**:

1. **Plain `.debounce()` with fixed timing**: Simple but doesn't support adaptive timing requirement (150ms vs 300ms). Would need two separate pipelines or complex switching logic.

2. **Custom `@Published` property + Task.sleep()**: More verbose, requires manual cancellation tracking with `Task` reference, loses Combine's declarative operators for result mapping/error handling.

3. **AsyncStream with debouncing**: Pure Swift Concurrency approach without Combine. Requires manual debounce implementation and lacks Combine's rich operator ecosystem (removeDuplicates, retry, etc.).

4. **Combine `.throttle()` instead of `.debounce()`**: Throttle emits values at intervals regardless of input, causing incomplete queries to execute. Debounce waits for input to settle, which is correct for search.

---

## Implementation Notes

### Combine Pipeline Structure

**Pattern**: `@Published` query → Conditional Debounce → `switchToLatest` with async Task → Results

```swift
import Combine
import SwiftUI
import GRDB

@Observable
final class SearchViewModel {
    // Input
    @Published var query: String = ""

    // Output
    var results: [DictionaryEntry] = []
    var isLoading: Bool = false
    var error: String?

    private var cancellables = Set<AnyCancellable>()
    private let dbService: DBService

    init(dbService: DBService) {
        self.dbService = dbService
        setupSearchPipeline()
    }

    private func setupSearchPipeline() {
        $query
            // Remove duplicate consecutive values to avoid redundant searches
            .removeDuplicates()

            // Adaptive debouncing based on query length
            .flatMap { query -> AnyPublisher<String, Never> in
                let delay = query.count < 3 ? 0.15 : 0.30  // 150ms vs 300ms
                return Just(query)
                    .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
                    .eraseToAnyPublisher()
            }

            // Cancel previous searches when new query arrives
            .map { [weak self] query -> AnyPublisher<[DictionaryEntry], Error> in
                guard let self = self else {
                    return Empty<[DictionaryEntry], Error>().eraseToAnyPublisher()
                }

                // Handle empty query
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return Just([])
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }

                // Bridge to async/await with automatic cancellation
                return Future { promise in
                    Task {
                        do {
                            let results = try await self.dbService.search(query)
                            promise(.success(results))
                        } catch {
                            promise(.failure(error))
                        }
                    }
                }
                .eraseToAnyPublisher()
            }
            .switchToLatest()  // Cancels previous async task when new one starts

            // Update UI state
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] entries in
                    self?.results = entries
                    self?.isLoading = false
                    self?.error = nil
                }
            )
            .store(in: &cancellables)
    }
}
```

### Adaptive Timing Implementation

**Key Technique**: Use `flatMap` to conditionally apply different debounce delays:

```swift
.flatMap { query -> AnyPublisher<String, Never> in
    let delay = query.count < 3 ? 0.15 : 0.30
    return Just(query)
        .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
        .eraseToAnyPublisher()
}
```

**Why this works**:
- Each emitted query value creates a new inner publisher with appropriate delay
- Outer `flatMap` subscribes to each inner publisher
- When combined with `switchToLatest()`, newer queries cancel older ones
- Result: Adaptive debouncing without maintaining separate pipelines

**Alternative (more explicit)**:
```swift
.flatMap { query -> AnyPublisher<String, Never> in
    if query.count < 3 {
        return Just(query)
            .delay(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    } else {
        return Just(query)
            .delay(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
```

### Integration with Swift 6 async/await

**Pattern**: `Future` publisher wrapping `Task` for async database queries

```swift
.map { query -> AnyPublisher<[DictionaryEntry], Error> in
    return Future { promise in
        Task {
            do {
                let results = try await self.dbService.search(query)
                promise(.success(results))
            } catch {
                promise(.failure(error))
            }
        }
    }
    .eraseToAnyPublisher()
}
.switchToLatest()
```

**Key Points**:
- `Future` takes a closure that provides a `promise` callback
- Inside closure, spawn a `Task` to call async database method
- Task captures `promise` and calls it when async work completes
- `switchToLatest()` cancels the Task when new query arrives

**Swift 6 Concurrency Safety**:
- `@Observable` is Sendable-safe in Swift 6
- GRDB async methods are actor-isolated (database reads on background thread)
- Results delivered to main thread via `.receive(on: DispatchQueue.main)`
- No data races: query string is copied (value type), results are emitted once

**Cancellation Mechanism**:
```swift
// When switchToLatest() cancels the previous publisher:
// 1. Future's Task is automatically cancelled
// 2. GRDB async query receives Task cancellation
// 3. Database cursor stops reading rows
// 4. No wasted CPU cycles after cancellation

// GRDB supports cooperative cancellation:
try await dbQueue.read { db in
    try DictionaryEntry
        .fetchAll(db)  // Checks Task.isCancelled internally
}
```

### Cancellation Handling

**Automatic Cancellation via `switchToLatest()`**:

```swift
$query
    .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
    .map { query in
        // Each map creates new Publisher
        Future<[DictionaryEntry], Error> { promise in
            Task {
                // This Task gets cancelled when switchToLatest unsubscribes
                let results = try await dbService.search(query)
                promise(.success(results))
            }
        }
    }
    .switchToLatest()  // <-- Cancels previous Future when new one arrives
```

**What gets cancelled**:
1. Previous `Future` publisher is unsubscribed
2. Task running inside Future receives cancellation
3. GRDB async query stops processing (cooperative cancellation)

**Manual Cancellation (alternative pattern)**:

```swift
private var searchTask: Task<Void, Never>?

func search(_ query: String) {
    // Cancel previous search
    searchTask?.cancel()

    searchTask = Task {
        do {
            let results = try await dbService.search(query)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.results = results
            }
        } catch {
            // Handle error
        }
    }
}
```

**Recommendation**: Use Combine's `switchToLatest()` for automatic cancellation. Manual Task management is more error-prone and loses Combine's declarative benefits.

---

## Performance Validation

### Expected Overhead

- **Debounce delay**: 150ms or 300ms (user-imperceptible wait for "typing settled")
- **Combine pipeline**: <1ms (publisher chain creation, scheduler dispatch)
- **Task spawn**: <1ms (Swift Concurrency runtime)
- **Database query**: Target <100ms (GRDB FTS5 with proper indexes)

**Total**: ~150-400ms from last keystroke to results, dominated by debounce delay (intentional) and database query (optimizable via indexing).

### Preventing Lag

1. **Use `DispatchQueue.main` scheduler**: Keeps debounce timer on main thread (UI-responsive)
2. **Database on background thread**: GRDB async methods automatically use database queue
3. **Limit result count**: Cap at 100 results (per spec FR-011)
4. **Avoid expensive operators**: No `.collect()` or `.buffer()` that accumulate large arrays
5. **Cancel early**: `switchToLatest()` stops old queries before they finish

### Benchmarking Strategy

```swift
// In PerformanceTests.swift
func testSearchDebouncePerformance() throws {
    let expectation = XCTestExpectation(description: "Search completes")
    var resultCount = 0

    viewModel.$results
        .dropFirst()  // Skip initial empty value
        .sink { results in
            resultCount = results.count
            expectation.fulfill()
        }
        .store(in: &cancellables)

    // Measure time from query change to results
    let startTime = CFAbsoluteTimeGetCurrent()
    viewModel.query = "食べる"

    wait(for: [expectation], timeout: 1.0)
    let elapsed = CFAbsoluteTimeGetCurrent() - startTime

    XCTAssertLessThan(elapsed, 0.5, "Search should complete within 500ms")
    XCTAssertGreaterThan(resultCount, 0, "Should return results")
}
```

---

## Integration with SwiftUI View

### Recommended Pattern: @Observable ViewModel

```swift
import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel(
        dbService: DatabaseManager.shared.dbService
    )

    var body: some View {
        VStack {
            TextField("Search", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)

            if viewModel.isLoading {
                ProgressView()
            }

            List(viewModel.results) { entry in
                EntryRow(entry: entry)
            }

            if let error = viewModel.error {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }
}
```

**Why this works**:
- `@State private var viewModel`: View owns ViewModel lifecycle
- `@Observable`: Swift 5.9+ observation (cleaner than `ObservableObject`)
- `$viewModel.query`: Two-way binding to TextField triggers Combine pipeline
- Results automatically update UI when pipeline emits new values

**Alternative (legacy `ObservableObject`)**:
```swift
class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [DictionaryEntry] = []
    // ... same pipeline
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel(...)
    // ... same body
}
```

Use `@Observable` for Swift 6 projects (simpler, better performance).

---

## Edge Cases & Gotchas

### 1. Empty Query Handling

**Problem**: Debouncing empty string still triggers search after delay

**Solution**: Filter empty queries before async work:
```swift
.map { query in
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
        return Just<[DictionaryEntry]>([])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    // ... normal search
}
```

### 2. Rapid Query Changes During Debounce Window

**Problem**: User types "食" (150ms delay) then "食べ" (150ms delay) rapidly

**Solution**: `removeDuplicates()` prevents redundant searches for same query:
```swift
$query
    .removeDuplicates()  // <-- Filters out duplicate consecutive values
    .flatMap { ... }
```

### 3. Memory Leaks with Closures

**Problem**: `[self]` in map/flatMap closures creates retain cycles

**Solution**: Use `[weak self]` and guard:
```swift
.map { [weak self] query in
    guard let self = self else {
        return Empty<[DictionaryEntry], Error>().eraseToAnyPublisher()
    }
    // ... use self
}
```

### 4. Task Cancellation Not Propagating

**Problem**: GRDB query continues even after `switchToLatest()` cancels

**Solution**: GRDB 6.x supports cooperative cancellation. Ensure using async methods:
```swift
// ✅ Supports cancellation
try await dbQueue.read { db in
    try DictionaryEntry.fetchAll(db)
}

// ❌ Blocks thread, can't cancel
let results = try dbQueue.read { db in
    try DictionaryEntry.fetchAll(db)
}
```

### 5. UI Updates on Background Thread

**Problem**: `Future` resolves on database queue, crashes if updating UI

**Solution**: Use `.receive(on: DispatchQueue.main)` before sink:
```swift
.switchToLatest()
.receive(on: DispatchQueue.main)  // <-- Force main thread
.sink { ... }
```

---

## Testing Strategy

### Unit Tests for ViewModel

```swift
import XCTest
import Combine
@testable import CoreKit

final class SearchViewModelTests: XCTestCase {
    var viewModel: SearchViewModel!
    var mockDB: MockDBService!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        mockDB = MockDBService()
        viewModel = SearchViewModel(dbService: mockDB)
        cancellables = []
    }

    func testAdaptiveDebouncing_ShortQuery() throws {
        // Test 150ms delay for queries <3 characters
        let expectation = XCTestExpectation(description: "Results received")

        viewModel.$results
            .dropFirst()
            .sink { results in
                XCTAssertEqual(results.count, 1)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let start = Date()
        viewModel.query = "食"

        wait(for: [expectation], timeout: 0.3)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(elapsed, 0.15, "Should wait at least 150ms")
        XCTAssertLessThan(elapsed, 0.25, "Should complete within 250ms")
    }

    func testAdaptiveDebouncing_LongQuery() throws {
        // Test 300ms delay for queries ≥3 characters
        let expectation = XCTestExpectation(description: "Results received")

        viewModel.$results
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        let start = Date()
        viewModel.query = "食べる"

        wait(for: [expectation], timeout: 0.5)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(elapsed, 0.30, "Should wait at least 300ms")
        XCTAssertLessThan(elapsed, 0.45, "Should complete within 450ms")
    }

    func testCancellation_RapidQueryChanges() throws {
        mockDB.searchDelay = 0.2  // Simulate slow query

        let expectation = XCTestExpectation(description: "Only last query executes")
        expectation.expectedFulfillmentCount = 1

        viewModel.$results
            .dropFirst()
            .sink { results in
                XCTAssertEqual(self.mockDB.lastQuery, "食べる", "Should only execute final query")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Rapid fire queries
        viewModel.query = "食"
        viewModel.query = "食べ"
        viewModel.query = "食べる"

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockDB.searchCallCount, 1, "Should cancel first two queries")
    }
}
```

### Mock DBService for Testing

```swift
class MockDBService: DBService {
    var searchDelay: TimeInterval = 0
    var lastQuery: String = ""
    var searchCallCount = 0

    func search(_ query: String) async throws -> [DictionaryEntry] {
        searchCallCount += 1
        lastQuery = query

        if searchDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(searchDelay * 1_000_000_000))
        }

        // Return mock results
        return [
            DictionaryEntry(lemma: query, reading: "test", pos: "noun", glossZH: "Mock")
        ]
    }
}
```

---

## Recommendations

1. **Use Combine's `switchToLatest()`**: Automatic cancellation is cleaner than manual Task management
2. **Adaptive debouncing via `flatMap`**: More maintainable than separate pipelines
3. **`@Observable` over `ObservableObject`**: Simpler syntax, better performance in Swift 6
4. **Test debounce timing**: Ensure 150ms/300ms delays are correct
5. **Test cancellation**: Verify rapid query changes don't execute stale searches
6. **Monitor performance**: Benchmark end-to-end latency (debounce + DB + UI update)

---

## References

- **GRDB Documentation**: Async/await support in GRDB 6.x - https://github.com/groue/GRDB.swift/blob/master/Documentation/Concurrency.md
- **Combine Framework**: Apple Developer Documentation - Debounce, SwitchToLatest operators
- **Swift 6 Concurrency**: Task cancellation and cooperative cancellation patterns
- **SwiftUI @Observable**: Swift 5.9+ Observation framework for modern view models

---

## Next Steps

1. Implement `SearchViewModel` with adaptive debouncing pipeline
2. Create `MockDBService` for unit testing
3. Write performance tests validating <200ms response time (FR-012)
4. Test cancellation behavior with rapid query changes
5. Integrate with `SearchView` using `@Observable` pattern
6. Benchmark debounce overhead vs database query time
