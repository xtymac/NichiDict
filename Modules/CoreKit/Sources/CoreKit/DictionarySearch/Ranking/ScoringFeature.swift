import Foundation

/// Protocol for scoring features in the ranking engine
/// Each feature contributes a score within its defined range
public protocol ScoringFeature: Sendable {
    /// Unique name for this feature (e.g., "exactMatch", "jlpt", "frequency")
    var name: String { get }

    /// Weight multiplier for this feature's score (typically 0.5 - 2.0)
    var weight: Double { get }

    /// Allowed score range (enforces min/max limits)
    var range: ClosedRange<Double> { get }

    /// Whether this feature is enabled
    var enabled: Bool { get }

    /// Calculate the score for a given entry and query
    /// - Parameters:
    ///   - entry: The dictionary entry to score
    ///   - context: Scoring context with query and match information
    /// - Returns: Raw score (will be clamped to range and multiplied by weight)
    func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double

    /// Validate feature configuration
    /// - Throws: ValidationError if configuration is invalid
    func validate() throws
}

/// Validation errors for feature configuration
public enum FeatureValidationError: Error, CustomStringConvertible {
    case invalidRange(feature: String, min: Double, max: Double)
    case invalidWeight(feature: String, weight: Double)
    case missingRequiredParameter(feature: String, parameter: String)
    case invalidParameter(feature: String, parameter: String, reason: String)

    public var description: String {
        switch self {
        case .invalidRange(let feature, let min, let max):
            return "\(feature): Invalid range (\(min), \(max)) - min must be <= max"
        case .invalidWeight(let feature, let weight):
            return "\(feature): Invalid weight \(weight) - must be in range 0...10"
        case .missingRequiredParameter(let feature, let param):
            return "\(feature): Missing required parameter '\(param)'"
        case .invalidParameter(let feature, let param, let reason):
            return "\(feature): Invalid parameter '\(param)' - \(reason)"
        }
    }
}

/// Base implementation for common feature operations
public extension ScoringFeature {
    /// Apply range clamping and weight to raw score
    func finalScore(_ rawScore: Double) -> Double {
        let clamped = min(max(rawScore, range.lowerBound), range.upperBound)
        return clamped * weight
    }

    /// Default validation checks range and weight
    func validate() throws {
        if range.lowerBound > range.upperBound {
            throw FeatureValidationError.invalidRange(
                feature: name,
                min: range.lowerBound,
                max: range.upperBound
            )
        }
        if weight < 0 || weight > 10 {
            throw FeatureValidationError.invalidWeight(feature: name, weight: weight)
        }
    }
}
