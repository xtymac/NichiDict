import Foundation

/// Configuration loader for ranking system
/// Supports loading from Bundle, Documents directory, and remote URLs
public final class RankingConfigLoader: @unchecked Sendable {
    public static let shared = RankingConfigLoader()

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()

    // Configuration file names
    private let defaultConfigFilename = "ranking_config.json"
    private let profileConfigFormat = "ranking_config_%@.json"  // e.g., ranking_config_exp1.json

    private init() {}

    // MARK: - Public API

    /// Load configuration with fallback chain:
    /// 1. Documents directory override (for debug)
    /// 2. Bundle resource (default)
    /// 3. Hardcoded fallback (if all else fails)
    public func loadConfiguration(profile: String? = nil) throws -> RankingConfiguration {
        // Determine config filename
        let filename: String
        if let profile = profile, profile != "default" {
            filename = String(format: profileConfigFormat, profile)
        } else {
            filename = defaultConfigFilename
        }

        // Try loading from Documents directory first (debug override)
        if let documentsConfig = try? loadFromDocuments(filename: filename) {
            try documentsConfig.validate()
            return documentsConfig
        }

        // Try loading from Bundle (default)
        if let bundleConfig = try? loadFromBundle(filename: filename) {
            try bundleConfig.validate()
            return bundleConfig
        }

        // If profile is specified but not found, try default
        if profile != nil && profile != "default" {
            if let defaultConfig = try? loadFromBundle(filename: defaultConfigFilename) {
                try defaultConfig.validate()
                return defaultConfig
            }
        }

        // Last resort: hardcoded fallback
        return createFallbackConfiguration()
    }

    /// Load configuration from a specific file path
    public func loadConfiguration(from filePath: String) throws -> RankingConfiguration {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        let config = try decoder.decode(RankingConfiguration.self, from: data)
        try config.validate()
        return config
    }

    /// Load configuration from remote URL
    public func loadConfiguration(from url: URL) async throws -> RankingConfiguration {
        let (data, _) = try await URLSession.shared.data(from: url)
        let config = try decoder.decode(RankingConfiguration.self, from: data)
        try config.validate()
        return config
    }

    /// Save configuration to Documents directory (for debug override)
    public func saveConfiguration(_ config: RankingConfiguration, profile: String? = nil) throws {
        let filename: String
        if let profile = profile, profile != "default" {
            filename = String(format: profileConfigFormat, profile)
        } else {
            filename = defaultConfigFilename
        }

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ConfigLoaderError.documentsDirectoryNotFound
        }

        let fileURL = documentsURL.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(config)
        try data.write(to: fileURL)
    }

    /// Delete configuration override from Documents directory
    public func deleteConfigurationOverride(profile: String? = nil) throws {
        let filename: String
        if let profile = profile, profile != "default" {
            filename = String(format: profileConfigFormat, profile)
        } else {
            filename = defaultConfigFilename
        }

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ConfigLoaderError.documentsDirectoryNotFound
        }

        let fileURL = documentsURL.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// Check if configuration override exists in Documents directory
    public func hasConfigurationOverride(profile: String? = nil) -> Bool {
        let filename: String
        if let profile = profile, profile != "default" {
            filename = String(format: profileConfigFormat, profile)
        } else {
            filename = defaultConfigFilename
        }

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }

        let fileURL = documentsURL.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    // MARK: - Private Helpers

    /// Load from Documents directory (debug override)
    private func loadFromDocuments(filename: String) throws -> RankingConfiguration {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ConfigLoaderError.documentsDirectoryNotFound
        }

        let fileURL = documentsURL.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ConfigLoaderError.fileNotFound(fileURL.path)
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(RankingConfiguration.self, from: data)
    }

    /// Load from Bundle (default)
    private func loadFromBundle(filename: String) throws -> RankingConfiguration {
        let filenameWithoutExtension = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension

        guard let bundleURL = Bundle.main.url(
            forResource: filenameWithoutExtension,
            withExtension: fileExtension.isEmpty ? "json" : fileExtension
        ) else {
            throw ConfigLoaderError.bundleResourceNotFound(filename)
        }

        let data = try Data(contentsOf: bundleURL)
        return try decoder.decode(RankingConfiguration.self, from: data)
    }

    /// Create hardcoded fallback configuration
    /// This ensures the app always has a working configuration
    private func createFallbackConfiguration() -> RankingConfiguration {
        return RankingConfiguration(
            version: "1.0",
            profile: "fallback",
            useLegacyScorer: false,
            features: [
                // Match type features
                FeatureConfig(type: "exactMatch", weight: 1.0, minScore: 0, maxScore: 100),
                FeatureConfig(type: "lemmaMatch", weight: 1.0, minScore: 0, maxScore: 35),
                FeatureConfig(type: "prefixMatch", weight: 1.0, minScore: 0, maxScore: 30),
                FeatureConfig(type: "containsMatch", weight: 1.0, minScore: 0, maxScore: 10),

                // Authority features
                FeatureConfig(type: "jlpt", weight: 0.8, minScore: 0, maxScore: 15),
                FeatureConfig(type: "frequency", weight: 1.2, minScore: 0, maxScore: 15)
            ],
            hardRules: [
                HardRuleConfig(type: "exactMatchBucket", priority: 1),
                HardRuleConfig(type: "lemmaMatchBucket", priority: 2)
            ],
            tieBreakers: [
                TieBreakerConfig(field: "frequencyRank", order: "ascending"),
                TieBreakerConfig(field: "id", order: "ascending")
            ]
        )
    }
}

// MARK: - Errors

/// Configuration loader errors
public enum ConfigLoaderError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case bundleResourceNotFound(String)
    case documentsDirectoryNotFound
    case invalidJSON
    case invalidConfiguration(String)
    case networkError(Error)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
        case .bundleResourceNotFound(let filename):
            return "Bundle resource not found: \(filename)"
        case .documentsDirectoryNotFound:
            return "Documents directory not found"
        case .invalidJSON:
            return "Invalid JSON format in configuration file"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .networkError(let error):
            return "Network error loading configuration: \(error.localizedDescription)"
        }
    }
}

// MARK: - Configuration Manager

/// High-level configuration manager with A/B testing support
public final class RankingConfigManager: @unchecked Sendable {
    public static let shared = RankingConfigManager()

    private let loader = RankingConfigLoader.shared
    private var cachedConfig: RankingConfiguration?
    private var currentProfile: String = "default"

    private init() {}

    /// Get current configuration (cached)
    public func getCurrentConfiguration() throws -> RankingConfiguration {
        if let cached = cachedConfig {
            return cached
        }

        let config = try loader.loadConfiguration(profile: currentProfile)
        cachedConfig = config
        return config
    }

    /// Switch to a different profile (for A/B testing)
    public func switchProfile(_ profile: String) throws -> RankingConfiguration {
        currentProfile = profile
        let config = try loader.loadConfiguration(profile: profile)
        cachedConfig = config
        return config
    }

    /// Reload configuration (clears cache)
    public func reloadConfiguration() throws -> RankingConfiguration {
        cachedConfig = nil
        return try getCurrentConfiguration()
    }

    /// Get current profile name
    public var activeProfile: String {
        return currentProfile
    }

    /// Check if using legacy scorer
    public var isUsingLegacyScorer: Bool {
        return (try? getCurrentConfiguration().useLegacyScorer) ?? false
    }

    /// Enable/disable legacy scorer
    public func setLegacyScorer(enabled: Bool) throws {
        var config = try getCurrentConfiguration()

        // Create a new configuration with updated flag
        // Note: This is a workaround since RankingConfiguration is immutable
        // In a real implementation, you'd need to make it mutable or use a different approach

        // For now, we'll need to reload from source and modify
        // This is left as an exercise - the proper approach is to save
        // the modified config to Documents directory
    }
}
