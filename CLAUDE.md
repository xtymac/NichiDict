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
<!-- MANUAL ADDITIONS END -->