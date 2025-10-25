# English → Japanese Reverse Search Ranking Refinement

**Status:** ✅ Complete
**Date:** 2025-10-20

## Overview

Refined the English → Japanese reverse search algorithm to prioritize native Japanese equivalents (e.g., 星, 行く, 言語, 俳優) over katakana loanwords, brand titles, and rare transliterations.

## Problem Statement

Previously, searches for common English words like "star", "go", "language", and "actor" were returning katakana loanwords and entertainment titles first (e.g., スター８０, GOGO) instead of the canonical native Japanese terms. This was due to katakana boost logic and frequency-based ranking.

## Solution Architecture

### 1. Core Native Equivalents Mapping System

**File:** [Modules/CoreKit/Sources/CoreKit/DictionarySearch/Utilities/EnglishJapaneseMapping.swift](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Utilities/EnglishJapaneseMapping.swift)

- Created a comprehensive mapping of ~70 common English words to their canonical Japanese equivalents
- Categories: celestial/nature, verbs, people/roles, language, abstract concepts, common nouns
- Key mappings:
  - `"star"` → `["星", "恒星"]`
  - `"go"` → `["行く", "往く"]`
  - `"language"` → `["言語", "語"]`
  - `"actor"` → `["俳優"]`
  - `"eat"` → `["食べる", "食う"]`

### 2. Enhanced Database Scoring

**File:** [Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift)

Updated the SQL CTE in `searchReverse()` to include:

- **`pos_weight`**: Part-of-speech scoring (verb=0, noun=1, other=2)
- **Core headwords filtering**: Dynamic SQL injection for core native equivalents
- **Inverted katakana penalty**: Changed from boost to demotion (priority 5)

New ranking order:
1. **Core native equivalent** (if provided via `coreHeadwords` parameter)
2. **Parenthetical semantic match** (e.g., "language" in "Japanese (language)")
3. **Part-of-speech weight** (verbs > nouns > other)
4. **Common frequency** (≤5000 rank)
5. **Katakana demotion** (pure katakana entries ranked lower)
6. **Match quality** (exact > prefix > word boundary > contains)
7. **Frequency rank**
8. **Created date & ID** (tie-breakers)

### 3. SearchService Integration

**File:** [Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift)

Added intelligent query processing:

```swift
// Extract semantic hints from parenthetical queries
if EnglishJapaneseMapping.hasParenthetical(normalizedQuery) {
    semanticHint = EnglishJapaneseMapping.extractSemanticHint(from: normalizedQuery)
    searchQuery = EnglishJapaneseMapping.extractBaseWord(from: normalizedQuery)
}

// Get core native equivalents
coreHeadwords = EnglishJapaneseMapping.canonicalHeadwords(forEnglishWord: searchQuery)

// Pass to database layer
dbResults = try await dbService.searchReverse(
    query: searchQuery,
    limit: searchLimit,
    isEnglishQuery: isEnglishQuery,
    semanticHint: semanticHint,
    coreHeadwords: coreHeadwords
)
```

### 4. Protocol Updates

Updated `DBServiceProtocol` signature:

```swift
func searchReverse(
    query: String,
    limit: Int,
    isEnglishQuery: Bool,
    semanticHint: String?,      // NEW: e.g., "language" from "(language)"
    coreHeadwords: Set<String>? // NEW: e.g., ["言語", "語"]
) async throws -> [DictionaryEntry]
```

## Test Coverage

### Updated Tests

**File:** [Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/EnglishReverseSearchTests.swift](Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/EnglishReverseSearchTests.swift)

1. **`testEnglishReverseSearchPrefersNativeOverKatakana`**
   - Verifies "star" → 星 (native) before スター (katakana)
   - Tests core mapping priority

2. **`testParentheticalSemanticBoost`**
   - Tests "language" → 言語 before ランゲージ
   - Verifies semantic hint extraction

3. **`testActorRanking`**
   - Tests "actor" → 俳優 before アクター
   - Confirms professional term priority

4. **`testVerbRankingPriority`**
   - Tests "go" → 行く (verb) before 囲碁 (noun)
   - Validates part-of-speech weighting

5. **`testReverseSearchRanksVerbBeforeBoardGame`**
   - Additional verification of verb > noun ranking

6. **`testJapaneseLanguageRanking`**
   - Integration test with real database schema

### Test Results

```
✅ All 60 tests pass (0 failures)
✅ EnglishReverseSearchTests: 9/9 passed
```

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Core native terms rank first | ✅ | Tests show 星 > スター, 行く > 囲碁 |
| Parenthetical semantic boost | ✅ | "(language)" boosts 言語 |
| POS weighting (verb > noun) | ✅ | 行く ranks before 囲碁 |
| Common frequency considered | ✅ | Priority 4 in SQL ORDER BY |
| Katakana loanwords demoted | ✅ | Inverted logic in priority 5 |
| Titles/brands at bottom | ✅ | No frequency rank → low priority |
| Deterministic sorting | ✅ | created_at, id tie-breakers |
| CI smoke tests pass | ✅ | 9/9 EnglishReverseSearchTests pass |

## Example Queries

| Query | Expected Order | Actual Result |
|-------|---------------|---------------|
| `star` | 星 → スター → えとわーる | ✅ Pass |
| `go` | 行く → 囲碁 | ✅ Pass |
| `language` | 言語 → ランゲージ | ✅ Pass |
| `actor` | 俳優 → アクター | ✅ Pass |
| `eat` | 食べる (verb) first | ✅ Pass |

## Performance Considerations

- **SQL Optimization**: Dynamic SQL generation only when `coreHeadwords` provided
- **CTE Efficiency**: Aggregation happens before JOIN to reduce row scans
- **Index Usage**: Leverages existing indexes on `headword`, `frequency_rank`, `created_at`

## Future Enhancements

1. **Expand Core Mappings**: Add more English→Japanese canonical pairs
2. **Title Tag Detection**: Implement `is_title` flag based on usage_notes or tags
3. **Machine Learning**: Train model to identify core vs loanword patterns
4. **User Preferences**: Allow users to toggle native-first vs loanword-first
5. **Frequency Recalibration**: Update frequency thresholds based on usage analytics

## Files Modified

1. ✅ `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Utilities/EnglishJapaneseMapping.swift` (new)
2. ✅ `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift`
3. ✅ `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift`
4. ✅ `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/EnglishReverseSearchTests.swift`

## Migration Notes

- **Backward Compatible**: Optional parameters with default values ensure existing code works
- **No Schema Changes**: Solution purely algorithmic, no database migrations needed
- **Gradual Rollout**: Can be feature-flagged if needed

## Debug Logging

Enhanced logging for troubleshooting:

```
🔍 SearchService: Core native headwords: ["星", "恒星"]
🗄️ DBService.searchReverse: query='star' semanticHint=nil coreHeadwords=2
🗄️ DBService.searchReverse: SQL returned 3 entries before filtering
```

## Conclusion

The refinement successfully addresses the core requirement: **native Japanese equivalents now rank before katakana loanwords and titles** in English→Japanese reverse search. The solution is robust, well-tested, and maintains backward compatibility.

**Ready for Production:** ✅

---

*Generated: 2025-10-20*
*Test Status: 60/60 passing*
*Branch: 002-search-debug-and-ci-verification*
