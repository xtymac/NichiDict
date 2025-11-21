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

## Variant Type System (2025-11)

Database-driven kanji variant classification using JMDict ke_inf tags:

| Type | Description | Display |
|------|-------------|---------|
| `uk` | Usually kana | Show kana |
| `primary` | Normal spelling | Show original |
| `rK` | Rare kanji | Show kana |
| `oK` | Old kanji | Show kana |
| `sK` | Search-only | Hidden |

**Key files**:
- `DictionaryEntry.swift`: VariantType enum, displayHeadword, displayPriority
- `DBService.swift`: Sorting logic (exact match first, then variant priority)
- `import_jmdict_with_variants.py`: JMDict import with variant parsing

**Sorting rules**:
1. Exact headword/reading match first
2. Same-reading variants sorted by displayPriority
3. Otherwise preserve SQL order (match_priority, JLPT, frequency)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->