import Foundation

/// Top-level configuration for the ranking engine
public struct RankingConfiguration: Codable, Sendable {
    /// Configuration version
    public let version: String

    /// Profile name for A/B testing ("default", "exp1", etc.)
    public let profile: String

    /// Whether to use legacy scorer (fallback option)
    public let useLegacyScorer: Bool

    /// List of scoring features
    public let features: [FeatureConfig]

    /// List of hard rules for bucket assignment
    public let hardRules: [HardRuleConfig]

    /// Tie-breaker fields for stable sorting
    public let tieBreakers: [TieBreakerConfig]

    public init(
        version: String = "1.0",
        profile: String = "default",
        useLegacyScorer: Bool = false,
        features: [FeatureConfig],
        hardRules: [HardRuleConfig],
        tieBreakers: [TieBreakerConfig]
    ) {
        self.version = version
        self.profile = profile
        self.useLegacyScorer = useLegacyScorer
        self.features = features
        self.hardRules = hardRules
        self.tieBreakers = tieBreakers
    }
}

/// Configuration for a single scoring feature
public struct FeatureConfig: Codable, Sendable {
    /// Feature type identifier (e.g., "exactMatch", "jlpt", "frequency")
    public let type: String

    /// Weight multiplier (0.5 - 2.0 typically)
    public let weight: Double

    /// Minimum score this feature can produce
    public let minScore: Double

    /// Maximum score this feature can produce
    public let maxScore: Double

    /// Whether this feature is enabled
    public let enabled: Bool

    /// Feature-specific parameters (decoded by FeatureRegistry)
    public let parameters: [String: AnyCodable]?

    public init(
        type: String,
        weight: Double,
        minScore: Double,
        maxScore: Double,
        enabled: Bool = true,
        parameters: [String: AnyCodable]? = nil
    ) {
        self.type = type
        self.weight = weight
        self.minScore = minScore
        self.maxScore = maxScore
        self.enabled = enabled
        self.parameters = parameters
    }
}

/// Configuration for a hard rule
public struct HardRuleConfig: Codable, Sendable {
    /// Rule type identifier (e.g., "exactMatchBucket", "expressionBucket")
    public let type: String

    /// Priority order (lower = higher priority)
    public let priority: Int

    /// Whether this rule is enabled
    public let enabled: Bool

    /// Rule-specific parameters
    public let parameters: [String: AnyCodable]?

    public init(
        type: String,
        priority: Int,
        enabled: Bool = true,
        parameters: [String: AnyCodable]? = nil
    ) {
        self.type = type
        self.priority = priority
        self.enabled = enabled
        self.parameters = parameters
    }
}

/// Configuration for tie-breaker sorting
public struct TieBreakerConfig: Codable, Sendable {
    /// Field name to sort by
    public let field: String

    /// Sort order ("ascending" or "descending")
    public let order: String

    public init(field: String, order: String) {
        self.field = field
        self.order = order
    }

    public var isAscending: Bool {
        order.lowercased() == "ascending"
    }
}

/// Type-erased wrapper for arbitrary Codable values, limited to JSON-compatible, Sendable types.
public enum AnyCodable: Sendable, Codable, Equatable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)
    case array([AnyCodable])
    case object([String: AnyCodable])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
        if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
            return
        }
        if let object = try? container.decode([String: AnyCodable].self) {
            self = .object(object)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported type in AnyCodable"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .bool(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        case .object(let v):
            try container.encode(v)
        }
    }
}

/// Configuration validation
public extension RankingConfiguration {
    func validate() throws {
        // Validate features
        for feature in features {
            if feature.minScore > feature.maxScore {
                throw FeatureValidationError.invalidRange(
                    feature: feature.type,
                    min: feature.minScore,
                    max: feature.maxScore
                )
            }
            if feature.weight < 0 || feature.weight > 10 {
                throw FeatureValidationError.invalidWeight(
                    feature: feature.type,
                    weight: feature.weight
                )
            }
        }

        // Validate hard rules have unique priorities
        let priorities = hardRules.filter { $0.enabled }.map { $0.priority }
        let uniquePriorities = Set(priorities)
        if priorities.count != uniquePriorities.count {
            throw ConfigValidationError.duplicatePriorities
        }

        // Validate tie-breakers
        let validFields = ["frequencyRank", "jlptBonus", "surfaceLength", "createdAt", "id"]
        for tieBreaker in tieBreakers {
            if !validFields.contains(tieBreaker.field) {
                throw ConfigValidationError.invalidTieBreakerField(tieBreaker.field)
            }
            if tieBreaker.order != "ascending" && tieBreaker.order != "descending" {
                throw ConfigValidationError.invalidTieBreakerOrder(tieBreaker.order)
            }
        }
    }
}

/// Configuration-level validation errors
public enum ConfigValidationError: Error, CustomStringConvertible {
    case duplicatePriorities
    case invalidTieBreakerField(String)
    case invalidTieBreakerOrder(String)
    case invalidProfile(String)

    public var description: String {
        switch self {
        case .duplicatePriorities:
            return "Hard rules have duplicate priorities"
        case .invalidTieBreakerField(let field):
            return "Invalid tie-breaker field: \(field)"
        case .invalidTieBreakerOrder(let order):
            return "Invalid tie-breaker order: \(order) (must be 'ascending' or 'descending')"
        case .invalidProfile(let profile):
            return "Invalid profile: \(profile)"
        }
    }
}
