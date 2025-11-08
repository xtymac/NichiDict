import Foundation

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: Int
    public let entry: DictionaryEntry
    public let matchType: MatchType
    public let relevanceScore: Double
    public let bucket: ResultBucket  // 分桶排序

    public enum MatchType: String, Codable, Comparable, Sendable {
        case exact, prefix, contains

        public var sortOrder: Int {
            switch self {
            case .exact: return 0
            case .prefix: return 1
            case .contains: return 2
            }
        }

        public static func < (lhs: MatchType, rhs: MatchType) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    // 分桶：A > B > C > D，桶内按得分排序
    public enum ResultBucket: Int, Codable, Comparable, Sendable {
        case exactMatch = 0          // A: 完全匹配/基本形
        case commonPrefixMatch = 1   // B: 前缀匹配 + 高频
        case generalMatch = 2        // C: 其他包含/固定搭配
        case specializedTerm = 3     // D: 专有名词/百科型

        public static func < (lhs: ResultBucket, rhs: ResultBucket) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public init(id: Int, entry: DictionaryEntry, matchType: MatchType, relevanceScore: Double, bucket: ResultBucket) {
        self.id = id
        self.entry = entry
        self.matchType = matchType
        self.relevanceScore = relevanceScore
        self.bucket = bucket
    }
}
