# Implementation Tasks: Offline Dictionary Search

**Feature**: 001-offline-dictionary-search
**Branch**: `001-offline-dictionary-search`
**Created**: 2025-10-08
**Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Task Summary

- **Total Tasks**: 39
- **User Story 1 (P1)**: 20 tasks (MVP)
- **User Story 2 (P2)**: 8 tasks
- **User Story 3 (P3)**: 5 tasks
- **Setup/Foundation**: 4 tasks
- **Polish/Integration**: 2 tasks

## Implementation Strategy

**TDD Approach**: This feature uses Test-Driven Development with 80% coverage target.
- Tests are written BEFORE implementation for each component
- Run tests after each task to validate progress
- Use red-green-refactor cycle per [quickstart.md](quickstart.md)

**Incremental Delivery by User Story**:
1. **MVP (User Story 1)**: Basic word lookup - fully functional dictionary
2. **Enhancement (User Story 2)**: Detailed information (pitch accent, frequency)
3. **Advanced (User Story 3)**: Example sentences

Each user story delivers independent, testable value.

---

## Phase 1: Project Setup

**Goal**: Initialize project structure and dependencies

### T001: Setup CoreKit SPM Package Structure

**Story**: Setup
**Type**: Project initialization
**Parallelizable**: No

**Description**: Create CoreKit Swift Package Manager structure for the DictionarySearch feature module.

**Actions**:
```bash
cd Modules/CoreKit
mkdir -p Sources/CoreKit/DictionarySearch/{Models,Services,Database,Utilities}
mkdir -p Tests/CoreKitTests/DictionarySearchTests
mkdir -p Tests/CoreKitTests/Fixtures
```

**Files Created**:
- `Modules/CoreKit/Sources/CoreKit/DictionarySearch/` (directory structure)
- `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/` (directory structure)

**Acceptance**:
- [ ] Directory structure created
- [ ] Directories visible in Xcode Project Navigator

---

### T002: Configure Package.swift Dependencies

**Story**: Setup
**Type**: Dependency configuration
**Parallelizable**: No
**Depends on**: T001

**Description**: Add GRDB.swift dependency to Package.swift and configure Swift 6 strict concurrency.

**Actions**:
1. Edit `Modules/CoreKit/Package.swift`
2. Add GRDB.swift 6.x dependency
3. Enable strict concurrency checking

**File**: `Modules/CoreKit/Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "CoreKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"],
            resources: [
                .copy("Fixtures/test-seed.sqlite")
            ]
        ),
    ]
)
```

**Acceptance**:
- [ ] Package.swift compiles
- [ ] GRDB.swift resolves successfully (File ’ Packages ’ Resolve Package Versions)
- [ ] Strict concurrency enabled

---

### T003: Create Test Database Fixture

**Story**: Setup
**Type**: Test infrastructure
**Parallelizable**: Yes [P]

**Description**: Generate test-seed.sqlite with sample data for unit tests.

**File**: `Modules/CoreKit/Tests/CoreKitTests/Fixtures/create-test-db.sh`

Use the script from [quickstart.md](quickstart.md) to create a minimal test database with:
- 5 sample entries (ßy‹, \, f!, _y‹, ß)
- Corresponding word senses and example sentences
- FTS5 virtual table populated

**Actions**:
```bash
cd Modules/CoreKit/Tests/CoreKitTests/Fixtures
chmod +x create-test-db.sh
./create-test-db.sh
```

**Acceptance**:
- [ ] test-seed.sqlite created
- [ ] Database contains 5 entries
- [ ] FTS5 table populated: `SELECT COUNT(*) FROM dictionary_fts` returns 5
- [ ] File added to CoreKitTests resources in Package.swift

---

### T004: Verify Development Environment

**Story**: Setup
**Type**: Environment validation
**Parallelizable**: Yes [P]

**Description**: Run quickstart verification steps to ensure all tools are installed.

**Actions**:
```bash
# Verify Xcode and Swift versions
xcodebuild -version  # Should show Xcode 15+
swift --version      # Should show Swift 6.0+

# Open project
cd /Users/mac/Maku\ Box\ Dropbox/Maku\ Box/Project/NichiDict
open NichiDict.xcodeproj

# Select CoreKit scheme and build (Cmd+B)
```

**Acceptance**:
- [ ] Xcode 15+ installed
- [ ] Swift 6.0+ available
- [ ] Project builds successfully
- [ ] CoreKit scheme selectable

** Checkpoint**: Setup complete. Ready for foundational implementation.

---

## Phase 2: Foundational Layer

**Goal**: Implement core models and database infrastructure needed by ALL user stories

### T005: [US1] Write DictionaryEntry Model Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Write tests for DictionaryEntry model GRDB integration.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/DictionaryEntryTests.swift`

**Test Cases**:
- `testFetchDictionaryEntry()`: Fetch entry by ID
- `testDecodeDictionaryEntry()`: GRDB decoding from row
- `testDictionaryEntryEquality()`: Hashable/Equatable conformance
- `testFetchMultipleEntries()`: Fetch array of entries

**Acceptance**:
- [ ] Tests compile
- [ ] Tests fail (Red) - DictionaryEntry doesn't exist yet
- [ ] File coverage tracking enabled in Xcode scheme

---

### T006: [US1] Implement DictionaryEntry Model

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Model implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T005

**Description**: Implement DictionaryEntry struct with GRDB conformance.

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Models/DictionaryEntry.swift`

**Implementation**: Follow [data-model.md](data-model.md) schema:
```swift
import Foundation
import GRDB

public struct DictionaryEntry: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let headword: String
    public let readingHiragana: String
    public let readingRomaji: String
    public let frequencyRank: Int?
    public let pitchAccent: String?
    public let createdAt: Int

    public var senses: [WordSense] = []

    public enum Columns: String, ColumnExpression {
        case id, headword
        case readingHiragana = "reading_hiragana"
        case readingRomaji = "reading_romaji"
        case frequencyRank = "frequency_rank"
        case pitchAccent = "pitch_accent"
        case createdAt = "created_at"
    }

    public static let databaseTableName = "dictionary_entries"
    public static let wordSenses = hasMany(WordSense.self)
}
```

**Acceptance**:
- [ ] Tests pass (Green)
- [ ] All GRDB protocols conformed
- [ ] Sendable conformance (Swift 6 concurrency)
- [ ] No compiler warnings

---

### T007: [US1] Write WordSense Model Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Write tests for WordSense model.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/WordSenseTests.swift`

**Test Cases**:
- `testFetchWordSensesForEntry()`: Fetch all senses for an entry, ordered by sense_order
- `testWordSenseRelationship()`: Verify GRDB association with DictionaryEntry
- `testDecodeWordSense()`: GRDB decoding

**Acceptance**:
- [ ] Tests compile
- [ ] Tests fail (Red)

---

### T008: [US1] Implement WordSense Model

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Model implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T007

**Description**: Implement WordSense struct per [data-model.md](data-model.md).

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Models/WordSense.swift`

```swift
import Foundation
import GRDB

public struct WordSense: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let entryId: Int
    public let definitionEnglish: String
    public let partOfSpeech: String
    public let usageNotes: String?
    public let senseOrder: Int

    public var examples: [ExampleSentence] = []

    public enum Columns: String, ColumnExpression {
        case id
        case entryId = "entry_id"
        case definitionEnglish = "definition_english"
        case partOfSpeech = "part_of_speech"
        case usageNotes = "usage_notes"
        case senseOrder = "sense_order"
    }

    public static let databaseTableName = "word_senses"
    public static let entry = belongsTo(DictionaryEntry.self)
    public static let exampleSentences = hasMany(ExampleSentence.self)
}
```

**Acceptance**:
- [ ] Tests pass (Green)
- [ ] Relationship to DictionaryEntry works

---

### T009: [US1] Write SearchResult Domain Model Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test SearchResult domain model (not persisted to database).

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/SearchResultTests.swift`

**Test Cases**:
- `testSearchResultCreation()`: Create SearchResult with all fields
- `testMatchTypeOrdering()`: Verify exact < prefix < contains
- `testSearchResultEquality()`: Hashable conformance

**Acceptance**:
- [ ] Tests compile and fail (Red)

---

### T010: [US1] Implement SearchResult Domain Model

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Model implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T009

**Description**: Implement SearchResult per [contracts/SearchService.swift.md](contracts/SearchService.swift.md).

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Models/SearchResult.swift`

```swift
import Foundation

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: Int
    public let entry: DictionaryEntry
    public let matchType: MatchType
    public let relevanceScore: Double

    public enum MatchType: String, Codable, Comparable {
        case exact, prefix, contains

        public var sortOrder: Int {
            switch self {
            case .exact: return 0
            case .prefix: return 1
            case .contains: return 2
            }
        }

        public static func < (lhs: MatchType, rhs: MatchType) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }
}
```

**Acceptance**:
- [ ] Tests pass (Green)
- [ ] MatchType ordering correct

---

### T011: [US1] Write DatabaseManager Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test DatabaseManager initialization and validation.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/DatabaseManagerTests.swift`

**Test Cases**:
- `testDatabaseInitialization()`: Open bundled database
- `testDatabaseReadOnly()`: Verify readonly mode
- `testValidateSchema()`: Check all tables exist
- `testValidateFTSSync()`: FTS5 row count matches entries

**Acceptance**:
- [ ] Tests compile and fail (Red)

---

### T012: [US1] Implement DatabaseManager

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Infrastructure implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T011

**Description**: Implement DatabaseManager per [research.md](research.md) GRDB patterns.

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Database/DatabaseManager.swift`

**Implementation**: Read-only DatabaseQueue with optimizations:
- `PRAGMA mmap_size = 268435456` (256MB)
- `PRAGMA cache_size = -8000` (8MB)
- `PRAGMA query_only = 1`
- Schema validation on initialization

**Acceptance**:
- [ ] Tests pass (Green)
- [ ] Database opens in readonly mode
- [ ] Schema validation works
- [ ] Performance: <30ms to open database

** Checkpoint**: Foundation complete. Database layer operational. Ready for US1 implementation.

---

## Phase 3: User Story 1 - Basic Word Lookup (P1 - MVP)

**Goal**: Deliver fully functional dictionary search
**Independent Test**: User can search "ßy‹" or "taberu" and see meanings and readings
**Value**: Core dictionary functionality - users can look up words

### T013: [US1] Write DBService Contract Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test DBService protocol implementation per [contracts/DBService.swift.md](contracts/DBService.swift.md).

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/DBServiceTests.swift`

**Test Cases**:
- `testSearchEntriesKanjiQuery()`: Search with kanji returns results
- `testSearchEntriesRomajiQuery()`: Search with romaji returns results
- `testSearchEntriesEmptyQuery()`: Empty query returns empty array
- `testSearchEntriesNoResults()`: Query "xyzabc" returns empty array
- `testSearchEntriesRanking()`: Exact match ranks before prefix match
- `testFetchEntryWithSensesAndExamples()`: Deep fetch with associations
- `testFetchEntryNotFound()`: Returns nil for invalid ID
- `testValidateDatabaseIntegrity()`: Schema validation passes

**Acceptance**:
- [ ] All 8 test cases compile
- [ ] Tests fail (Red) - DBService doesn't exist

---

### T014: [US1] Implement DBService

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Service implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T013, T012

**Description**: Implement DBServiceProtocol per [contracts/DBService.swift.md](contracts/DBService.swift.md).

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift`

**Implementation**:
- `searchEntries(query:limit:)`: FTS5 MATCH query with BM25 ranking
- `fetchEntry(id:)`: Deep fetch with GRDB associations
- `validateDatabaseIntegrity()`: Schema and FTS validation

**SQL Pattern** (from contract):
```sql
SELECT e.*, bm25(fts, 10.0, 5.0, 1.0) AS rank_score,
    CASE
        WHEN e.headword = :query THEN 0
        WHEN e.headword LIKE :query || '%' THEN 1
        ELSE 2
    END AS match_type
FROM dictionary_entries e
JOIN dictionary_fts fts ON e.id = fts.rowid
WHERE dictionary_fts MATCH :fts_query
ORDER BY match_type ASC, rank_score DESC, e.frequency_rank ASC
LIMIT :limit
```

**Acceptance**:
- [ ] All tests pass (Green)
- [ ] Performance: <100ms for search queries
- [ ] Error handling: DatabaseError types thrown correctly

---

### T015: [US1] Write RomajiConverter Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test romaji conversion per [research.md](research.md) conversion algorithm.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/RomajiConverterTests.swift`

**Test Cases**:
- `testKanaToHepburnRomaji()`: "_y‹" ’ "taberu"
- `testKunreiToHepburnNormalization()`: "si" ’ "shi", "ti" ’ "chi"
- `testLongVowelHandling()`: "toukyou", "tMkyM", "tookyoo" all normalize to same form
- `testGeminationHandling()`: "kitte" ’ "Mcf" (small tsu)
- `testSyllabicNHandling()`: "kanna" ’ "K“j", "kan'na" ’ "K“j"
- `testConversionPerformance()`: 1000 conversions in <10ms

**Acceptance**:
- [ ] Tests compile and fail (Red)

---

### T016: [US1] Implement RomajiConverter

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Utility implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T015

**Description**: Implement RomajiConverter using lookup table approach from [research.md](research.md).

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/RomajiConverter.swift`

**Implementation**:
- Static lookup tables for kana ” romaji
- Kunrei-shiki to Hepburn normalization
- Edge case handlers: long vowels, gemination, syllabic n
- `toRomaji(_ kana: String) -> String`
- `toKana(_ romaji: String) -> String`
- `normalizeForSearch(_ input: String) -> String`

**Acceptance**:
- [ ] All tests pass (Green)
- [ ] Performance: <0.1ms per conversion
- [ ] Edge cases handled correctly

---

### T017: [US1] Write ScriptDetector Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test script detection utility.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/ScriptDetectorTests.swift`

**Test Cases**:
- `testDetectKanji()`: "ßy‹" ’ .mixed (kanji + hiragana)
- `testDetectHiragana()`: "_y‹" ’ .hiragana
- `testDetectKatakana()`: "«¿«Ê" ’ .katakana
- `testDetectRomaji()`: "taberu" ’ .romaji
- `testDetectMixed()`: "ßtab" ’ .mixed

**Acceptance**:
- [ ] Tests compile and fail (Red)

---

### T018: [US1] Implement ScriptDetector

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Utility implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T017

**Description**: Implement script detection using Unicode ranges from [research.md](research.md).

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/ScriptDetector.swift`

**Implementation**:
```swift
public enum ScriptType {
    case kanji, hiragana, katakana, romaji, mixed
}

public struct ScriptDetector {
    public static func detect(_ text: String) -> ScriptType {
        // Unicode range checks:
        // Kanji: U+4E00-U+9FFF
        // Hiragana: U+3040-U+309F
        // Katakana: U+30A0-U+30FF
        // Romaji: ASCII letters
    }
}
```

**Acceptance**:
- [ ] All tests pass (Green)
- [ ] Performance: <1ms for typical queries

---

### T019: [US1] Write SearchService Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test SearchService orchestration per [contracts/SearchService.swift.md](contracts/SearchService.swift.md).

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/SearchServiceTests.swift`

**Test Cases**:
- `testSearchEmptyQuery()`: Returns empty array
- `testSearchKanjiQuery()`: Returns results with kanji matches
- `testSearchRomajiQuery()`: Normalizes romaji and searches
- `testSearchHiraganaQuery()`: Searches hiragana column
- `testRankingExactBeforePrefix()`: Exact matches rank first
- `testRankingFrequencyWithinMatchType()`: Higher frequency ranks higher
- `testSearchPerformance()`: <200ms for typical query

**Acceptance**:
- [ ] All 7+ tests compile
- [ ] Tests fail (Red)

---

### T020: [US1] Implement SearchService

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Service implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T019, T014, T016, T018

**Description**: Implement SearchServiceProtocol coordinating DBService, RomajiConverter, and ScriptDetector.

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift`

**Algorithm** (from contract):
1. Validate & sanitize input
2. Detect script type
3. Normalize query (romaji conversion if needed)
4. Execute DBService.searchEntries()
5. Classify match types
6. Rank results
7. Transform to SearchResult array
8. Limit to maxResults

**Acceptance**:
- [ ] All tests pass (Green)
- [ ] Performance: <200ms total (constitution requirement met)
- [ ] Edge cases handled (empty query, special chars, long queries)

---

### T021: [US1] Write SearchViewModel Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test SearchViewModel with Combine debouncing.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/SearchViewModelTests.swift`

**Test Cases**:
- `testAdaptiveDebouncing_ShortQuery()`: <3 chars = 150ms delay
- `testAdaptiveDebouncing_LongQuery()`: e3 chars = 300ms delay
- `testCancellation_RapidQueryChanges()`: Only last query executes
- `testEmptyQueryReturnsEmptyResults()`: No search for empty string
- `testSearchErrorHandling()`: Displays error on search failure

**Acceptance**:
- [ ] Tests compile and fail (Red)
- [ ] Mock SearchService created for testing

---

### T022: [US1] Implement SearchViewModel

**Story**: US1 (P1) - Basic Word Lookup
**Type**: ViewModel implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T021, T020

**Description**: Implement SearchViewModel with adaptive debouncing per [research.md](research.md) Combine patterns.

**File**: `NichiDict/NichiDict/ViewModels/SearchViewModel.swift`

**Implementation**:
- `@Observable` (Swift 5.9+)
- `@Published var query: String`
- `var searchResults: [SearchResult]`
- Combine pipeline: debounce ’ script detection ’ search ’ update results
- Adaptive debounce: 150ms for <3 chars, 300ms for 3+ chars
- `switchToLatest()` for automatic cancellation

**Acceptance**:
- [ ] All tests pass (Green)
- [ ] Debouncing works correctly
- [ ] Query cancellation prevents stale results

---

### T023: [US1] Implement SearchView UI

**Story**: US1 (P1) - Basic Word Lookup
**Type**: UI implementation
**Parallelizable**: No
**Depends on**: T022

**Description**: Build SwiftUI search interface.

**File**: `NichiDict/NichiDict/Views/SearchView.swift`

**UI Components**:
- TextField with binding to viewModel.query
- List displaying searchResults
- Each row shows: headword, reading (kana + romaji), first definition
- Loading indicator while searching
- Empty state: "Enter a word to search"
- No results state: "No results found"

**Accessibility**:
- VoiceOver labels for search field and results
- Dynamic Type support (automatic via SwiftUI)

**Acceptance**:
- [ ] UI matches design
- [ ] Real-time search works as user types
- [ ] VoiceOver announces search field and results
- [ ] Empty/no results states display correctly

---

### T024: [US1] Write UI Tests for Search Flow

**Story**: US1 (P1) - Basic Word Lookup
**Type**: UI Test
**Parallelizable**: Yes [P]

**Description**: Test acceptance scenarios from spec.md User Story 1.

**File**: `NichiDict/NichiDictTests/UITests/SearchFlowTests.swift`

**Test Cases** (from spec.md acceptance scenarios):
- `testSearchWithKanji()`: Type "\", verify results show "sakura" and meanings
- `testSearchWithHiragana()`: Type "_y‹", verify results show "ßy‹" and "taberu"
- `testSearchWithRomaji()`: Type "taberu", verify results show "ßy‹"
- `testSearchOffline()`: Disable network, search still works
- `testRealTimeSearch()`: Type "_y", verify results update as typing continues

**Acceptance**:
- [ ] All 5 acceptance tests pass
- [ ] Tests run in airplane mode (offline verification)
- [ ] Tests measure performance (<2s launch, <200ms search)

---

### T025: [US1] Performance Validation Tests

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Performance test
**Parallelizable**: Yes [P]

**Description**: Validate performance requirements from spec.md.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/PerformanceTests.swift`

**Test Cases**:
- `testSearchPerformance_SmallQuery()`: <100ms for <3 char query (constitution)
- `testSearchPerformance_LongerQuery()`: <200ms for all queries (spec)
- `testDatabaseOpenPerformance()`: <30ms cold start
- `testAppLaunchToSearchable()`: <2s from launch to searchable state

**Acceptance**:
- [ ] All performance tests pass
- [ ] Constitution requirement (<100ms) met
- [ ] Spec requirement (<200ms) met

---

### T026: [US1] Integration Testing

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Integration test
**Parallelizable**: No
**Depends on**: T024, T025

**Description**: End-to-end integration test of complete search flow.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/SearchIntegrationTests.swift`

**Test Cases**:
- `testCompleteSearchFlow()`: DatabaseManager ’ DBService ’ SearchService ’ SearchResult
- `testMultiScriptSearch()`: Search kanji, kana, romaji all return correct results
- `testResultRanking()`: Verify exact > prefix > contains ordering
- `testErrorHandling()`: Corrupted database throws appropriate error

**Acceptance**:
- [ ] All integration tests pass
- [ ] Full flow works end-to-end
- [ ] No memory leaks detected

---

### T027: [US1] Code Coverage Validation

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Quality gate
**Parallelizable**: No
**Depends on**: T026

**Description**: Verify 80% code coverage target per TDD principle.

**Actions**:
1. Enable code coverage in Xcode: Product ’ Scheme ’ Edit Scheme ’ Test ’ Options ’ Code Coverage 
2. Run all tests: Cmd+U
3. View coverage report: Cmd+9 (Report Navigator) ’ Coverage tab

**Coverage Targets** (per constitution principle III):
- DBService: e80%
- SearchService: e80%
- RomajiConverter: e80%
- ScriptDetector: e80%
- SearchViewModel: e80%
- Overall CoreKit/DictionarySearch: e80%

**Acceptance**:
- [ ] Coverage report generated
- [ ] All targets meet 80% threshold
- [ ] Uncovered code identified and justified (if any)

---

### T028: [US1] MVP Documentation

**Story**: US1 (P1) - Basic Word Lookup
**Type**: Documentation
**Parallelizable**: Yes [P]

**Description**: Document US1 implementation for developers.

**Files**:
- Update README.md with build instructions
- Add inline documentation to public APIs
- Document known limitations

**Acceptance**:
- [ ] README has usage examples
- [ ] Public APIs have doc comments
- [ ] Known issues documented

** Checkpoint**: User Story 1 (MVP) complete! Users can search for words and see meanings. App is functionally a working dictionary.

---

## Phase 4: User Story 2 - Detailed Entry Information (P2)

**Goal**: Display pitch accent, frequency rank, and detailed part-of-speech
**Independent Test**: User taps search result, sees detail view with pitch accent notation and frequency rank
**Value**: Elevates dictionary to learning tool with pronunciation and frequency guidance

### T029: [US2] Implement ExampleSentence Model

**Story**: US2 (P2) - Detailed Entry Information
**Type**: Model implementation
**Parallelizable**: Yes [P]

**Description**: Add ExampleSentence model for US3 (needed for deep fetch in US2).

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Models/ExampleSentence.swift`

**Note**: ExampleSentence is implemented now because US2's detail view uses deep fetch (entry + senses + examples). The UI will be added in US3.

```swift
import Foundation
import GRDB

public struct ExampleSentence: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let senseId: Int
    public let japaneseText: String
    public let englishTranslation: String
    public let exampleOrder: Int

    public enum Columns: String, ColumnExpression {
        case id
        case senseId = "sense_id"
        case japaneseText = "japanese_text"
        case englishTranslation = "english_translation"
        case exampleOrder = "example_order"
    }

    public static let databaseTableName = "example_sentences"
    public static let wordSense = belongsTo(WordSense.self)
}
```

**Acceptance**:
- [ ] Model compiles
- [ ] GRDB fetch works
- [ ] Relationship to WordSense works

---

### T030: [US2] Write PitchAccentFormatter Tests

**Story**: US2 (P2) - Detailed Entry Information
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test pitch accent formatting utility.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/PitchAccentFormatterTests.swift`

**Test Cases**:
- `testFormatDownstepNotation()`: "_“y‹" renders correctly
- `testFormatNoPitchAccent()`: Nil pitch accent returns empty/placeholder
- `testFormatInvalidNotation()`: Malformed notation handled gracefully

**Acceptance**:
- [ ] Tests compile and fail (Red)

---

### T031: [US2] Implement PitchAccentFormatter

**Story**: US2 (P2) - Detailed Entry Information
**Type**: Utility implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T030

**Description**: Format pitch accent with downstep arrows for display.

**File**: `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Utilities/PitchAccentFormatter.swift`

**Implementation**:
```swift
public struct PitchAccentFormatter {
    /// Format pitch accent notation for display
    /// - Parameter pitchAccent: Raw notation like "_“y‹"
    /// - Returns: Formatted attributed string or plain text
    public static func format(_ pitchAccent: String?) -> String {
        guard let pitch = pitchAccent, !pitch.isEmpty else {
            return "" // Or "No pitch accent data"
        }
        return pitch // SwiftUI handles Unicode arrows automatically
    }
}
```

**Acceptance**:
- [ ] Tests pass (Green)
- [ ] Downstep arrows display correctly in UI

---

### T032: [US2] Write EntryDetailViewModel Tests

**Story**: US2 (P2) - Detailed Entry Information
**Type**: Test (TDD - Red)
**Parallelizable**: Yes [P]

**Description**: Test EntryDetailViewModel data loading.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/EntryDetailViewModelTests.swift`

**Test Cases**:
- `testLoadEntryDetails()`: Fetch entry with all senses and examples
- `testLoadEntryNotFound()`: Handle missing entry gracefully
- `testFrequencyRankFormatting()`: "Rank 100" ’ "Top 100", nil ’ "Uncommon"
- `testPartOfSpeechFormatting()`: Display comma-separated POS tags

**Acceptance**:
- [ ] Tests compile and fail (Red)

---

### T033: [US2] Implement EntryDetailViewModel

**Story**: US2 (P2) - Detailed Entry Information
**Type**: ViewModel implementation (TDD - Green)
**Parallelizable**: No
**Depends on**: T032

**Description**: ViewModel for entry detail screen with deep fetch.

**File**: `NichiDict/NichiDict/ViewModels/EntryDetailViewModel.swift`

**Implementation**:
- `@Observable`
- `var entry: DictionaryEntry?`
- `func loadEntry(id: Int) async`
- Uses DBService.fetchEntry(id:) for deep fetch
- Formats frequency rank: 1-500 = "Top 500", nil = "Uncommon"
- Formats part of speech for display

**Acceptance**:
- [ ] Tests pass (Green)
- [ ] Deep fetch includes senses and examples
- [ ] Formatting functions work correctly

---

### T034: [US2] Implement EntryDetailView UI

**Story**: US2 (P2) - Detailed Entry Information
**Type**: UI implementation
**Parallelizable**: No
**Depends on**: T033, T031

**Description**: Detail view showing pitch accent, frequency, and POS.

**File**: `NichiDict/NichiDict/Views/EntryDetailView.swift`

**UI Layout**:
- Header: Headword (large), reading (kana + romaji)
- Pitch accent: Formatted with downstep arrows
- Frequency rank: "Top 500" badge or "Uncommon"
- Part of speech: Comma-separated tags
- Senses: List of definitions with order numbers
- (Examples section placeholder for US3)

**Accessibility**:
- VoiceOver reads headword, reading, pitch accent, frequency
- Dynamic Type support

**Acceptance**:
- [ ] UI displays all US2 fields
- [ ] Pitch accent arrows render correctly
- [ ] VoiceOver announces all fields
- [ ] Empty states handled (no pitch accent, no frequency)

---

### T035: [US2] Write UI Tests for Detail View

**Story**: US2 (P2) - Detailed Entry Information
**Type**: UI Test
**Parallelizable**: Yes [P]

**Description**: Test US2 acceptance scenarios.

**File**: `NichiDict/NichiDictTests/UITests/DetailViewTests.swift`

**Test Cases** (from spec.md):
- `testDetailViewShowsPitchAccent()`: Search "ßy‹", tap result, verify "_“y‹" displayed
- `testDetailViewShowsFrequencyRank()`: Verify "Top 500" displayed
- `testDetailViewShowsPartOfSpeech()`: Verify "Ichidan verb, transitive" displayed
- `testDetailViewRareWord()`: Rare word shows "Uncommon" frequency
- `testDetailViewOffline()`: All data loads offline

**Acceptance**:
- [ ] All 5 acceptance tests pass
- [ ] Tests verify pitch accent, frequency, POS display

---

### T036: [US2] Navigation Integration

**Story**: US2 (P2) - Detailed Entry Information
**Type**: Integration
**Parallelizable**: No
**Depends on**: T034

**Description**: Integrate SearchView ’ EntryDetailView navigation.

**File**: Update `NichiDict/NichiDict/Views/SearchView.swift`

**Changes**:
- Wrap List in NavigationStack
- Add NavigationLink to EntryDetailView for each result
- Pass entry.id to EntryDetailView

**Acceptance**:
- [ ] Tap search result navigates to detail view
- [ ] Back button returns to search
- [ ] Navigation smooth (60fps)

** Checkpoint**: User Story 2 complete! Users can view detailed word information with pitch accent and frequency.

---

## Phase 5: User Story 3 - Example Sentences (P3)

**Goal**: Display example sentences showing word usage in context
**Independent Test**: User views detail view, scrolls to examples section, sees Japanese sentences with translations
**Value**: Context and usage patterns for intermediate/advanced learners

### T037: [US3] Implement ExampleSentencesView Component

**Story**: US3 (P3) - Example Sentences
**Type**: UI implementation
**Parallelizable**: Yes [P]

**Description**: SwiftUI component displaying example sentences.

**File**: `NichiDict/NichiDict/Views/ExampleSentencesView.swift`

**UI Layout**:
- Section header: "Examples"
- For each example:
  - Japanese text with target word highlighted
  - English translation below
- Empty state: "No example sentences available"

**Word Highlighting**:
- Use AttributedString to highlight target word in Japanese text
- Yellow background or bold font

**Accessibility**:
- VoiceOver reads Japanese, then English
- Dynamic Type support

**Acceptance**:
- [ ] Examples display in order (example_order)
- [ ] Target word highlighted correctly
- [ ] Empty state for words without examples
- [ ] VoiceOver announces Japanese and English separately

---

### T038: [US3] Integrate ExampleSentencesView into EntryDetailView

**Story**: US3 (P3) - Example Sentences
**Type**: Integration
**Parallelizable**: No
**Depends on**: T037

**Description**: Add examples section to EntryDetailView.

**File**: Update `NichiDict/NichiDict/Views/EntryDetailView.swift`

**Changes**:
- Add ExampleSentencesView below definitions
- Pass entry.senses[0].examples to component (first sense examples)
- If multiple senses, show examples per sense

**Acceptance**:
- [ ] Examples section appears below definitions
- [ ] Examples load from deep fetch (already working from T033)
- [ ] Scrolling smooth

---

### T039: [US3] Write UI Tests for Examples View

**Story**: US3 (P3) - Example Sentences
**Type**: UI Test
**Parallelizable**: Yes [P]

**Description**: Test US3 acceptance scenarios.

**File**: `NichiDict/NichiDictTests/UITests/ExamplesViewTests.swift`

**Test Cases** (from spec.md):
- `testExamplesDisplayed()`: Search "ßy‹", open detail, verify e3 examples shown
- `testTargetWordHighlighted()`: Verify "ßy‹" is highlighted in sentences
- `testExamplesOrdered()`: Examples sorted by simplicity/frequency
- `testNoExamplesMessage()`: Rare word shows "No example sentences available"
- `testExamplesOffline()`: Examples load offline

**Acceptance**:
- [ ] All 5 acceptance tests pass
- [ ] Highlighting visually confirmed

---

### T040: [US3] Polish Example Sentence Formatting

**Story**: US3 (P3) - Example Sentences
**Type**: Polish
**Parallelizable**: No
**Depends on**: T038

**Description**: Refine example sentence formatting and layout.

**Actions**:
- Adjust spacing between Japanese and English text
- Ensure highlighting contrast is accessible
- Test with various sentence lengths

**Acceptance**:
- [ ] Formatting looks polished
- [ ] Long sentences wrap correctly
- [ ] Contrast meets accessibility guidelines

---

### T041: [US3] Example Sentences Performance Test

**Story**: US3 (P3) - Example Sentences
**Type**: Performance test
**Parallelizable**: Yes [P]

**Description**: Verify examples don't impact scroll performance.

**File**: `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/PerformanceTests.swift`

**Test Cases**:
- `testScrollPerformanceWithExamples()`: 60fps scrolling with 10+ examples
- `testExampleLoadTime()`: Examples load <50ms

**Acceptance**:
- [ ] Scroll performance maintained at 60fps
- [ ] No lag with many examples

** Checkpoint**: User Story 3 complete! All acceptance criteria met. Feature fully implemented.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Goal**: Final integration, edge case handling, and polish

### T042: Edge Case Handling

**Story**: Polish
**Type**: Bug fixes and edge cases
**Parallelizable**: No

**Description**: Handle edge cases from spec.md:
- Empty search query ’ show prompt
- No results ’ show helpful message
- Very long queries (>100 chars) ’ truncate gracefully
- Partial kanji search ’ limit to top 100 results with message
- Database corruption ’ detect and show error
- Special characters ’ sanitize input
- Memory constraints ’ virtualize lists

**Files**: Multiple (SearchView.swift, SearchService.swift, DatabaseManager.swift)

**Acceptance**:
- [ ] All edge cases from spec.md handled
- [ ] Error messages user-friendly
- [ ] App doesn't crash on edge cases

---

### T043: Final Code Review and Cleanup

**Story**: Polish
**Type**: Code quality
**Parallelizable**: No
**Depends on**: T042

**Description**: Final review and cleanup before merge.

**Actions**:
- Remove debug print statements
- Remove unused imports
- Verify all TODOs resolved
- Run SwiftLint (if configured)
- Review for memory leaks (Instruments)
- Verify no force unwraps or unsafe code

**Acceptance**:
- [ ] No compiler warnings
- [ ] No memory leaks detected
- [ ] Code passes linting
- [ ] All TODOs resolved or documented

---

## Task Dependencies

### Critical Path (Blocking Tasks)

**Setup Phase**:
- T001 ’ T002 ’ T003, T004 (can run in parallel after T002)

**Foundation Phase**:
- T005 ’ T006 (DictionaryEntry)
- T007 ’ T008 (WordSense)
- T009 ’ T010 (SearchResult)
- T011 ’ T012 (DatabaseManager)

**User Story 1 (MVP)**:
- T013 ’ T014 (DBService) - depends on T006, T008, T012
- T015 ’ T016 (RomajiConverter) - independent
- T017 ’ T018 (ScriptDetector) - independent
- T019 ’ T020 (SearchService) - depends on T014, T016, T018
- T021 ’ T022 (SearchViewModel) - depends on T020
- T023 (SearchView) - depends on T022
- T024, T025 (UI/Performance tests) - depends on T023
- T026 (Integration) - depends on T024, T025
- T027 (Coverage) - depends on T026
- T028 (Docs) - can run anytime after T023

**User Story 2**:
- T029 (ExampleSentence) - independent, can run in parallel with US1 tasks
- T030 ’ T031 (PitchAccentFormatter) - independent
- T032 ’ T033 (EntryDetailViewModel) - depends on T014, T029
- T034 (EntryDetailView) - depends on T033, T031
- T035 (UI tests) - depends on T034
- T036 (Navigation) - depends on T034, T023

**User Story 3**:
- T037 (ExampleSentencesView) - depends on T029
- T038 (Integration) - depends on T037, T034
- T039 (UI tests) - depends on T038
- T040 (Polish) - depends on T038
- T041 (Performance) - depends on T038

**Polish**:
- T042 (Edge cases) - depends on all US tasks
- T043 (Cleanup) - depends on T042

### Parallelizable Tasks

**Setup Phase**:
- T003 [P] and T004 [P] can run in parallel after T002

**Foundation Phase**:
- T005 [P], T007 [P], T009 [P], T011 [P] - all test files can be written in parallel
- After models complete: T006, T008, T010, T012 must run sequentially (same files)

**US1 Implementation**:
- T015 [P], T017 [P], T013 [P] - test files, can write in parallel
- T024 [P], T025 [P], T028 [P] - can run in parallel after T023

**US2 Implementation**:
- T029 [P], T030 [P], T032 [P] - can start early, parallel with US1
- T035 [P] - can run in parallel with other test tasks

**US3 Implementation**:
- T037 [P], T039 [P], T041 [P] - independent components

## Parallel Execution Examples

### Maximum Parallelism During US1

After foundation complete, these tasks can run simultaneously:
- T015 (Write RomajiConverter tests) [P]
- T017 (Write ScriptDetector tests) [P]
- T013 (Write DBService tests) [P]

Then after implementation:
- T024 (UI tests) [P]
- T025 (Performance tests) [P]
- T028 (Documentation) [P]

### Maximum Parallelism During US2

While US1 is finishing:
- T029 (ExampleSentence model) [P]
- T030 (PitchAccentFormatter tests) [P]
- T032 (EntryDetailViewModel tests) [P]

---

## Implementation Notes

### Test-Driven Development (TDD)

Every service, model, and utility follows the TDD cycle:
1. **Red**: Write failing test (T005, T007, T009, etc.)
2. **Green**: Implement minimum code to pass (T006, T008, T010, etc.)
3. **Refactor**: Improve code quality (covered in each implementation task)

### Coverage Target

Constitution principle III requires 80% code coverage. T027 validates this before US1 completion.

### Performance Validation

T025 validates constitution requirements:
- <100ms for <3 character queries
- <200ms for all queries
- <2s app launch to searchable state

### Independent User Stories

Each user story (P1, P2, P3) can be tested independently:
- **US1**: Search works, results display meanings/readings
- **US2**: Detail view adds pitch accent and frequency (US1 still works)
- **US3**: Example sentences added (US1 and US2 still work)

---

## Success Criteria Validation

### From spec.md Success Criteria

- **SC-001**: Users can find any top 5000 word in <3 interactions ’ Validated by T024
- **SC-002**: <200ms query response for 95% of searches ’ Validated by T025
- **SC-003**: 100% offline feature parity ’ Validated by T024 (airplane mode test)
- **SC-004**: Complete word info in single detail view ’ Validated by T035
- **SC-005**: 95%+ search accuracy (top 3 results) ’ Validated by T019, T026
- **SC-006**: <2s launch to searchable ’ Validated by T025
- **SC-007**: Database <100MB ’ Validated during database seed generation (not in tasks, pre-implementation)

---

**Status**:  Task breakdown complete. 43 tasks across 3 user stories. Ready for `/speckit.implement`.
