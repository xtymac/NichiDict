#if DEBUG
import Foundation

public enum DebugTools {
    /// Dumps script-detection statistics to the console and returns the formatted string.
    /// - Parameters:
    ///   - minCount: Minimum occurrence threshold for counters to be displayed.
    ///   - asJSON: When true, the snapshot is emitted as JSON instead of text.
    ///   - pretty: Controls JSON pretty-printing.
    /// - Returns: The formatted output string.
    @discardableResult
    public static func dumpScriptStats(
        minCount: Int = 0,
        asJSON: Bool = false,
        pretty: Bool = true
    ) async -> String {
        let snapshot = await ScriptDetectionMonitor.shared.snapshot(minCount: minCount)

        if asJSON, let json = snapshot.json(pretty: pretty) {
            print(json)
            return json
        }

        let output = snapshot.formattedText(minCount: minCount)
        print(output)
        return output
    }

    /// Exports the snapshot as JSON without printing to the console.
    public static func exportScriptStatsJSON(
        minCount: Int = 0,
        pretty: Bool = true
    ) async -> String? {
        await ScriptDetectionMonitor.shared.exportJSON(minCount: minCount, pretty: pretty)
    }

    /// Resets script-detection counters and suspicious records.
    public static func resetScriptStats() async {
        await ScriptDetectionMonitor.shared.reset()
    }

    /// Adjusts the romaji outlier threshold for future recordings.
    public static func setOutlierThreshold(_ threshold: Int) async {
        await ScriptDetectionMonitor.shared.setOutlierThreshold(threshold)
    }
}
#endif
