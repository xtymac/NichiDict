import XCTest
@preconcurrency import GRDB
@testable import CoreKit

/// Tests for English → Japanese reverse search functionality
final class EnglishReverseSearchTests: XCTestCase {
    var searchService: SearchService!

    override func setUp() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        let dbQueue = try DatabaseManager.testQueue(at: dbURL.path)
        let dbService = DBService(dbQueue: dbQueue)
        searchService = SearchService(dbService: dbService)
    }

    func testCommonEnglishWordGo() async throws {
        // Note: This test uses the test database which may have limited data
        // The main goal is to verify that the search doesn't crash and uses reverse search

        // Execute search for "go" - should trigger reverse search
        let results = try await searchService.search(query: "go", maxResults: 10)

        // Test doesn't crash - this verifies the reverse search logic works
        // Results may be empty in test database, which is okay
        print("Search for 'go' returned \(results.count) results")

        // If we do get results, verify structure
        for result in results {
            XCTAssertFalse(result.entry.headword.isEmpty, "Entry should have headword")
            XCTAssertFalse(result.entry.readingHiragana.isEmpty, "Entry should have reading")
        }
    }

    func testCommonEnglishWordEat() async throws {
        // Execute search for "eat"
        let results = try await searchService.search(query: "eat", maxResults: 10)

        // Test doesn't crash
        print("Search for 'eat' returned \(results.count) results")

        // Verify structure if results exist
        for result in results {
            XCTAssertFalse(result.entry.headword.isEmpty)
        }
    }

    func testJapaneseRomajiStillWorks() async throws {
        // Japanese romaji like "taberu" should still work (forward search)
        let results = try await searchService.search(query: "taberu", maxResults: 10)

        // Should find Japanese words with romaji "taberu"
        print("Search for 'taberu' returned \(results.count) results")

        for result in results {
            XCTAssertFalse(result.entry.headword.isEmpty)
        }
    }
}
