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

## Sense Prioritization for Onomatopoeia (2025-11)

**Problem**: JMDict often lists onomatopoeia senses first, but these are less common in daily usage.

**Example**: どんどん (dondond)
- ❌ Original order: "drumming (noise); beating" → "rapidly; steadily"
- ✅ New order: "rapidly; steadily" → "drumming (noise); beating"

**Implementation** ([DBService.swift](Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L1490-L1530)):
- Added `sortSensesByPriority()` helper function
- Added `isOnomatopoeiaSense()` detector (checks for adverb-to + sound keywords)
- Applied to both forward search (`searchEntries`) and reverse search (`searchReverse`)
- Prioritizes common meanings (rapidly, steadily) over sound effects (drumming, pounding)

**Detection logic**:
- Onomatopoeia = `adverb taking the 'to' particle` + sound keywords (noise, drumming, pounding, etc.)
- Non-onomatopoeia adverb-to words (like やっと "finally") are NOT deprioritized
<!-- MANUAL ADDITIONS END -->