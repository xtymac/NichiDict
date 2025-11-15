import Foundation

// MARK: - Common Pattern Penalty Feature

/// Feature for penalizing common grammatical patterns
/// Reduces scores for entries with overly common patterns that clutter results
public struct CommonPatternPenaltyFeature: ScoringFeature {
    public let name = "commonPatternPenalty"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let patterns: [String: Double]

    public init(
        weight: Double = 1.0,
        range: ClosedRange<Double> = -10...0,
        enabled: Bool = true,
        patterns: [String: Double]? = nil
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled

        // Default penalty patterns
        let defaultPatterns: [String: Double] = [
            // Verb patterns
            "する": -3.0,         // する verbs (very common)
            "させる": -2.0,       // Causative
            "られる": -2.0,       // Passive/potential
            "ている": -2.0,       // Progressive

            // Adjective patterns
            "ぽい": -2.0,         // -ppoi (似合わない)
            "らしい": -2.0,       // -rashii (seems like)
            "っぽい": -2.0,       // -ppoi variant

            // Noun patterns
            "もの": -1.5,         // Generic "thing"
            "こと": -1.5,         // Generic "matter"
            "やつ": -1.5,         // Colloquial "thing/guy"

            // Compound patterns
            "〜的": -2.0,         // -teki (adjectival suffix)
            "〜化": -2.0,         // -ka (nominalization)
            "〜性": -2.0          // -sei (quality/nature)
        ]

        self.patterns = patterns ?? defaultPatterns
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        let headword = entry.headword
        var totalPenalty: Double = 0

        // Check if headword contains any penalty patterns
        for (pattern, penalty) in patterns {
            if headword.contains(pattern) {
                totalPenalty += penalty
            }
        }

        // Clamp to range
        return max(totalPenalty, range.lowerBound)
    }
}

// MARK: - Rare Word Penalty Feature

/// Feature for penalizing very rare words
/// Complements frequency feature by explicitly penalizing words outside common usage
public struct RareWordPenaltyFeature: ScoringFeature {
    public let name = "rareWordPenalty"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let rareThreshold: Int
    private let penaltyRate: Double

    public init(
        weight: Double = 0.8,
        range: ClosedRange<Double> = -8...0,
        enabled: Bool = true,
        rareThreshold: Int = 10000,
        penaltyRate: Double = 0.001
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled
        self.rareThreshold = rareThreshold
        self.penaltyRate = penaltyRate
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        guard let rank = entry.frequencyRank else {
            // No frequency data = potentially rare, apply moderate penalty
            return -2.0
        }

        // No penalty for common words
        if rank < rareThreshold {
            return 0
        }

        // Calculate penalty based on how far beyond threshold
        let excess = rank - rareThreshold
        let penalty = -Double(excess) * penaltyRate

        // Clamp to range
        return max(penalty, range.lowerBound)
    }
}

// MARK: - Archaic Word Penalty Feature

/// Feature for penalizing archaic or obsolete words
/// Reduces scores for words marked as archaic, obsolete, or rare usage
public struct ArchaicWordPenaltyFeature: ScoringFeature {
    public let name = "archaicWordPenalty"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let archaicTags: Set<String>
    private let archaicPenalty: Double

    public init(
        weight: Double = 1.0,
        range: ClosedRange<Double> = -12...0,
        enabled: Bool = true,
        archaicTags: Set<String>? = nil,
        archaicPenalty: Double = -12.0
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled

        // Default archaic tags (case-insensitive matching)
        let defaultTags: Set<String> = [
            "archaic",
            "obsolete",
            "rare",
            "old-fashioned",
            "dated",
            "archaism",
            "古語",
            "廃語"
        ]

        self.archaicTags = archaicTags ?? defaultTags
        self.archaicPenalty = archaicPenalty
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        // Check senses' usageNotes for archaic markers
        for sense in entry.senses {
            if let notes = sense.usageNotes?.lowercased() {
                for tag in archaicTags {
                    if notes.contains(tag.lowercased()) {
                        return archaicPenalty
                    }
                }
            }

            // Also check partOfSpeech for archaic markers
            let pos = sense.partOfSpeech.lowercased()
            for tag in archaicTags {
                if pos.contains(tag.lowercased()) {
                    return archaicPenalty
                }
            }
        }

        return 0
    }
}

// MARK: - Specialized Domain Penalty Feature

/// Feature for penalizing highly specialized domain-specific terms
/// Reduces scores for technical jargon unless user is searching in that domain
public struct SpecializedDomainPenaltyFeature: ScoringFeature {
    public let name = "specializedDomainPenalty"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let domainTags: Set<String>
    private let penalty: Double

    public init(
        weight: Double = 0.7,
        range: ClosedRange<Double> = -6...0,
        enabled: Bool = true,
        domainTags: Set<String>? = nil,
        penalty: Double = -6.0
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled

        // Default specialized domain tags
        let defaultTags: Set<String> = [
            "medicine",
            "law",
            "chemistry",
            "physics",
            "mathematics",
            "computer",
            "engineering",
            "biology",
            "astronomy",
            "geology",
            "anatomy",
            "botany",
            "zoology",
            "医学",
            "法律",
            "化学",
            "物理学",
            "数学",
            "計算機"
        ]

        self.domainTags = domainTags ?? defaultTags
        self.penalty = penalty
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        // Check senses' usageNotes and partOfSpeech for domain markers
        for sense in entry.senses {
            if let notes = sense.usageNotes?.lowercased() {
                for tag in domainTags {
                    if notes.contains(tag.lowercased()) {
                        return penalty
                    }
                }
            }

            // Also check partOfSpeech
            let pos = sense.partOfSpeech.lowercased()
            for tag in domainTags {
                if pos.contains(tag.lowercased()) {
                    return penalty
                }
            }
        }

        return 0
    }
}

// MARK: - Vulgar/Slang Penalty Feature

/// Feature for penalizing vulgar, slang, or colloquial expressions
/// Reduces scores unless user is specifically searching for informal language
public struct VulgarSlangPenaltyFeature: ScoringFeature {
    public let name = "vulgarSlangPenalty"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let vulgarTags: Set<String>
    private let penalty: Double

    public init(
        weight: Double = 0.9,
        range: ClosedRange<Double> = -8...0,
        enabled: Bool = true,
        vulgarTags: Set<String>? = nil,
        penalty: Double = -8.0
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled

        // Default vulgar/slang tags
        let defaultTags: Set<String> = [
            "vulgar",
            "slang",
            "colloquial",
            "derogatory",
            "crude",
            "obscene",
            "offensive",
            "俗語",
            "卑語",
            "下品"
        ]

        self.vulgarTags = vulgarTags ?? defaultTags
        self.penalty = penalty
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        // Check senses' usageNotes and partOfSpeech for vulgar/slang markers
        for sense in entry.senses {
            if let notes = sense.usageNotes?.lowercased() {
                for tag in vulgarTags {
                    if notes.contains(tag.lowercased()) {
                        return penalty
                    }
                }
            }

            // Also check partOfSpeech
            let pos = sense.partOfSpeech.lowercased()
            for tag in vulgarTags {
                if pos.contains(tag.lowercased()) {
                    return penalty
                }
            }
        }

        return 0
    }
}

// MARK: - Feature Registration

extension FeatureRegistry {
    /// Register penalty features
    func registerPenaltyFeatures() {
        registerFeature(type: "commonPatternPenalty") { config in
            let patterns: [String: Double]?
            if let params = config.parameters,
               let patternsValue = params["patterns"] {
                if case .object(let dict) = patternsValue {
                    patterns = dict.compactMapValues { value in
                        if case .double(let d) = value { return d }
                        if case .int(let i) = value { return Double(i) }
                        return nil
                    }
                } else {
                    patterns = nil
                }
            } else {
                patterns = nil
            }

            return CommonPatternPenaltyFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                patterns: patterns
            )
        }

        registerFeature(type: "rareWordPenalty") { config in
            let rareThreshold: Int
            let penaltyRate: Double

            if let params = config.parameters {
                if case .int(let threshold) = params["rareThreshold"] {
                    rareThreshold = threshold
                } else {
                    rareThreshold = 10000
                }

                if case .double(let rate) = params["penaltyRate"] {
                    penaltyRate = rate
                } else if case .int(let rate) = params["penaltyRate"] {
                    penaltyRate = Double(rate)
                } else {
                    penaltyRate = 0.001
                }
            } else {
                rareThreshold = 10000
                penaltyRate = 0.001
            }

            return RareWordPenaltyFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                rareThreshold: rareThreshold,
                penaltyRate: penaltyRate
            )
        }

        registerFeature(type: "archaicWordPenalty") { config in
            let archaicTags: Set<String>?
            let archaicPenalty: Double

            if let params = config.parameters {
                if case .array(let tagsArray) = params["archaicTags"] {
                    archaicTags = Set(tagsArray.compactMap { value in
                        if case .string(let s) = value { return s }
                        return nil
                    })
                } else {
                    archaicTags = nil
                }

                if case .double(let penalty) = params["archaicPenalty"] {
                    archaicPenalty = penalty
                } else if case .int(let penalty) = params["archaicPenalty"] {
                    archaicPenalty = Double(penalty)
                } else {
                    archaicPenalty = -12.0
                }
            } else {
                archaicTags = nil
                archaicPenalty = -12.0
            }

            return ArchaicWordPenaltyFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                archaicTags: archaicTags,
                archaicPenalty: archaicPenalty
            )
        }

        registerFeature(type: "specializedDomainPenalty") { config in
            let domainTags: Set<String>?
            let penalty: Double

            if let params = config.parameters {
                if case .array(let tagsArray) = params["domainTags"] {
                    domainTags = Set(tagsArray.compactMap { value in
                        if case .string(let s) = value { return s }
                        return nil
                    })
                } else {
                    domainTags = nil
                }

                if case .double(let p) = params["penalty"] {
                    penalty = p
                } else if case .int(let p) = params["penalty"] {
                    penalty = Double(p)
                } else {
                    penalty = -6.0
                }
            } else {
                domainTags = nil
                penalty = -6.0
            }

            return SpecializedDomainPenaltyFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                domainTags: domainTags,
                penalty: penalty
            )
        }

        registerFeature(type: "vulgarSlangPenalty") { config in
            let vulgarTags: Set<String>?
            let penalty: Double

            if let params = config.parameters {
                if case .array(let tagsArray) = params["vulgarTags"] {
                    vulgarTags = Set(tagsArray.compactMap { value in
                        if case .string(let s) = value { return s }
                        return nil
                    })
                } else {
                    vulgarTags = nil
                }

                if case .double(let p) = params["penalty"] {
                    penalty = p
                } else if case .int(let p) = params["penalty"] {
                    penalty = Double(p)
                } else {
                    penalty = -8.0
                }
            } else {
                vulgarTags = nil
                penalty = -8.0
            }

            return VulgarSlangPenaltyFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                vulgarTags: vulgarTags,
                penalty: penalty
            )
        }
    }
}
