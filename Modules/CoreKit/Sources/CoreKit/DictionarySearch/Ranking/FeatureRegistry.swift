import Foundation

/// Type-safe registry for feature and hard rule construction
/// Decodes feature-specific parameters from AnyCodable to concrete types
public final class FeatureRegistry: @unchecked Sendable {
    public static let shared = FeatureRegistry()

    private var featureBuilders: [String: @Sendable (FeatureConfig) throws -> any ScoringFeature] = [:]
    private var ruleBuilders: [String: @Sendable (HardRuleConfig) throws -> any HardRule] = [:]

    private init() {
        registerDefaultFeatures()
        registerDefaultRules()
    }

    // MARK: - Registration

    /// Register a feature builder
    public func registerFeature(
        type: String,
        builder: @escaping @Sendable (FeatureConfig) throws -> any ScoringFeature
    ) {
        featureBuilders[type] = builder
    }

    /// Register a hard rule builder
    public func registerRule(
        type: String,
        builder: @escaping @Sendable (HardRuleConfig) throws -> any HardRule
    ) {
        ruleBuilders[type] = builder
    }

    // MARK: - Construction

    /// Build a feature from configuration
    public func buildFeature(_ config: FeatureConfig) throws -> any ScoringFeature {
        guard let builder = featureBuilders[config.type] else {
            throw RegistryError.unknownFeatureType(config.type)
        }
        return try builder(config)
    }

    /// Build a hard rule from configuration
    public func buildRule(_ config: HardRuleConfig) throws -> any HardRule {
        guard let builder = ruleBuilders[config.type] else {
            throw RegistryError.unknownRuleType(config.type)
        }
        return try builder(config)
    }

    /// Build all features from configurations
    public func buildFeatures(_ configs: [FeatureConfig]) throws -> [any ScoringFeature] {
        try configs.map { try buildFeature($0) }
    }

    /// Build all hard rules from configurations
    public func buildRules(_ configs: [HardRuleConfig]) throws -> [any HardRule] {
        try configs.map { try buildRule($0) }
    }

    // MARK: - Parameter Decoding

    /// Decode typed parameters from AnyCodable dictionary
    public func decodeParameters<T: Codable>(
        _ type: T.Type,
        from parameters: [String: AnyCodable]?
    ) throws -> T {
        guard let parameters = parameters else {
            throw RegistryError.missingParameters
        }

        // Encode the AnyCodable dictionary directly and decode into the target type
        let data = try JSONEncoder().encode(EncodableDictionary(parameters))
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Decode a single typed parameter
    public func decodeParameter<T: Codable>(
        _ type: T.Type,
        key: String,
        from parameters: [String: AnyCodable]?
    ) throws -> T {
        guard let parameters = parameters else {
            throw RegistryError.missingParameter(key)
        }
        guard let anyCodable = parameters[key] else {
            throw RegistryError.missingParameter(key)
        }

        // Encode the single AnyCodable and decode it into the target type
        let data = try JSONEncoder().encode(anyCodable)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Default Registration

    private func registerDefaultFeatures() {
        registerMatchTypeFeatures()
        registerAuthorityFeatures()
        registerPOSFeatures()
        registerPenaltyFeatures()
    }

    private func registerDefaultRules() {
        registerBucketRules()
    }
}

/// A lightweight wrapper to encode a [String: AnyCodable] with JSONEncoder
/// because JSONEncoder cannot directly encode a dictionary with non-concrete key/value types
private struct EncodableDictionary: Encodable {
    let storage: [String: AnyCodable]

    init(_ storage: [String: AnyCodable]) {
        self.storage = storage
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        for (key, value) in storage {
            try container.encode(value, forKey: DynamicCodingKeys(stringValue: key))
        }
    }

    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// Registry errors
public enum RegistryError: Error, CustomStringConvertible {
    case unknownFeatureType(String)
    case unknownRuleType(String)
    case missingParameters
    case missingParameter(String)
    case invalidParameterType(String, expected: String, got: String)

    public var description: String {
        switch self {
        case .unknownFeatureType(let type):
            return "Unknown feature type: \(type)"
        case .unknownRuleType(let type):
            return "Unknown rule type: \(type)"
        case .missingParameters:
            return "Missing required parameters"
        case .missingParameter(let key):
            return "Missing required parameter: \(key)"
        case .invalidParameterType(let key, let expected, let got):
            return "Invalid parameter type for '\(key)': expected \(expected), got \(got)"
        }
    }
}
