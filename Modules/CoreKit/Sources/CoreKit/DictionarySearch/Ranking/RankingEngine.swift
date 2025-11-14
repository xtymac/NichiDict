import Foundation

/// Core ranking engine that orchestrates feature scoring and bucket assignment
public final class RankingEngine: @unchecked Sendable {
    /// Configuration for this engine
    public let config: RankingConfiguration

    /// Scoring features (enabled only)
    private let features: [any ScoringFeature]

    /// Hard rule evaluator for bucket assignment
    private let ruleEvaluator: HardRuleEvaluator

    /// Feature registry for construction
    private let registry: FeatureRegistry

    public init(config: RankingConfiguration, registry: FeatureRegistry = .shared) throws {
        self.config = config
        self.registry = registry

        // Validate configuration
        try config.validate()

        // Build features from configuration
        self.features = try registry.buildFeatures(config.features.filter { $0.enabled })

        // Build hard rules and create evaluator
        let rules = try registry.buildRules(config.hardRules.filter { $0.enabled })
        self.ruleEvaluator = HardRuleEvaluator(rules: rules)

        // Validate all features
        for feature in features {
            try feature.validate()
        }
    }

    // MARK: - Scoring

    /// Calculate relevance score and bucket for an entry
    /// - Parameters:
    ///   - entry: Dictionary entry to score
    ///   - context: Scoring context with query and match information
    /// - Returns: Tuple of (relevanceScore, bucket, scoreBreakdown)
    public func calculate(
        entry: DictionaryEntry,
        context: ScoringContext
    ) -> (score: Double, bucket: SearchResult.ResultBucket, breakdown: ScoreBreakdown) {
        // Step 1: Determine bucket via hard rules
        let bucketAssignment = ruleEvaluator.evaluate(entry: entry, context: context)

        // Step 2: Calculate feature scores
        var totalScore: Double = 0
        var featureScores: [String: Double] = [:]

        for feature in features {
            let rawScore = feature.calculate(entry: entry, context: context)
            let finalScore = feature.finalScore(rawScore)
            totalScore += finalScore
            featureScores[feature.name] = finalScore
        }

        // Step 3: Create score breakdown for debugging
        let breakdown = ScoreBreakdown(
            totalScore: totalScore,
            bucket: bucketAssignment.bucket,
            bucketRule: bucketAssignment.ruleName,
            featureScores: featureScores
        )

        return (totalScore, bucketAssignment.bucket, breakdown)
    }

    // MARK: - Ranking

    /// Rank a list of entries using the configured scoring and tie-breakers
    /// - Parameters:
    ///   - entries: Entries to rank
    ///   - query: Search query
    ///   - context: Scoring context
    /// - Returns: Sorted array of RankedEntry
    public func rank(
        entries: [(entry: DictionaryEntry, context: ScoringContext)]
    ) -> [RankedEntry] {
        // Calculate scores for all entries
        let rankedEntries = entries.map { (entry, context) -> RankedEntry in
            let (score, bucket, breakdown) = calculate(entry: entry, context: context)
            return RankedEntry(
                entry: entry,
                score: score,
                bucket: bucket,
                breakdown: breakdown,
                context: context
            )
        }

        // Sort by bucket first, then by score, then by tie-breakers
        return rankedEntries.sorted { lhs, rhs in
            // Primary: Bucket (A → B → C → D)
            if lhs.bucket != rhs.bucket {
                return lhs.bucket < rhs.bucket
            }

            // Secondary: Relevance score (descending)
            if abs(lhs.score - rhs.score) > 0.001 {  // Floating point tolerance
                return lhs.score > rhs.score
            }

            // Tertiary: Tie-breakers
            return applyTieBreakers(lhs: lhs.entry, rhs: rhs.entry)
        }
    }

    // MARK: - Tie Breakers

    /// Apply tie-breaker rules in order
    private func applyTieBreakers(lhs: DictionaryEntry, rhs: DictionaryEntry) -> Bool {
        for tieBreaker in config.tieBreakers {
            switch tieBreaker.field {
            case "frequencyRank":
                let lhsRank = lhs.frequencyRank ?? Int.max
                let rhsRank = rhs.frequencyRank ?? Int.max
                if lhsRank != rhsRank {
                    return tieBreaker.isAscending ? lhsRank < rhsRank : lhsRank > rhsRank
                }

            case "jlptBonus":
                let lhsBonus = jlptToNumeric(lhs.jlptLevel)
                let rhsBonus = jlptToNumeric(rhs.jlptLevel)
                if lhsBonus != rhsBonus {
                    return tieBreaker.isAscending ? lhsBonus < rhsBonus : lhsBonus > rhsBonus
                }

            case "surfaceLength":
                let lhsLen = lhs.headword.count
                let rhsLen = rhs.headword.count
                if lhsLen != rhsLen {
                    return tieBreaker.isAscending ? lhsLen < rhsLen : lhsLen > rhsLen
                }

            case "createdAt":
                if lhs.createdAt != rhs.createdAt {
                    return tieBreaker.isAscending ? lhs.createdAt < rhs.createdAt : lhs.createdAt > rhs.createdAt
                }

            case "id":
                if lhs.id != rhs.id {
                    return tieBreaker.isAscending ? lhs.id < rhs.id : lhs.id > rhs.id
                }

            default:
                continue
            }
        }

        // Final fallback: ID ascending
        return lhs.id < rhs.id
    }

    /// Convert JLPT level to numeric for sorting (N5=5, N4=4, ..., none=0)
    private func jlptToNumeric(_ level: String?) -> Int {
        guard let level = level else { return 0 }
        switch level {
        case "N5": return 5
        case "N4": return 4
        case "N3": return 3
        case "N2": return 2
        case "N1": return 1
        default: return 0
        }
    }
}

// MARK: - Ranked Entry

/// Entry with scoring information
public struct RankedEntry: Sendable {
    public let entry: DictionaryEntry
    public let score: Double
    public let bucket: SearchResult.ResultBucket
    public let breakdown: ScoreBreakdown
    public let context: ScoringContext

    public init(
        entry: DictionaryEntry,
        score: Double,
        bucket: SearchResult.ResultBucket,
        breakdown: ScoreBreakdown,
        context: ScoringContext
    ) {
        self.entry = entry
        self.score = score
        self.bucket = bucket
        self.breakdown = breakdown
        self.context = context
    }
}

// MARK: - Score Breakdown

/// Detailed breakdown of scoring for debugging
public struct ScoreBreakdown: Sendable {
    /// Total final score
    public let totalScore: Double

    /// Assigned bucket
    public let bucket: SearchResult.ResultBucket

    /// Name of the hard rule that assigned this bucket
    public let bucketRule: String

    /// Individual feature contributions
    public let featureScores: [String: Double]

    public init(
        totalScore: Double,
        bucket: SearchResult.ResultBucket,
        bucketRule: String,
        featureScores: [String: Double]
    ) {
        self.totalScore = totalScore
        self.bucket = bucket
        self.bucketRule = bucketRule
        self.featureScores = featureScores
    }

    /// Format as readable string for debugging
    public func formatted(headword: String) -> String {
        var lines: [String] = []
        lines.append("📊 Breakdown for '\(headword)':")
        lines.append("   Total: \(String(format: "%.2f", totalScore))")
        lines.append("   Bucket: \(bucket) (\(bucketRule))")
        lines.append("   Features:")

        let sortedFeatures = featureScores.sorted { $0.value > $1.value }
        for (feature, score) in sortedFeatures {
            lines.append("      \(feature): \(String(format: "%.2f", score))")
        }

        return lines.joined(separator: "\n")
    }
}
