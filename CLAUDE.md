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

## Japanese Search Ranking (2025-11-22)

**Rare kanji penalty system**: For Japanese kana searches, downrank academic/literary compounds with uncommon kanji:
- Search "じこ" → 事故 (accident, N4), 自己 (self, N3) rank before 自己韜晦 (concealing one's talents)
- Penalized kanji: 韜晦躊躇憚瞠嘯囁竦戮慄謗詭諌蘊揶揄逡巡 and others
- These characters are outside 常用漢字 (jōyō kanji) and unfamiliar to ~90% of native speakers

**Implementation** ([DBService.swift:141](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L141)):
- Added rare kanji penalty check using `INSTR()` for specific uncommon characters
- Ranking priority: match_priority → compound_priority → JLPT level → katakana penalty → **rare kanji penalty** → frequency_rank → length
- Ensures learners see common vocabulary before specialized literary/classical terms
- Targeted at academic compounds that appear in dictionaries but not in everyday usage

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