import XCTest
@preconcurrency import GRDB
@testable import CoreKit

final class SearchServiceTests: XCTestCase {
    var searchService: SearchService!
    
    override func setUp() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        let dbQueue = try DatabaseManager.testQueue(at: dbURL.path)
        let dbService = DBService(dbQueue: dbQueue)
        searchService = SearchService(dbService: dbService)
    }
    
    func testSearchEmptyQuery() async throws {
        let results = try await searchService.search(query: "", maxResults: 10)
        XCTAssertTrue(results.isEmpty)
    }
    
    func testSearchKanjiQuery() async throws {
        let results = try await searchService.search(query: "食", maxResults: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.contains { $0.entry.headword.contains("食") })
    }
    
    func testSearchRomajiQuery() async throws {
        let results = try await searchService.search(query: "taberu", maxResults: 10)
        XCTAssertFalse(results.isEmpty)
    }
    
    func testSearchHiraganaQuery() async throws {
        let results = try await searchService.search(query: "たべる", maxResults: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.contains { $0.entry.readingHiragana == "たべる" })
    }
    
    func testSearchNoResults() async throws {
        let results = try await searchService.search(query: "xyzabc", maxResults: 10)
        XCTAssertTrue(results.isEmpty)
    }
    
    func testRankingExactBeforePrefix() async throws {
        // Search for exact match
        let results = try await searchService.search(query: "食べる", maxResults: 10)
        
        if let firstResult = results.first {
            // First result should be exact match or high relevance
            XCTAssertTrue(
                firstResult.entry.headword == "食べる" ||
                firstResult.matchType == .exact
            )
        }
    }
}
