import Foundation

// MARK: - JLPT Feature

/// Feature for JLPT level scoring
/// Rewards entries with JLPT certification (N5 > N4 > N3 > N2 > N1)
public struct JLPTFeature: ScoringFeature {
    public let name = "jlpt"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let levelScores: [String: Double]

    public init(
        weight: Double = 0.8,
        range: ClosedRange<Double> = 0...15,
        enabled: Bool = true,
        levelScores: [String: Double]? = nil
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled

        // Default JLPT level scores (scaled to range max)
        let defaultScores: [String: Double] = [
            "N5": 10.0,
            "N4": 7.0,
            "N3": 4.0,
            "N2": 2.0,
            "N1": 0.0
        ]

        self.levelScores = levelScores ?? defaultScores
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        guard let level = entry.jlptLevel else { return 0 }
        return levelScores[level] ?? 0
    }
}

// MARK: - Frequency Feature

/// Feature for word frequency scoring
/// Uses sigmoid smoothing to avoid step-function artifacts
public struct FrequencyFeature: ScoringFeature {
    public let name = "frequency"
    public let weight: Double
    public let range: ClosedRange<Double>
    public let enabled: Bool

    private let smoothing: SmoothingType
    private let midpoint: Double

    public enum SmoothingType: String, Codable, Sendable {
        case linear      // Simple linear interpolation
        case sigmoid     // Sigmoid (S-curve) smoothing (recommended)
        case logarithmic // Logarithmic decay
        case stepwise    // Traditional step function (legacy)
    }

    public init(
        weight: Double = 1.2,
        range: ClosedRange<Double> = 0...15,
        enabled: Bool = true,
        smoothing: SmoothingType = .sigmoid,
        midpoint: Double = 5.0
    ) {
        self.weight = weight
        self.range = range
        self.enabled = enabled
        self.smoothing = smoothing
        self.midpoint = midpoint
    }

    public func calculate(entry: DictionaryEntry, context: ScoringContext) -> Double {
        guard let rank = entry.frequencyRank else { return 0 }

        switch smoothing {
        case .linear:
            return calculateLinear(rank: rank)
        case .sigmoid:
            return calculateSigmoid(rank: rank)
        case .logarithmic:
            return calculateLogarithmic(rank: rank)
        case .stepwise:
            return calculateStepwise(rank: rank)
        }
    }

    // MARK: - Smoothing Functions

    /// Linear interpolation (simple but has discontinuities at bounds)
    private func calculateLinear(rank: Int) -> Double {
        let maxScore = range.upperBound
        let maxRank: Double = 5000.0  // Beyond this, score = 0

        if rank <= 1 {
            return maxScore
        }
        if rank >= Int(maxRank) {
            return 0
        }

        // Linear decay from maxScore to 0
        let ratio = Double(rank) / maxRank
        return maxScore * (1.0 - ratio)
    }

    /// Sigmoid (S-curve) smoothing - RECOMMENDED
    /// Provides smooth transitions without discontinuities
    private func calculateSigmoid(rank: Int) -> Double {
        let maxScore = range.upperBound

        // Transform rank to log scale for better distribution
        let x = log(Double(rank + 1))

        // Sigmoid function: maxScore / (1 + exp(x - midpoint))
        // midpoint controls where the curve inflects (typically 5.0)
        let score = maxScore / (1.0 + exp(x - midpoint))

        return score
    }

    /// Logarithmic decay (smooth but may be too slow)
    private func calculateLogarithmic(rank: Int) -> Double {
        let maxScore = range.upperBound

        if rank <= 1 {
            return maxScore
        }

        // Logarithmic decay: maxScore / log(rank + base)
        let base = 2.0
        let score = maxScore / log(Double(rank) + base)

        return min(score, maxScore)
    }

    /// Stepwise function (legacy, matches old behavior)
    private func calculateStepwise(rank: Int) -> Double {
        let maxScore = range.upperBound

        // Traditional step function
        if rank <= 10 {
            return maxScore * 0.8  // 12 points at max=15
        } else if rank <= 30 {
            return maxScore * 0.6  // 9 points at max=15
        } else if rank <= 50 {
            return maxScore * 0.47 // 7 points at max=15
        } else if rank <= 200 {
            return maxScore * 0.33 // 5 points at max=15
        } else if rank <= 1000 {
            return maxScore * 0.27 // 4 points at max=15
        } else if rank <= 5000 {
            return maxScore * 0.2  // 3 points at max=15
        } else {
            return 0
        }
    }
}

// MARK: - Feature Registration

extension FeatureRegistry {
    /// Register authority features
    func registerAuthorityFeatures() {
        registerFeature(type: "jlpt") { config in
            // Extract level scores from parameters if provided
            let levelScores: [String: Double]?
            if let params = config.parameters,
               case .object(let levelsDict) = params["levels"] {
                // Convert AnyCodable values to Double
                levelScores = levelsDict.compactMapValues { value in
                    if case .double(let d) = value { return d }
                    if case .int(let i) = value { return Double(i) }
                    return nil
                }
            } else {
                levelScores = nil
            }

            return JLPTFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                levelScores: levelScores
            )
        }

        registerFeature(type: "frequency") { config in
            // Extract smoothing parameters
            let smoothingType: FrequencyFeature.SmoothingType
            let midpoint: Double

            if let params = config.parameters {
                // Extract smoothing type
                if case .string(let smoothingStr) = params["smoothing"],
                   let parsed = FrequencyFeature.SmoothingType(rawValue: smoothingStr) {
                    smoothingType = parsed
                } else {
                    smoothingType = .sigmoid
                }

                // Extract midpoint
                if case .double(let mid) = params["midpoint"] {
                    midpoint = mid
                } else if case .int(let mid) = params["midpoint"] {
                    midpoint = Double(mid)
                } else {
                    midpoint = 5.0
                }
            } else {
                smoothingType = .sigmoid
                midpoint = 5.0
            }

            return FrequencyFeature(
                weight: config.weight,
                range: config.minScore...config.maxScore,
                enabled: config.enabled,
                smoothing: smoothingType,
                midpoint: midpoint
            )
        }
    }
}
