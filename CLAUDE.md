# NichiDict Development Guidelines

Auto-generated from all feature plans. Last updated: 2025-10-08

## Active Technologies
- Swift 6.0 with strict concurrency checking enabled (001-offline-dictionary-search)

## Project Structure
```
src/
tests/
```

## Commands
# Add commands for Swift 6.0 with strict concurrency checking enabled

## Code Style
Swift 6.0 with strict concurrency checking enabled: Follow standard conventions

## Recent Changes
- 001-offline-dictionary-search: Added Swift 6.0 with strict concurrency checking enabled
- 2025-11: Added JMDict variant_type system for kanji variant normalization
- 2025-11: Added phrasal penalty system for English reverse search (prioritize JLPT core vocab)
- 2025-11-22: Added rare kanji penalty for Japanese search (downrank academic/literary compounds)
- 2025-11-23: Added verb phrase penalty for English reverse search (prioritize noun definitions for noun-like queries)

<!-- MANUAL ADDITIONS START -->
## English Reverse Search (2025-11)

**Phrasal penalty system**: For basic English words, prioritize core JLPT vocabulary over idiomatic phrases:
- Search "all" → ぜんぶ (all; entire) ranks before 更に (after all)
- Search "if" → もし (if) ranks before たとえ (even if)
- Search "so" → だから (so; therefore) ranks before でも (even so)

**Implementation** ([DBService.swift](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift)):
- Added `phrasal_penalty` field to detect phrases like "after all", "if only", "so that"
- Adjusted search priority: phrasal_penalty → match_priority → JLPT level → conjunction_priority
- Ensures learners see common, direct translations before specialized idiomatic usages

**Semantic boosting system** (2025-11-22): For contextual disambiguation, users can provide semantic hints:
- Search "treat (请客)" or "treat (food)" → boosts entries with "(esp. food and drink)" or "someone to dinner"
- Search "wear (shoes)" → boosts entries with "(lower-body)" or "(footwear)"
- Hint extraction: parentheses or Chinese characters (e.g., 请客 = "invite to dinner")

**Implementation** ([DBService.swift:1285](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L1285)):
- Added `semantic_boost` field to prioritize entries matching semantic keywords from user hints
- Maps Chinese hints to English patterns: 请客 → ["%food and drink%", "%someone to%dinner%"]
- Extracts keywords from parentheses: "treat (food, meal)" → boosts definitions with "food" or "meal"
- Priority order: phrasal_penalty → semantic_boost → match_priority → JLPT level
- Ensures learners see contextually relevant translations first (ごちそう before 苛める for "treat (food)")

**Verb phrase penalty system** (2025-11-23): For noun-like English queries, prioritize noun definitions over verb phrase definitions:
- Search "schedule" → 予定 (schedule; plan), 日程 (schedule; agenda) rank before 押す (to fall behind schedule)
- Search "test" → 試験 (examination; test) ranks before 試す (to test; to try)
- Only activates for non-verb queries (queries that don't start with "to ")

**Implementation** ([DBService.swift:585](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L585), [DBService.swift:1046](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L1046)):
- Added `verb_phrase_penalty` field to detect "to verb" definitions (LIKE 'to %')
- Query type detection: `isVerbQuery = lowerQuery.hasPrefix("to ")`, `isNounQuery = !isVerbQuery`
- **CRITICAL**: verb_phrase_penalty must come BEFORE JLPT existence in ORDER BY
  - Example: 押す (N5, "to fall behind schedule") would beat 日程 (no JLPT, "schedule; agenda") if JLPT came first
  - With correct ordering: ALL noun definitions (regardless of JLPT) rank before ALL verb phrase definitions
- Priority order: phrasal_penalty → semantic_boost → **verb_phrase_penalty** → JLPT existence → match_priority → JLPT level
- Only penalizes when isNounQuery=1, so "to test" queries still work correctly (押す won't be penalized for "to fall behind")
- Uses LTRIM() to handle leading spaces in definitions before checking 'to %' pattern
- Ensures learners searching for nouns see noun results first, not verb phrases containing the noun

## Japanese Search Ranking (2025-11-22)

**Rare kanji penalty system**: For Japanese kana searches, downrank academic/literary/archaic compounds with uncommon kanji:
- Search "じこ" → 事故 (accident, N4), 自己 (self, N3) rank before 自己韜晦 (concealing one's talents)
- Search "よてい" → 予定 (schedule, N4) ranks before 輿丁 (palanquin bearer, archaic)
- Penalized kanji: 韜晦躊躇憚瞠嘯囁竦戮慄謗詭諌蘊揶揄逡巡輿 and others
- These characters are outside 常用漢字 (jōyō kanji) and unfamiliar to ~90% of native speakers
- Archaic kanji like 輿 (palanquin/carriage) appear in historical terms but not modern usage

**Implementation** ([DBService.swift:117](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L117), [DBService.swift:195](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L195), [DBService.swift:256](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L256)):
- Added rare kanji penalty check using `INSTR()` for specific uncommon characters in all search paths
- **Rare kanji penalty is now the HIGHEST priority** (above match_priority) to ensure archaic words always rank last:
  - Main FTS search (line 117-133)
  - Variant search for pure kana queries (line 195-210)
  - Contains search for partial matches (line 256-271)
- Ranking priority: **rare_kanji_penalty** → match_priority → compound_priority → JLPT level → katakana penalty → frequency_rank → length
- Ensures modern compound words (予定外, 予定納税) rank before archaic exact matches (輿丁)
- Targeted at academic compounds and historical words that appear in dictionaries but not in modern usage
- Example: "よてい" shows 予定 (N4), 予定外, 予定納税... before 輿丁 (archaic, rank 21)

## Kana/Kanji Display Rules (2025-11-22)

**Display logic for search results**: Determines when to show kana vs kanji headwords in search results.

**Rules**:
1. ✅ **Adverbs** (副詞) may display kana when:
   - Pure adverbs with rare kanji variants (e.g., 屹度 → きっと, 頗る → すこぶる, 殊更 → ことさら)
   - Multiple kanji variants exist (e.g., きっと: 屹度, 急度, きっと)
   - Examples: ぜんぜん、すごく、やっぱり are commonly written in kana

2. ❌ **Nouns** (名詞) NEVER show kana automatically:
   - Nouns with multiple kanji variants always show kanji (e.g., 事務所, not じむしょ)
   - Exception: Words habitually written in kana in modern usage (e.g., こと、もの)
   - Ensures learners recognize standard kanji forms for nouns

**Implementation** ([SearchView.swift:127-131](NichiDict/NichiDict/Views/SearchView.swift#L127-L131), [SearchView.swift:147-150](NichiDict/NichiDict/Views/SearchView.swift#L147-L150)):
- `isRareKanjiWriting`: Only applies to pure adverbs (not nouns or mixed POS)
- Multiple kanji variants check: Only shows kana for pure adverbs
- Priority: hasKanaVariant → isRareKanjiWriting → multiple variants (adverbs only)
- Removed low frequency condition that was incorrectly showing kana for nouns
<!-- MANUAL ADDITIONS END -->