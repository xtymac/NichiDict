# English → Japanese Reverse Search API

## Overview

The reverse search system now intelligently prioritizes native Japanese terms over katakana loanwords using a multi-tier ranking algorithm.

## Core Components

### 1. EnglishJapaneseMapping

**Location:** `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Utilities/EnglishJapaneseMapping.swift`

Provides canonical mappings between English words and their native Japanese equivalents.

#### Methods

```swift
// Check if headword is a core native equivalent
EnglishJapaneseMapping.isCoreNativeEquivalent(
    headword: "星",
    forEnglishWord: "star"
) // Returns: true

// Get all canonical headwords for an English word
EnglishJapaneseMapping.canonicalHeadwords(
    forEnglishWord: "star"
) // Returns: ["星", "恒星"]

// Extract semantic hint from parenthetical query
EnglishJapaneseMapping.extractSemanticHint(
    from: "japanese (language)"
) // Returns: "language"

// Extract base word without parentheses
EnglishJapaneseMapping.extractBaseWord(
    from: "japanese (language)"
) // Returns: "japanese"

// Check if query contains parentheses
EnglishJapaneseMapping.hasParenthetical(
    "japanese (language)"
) // Returns: true
```

### 2. DBService.searchReverse()

**Location:** `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift`

Enhanced with new parameters for intelligent ranking.

#### Signature

```swift
func searchReverse(
    query: String,              // The search query (e.g., "star", "go")
    limit: Int,                 // Maximum results to return
    isEnglishQuery: Bool,       // Whether this is English (vs Chinese)
    semanticHint: String?,      // Optional: hint from parentheses
    coreHeadwords: Set<String>? // Optional: native equivalents to boost
) async throws -> [DictionaryEntry]
```

#### Example Usage

```swift
let dbService = DBService(dbQueue: dbQueue)

// Basic search
let results = try await dbService.searchReverse(
    query: "star",
    limit: 10,
    isEnglishQuery: true,
    semanticHint: nil,
    coreHeadwords: nil
)

// Enhanced search with core mappings
let coreHeadwords = Set(["星", "恒星"])
let enhancedResults = try await dbService.searchReverse(
    query: "star",
    limit: 10,
    isEnglishQuery: true,
    semanticHint: nil,
    coreHeadwords: coreHeadwords
)
// Result: 星 ranks first, then スター
```

### 3. SearchService.search()

**Location:** `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift`

High-level search interface that automatically applies core mappings.

#### Signature

```swift
func search(
    query: String,      // User's search query
    maxResults: Int     // Maximum results to return
) async throws -> [SearchResult]
```

#### Behavior

The SearchService now automatically:
1. Detects English queries
2. Extracts parenthetical hints (e.g., "(language)")
3. Looks up core native equivalents
4. Passes enhanced parameters to DBService

#### Example

```swift
let searchService = SearchService(dbService: dbService)

// User searches for "star"
let results = try await searchService.search(query: "star", maxResults: 10)

// Internally:
// 1. Detects English query
// 2. Looks up core mappings: ["星", "恒星"]
// 3. Calls DBService with coreHeadwords
// 4. Returns ranked results: 星 → スター → えとわーる
```

## Ranking Algorithm

### Priority Order

1. **Core Native Equivalent** (Priority 1)
   - Exact match with canonical mapping
   - Example: "star" → 星 (core) vs スター (loanword)

2. **Parenthetical Semantic Match** (Priority 2)
   - Matches semantic hint from parentheses
   - Example: "japanese (language)" → 言語

3. **Part-of-Speech Weight** (Priority 3)
   - Verbs: weight = 0 (highest)
   - Nouns: weight = 1
   - Other: weight = 2 (lowest)
   - Example: "go" → 行く (verb) vs 囲碁 (noun)

4. **Common Frequency** (Priority 4)
   - Entries with frequency_rank ≤ 5000 boosted
   - Common words rank before rare words

5. **Katakana Demotion** (Priority 5)
   - Pure katakana entries demoted (was boost before)
   - Only applies when `isEnglishQuery=true`
   - Example: スター ranks after native 星

6. **Match Quality** (Priority 6)
   - Exact match > prefix > word boundary > contains
   - Same as before

7. **Frequency Rank** (Priority 7)
   - Lower rank = more common = higher priority
   - Same as before

8. **Tie-Breakers** (Priority 8)
   - created_at ASC
   - id ASC

### SQL Implementation

```sql
ORDER BY
    -- Priority 1: Core native
    CASE WHEN e.headword IN (?, ?) THEN 0 ELSE 1 END,

    -- Priority 2: Parenthetical
    agg.parenthetical_priority,

    -- Priority 3: Part-of-speech
    agg.pos_weight,

    -- Priority 4: Common frequency
    CASE WHEN e.frequency_rank <= 5000 THEN 0 ELSE 1 END,

    -- Priority 5: DEMOTE katakana
    CASE WHEN katakana_only THEN 1 ELSE 0 END,

    -- Priority 6: Match quality
    agg.match_priority,

    -- Priority 7: Frequency
    COALESCE(e.frequency_rank, 999999),

    -- Priority 8: Tie-breakers
    e.created_at,
    e.id
```

## Adding New Core Mappings

To add new canonical mappings, edit the `coreNativeMap` in `EnglishJapaneseMapping.swift`:

```swift
private static let coreNativeMap: [String: Set<String>] = [
    // Add your mappings here
    "love": ["愛"],
    "water": ["水"],
    "fire": ["火"],
    // ...
]
```

## Testing

### Unit Tests

**File:** `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/EnglishReverseSearchTests.swift`

Key test cases:
- `testEnglishReverseSearchPrefersNativeOverKatakana`
- `testActorRanking`
- `testVerbRankingPriority`
- `testParentheticalSemanticBoost`
- `testReverseSearchRanksVerbBeforeBoardGame`

### Running Tests

```bash
cd Modules/CoreKit
swift test --filter EnglishReverseSearchTests
```

## Migration Guide

### Before (Old API)

```swift
// Old: No control over ranking
let results = try await dbService.searchReverse(
    query: "star",
    limit: 10,
    isEnglishQuery: true
)
// Result: スター might rank before 星 (incorrect)
```

### After (New API)

```swift
// New: Automatic core mapping
let results = try await searchService.search(
    query: "star",
    maxResults: 10
)
// Result: 星 ranks before スター (correct)
```

### Backward Compatibility

The new parameters are **optional with defaults**, so existing code continues to work:

```swift
// Still works (defaults: semanticHint=nil, coreHeadwords=nil)
let results = try await dbService.searchReverse(
    query: "star",
    limit: 10,
    isEnglishQuery: true
)
```

## Performance Notes

- **Negligible Overhead**: Core mapping lookup is O(1) dictionary access
- **SQL Optimization**: Dynamic IN clause only generated when coreHeadwords provided
- **CTE Efficiency**: Aggregation before JOIN reduces row scans
- **Index Usage**: Leverages existing indexes on headword, frequency_rank, created_at

## Debug Logging

Enable detailed logging to see ranking decisions:

```swift
// Console output:
🔍 SearchService: Core native headwords: ["星", "恒星"]
🗄️ DBService.searchReverse: query='star' semanticHint=nil coreHeadwords=2
🗄️ DBService.searchReverse: SQL returned 3 entries before filtering
🗄️ DBService.searchReverse: Returning 3 filtered entries
```

## Example Scenarios

### Scenario 1: Simple English Word

```swift
let results = try await searchService.search(query: "star", maxResults: 10)

// Result order:
// 1. 星 (core native)
// 2. 恒星 (core native)
// 3. スター (common katakana)
// 4. えとわーる (rare transliteration)
```

### Scenario 2: Verb vs Noun

```swift
let results = try await searchService.search(query: "go", maxResults: 10)

// Result order:
// 1. 行く (verb, core native)
// 2. 往く (verb, core native)
// 3. 囲碁 (noun, board game)
```

### Scenario 3: Parenthetical Hint

```swift
let results = try await searchService.search(
    query: "japanese (language)",
    maxResults: 10
)

// Internally:
// - Base word: "japanese"
// - Semantic hint: "language"
// - Core mappings for "language": ["言語", "語"]

// Result order:
// 1. 言語 (core native for "language")
// 2. Other matches...
```

## Limitations

1. **Manual Mapping Maintenance**: Core mappings must be manually curated
2. **English-Only**: Currently only supports English→Japanese (not French, German, etc.)
3. **Static Mappings**: No dynamic learning from user behavior (yet)
4. **Limited Coverage**: ~70 words mapped (can be expanded)

## Future Enhancements

1. **Tag-Based Detection**: Identify titles via `film`, `song`, `brand` tags
2. **ML-Based Classification**: Train model to identify core vs loanword patterns
3. **User Preferences**: Allow toggling native-first vs loanword-first
4. **Analytics Integration**: Track which results users click to refine rankings

---

**Last Updated:** 2025-10-20
**Version:** 1.0
**Status:** Production Ready
