import Foundation

public struct ScriptDetectionSnapshot: Codable, Sendable {
    public struct RomajiOutlier: Codable, Sendable {
        public let query: String
        public let route: String
        public let occurrences: Int
        public let timestamp: Date

        var formattedDescription: String {
            "[\(timestamp)] \(route): \(query) (\(occurrences)x)"
        }
    }

    public let counts: [String: Int]
    public let romajiOutliers: [RomajiOutlier]

    public func formattedText(minCount: Int) -> String {
        var lines: [String] = []
        lines.append("📊 Script detection counts (≥\(minCount))")
        if counts.isEmpty {
            lines.append("  (no data)")
        } else {
            for (key, value) in counts.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key): \(value)")
            }
        }

        if !romajiOutliers.isEmpty {
            lines.append("⚠️ Romaji reverse-search outliers")
            for outlier in romajiOutliers {
                lines.append("  \(outlier.formattedDescription)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public func json(pretty: Bool = true) -> String? {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }

        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Tracks script detection calls for diagnostic purposes.
public actor ScriptDetectionMonitor {
    public static let shared = ScriptDetectionMonitor()

    private struct CounterKey: Hashable {
        let scriptLabel: String
        let route: String
    }

    private struct SuspiciousRecord: Codable {
        let query: String
        let scriptLabel: String
        let route: String
        let timestamp: Date
        let occurrences: Int
    }

    private var counters: [CounterKey: Int] = [:]
    private var recentSuspicious: [SuspiciousRecord] = []
    private let maxSuspiciousRecords = 50
    private var outlierThreshold: Int = 3

    /// Adjusts the threshold for highlighting romaji reverse-search decisions.
    /// Set to 0 to log every occurrence.
    public func setOutlierThreshold(_ threshold: Int) {
        outlierThreshold = max(0, threshold)
    }

    /// Reset collected stats (useful between QA sessions).
    public func reset() {
        counters.removeAll()
        recentSuspicious.removeAll()
    }

    /// Records the script detection decision for a single query.
    /// - Parameters:
    ///   - query: Sanitized input query.
    ///   - scriptType: Detected script classification.
    ///   - useReverseSearch: Whether reverse search logic will run.
    public func record(query: String, scriptType: ScriptType, useReverseSearch: Bool) {
        let label = String(describing: scriptType)
        let route = useReverseSearch ? "reverse" : "forward"
        let key = CounterKey(scriptLabel: label, route: route)
        let newCount = (counters[key] ?? 0) + 1
        counters[key] = newCount

        // Highlight potentially ambiguous romaji decisions.
        if scriptType == .romaji && useReverseSearch {
            if outlierThreshold == 0 || newCount >= outlierThreshold {
                let record = SuspiciousRecord(
                    query: query,
                    scriptLabel: label,
                    route: route,
                    timestamp: Date(),
                    occurrences: newCount
                )
                recentSuspicious.append(record)
                if recentSuspicious.count > maxSuspiciousRecords {
                    recentSuspicious.removeFirst(recentSuspicious.count - maxSuspiciousRecords)
                }
                print("📈 ScriptMonitor: query='\(query)' script=\(label) route=\(route) count=\(newCount)")
            }
        }
    }

    /// Returns current aggregate counters for diagnostics or unit tests.
    public func snapshot(minCount: Int = 0) -> ScriptDetectionSnapshot {
        let filteredCounts = counters.reduce(into: [String: Int]()) { partialResult, element in
            if element.value >= minCount {
                let key = "\(element.key.scriptLabel)|\(element.key.route)"
                partialResult[key] = element.value
            }
        }

        let filteredOutliers = recentSuspicious.compactMap { record -> ScriptDetectionSnapshot.RomajiOutlier? in
            guard record.occurrences >= max(minCount, 1) else { return nil }
            return ScriptDetectionSnapshot.RomajiOutlier(
                query: record.query,
                route: record.route,
                occurrences: record.occurrences,
                timestamp: record.timestamp
            )
        }

        return ScriptDetectionSnapshot(
            counts: filteredCounts,
            romajiOutliers: filteredOutliers
        )
    }

    /// Convenience wrapper with default threshold.
    public func snapshot() -> ScriptDetectionSnapshot {
        snapshot(minCount: 0)
    }

    /// Exports stats as a JSON string for QA reports.
    public func exportJSON(minCount: Int = 0, pretty: Bool = true) -> String? {
        snapshot(minCount: minCount).json(pretty: pretty)
    }

    /// Provides the most recent suspicious records in string format.
    public func recentSuspiciousRecords() -> [String] {
        snapshot().romajiOutliers.map { $0.formattedDescription }
    }
}
