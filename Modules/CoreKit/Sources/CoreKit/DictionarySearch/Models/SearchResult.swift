import Foundation

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: Int
    public let entry: DictionaryEntry
    public let matchType: MatchType
    public let relevanceScore: Double
    
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
    
    public init(id: Int, entry: DictionaryEntry, matchType: MatchType, relevanceScore: Double) {
        self.id = id
        self.entry = entry
        self.matchType = matchType
        self.relevanceScore = relevanceScore
    }
}
