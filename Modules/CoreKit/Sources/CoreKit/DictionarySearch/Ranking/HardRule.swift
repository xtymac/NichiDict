import Foundation

/// Protocol for hard rules that determine bucket assignment
/// Hard rules execute before feature scoring and cannot be overridden by scores
public protocol HardRule: Sendable {
    /// Priority order (lower = higher priority, executes first)
    /// - 0: Bucket A (Exact match/Lemma)
    /// - 1: Bucket B (Common prefix/Expression)
    /// - 2: Bucket D (Specialized terms)
    /// - 3: Bucket C (Default)
    var priority: Int { get }

    /// Unique name for this rule
    var name: String { get }

    /// Target bucket if rule matches
    var targetBucket: SearchResult.ResultBucket { get }

    /// Whether this rule is enabled
    var enabled: Bool { get }

    /// Check if this entry matches the rule
    /// - Parameters:
    ///   - entry: The dictionary entry to check
    ///   - context: Scoring context with query and match information
    /// - Returns: true if this entry matches the rule
    func matches(entry: DictionaryEntry, context: ScoringContext) -> Bool
}

/// Concrete bucket assignment result
public struct BucketAssignment: Sendable {
    public let bucket: SearchResult.ResultBucket
    public let ruleName: String
    public let priority: Int

    public init(bucket: SearchResult.ResultBucket, ruleName: String, priority: Int) {
        self.bucket = bucket
        self.ruleName = ruleName
        self.priority = priority
    }
}

/// Hard rule evaluation engine
public struct HardRuleEvaluator: Sendable {
    private let rules: [HardRule]

    public init(rules: [HardRule]) {
        // Sort rules by priority (lower = higher priority)
        self.rules = rules.filter { $0.enabled }.sorted { $0.priority < $1.priority }
    }

    /// Evaluate all rules and return the first match
    /// - Parameters:
    ///   - entry: The dictionary entry to evaluate
    ///   - context: Scoring context
    /// - Returns: Bucket assignment from the first matching rule (or default Bucket C)
    public func evaluate(entry: DictionaryEntry, context: ScoringContext) -> BucketAssignment {
        for rule in rules {
            if rule.matches(entry: entry, context: context) {
                return BucketAssignment(
                    bucket: rule.targetBucket,
                    ruleName: rule.name,
                    priority: rule.priority
                )
            }
        }

        // Default to Bucket C (generalMatch) if no rule matches
        return BucketAssignment(
            bucket: .generalMatch,
            ruleName: "default",
            priority: 999
        )
    }
}
