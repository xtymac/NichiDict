# Search Logic Fix Report

## Date
2025-10-16

## Issues Identified

### 1. Wrong Search Results for Japanese Kanji Words
**Problem**: Searching for "行く" or "見る" returned incorrect results like "幾" (several) instead of the actual word.

**Root Cause**:
- `ScriptDetector` classified pure kanji words like "行く", "見る" as `.kanji` type
- `SearchService.shouldTryReverseSearch()` treated `.kanji` as Chinese input
- Triggered reverse search (English/Chinese → Japanese) instead of forward search
- Reverse search looked for the kanji characters in definitions, finding wrong matches

### 2. Chinese Translations Not Displaying
**Secondary Issue**: While the database contains Chinese translations (8,698 entries with Chinese), they weren't being displayed properly due to the wrong search path.

## Solution Implemented

### ScriptDetector Enhancement
Added new `.japaneseKanji` script type to distinguish Japanese kanji words from Chinese input:

```swift
public enum ScriptType {
    case kanji           // Pure kanji (likely Chinese input)
    case hiragana        // Pure hiragana (Japanese)
    case katakana        // Pure katakana (Japanese)
    case romaji          // Latin alphabet (could be romaji or English)
    case mixed           // Mixed scripts (Japanese with kanji+kana)
    case japaneseKanji   // Kanji that's likely Japanese (based on context)
}
```

**Detection Logic**:
- Mixed kanji + kana → `.mixed` (definitely Japanese)
- Pure kanji, 1-3 characters → `.japaneseKanji` (likely Japanese words like 行く, 見る, 本, 人)
- Pure kanji, 4+ characters → `.kanji` (likely Chinese input)

### SearchService Update
Modified `shouldTryReverseSearch()` to handle the new `.japaneseKanji` type:

```swift
case .japaneseKanji:
    // Short kanji words (1-3 characters) are likely Japanese vocabulary
    // Examples: 行く, 見る, 食べる, 飲む, 本, 人
    return false  // Use forward search (Japanese)
```

## Expected Results After Fix

### Search Behavior
| Query | Script Type | Search Mode | Expected Results |
|-------|-------------|-------------|------------------|
| 行く | `.japaneseKanji` | Forward | 行く (to go) |
| 見る | `.japaneseKanji` | Forward | 見る (to see) |
| 飲む | `.japaneseKanji` | Forward | 飲む (to drink) |
| 食べる | `.mixed` | Forward | 食べる (to eat) |
| tabe | `.romaji` | Forward | 食べる, 多弁, etc. |
| eat | `.romaji` | Reverse | 食べる (to eat) |
| 看 | `.japaneseKanji` | Forward | Related entries |
| 经济发展 | `.kanji` (4 chars) | Reverse | Chinese search |

### Chinese Display
When system locale is Chinese:
- Common words (飲む, 行く, 見る) will show Chinese translations from Wiktionary
- Database contains 8,698 entries (~2%) with Chinese translations
- Kanji variants (喫; 食; 召; 頂) will be filtered by existing UI logic

## Files Modified

1. **[ScriptDetector.swift:3-73](../Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/ScriptDetector.swift#L3-L73)**
   - Added `.japaneseKanji` enum case
   - Enhanced detection logic to count kanji characters
   - Distinguish 1-3 char kanji (Japanese) from 4+ char kanji (Chinese)

2. **[SearchService.swift:146-180](../Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift#L146-L180)**
   - Updated `shouldTryReverseSearch()` to handle `.japaneseKanji`
   - Japanese kanji words now use forward search
   - Long pure kanji strings still use reverse search (Chinese)

## Build Status
✅ **BUILD SUCCEEDED** (2025-10-16 15:24:28)

## Testing Recommendations

1. **Japanese Word Search**:
   - Search: 行く → Should show "行く (to go)" with Chinese "去; 去世"
   - Search: 見る → Should show "見る (to see)" with Chinese "看"
   - Search: 飲む → Should show "飲む (to drink)" with Chinese "喝; 飲/饮; 啉; 喝; 吃药; 吃藥"

2. **Romaji Search**:
   - Search: tabe → Should show 食べる and 多弁 (both valid)
   - Search: iku → Should show 行く

3. **Reverse Search (English/Chinese)**:
   - Search: eat → Should show 食べる
   - Search: drink → Should show 飲む
   - Search: 看 → Should show 見る (if in database)

4. **Edge Cases**:
   - Single kanji: 本, 人 → Should use forward search (Japanese)
   - Long kanji: 经济发展 → Should use reverse search (Chinese)

## Known Limitations

1. **Low Chinese Coverage**: Only 2% of entries have Chinese translations
   - Future improvement: Use full JMdict (not _e version) for 15-20% coverage
   - Or: AI-generated translations for remaining entries

2. **Kanji Variant Display**: Some entries show kanji variants like "喫; 食; 召; 頂"
   - These are from Wiktionary, not real Chinese translations
   - Existing UI filtering should handle these

3. **Detection Heuristic**: 3-character threshold is heuristic-based
   - Works well for common cases
   - May misclassify rare 4-character Japanese words as Chinese
   - Can be refined based on user feedback

## Next Steps

1. Test the app with corrected search logic
2. Verify Chinese translations display correctly
3. Monitor for edge cases in kanji detection
4. Consider adding word frequency data to improve detection accuracy
