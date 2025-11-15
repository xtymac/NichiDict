import Foundation

// MARK: - Exact Match Feature

/// Feature for exact headword matches
/// Provides highest base score for perfect matches
public struct ExactMatchFeature: ScoringFeature {
    public let name = "exactMatch"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    public init(weight: Double = 1.0, range: ClosedRange<Double> = 0...100, enabled: Bool = true) {
        self.weight = weight
        self.range = range
        self.enabled = enabled
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        return context.isExactHeadword ? range.upperBound : 0
    }
}

// MARK: - Lemma Match Feature

/// Feature for lemma (reading) matches
/// Rewards entries where reading matches even if headword doesn't
public struct LemmaMatchFeature: ScoringFeature {
    public let name = "lemmaMatch"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    public init(weight: Double = 1.0, range: ClosedRange<Double> = 0...60, enabled: Bool = true) {
        self.weight = weight
        self.range = range
        self.enabled = enabled
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        // Only award if it's a lemma match but NOT an exact headword match
        return context.isLemmaMatch && !context.isExactHeadword ? range.upperBound : 0
    }
}

// MARK: - Prefix Match Feature

/// Feature for prefix matches
/// Rewards entries that start with the query
public struct PrefixMatchFeature: ScoringFeature {
    public let name = "prefixMatch"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    public init(weight: Double = 1.0, range: ClosedRange<Double> = 0...30, enabled: Bool = true) {
        self.weight = weight
        self.range = range
        self.enabled = enabled
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        switch context.matchType {
        case .prefix:
            // Prefix match, but not exact or lemma
            if !context.isExactHeadword && !context.isLemmaMatch {
                return range.upperBound
            }
            return 0
        default:
            return 0
        }
    }
}

// MARK: - Contains Match Feature

/// Feature for contains matches
/// Provides minimal base score for entries containing the query anywhere
public struct ContainsMatchFeature: ScoringFeature {
    public let name = "containsMatch"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    public init(weight: Double = 1.0, range: ClosedRange<Double> = 0...10, enabled: Bool = true) {
        self.weight = weight
        self.range = range
        self.enabled = enabled
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        switch context.matchType {
        case .contains:
            // Contains match, but not prefix/exact/lemma
            if !context.isExactHeadword && !context.isLemmaMatch {
                return range.upperBound
            }
            return 0
        default:
            return 0
        }
    }
}

// MARK: - Feature Registration

extension FeatureRegistry {
    /// Register match type features
    func registerMatchTypeFeatures() {
        registerFeature(type: "exactMatch") { config in
            ExactMatchFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled
            )
        }

        registerFeature(type: "lemmaMatch") { config in
            LemmaMatchFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled
            )
        }

        registerFeature(type: "prefixMatch") { config in
            PrefixMatchFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled
            )
        }

        registerFeature(type: "containsMatch") { config in
            ContainsMatchFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled
            )
        }
    }
}
