import XCTest
@testable import CoreKit

final class SearchResultTests: XCTestCase {
    func testSearchResultCreation() {
        let entry = DictionaryEntry(
            id: 1,
            headword: "食べる",
            readingHiragana: "たべる",
            readingRomaji: "taberu",
            frequencyRank: 100,
            pitchAccent: nil,
            createdAt: 0
        )
        
        let result = SearchResult(
            id: 1,
            entry: entry,
            matchType: .exact,
            relevanceScore: 100.0
        )
        
        XCTAssertEqual(result.id, 1)
        XCTAssertEqual(result.matchType, .exact)
        XCTAssertEqual(result.relevanceScore, 100.0)
    }
    
    func testMatchTypeOrdering() {
        XCTAssertLessThan(SearchResult.MatchType.exact, .prefix)
        XCTAssertLessThan(SearchResult.MatchType.prefix, .contains)
        
        XCTAssertEqual(SearchResult.MatchType.exact.sortOrder, 0)
        XCTAssertEqual(SearchResult.MatchType.prefix.sortOrder, 1)
        XCTAssertEqual(SearchResult.MatchType.contains.sortOrder, 2)
    }
    
    func testSearchResultEquality() {
        let entry = DictionaryEntry(
            id: 1,
            headword: "食べる",
            readingHiragana: "たべる",
            readingRomaji: "taberu",
            frequencyRank: 100,
            pitchAccent: nil,
            createdAt: 0
        )
        
        let result1 = SearchResult(id: 1, entry: entry, matchType: .exact, relevanceScore: 100.0)
        let result2 = SearchResult(id: 1, entry: entry, matchType: .exact, relevanceScore: 100.0)
        
        XCTAssertEqual(result1, result2)
    }
}
