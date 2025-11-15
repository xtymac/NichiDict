import Foundation

// MARK: - Exact Match Bucket Rule

/// Rule for assigning exact matches to Bucket A
/// Highest priority bucket for perfect headword matches
public struct ExactMatchBucketRule: HardRule {
    public let name = "exactMatchBucket"
    public let priority: Int
    public let targetBucket: SearchResult.ResultBucket = .exactMatch
    public let enabled: Bool

    public init(priority: Int = 1, enabled: Bool = true) {
        self.priority = priority
        self.enabled = enabled
    }

    public func matches(entry: DictionaryEntry, context: ScoringContext) -> Bool {
        return context.isExactHeadword
    }
}

// MARK: - Lemma Match Bucket Rule

/// Rule for assigning lemma matches to Bucket A
/// Same priority as exact matches since both are precise matches
public struct LemmaMatchBucketRule: HardRule {
    public let name = "lemmaMatchBucket"
    public let priority: Int
    public let targetBucket: SearchResult.ResultBucket = .exactMatch
    public let enabled: Bool

    public init(priority: Int = 2, enabled: Bool = true) {
        self.priority = priority
        self.enabled = enabled
    }

    public func matches(entry: DictionaryEntry, context: ScoringContext) -> Bool {
        return context.isLemmaMatch && !context.isExactHeadword
    }
}

// MARK: - Expression Bucket Rule

/// Rule for assigning expression entries to Bucket B
/// CRITICAL FIX: Prevents common expressions like "また明日" from being
/// suppressed by rare compounds like "今明日/大明日"
public struct ExpressionBucketRule: HardRule {
    public let name = "expressionBucket"
    public let priority: Int
    public let targetBucket: SearchResult.ResultBucket = .commonPrefixMatch
    public let enabled: Bool

    private let expressionTags: Set<String>

    public init(
        priority: Int = 3,
        enabled: Bool = true,
        expressionTags: Set<String>? = nil
    ) {
        self.priority = priority
        self.enabled = enabled

        // Default expression tags
        let defaultTags: Set<String> = [
            "expression",
            "expressions",
            "phrase",
            "idiom",
            "saying",
            "proverb",
            "成句",
            "慣用句",
            "熟語"
        ]

        self.expressionTags = expressionTags ?? defaultTags
    }

    public func matches(entry: DictionaryEntry, context: ScoringContext) -> Bool {
        // Don't override exact/lemma matches
        if context.isExactHeadword || context.isLemmaMatch {
            return false
        }

        // Check if entry contains expression markers in headword
        let headword = entry.headword
        if headword.contains(" ") || headword.contains("・") {
            return true
        }

        // Check senses' usageNotes for expression markers
        for sense in entry.senses {
            if let notes = sense.usageNotes?.lowercased() {
                for tag in expressionTags {
                    if notes.contains(tag.lowercased()) {
                        return true
                    }
                }
            }

            // Check partOfSpeech for expression markers
            let pos = sense.partOfSpeech.lowercased()
            for tag in expressionTags {
                if pos.contains(tag.lowercased()) {
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Common Prefix Bucket Rule

/// Rule for assigning common prefix matches to Bucket B
/// Rewards entries that start with the query and are commonly used
public struct CommonPrefixBucketRule: HardRule {
    public let name = "commonPrefixBucket"
    public let priority: Int
    public let targetBucket: SearchResult.ResultBucket = .commonPrefixMatch
    public let enabled: Bool

    private let frequencyThreshold: Int

    public init(
        priority: Int = 4,
        enabled: Bool = true,
        frequencyThreshold: Int = 2000
    ) {
        self.priority = priority
        self.enabled = enabled
        self.frequencyThreshold = frequencyThreshold
    }

    public func matches(entry: DictionaryEntry, context: ScoringContext) -> Bool {
        // Don't override exact/lemma matches
        if context.isExactHeadword || context.isLemmaMatch {
            return false
        }

        // Must be a prefix match
        guard context.matchType == .prefix else {
            return false
        }

        // Must be a common word (within frequency threshold)
        if let rank = entry.frequencyRank, rank <= frequencyThreshold {
            return true
        }

        return false
    }
}

// MARK: - JLPT Bucket Rule

/// Rule for promoting JLPT entries to Bucket B
/// Ensures certified learning vocabulary gets higher priority
public struct JLPTBucketRule: HardRule {
    public let name = "jlptBucket"
    public let priority: Int
    public let targetBucket: SearchResult.ResultBucket = .commonPrefixMatch
    public let enabled: Bool

    private let eligibleLevels: Set<String>

    public init(
        priority: Int = 5,
        enabled: Bool = true,
        eligibleLevels: Set<String>? = nil
    ) {
        self.priority = priority
        self.enabled = enabled

        // Default: N5 and N4 (most common levels)
        let defaultLevels: Set<String> = ["N5", "N4"]
        self.eligibleLevels = eligibleLevels ?? defaultLevels
    }

    public func matches(entry: DictionaryEntry, context: ScoringContext) -> Bool {
        // Don't override exact/lemma matches
        if context.isExactHeadword || context.isLemmaMatch {
            return false
        }

        // Check if entry has eligible JLPT level
        if let level = entry.jlptLevel, eligibleLevels.contains(level) {
            return true
        }

        return false
    }
}

// MARK: - Specialized Domain Bucket Rule

/// Rule for demoting highly specialized terms to Bucket D
/// Ensures technical jargon doesn't clutter general search results
public struct SpecializedDomainBucketRule: HardRule {
    public let name = "specializedDomainBucket"
    public let priority: Int
    public let targetBucket: SearchResult.ResultBucket = .specializedTerm
    public let enabled: Bool

    private let domainTags: Set<String>

    public init(
        priority: Int = 10,  // Lower priority = evaluated later
        enabled: Bool = true,
        domainTags: Set<String>? = nil
    ) {
        self.priority = priority
        self.enabled = enabled

        // Default specialized domain tags (same as penalty feature)
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
    }

    public func matches(entry: DictionaryEntry, context: ScoringContext) -> Bool {
        // Check senses' usageNotes and partOfSpeech for domain markers
        for sense in entry.senses {
            if let notes = sense.usageNotes?.lowercased() {
                for tag in domainTags {
                    if notes.contains(tag.lowercased()) {
                        return true
                    }
                }
            }

            // Check partOfSpeech
            let pos = sense.partOfSpeech.lowercased()
            for tag in domainTags {
                if pos.contains(tag.lowercased()) {
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Archaic Word Bucket Rule

/// Rule for demoting archaic words to Bucket D
/// Ensures obsolete vocabulary doesn't clutter modern search results
public struct ArchaicWordBucketRule: HardRule {
    public let name = "archaicWordBucket"
    public let priority: Int
    public let targetBucket: SearchResult.ResultBucket = .specializedTerm
    public let enabled: Bool

    private let archaicTags: Set<String>

    public init(
        priority: Int = 11,
        enabled: Bool = true,
        archaicTags: Set<String>? = nil
    ) {
        self.priority = priority
        self.enabled = enabled

        // Default archaic tags (same as penalty feature)
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
    }

    public func matches(entry: DictionaryEntry, context: ScoringContext) -> Bool {
        // Check senses' usageNotes and partOfSpeech for archaic markers
        for sense in entry.senses {
            if let notes = sense.usageNotes?.lowercased() {
                for tag in archaicTags {
                    if notes.contains(tag.lowercased()) {
                        return true
                    }
                }
            }

            // Check partOfSpeech
            let pos = sense.partOfSpeech.lowercased()
            for tag in archaicTags {
                if pos.contains(tag.lowercased()) {
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Feature Registration

extension FeatureRegistry {
    /// Register hard rules for bucket assignment
    func registerBucketRules() {
        registerRule(type: "exactMatchBucket") { config in
            ExactMatchBucketRule(
                priority: config.priority,
                enabled: config.enabled
            )
        }

        registerRule(type: "lemmaMatchBucket") { config in
            LemmaMatchBucketRule(
                priority: config.priority,
                enabled: config.enabled
            )
        }

        registerRule(type: "expressionBucket") { config in
            let expressionTags: Set<String>?
            if let params = config.parameters,
               case .array(let tagsArray) = params["expressionTags"] {
                expressionTags = Set(tagsArray.compactMap { value in
                    if case .string(let s) = value { return s }
                    return nil
                })
            } else {
                expressionTags = nil
            }

            return ExpressionBucketRule(
                priority: config.priority,
                enabled: config.enabled,
                expressionTags: expressionTags
            )
        }

        registerRule(type: "commonPrefixBucket") { config in
            let frequencyThreshold: Int
            if let params = config.parameters,
               case .int(let threshold) = params["frequencyThreshold"] {
                frequencyThreshold = threshold
            } else {
                frequencyThreshold = 2000
            }

            return CommonPrefixBucketRule(
                priority: config.priority,
                enabled: config.enabled,
                frequencyThreshold: frequencyThreshold
            )
        }

        registerRule(type: "jlptBucket") { config in
            let eligibleLevels: Set<String>?
            if let params = config.parameters,
               case .array(let levelsArray) = params["eligibleLevels"] {
                eligibleLevels = Set(levelsArray.compactMap { value in
                    if case .string(let s) = value { return s }
                    return nil
                })
            } else {
                eligibleLevels = nil
            }

            return JLPTBucketRule(
                priority: config.priority,
                enabled: config.enabled,
                eligibleLevels: eligibleLevels
            )
        }

        registerRule(type: "specializedDomainBucket") { config in
            let domainTags: Set<String>?
            if let params = config.parameters,
               case .array(let tagsArray) = params["domainTags"] {
                domainTags = Set(tagsArray.compactMap { value in
                    if case .string(let s) = value { return s }
                    return nil
                })
            } else {
                domainTags = nil
            }

            return SpecializedDomainBucketRule(
                priority: config.priority,
                enabled: config.enabled,
                domainTags: domainTags
            )
        }

        registerRule(type: "archaicWordBucket") { config in
            let archaicTags: Set<String>?
            if let params = config.parameters,
               case .array(let tagsArray) = params["archaicTags"] {
                archaicTags = Set(tagsArray.compactMap { value in
                    if case .string(let s) = value { return s }
                    return nil
                })
            } else {
                archaicTags = nil
            }

            return ArchaicWordBucketRule(
                priority: config.priority,
                enabled: config.enabled,
                archaicTags: archaicTags
            )
        }
    }
}
