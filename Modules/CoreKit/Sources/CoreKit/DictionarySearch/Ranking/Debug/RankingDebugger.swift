import Foundation

/// Debug visualization and analysis tools for ranking system
public final class RankingDebugger: @unchecked Sendable {
    public static let shared = RankingDebugger()

    private init() {}

    // MARK: - Breakdown Formatting

    /// Format a single entry's breakdown for display
    public func formatBreakdown(_ breakdown: ScoreBreakdown, headword: String) -> String {
        return breakdown.formatted(headword: headword)
    }

    /// Format multiple entries' breakdowns for comparison
    public func formatBreakdowns(_ entries: [RankedEntry], limit: Int = 10) -> String {
        var lines: [String] = []
        lines.append("=" * 60)
        lines.append("RANKING BREAKDOWN")
        lines.append("=" * 60)
        lines.append("")

        let limitedEntries = Array(entries.prefix(limit))

        for (index, rankedEntry) in limitedEntries.enumerated() {
            lines.append("[\(index + 1)] \(rankedEntry.entry.headword)")
            lines.append(rankedEntry.breakdown.formatted(headword: rankedEntry.entry.headword))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Format as HTML for web view display
    public func formatBreakdownHTML(_ breakdown: ScoreBreakdown, headword: String) -> String {
        var html = """
        <div class="breakdown">
            <h3>📊 Breakdown for '\(headword)'</h3>
            <div class="summary">
                <div class="score">Total Score: <strong>\(String(format: "%.2f", breakdown.totalScore))</strong></div>
                <div class="bucket">Bucket: <strong>\(breakdown.bucket)</strong> (\(breakdown.bucketRule))</div>
            </div>
            <h4>Feature Scores:</h4>
            <table class="features">
                <thead>
                    <tr>
                        <th>Feature</th>
                        <th>Score</th>
                        <th>Visual</th>
                    </tr>
                </thead>
                <tbody>
        """

        let sortedFeatures = breakdown.featureScores.sorted { $0.value > $1.value }
        let maxScore = sortedFeatures.first?.value ?? 1.0

        for (feature, score) in sortedFeatures {
            let percentage = abs(score / max(abs(maxScore), 0.1)) * 100
            let barColor = score >= 0 ? "#4CAF50" : "#f44336"
            let scoreFormatted = String(format: "%.2f", score)

            html += """
                    <tr>
                        <td>\(feature)</td>
                        <td>\(scoreFormatted)</td>
                        <td>
                            <div class="bar-container">
                                <div class="bar" style="width: \(percentage)%; background-color: \(barColor);"></div>
                            </div>
                        </td>
                    </tr>
            """
        }

        html += """
                </tbody>
            </table>
        </div>
        """

        return html
    }

    /// Generate CSS for HTML breakdown
    public func generateBreakdownCSS() -> String {
        return """
        <style>
            .breakdown {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                padding: 20px;
                background: #f5f5f5;
                border-radius: 8px;
                margin: 10px 0;
            }
            .summary {
                background: white;
                padding: 15px;
                border-radius: 6px;
                margin-bottom: 15px;
            }
            .score, .bucket {
                margin: 5px 0;
            }
            table.features {
                width: 100%;
                border-collapse: collapse;
                background: white;
                border-radius: 6px;
                overflow: hidden;
            }
            table.features th {
                background: #2196F3;
                color: white;
                padding: 12px;
                text-align: left;
            }
            table.features td {
                padding: 10px 12px;
                border-bottom: 1px solid #eee;
            }
            table.features tr:hover {
                background: #f9f9f9;
            }
            .bar-container {
                width: 100%;
                height: 20px;
                background: #eee;
                border-radius: 10px;
                overflow: hidden;
            }
            .bar {
                height: 100%;
                transition: width 0.3s ease;
            }
        </style>
        """
    }

    // MARK: - Comparison Tools

    /// Compare rankings between two different configurations
    public func compareRankings(
        query: String,
        entries: [DictionaryEntry],
        configA: RankingConfiguration,
        configB: RankingConfiguration
    ) throws -> ComparisonReport {
        // Create engines for both configs
        let engineA = try RankingEngine(config: configA)
        let engineB = try RankingEngine(config: configB)

        // Create contexts (simplified - assume same context for all entries)
        let context = ScoringContext(
            query: query,
            scriptType: .hiragana,
            matchType: .exact,
            isExactHeadword: false,
            isLemmaMatch: false,
            useReverseSearch: false
        )

        let entriesWithContext = entries.map { ($0, context) }

        // Rank with both engines
        let rankedA = engineA.rank(entries: entriesWithContext)
        let rankedB = engineB.rank(entries: entriesWithContext)

        // Analyze differences
        var differences: [ComparisonDifference] = []

        for (indexA, entryA) in rankedA.enumerated() {
            if let indexB = rankedB.firstIndex(where: { $0.entry.id == entryA.entry.id }) {
                let positionChange = indexB - indexA

                if positionChange != 0 {
                    differences.append(ComparisonDifference(
                        headword: entryA.entry.headword,
                        positionA: indexA,
                        positionB: indexB,
                        positionChange: positionChange,
                        scoreA: entryA.score,
                        scoreB: rankedB[indexB].score,
                        bucketA: entryA.bucket,
                        bucketB: rankedB[indexB].bucket
                    ))
                }
            }
        }

        // Sort by absolute position change
        differences.sort { abs($0.positionChange) > abs($1.positionChange) }

        return ComparisonReport(
            query: query,
            configA: configA.profile,
            configB: configB.profile,
            differences: differences,
            totalEntries: entries.count
        )
    }

    /// Format comparison report as readable string
    public func formatComparisonReport(_ report: ComparisonReport) -> String {
        var lines: [String] = []
        lines.append("=" * 60)
        lines.append("RANKING COMPARISON: \(report.configA) vs \(report.configB)")
        lines.append("Query: '\(report.query)'")
        lines.append("=" * 60)
        lines.append("")

        if report.differences.isEmpty {
            lines.append("✅ No differences found - rankings are identical")
        } else {
            lines.append("Found \(report.differences.count) differences:")
            lines.append("")

            for diff in report.differences.prefix(20) {
                let direction = diff.positionChange > 0 ? "⬇️" : "⬆️"
                let change = abs(diff.positionChange)

                lines.append("[\(diff.headword)]")
                lines.append("   \(direction) Position: \(diff.positionA + 1) → \(diff.positionB + 1) (Δ\(change))")
                lines.append("   Score: \(String(format: "%.2f", diff.scoreA)) → \(String(format: "%.2f", diff.scoreB))")
                lines.append("   Bucket: \(diff.bucketA) → \(diff.bucketB)")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Statistics

    /// Calculate ranking statistics
    public func calculateStatistics(_ entries: [RankedEntry]) -> RankingStatistics {
        let scores = entries.map { $0.score }
        let bucketCounts = Dictionary(grouping: entries, by: { $0.bucket })
            .mapValues { $0.count }

        let avgScore = scores.reduce(0, +) / Double(max(scores.count, 1))
        let minScore = scores.min() ?? 0
        let maxScore = scores.max() ?? 0

        // Calculate standard deviation
        let variance = scores.map { pow($0 - avgScore, 2) }.reduce(0, +) / Double(max(scores.count, 1))
        let stdDev = sqrt(variance)

        return RankingStatistics(
            totalEntries: entries.count,
            averageScore: avgScore,
            minScore: minScore,
            maxScore: maxScore,
            standardDeviation: stdDev,
            bucketDistribution: bucketCounts
        )
    }

    /// Format statistics as readable string
    public func formatStatistics(_ stats: RankingStatistics) -> String {
        var lines: [String] = []
        lines.append("📈 RANKING STATISTICS")
        lines.append("=" * 40)
        lines.append("Total Entries: \(stats.totalEntries)")
        lines.append("Average Score: \(String(format: "%.2f", stats.averageScore))")
        lines.append("Score Range: \(String(format: "%.2f", stats.minScore)) - \(String(format: "%.2f", stats.maxScore))")
        lines.append("Std Deviation: \(String(format: "%.2f", stats.standardDeviation))")
        lines.append("")
        lines.append("Bucket Distribution:")

        for (bucket, count) in stats.bucketDistribution.sorted(by: { $0.key < $1.key }) {
            let percentage = Double(count) / Double(stats.totalEntries) * 100
            lines.append("   \(bucket): \(count) (\(String(format: "%.1f", percentage))%)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Supporting Types

/// Comparison difference between two ranking configurations
public struct ComparisonDifference: Sendable {
    public let headword: String
    public let positionA: Int
    public let positionB: Int
    public let positionChange: Int
    public let scoreA: Double
    public let scoreB: Double
    public let bucketA: SearchResult.ResultBucket
    public let bucketB: SearchResult.ResultBucket
}

/// Comparison report
public struct ComparisonReport: Sendable {
    public let query: String
    public let configA: String
    public let configB: String
    public let differences: [ComparisonDifference]
    public let totalEntries: Int
}

/// Ranking statistics
public struct RankingStatistics: Sendable {
    public let totalEntries: Int
    public let averageScore: Double
    public let minScore: Double
    public let maxScore: Double
    public let standardDeviation: Double
    public let bucketDistribution: [SearchResult.ResultBucket: Int]
}

// MARK: - String Helpers

fileprivate extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
