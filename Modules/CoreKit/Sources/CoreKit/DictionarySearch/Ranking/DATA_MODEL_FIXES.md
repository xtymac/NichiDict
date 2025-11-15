# Data Model Compatibility Fixes

## Overview

Fixed all ranking features and rules to align with the actual `DictionaryEntry` and `WordSense` data models.

## Actual Data Model

### DictionaryEntry
```swift
public struct DictionaryEntry {
    public let id: Int
    public let headword: String
    public let readingHiragana: String
    public let readingRomaji: String
    public let frequencyRank: Int?
    public let pitchAccent: String?
    public let jlptLevel: String?
    public let createdAt: Int
    public var senses: [WordSense]
}
```

**Key point**: ❌ No `tags` array on DictionaryEntry

### WordSense
```swift
public struct WordSense {
    public let id: Int
    public let entryId: Int
    public let definitionEnglish: String
    public let definitionChineseSimplified: String?
    public let definitionChineseTraditional: String?
    public let partOfSpeech: String        // ⚠️ Singular, not plural!
    public let usageNotes: String?
    public let senseOrder: Int
    public var examples: [ExampleSentence]
}
```

**Key points**:
- ❌ No `tags` array on WordSense
- ❌ No `partsOfSpeech` array (it's singular `partOfSpeech`)
- ✅ Has `usageNotes` which we can use as substitute for tags

## Changes Made

### 1. POSFeatures.swift

#### POSPriorityFeature
**Before**:
```swift
guard let firstSense = entry.senses.first,
      let firstPOS = firstSense.partsOfSpeech.first else { ... }
```

**After**:
```swift
guard let firstSense = entry.senses.first else { return 0 }
let normalizedPOS = firstSense.partOfSpeech.lowercased()
```

**Fix**: Changed from array `partsOfSpeech.first` to singular `partOfSpeech`

#### EntryTypeFeature
**Before**:
```swift
if entry.tags.contains(where: { $0.lowercased().contains("expression") }) {
    return .expression
}
```

**After**:
```swift
// Check usageNotes for expression indicators
for sense in entry.senses {
    if let notes = sense.usageNotes?.lowercased() {
        if notes.contains("expression") || notes.contains("phrase") { ... }
    }
}
```

**Fix**: Use `usageNotes` instead of non-existent `tags`

### 2. PenaltyFeatures.swift

All penalty features were checking `entry.tags` and `sense.tags` which don't exist.

#### ArchaicWordPenaltyFeature
**Before**:
```swift
let normalizedTags = entry.tags.map { $0.lowercased() }
for tag in normalizedTags { ... }
```

**After**:
```swift
for sense in entry.senses {
    if let notes = sense.usageNotes?.lowercased() {
        for tag in archaicTags {
            if notes.contains(tag.lowercased()) { return archaicPenalty }
        }
    }

    // Also check partOfSpeech
    let pos = sense.partOfSpeech.lowercased()
    for tag in archaicTags {
        if pos.contains(tag.lowercased()) { return archaicPenalty }
    }
}
```

**Fix**: Check `usageNotes` and `partOfSpeech` instead of `tags`

#### SpecializedDomainPenaltyFeature
Same pattern - changed from `tags` to `usageNotes` + `partOfSpeech`

#### VulgarSlangPenaltyFeature
Same pattern - changed from `tags` to `usageNotes` + `partOfSpeech`

### 3. BucketRules.swift

All bucket rules that checked tags were fixed similarly.

#### ExpressionBucketRule
**Before**:
```swift
let normalizedTags = entry.tags.map { $0.lowercased() }
for tag in normalizedTags { ... }

for sense in entry.senses {
    let normalizedSenseTags = sense.tags.map { $0.lowercased() }
    ...
}
```

**After**:
```swift
// Check senses' usageNotes for expression markers
for sense in entry.senses {
    if let notes = sense.usageNotes?.lowercased() {
        for tag in expressionTags {
            if notes.contains(tag.lowercased()) { return true }
        }
    }

    // Check partOfSpeech for expression markers
    let pos = sense.partOfSpeech.lowercased()
    for tag in expressionTags {
        if pos.contains(tag.lowercased()) { return true }
    }
}
```

**Fix**: Use `usageNotes` and `partOfSpeech` instead of `tags`

#### SpecializedDomainBucketRule
Same pattern

#### ArchaicWordBucketRule
Same pattern

### 4. AuthorityFeatures.swift

Fixed parameter extraction to properly handle `AnyCodable` enum.

#### JLPTFeature Registration
**Before**:
```swift
if let levels = (params["levels"] as? [String: Double]) {
    levelScores = levels
}
```

**After**:
```swift
if let params = config.parameters,
   case .object(let levelsDict) = params["levels"] {
    levelScores = levelsDict.compactMapValues { value in
        if case .double(let d) = value { return d }
        if case .int(let i) = value { return Double(i) }
        return nil
    }
}
```

**Fix**: Properly pattern match on `AnyCodable.object` case

#### FrequencyFeature Registration
**Before**:
```swift
if let smoothingStr = params["smoothing"] as? String { ... }
midpoint = (params["midpoint"] as? Double) ?? 5.0
```

**After**:
```swift
if case .string(let smoothingStr) = params["smoothing"] { ... }

if case .double(let mid) = params["midpoint"] {
    midpoint = mid
} else if case .int(let mid) = params["midpoint"] {
    midpoint = Double(mid)
}
```

**Fix**: Properly pattern match on `AnyCodable` enum cases

## Impact Assessment

### ✅ Features Still Fully Functional
- ExactMatchFeature
- LemmaMatchFeature
- PrefixMatchFeature
- ContainsMatchFeature
- JLPTFeature
- FrequencyFeature (with S-curve)
- POSPriorityFeature
- CommonWordFeature
- SurfaceLengthFeature
- CommonPatternPenaltyFeature
- RareWordPenaltyFeature

### ⚠️ Features with Reduced Detection Capability

These features now rely on `usageNotes` and `partOfSpeech` heuristics instead of explicit tags:

1. **EntryTypeFeature** - May miss some expressions not marked in usageNotes
2. **ArchaicWordPenaltyFeature** - May miss archaic words without indicators in usageNotes
3. **SpecializedDomainPenaltyFeature** - May miss specialized terms without domain markers
4. **VulgarSlangPenaltyFeature** - May miss slang/vulgar terms without markers

### 🔧 Recommendations for Future Enhancement

If you want to improve detection accuracy, consider:

1. **Add tags table**: Create a separate `entry_tags` or `sense_tags` table in the database
2. **Enrich usageNotes**: Ensure import process adds tag-like markers to usageNotes
3. **Use external dictionaries**: Cross-reference with JMdict, EDICT, or other sources that have explicit tags
4. **ML-based classification**: Train a model to detect expressions, archaic words, etc.

## Testing Status

All compilation errors should now be resolved. The features will work with the current data model, though detection of specialized terms, archaic words, and expressions will be less accurate without explicit tags.

**Next step**: Build the project to confirm all compilation errors are fixed.
