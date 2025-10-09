# SearchService Contract

**Feature**: 001-offline-dictionary-search
**Created**: 2025-10-08
**Purpose**: High-level search orchestration with ranking, normalization, and result transformation

## Protocol Definition

```swift
import Foundation

/// Search orchestration service coordinating database queries, result ranking, and transformations
/// Thread-safe (Sendable)
protocol SearchServiceProtocol: Sendable {
    /// Perform intelligent multi-script search with ranking and filtering
    /// - Parameters:
    ///   - query: User's raw search input (any script: kanji, kana, romaji)
    ///   - maxResults: Maximum number of results to return (default: 100, per FR-011)
    /// - Returns: Ranked search results with match type and relevance scores
    /// - Throws: SearchError if query processing or database access fails
    /// - Performance: <200ms total (includes normalization + DB query + ranking)
    func search(
        query: String,
        maxResults: Int
    ) async throws -> [SearchResult]
}
```

## Domain Models

### SearchResult

```swift
/// Enriched search result with ranking metadata
struct SearchResult: Identifiable, Hashable {
    /// Unique identifier (same as entry.id)
    let id: Int

    /// Dictionary entry (shallow: without senses/examples)
    let entry: DictionaryEntry

    /// Type of match (exact, prefix, or contains)
    let matchType: MatchType

    /// BM25 relevance score from FTS5 (higher = more relevant)
    let relevanceScore: Double

    /// Match type classification for ranking
    enum MatchType: String, Codable {
        case exact      // Exact headword or reading match
        case prefix     // Query is prefix of headword/reading
        case contains   // Headword/reading contains query

        /// Sort order value (lower = higher priority)
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

## Implementation Contract

### `search(query:maxResults:)` Algorithm

**High-Level Flow**:
1. Validate and sanitize input
2. Normalize query (script detection + conversion)
3. Execute database search via DBService
4. Classify match types (exact/prefix/contains)
5. Rank results (match type > BM25 > frequency)
6. Transform to SearchResult domain models
7. Limit to maxResults

**Detailed Steps**:

#### Step 1: Input Validation

```swift
// Trim whitespace
let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

// Empty query edge case
guard !trimmedQuery.isEmpty else {
    return []  // No error, just empty results
}

// Sanitize for SQL injection (escape FTS5 special chars)
let sanitized = trimmedQuery
    .replacingOccurrences(of: "\"", with: "\"\"")  // Escape double quotes
    .replacingOccurrences(of: "*", with: "")       // Remove wildcards
    .replacingOccurrences(of: ":", with: "")       // Remove column specifiers

// Truncate long queries (edge case from spec)
let maxLength = 100
let finalQuery = String(sanitized.prefix(maxLength))
```

#### Step 2: Query Normalization

**Script Detection**:
```swift
enum ScriptType {
    case kanji       // Contains CJK unified ideographs (U+4E00-U+9FFF)
    case hiragana    // Contains hiragana (U+3040-U+309F)
    case katakana    // Contains katakana (U+30A0-U+30FF)
    case romaji      // Contains ASCII letters (A-Za-z)
    case mixed       // Multiple scripts detected
}

func detectScript(_ text: String) -> ScriptType {
    let hasKanji = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    let hasHiragana = text.unicodeScalars.contains { (0x3040...0x309F).contains($0.value) }
    let hasKatakana = text.unicodeScalars.contains { (0x30A0...0x30FF).contains($0.value) }
    let hasRomaji = text.unicodeScalars.contains { $0.isASCII && $0.properties.isAlphabetic }

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
        return .mixed  // Fallback for special characters only
    }
}
```

**Normalization Rules**:
- **Katakana**: Convert to hiragana for unified kana matching
  ```swift
  let hiraganaQuery = convertKatakanaToHiragana(query)
  ```
- **Romaji**: Accept both Hepburn and Kunrei-shiki, convert for search
  ```swift
  let normalizedRomaji = RomajiConverter.normalizeForSearch(query)
  ```
- **Kanji/Hiragana**: Use as-is (no normalization needed)
- **Mixed**: Use as-is, search all columns

#### Step 3: Database Query

```swift
let dbResults = try await dbService.searchEntries(
    query: finalQuery,
    limit: maxResults
)
```

**Note**: DBService already handles FTS5 query building and initial ranking. SearchService adds post-processing for match type classification.

#### Step 4: Match Type Classification

**Algorithm**: Determine if match is exact, prefix, or contains:

```swift
func classifyMatchType(entry: DictionaryEntry, query: String) -> SearchResult.MatchType {
    let lowercaseQuery = query.lowercased()

    // Exact match check
    if entry.headword.lowercased() == lowercaseQuery ||
       entry.readingHiragana.lowercased() == lowercaseQuery ||
       entry.readingRomaji.lowercased() == lowercaseQuery {
        return .exact
    }

    // Prefix match check
    if entry.headword.lowercased().hasPrefix(lowercaseQuery) ||
       entry.readingHiragana.lowercased().hasPrefix(lowercaseQuery) ||
       entry.readingRomaji.lowercased().hasPrefix(lowercaseQuery) {
        return .prefix
    }

    // Contains match (default)
    return .contains
}
```

#### Step 5: Result Ranking

**Ranking Order** (per clarification session):
1. Match type (exact > prefix > contains)
2. BM25 relevance score (higher = better)
3. Frequency rank (lower = more common)

```swift
let ranked = results.sorted { lhs, rhs in
    // Primary: Match type
    if lhs.matchType.sortOrder != rhs.matchType.sortOrder {
        return lhs.matchType.sortOrder < rhs.matchType.sortOrder
    }

    // Secondary: BM25 relevance
    if lhs.relevanceScore != rhs.relevanceScore {
        return lhs.relevanceScore > rhs.relevanceScore  // Higher is better
    }

    // Tertiary: Frequency rank
    let lhsRank = lhs.entry.frequencyRank ?? Int.max
    let rhsRank = rhs.entry.frequencyRank ?? Int.max
    return lhsRank < rhsRank  // Lower rank = more common
}
```

#### Step 6: Transform to SearchResult

```swift
let searchResults = dbResults.map { entry in
    SearchResult(
        id: entry.id,
        entry: entry,
        matchType: classifyMatchType(entry: entry, query: finalQuery),
        relevanceScore: 0.0  // BM25 score from DB (if exposed)
    )
}
```

#### Step 7: Limit Results

```swift
return Array(ranked.prefix(maxResults))
```

## Error Handling

### Custom Errors

```swift
enum SearchError: Error, LocalizedError {
    case emptyQuery
    case queryTooLong(Int)
    case invalidCharacters
    case databaseUnavailable
    case searchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Please enter a search term."
        case .queryTooLong(let length):
            return "Search query too long (\(length) characters). Maximum is 100."
        case .invalidCharacters:
            return "Search contains invalid characters."
        case .databaseUnavailable:
            return "Dictionary database is unavailable. Please restart the app."
        case .searchFailed(let error):
            return "Search failed: \(error.localizedDescription)"
        }
    }
}
```

**Note**: Most edge cases return empty arrays rather than errors:
- Empty query → `[]`
- No results → `[]`
- Query with only special characters → `[]` (after sanitization)

Errors only thrown for:
- Database connection failures
- Corruption detected mid-query
- Critical internal errors

## Performance Contract

**Total Search Time**: <200ms (95th percentile, per FR-002)

**Breakdown**:
- Input validation: <1ms
- Script detection: <1ms
- Normalization: <5ms (romaji conversion if needed)
- Database query: <100ms (target, per constitution)
- Match classification: <10ms (linear scan)
- Sorting: <20ms (O(n log n) for ~100 results)
- Transformation: <5ms
- **Total**: ~140ms typical, <200ms p95

**Optimization Strategies**:
1. Lazy evaluation where possible
2. Avoid redundant string operations
3. Reuse normalized queries
4. Database does heavy lifting (FTS5 + SQL ranking)
5. Limit results early (maxResults enforced in DB query)

## Dependencies

```swift
// Services
let dbService: DBServiceProtocol

// Utilities
let romajiConverter: RomajiConverterProtocol
let scriptDetector: ScriptDetectorProtocol

// Configuration
let defaultMaxResults: Int = 100  // Per FR-011
```

## Testing Contract

### Unit Tests

```swift
final class SearchServiceTests: XCTestCase {
    var searchService: SearchServiceProtocol!
    var mockDBService: MockDBService!

    // MARK: - Input Validation Tests

    func testSearchEmptyQuery() async throws {
        let results = try await searchService.search(query: "", maxResults: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchWhitespaceOnlyQuery() async throws {
        let results = try await searchService.search(query: "   ", maxResults: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchLongQuery() async throws {
        let longQuery = String(repeating: "a", count: 150)
        let results = try await searchService.search(query: longQuery, maxResults: 10)
        // Should truncate to 100 chars, not throw
        XCTAssertNotNil(results)
    }

    func testSearchSpecialCharactersSanitized() async throws {
        let results = try await searchService.search(query: "食べる\"*:", maxResults: 10)
        // Should escape special chars, not throw
        XCTAssertNotNil(results)
    }

    // MARK: - Script Detection Tests

    func testDetectKanjiScript() {
        let script = ScriptDetector.detect("食べる")
        XCTAssertEqual(script, .mixed)  // Contains both kanji and hiragana
    }

    func testDetectHiraganaScript() {
        let script = ScriptDetector.detect("たべる")
        XCTAssertEqual(script, .hiragana)
    }

    func testDetectRomajiScript() {
        let script = ScriptDetector.detect("taberu")
        XCTAssertEqual(script, .romaji)
    }

    // MARK: - Match Type Classification Tests

    func testClassifyExactMatch() {
        let entry = DictionaryEntry(headword: "食べる", readingRomaji: "taberu", ...)
        let matchType = searchService.classifyMatchType(entry: entry, query: "taberu")
        XCTAssertEqual(matchType, .exact)
    }

    func testClassifyPrefixMatch() {
        let entry = DictionaryEntry(headword: "食べる", readingRomaji: "taberu", ...)
        let matchType = searchService.classifyMatchType(entry: entry, query: "tabe")
        XCTAssertEqual(matchType, .prefix)
    }

    func testClassifyContainsMatch() {
        let entry = DictionaryEntry(headword: "食べる", readingRomaji: "taberu", ...)
        let matchType = searchService.classifyMatchType(entry: entry, query: "eru")
        XCTAssertEqual(matchType, .contains)
    }

    // MARK: - Ranking Tests

    func testRankingExactBeforePrefix() async throws {
        // Mock DB returns mixed results
        mockDBService.mockResults = [
            DictionaryEntry(headword: "食", readingRomaji: "shoku", frequencyRank: 100),
            DictionaryEntry(headword: "食べる", readingRomaji: "taberu", frequencyRank: 200),
        ]

        let results = try await searchService.search(query: "食", maxResults: 10)

        XCTAssertEqual(results[0].matchType, .exact)
        XCTAssertEqual(results[0].entry.headword, "食")
    }

    func testRankingFrequencyWithinMatchType() async throws {
        // Mock DB returns prefix matches with different frequencies
        mockDBService.mockResults = [
            DictionaryEntry(headword: "食事", readingRomaji: "shokuji", frequencyRank: 500),
            DictionaryEntry(headword: "食べる", readingRomaji: "taberu", frequencyRank: 50),
        ]

        let results = try await searchService.search(query: "食", maxResults: 10)

        // Both are prefix matches, should sort by frequency
        XCTAssertEqual(results[0].entry.frequencyRank, 50)  // More common first
    }

    // MARK: - Integration Tests

    func testSearchKanjiQuery() async throws {
        let results = try await searchService.search(query: "食", maxResults: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.allSatisfy { $0.entry.headword.contains("食") })
    }

    func testSearchRomajiQuery() async throws {
        let results = try await searchService.search(query: "taberu", maxResults: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.contains { $0.entry.readingRomaji.contains("taberu") })
    }

    func testSearchHiraganaQuery() async throws {
        let results = try await searchService.search(query: "たべる", maxResults: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.contains { $0.entry.readingHiragana == "たべる" })
    }

    func testSearchNoResults() async throws {
        let results = try await searchService.search(query: "xyzabc", maxResults: 10)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Performance Tests

    func testSearchPerformance() throws {
        measure {
            _ = try await searchService.search(query: "食", maxResults: 100)
        }
        // Assert: average < 200ms
    }
}
```

### Mock Dependencies

```swift
final class MockDBService: DBServiceProtocol {
    var mockResults: [DictionaryEntry] = []
    var shouldThrowError: Error?

    func searchEntries(query: String, limit: Int) async throws -> [DictionaryEntry] {
        if let error = shouldThrowError {
            throw error
        }
        return Array(mockResults.prefix(limit))
    }

    func fetchEntry(id: Int) async throws -> DictionaryEntry? {
        mockResults.first { $0.id == id }
    }

    func validateDatabaseIntegrity() async throws -> Bool {
        true
    }
}
```

## Integration with UI Layer

**SwiftUI ViewModel Usage**:

```swift
@Observable
final class SearchViewModel {
    @Published var query: String = ""
    var searchResults: [SearchResult] = []

    private let searchService: SearchServiceProtocol

    func performSearch() async {
        do {
            searchResults = try await searchService.search(
                query: query,
                maxResults: 100
            )
        } catch {
            // Handle error, show user-friendly message
            print("Search failed: \(error)")
        }
    }
}
```

**Combine Integration** (with debouncing):

```swift
$query
    .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
    .removeDuplicates()
    .sink { [weak self] query in
        Task {
            await self?.performSearch()
        }
    }
    .store(in: &cancellables)
```

## Implementation Notes

1. **Sendable Conformance**: Mark all types as `Sendable` for Swift 6 concurrency safety
2. **Actor Isolation**: Consider making SearchService an actor if mutable state is needed
3. **Cancellation**: Support Task cancellation for search operations (check `Task.isCancelled`)
4. **Caching**: Consider caching recent queries (not required for MVP)
5. **Logging**: Add structured logging for debugging (search query, result count, timing)

---

**Status**: ✅ Contract defined. Ready for implementation in CoreKit/DictionarySearch/Services/SearchService.swift
