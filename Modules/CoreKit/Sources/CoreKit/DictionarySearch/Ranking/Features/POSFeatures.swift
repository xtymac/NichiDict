import Foundation

// MARK: - Part of Speech Priority Feature

/// Feature for prioritizing certain parts of speech
/// Rewards entries with important POS tags (verbs, adjectives, etc.)
public struct POSPriorityFeature: ScoringFeature {
    public let name = "posPriority"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let priorityScores: [String: Double]

    public init(
        weight: Double = 0.9,
        range: ClosedRange<Double> = 0...8,
        enabled: Bool = true,
        priorityScores: [String: Double]? = nil
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled

        // Default POS priority scores
        let defaultScores: [String: Double] = [
            // High priority
            "verb": 8.0,          // 動詞
            "adjective": 7.0,     // 形容詞
            "i-adjective": 7.0,   // い形容詞
            "na-adjective": 7.0,  // な形容詞

            // Medium priority
            "noun": 5.0,          // 名詞
            "adverb": 4.0,        // 副詞

            // Lower priority
            "particle": 2.0,      // 助詞
            "auxiliary": 1.0,     // 助動詞
            "conjunction": 1.0,   // 接続詞

            // Minimal priority
            "suffix": 0.5,        // 接尾辞
            "prefix": 0.5         // 接頭辞
        ]

        self.priorityScores = priorityScores ?? defaultScores
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        // Get the first POS tag (primary part of speech)
        guard let firstSense = entry.senses.first else {
            return 0
        }

        // Normalize POS tag to lowercase for matching
        let normalizedPOS = firstSense.partOfSpeech.lowercased()

        // Try exact match first
        if let score = priorityScores[normalizedPOS] {
            return score
        }

        // Try partial matches for compound POS tags
        for (key, score) in priorityScores {
            if normalizedPOS.contains(key) {
                return score
            }
        }

        return 0
    }
}

// MARK: - Common Word Feature

/// Feature for common word bonus
/// Rewards words that are commonly used in everyday Japanese
public struct CommonWordFeature: ScoringFeature {
    public let name = "commonWord"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let thresholds: [Int: Double]

    public init(
        weight: Double = 0.7,
        range: ClosedRange<Double> = 0...5,
        enabled: Bool = true,
        thresholds: [Int: Double]? = nil
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled

        // Default thresholds based on frequency rank
        let defaultThresholds: [Int: Double] = [
            100: 5.0,    // Top 100 words
            500: 3.0,    // Top 500 words
            2000: 1.5,   // Top 2000 words
            5000: 0.5    // Top 5000 words
        ]

        self.thresholds = thresholds ?? defaultThresholds
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        guard let rank = entry.frequencyRank else { return 0 }

        // Find the appropriate threshold
        let sortedThresholds = thresholds.keys.sorted()
        for threshold in sortedThresholds {
            if rank <= threshold {
                return thresholds[threshold] ?? 0
            }
        }

        return 0
    }
}

// MARK: - Entry Type Feature

/// Feature for entry type differentiation
/// Distinguishes between single words, expressions, and compounds
public struct EntryTypeFeature: ScoringFeature {
    public let name = "entryType"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let typeScores: [String: Double]

    public enum EntryType: String, Sendable {
        case word          // Single word
        case expression    // Multi-word expression (handled by Bucket B)
        case compound      // Compound word
        case phrase        // Phrase
    }

    public init(
        weight: Double = 0.6,
        range: ClosedRange<Double> = 0...4,
        enabled: Bool = true,
        typeScores: [String: Double]? = nil
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled

        // Default type scores
        let defaultScores: [String: Double] = [
            "word": 4.0,
            "compound": 2.0,
            "expression": 1.0,  // Lower score (expressions go to Bucket B)
            "phrase": 0.5
        ]

        self.typeScores = typeScores ?? defaultScores
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        let entryType = determineEntryType(entry: entry)
        return typeScores[entryType.rawValue] ?? 0
    }

    private func determineEntryType(entry: DictionaryEntry) -> EntryType {
        let headword = entry.headword

        // Check if it's an expression (contains spaces or multiple kanji+kana units)
        if headword.contains(" ") || headword.contains("・") {
            return .expression
        }

        // Check usageNotes for expression indicators
        for sense in entry.senses {
            if let notes = sense.usageNotes?.lowercased() {
                if notes.contains("expression") || notes.contains("phrase") ||
                   notes.contains("idiom") || notes.contains("成句") {
                    return .expression
                }
            }
        }

        // Check if it's a compound (long word with multiple kanji)
        let kanjiCount = headword.filter { character in
            let scalar = character.unicodeScalars.first!
            return (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) // CJK Unified Ideographs
        }.count

        if kanjiCount > 2 && headword.count > 3 {
            return .compound
        }

        // Check if it's a phrase
        if headword.count > 5 {
            return .phrase
        }

        return .word
    }
}

// MARK: - Surface Length Feature

/// Feature for penalizing very long entries
/// Helps prioritize concise entries over verbose ones
public struct SurfaceLengthFeature: ScoringFeature {
    public let name = "surfaceLength"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let optimalLength: Int
    private let penaltyRate: Double

    public init(
        weight: Double = 0.5,
        range: ClosedRange<Double> = -5...0,
        enabled: Bool = true,
        optimalLength: Int = 3,
        penaltyRate: Double = 0.5
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled
        self.optimalLength = optimalLength
        self.penaltyRate = penaltyRate
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        let length = entry.headword.count

        // No penalty for short entries
        if length <= optimalLength {
            return 0
        }

        // Calculate penalty based on excess length
        let excess = length - optimalLength
        let penalty = -Double(excess) * penaltyRate

        // Clamp to range
        return max(penalty, range.lowerBound)
    }
}

// MARK: - Feature Registration

extension FeatureRegistry {
    /// Register POS and pattern features
    func registerPOSFeatures() {
        registerFeature(type: "posPriority") { config in
            let priorityScores: [String: Double]?
            if let params = config.parameters,
               let scores = params["scores"] {
                // Try to decode as [String: Double] dictionary
                if case .object(let dict) = scores {
                    priorityScores = dict.compactMapValues { value in
                        if case .double(let d) = value { return d }
                        if case .int(let i) = value { return Double(i) }
                        return nil
                    }
                } else {
                    priorityScores = nil
                }
            } else {
                priorityScores = nil
            }

            return POSPriorityFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                priorityScores: priorityScores
            )
        }

        registerFeature(type: "commonWord") { config in
            let thresholds: [Int: Double]?
            if let params = config.parameters,
               let thresh = params["thresholds"] {
                // Try to decode as [Int: Double] dictionary
                if case .object(let dict) = thresh {
                    thresholds = dict.reduce(into: [Int: Double]()) { result, pair in
                        if let intKey = Int(pair.key) {
                            if case .double(let d) = pair.value {
                                result[intKey] = d
                            } else if case .int(let i) = pair.value {
                                result[intKey] = Double(i)
                            }
                        }
                    }
                } else {
                    thresholds = nil
                }
            } else {
                thresholds = nil
            }

            return CommonWordFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                thresholds: thresholds
            )
        }

        registerFeature(type: "entryType") { config in
            let typeScores: [String: Double]?
            if let params = config.parameters,
               let scores = params["scores"] {
                if case .object(let dict) = scores {
                    typeScores = dict.compactMapValues { value in
                        if case .double(let d) = value { return d }
                        if case .int(let i) = value { return Double(i) }
                        return nil
                    }
                } else {
                    typeScores = nil
                }
            } else {
                typeScores = nil
            }

            return EntryTypeFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                typeScores: typeScores
            )
        }

        registerFeature(type: "surfaceLength") { config in
            let optimalLength: Int
            let penaltyRate: Double

            if let params = config.parameters {
                if case .int(let len) = params["optimalLength"] {
                    optimalLength = len
                } else {
                    optimalLength = 3
                }

                if case .double(let rate) = params["penaltyRate"] {
                    penaltyRate = rate
                } else if case .int(let rate) = params["penaltyRate"] {
                    penaltyRate = Double(rate)
                } else {
                    penaltyRate = 0.5
                }
            } else {
                optimalLength = 3
                penaltyRate = 0.5
            }

            return SurfaceLengthFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                optimalLength: optimalLength,
                penaltyRate: penaltyRate
            )
        }
    }
}
