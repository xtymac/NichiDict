import XCTest
@testable import CoreKit
import GRDB

/// Tests for edge cases in search functionality (T042)
final class EdgeCaseTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var dbService: DBService!
    var searchService: SearchService!

    override func setUp() async throws {
        // Use test database
        let testBundle = Bundle.module
        guard let dbURL = testBundle.url(forResource: "test-seed", withExtension: "sqlite") else {
            XCTFail("Test database not found")
            return
        }

        dbQueue = try DatabaseManager.testQueue(at: dbURL.path)
        dbService = DBService(dbQueue: dbQueue)
        searchService = SearchService(dbService: dbService)
    }

    override func tearDown() async throws {
        try dbQueue.close()
        dbQueue = nil
        dbService = nil
        searchService = nil
    }

    // MARK: - Empty Query Tests

    func testEmptyQuery() async throws {
        let results = try await searchService.search(query: "", maxResults: 50)
        XCTAssertTrue(results.isEmpty, "Empty query should return empty results")
    }

    func testWhitespaceOnlyQuery() async throws {
        let results = try await searchService.search(query: "   ", maxResults: 50)
        XCTAssertTrue(results.isEmpty, "Whitespace-only query should return empty results")
    }

    // MARK: - Long Query Tests

    func testQueryTooLong() async throws {
        let longQuery = String(repeating: "a", count: 101)

        do {
            _ = try await searchService.search(query: longQuery, maxResults: 50)
            XCTFail("Query > 100 chars should throw error")
        } catch let error as SearchError {
            if case .queryTooLong(let length) = error {
                XCTAssertEqual(length, 101)
            } else {
                XCTFail("Expected queryTooLong error, got \(error)")
            }
        }
    }

    func testMaxLengthQuery() async throws {
        // 100 characters should work fine
        let maxQuery = String(repeating: "a", count: 100)
        let results = try await searchService.search(query: maxQuery, maxResults: 50)
        // Should not throw, results may be empty (no match)
        XCTAssertNotNil(results)
    }

    // MARK: - Special Characters Tests

    func testSpecialCharactersSanitized() async throws {
        // FTS5 special characters that could break search
        let specialChars = "食べる!@#$%^&*()"
        let results = try await searchService.search(query: specialChars, maxResults: 50)
        // Should not throw, special characters should be filtered out
        XCTAssertNotNil(results)
    }

    func testOnlySpecialCharacters() async throws {
        let specialChars = "!@#$%^&*()"

        do {
            _ = try await searchService.search(query: specialChars, maxResults: 50)
            XCTFail("Query with only special characters should throw invalidCharacters error")
        } catch let error as SearchError {
            if case .invalidCharacters = error {
                // Test passed
            } else {
                XCTFail("Expected invalidCharacters error, got \(error)")
            }
        }
    }

    func testSQLInjectionAttempt() async throws {
        let maliciousQuery = "'; DROP TABLE dictionary_entries; --"

        // Should sanitize and not crash
        let results = try await searchService.search(query: maliciousQuery, maxResults: 50)
        XCTAssertNotNil(results)

        // Verify table still exists (wasn't dropped)
        let count = try await dbService.searchEntries(query: "食", limit: 1)
        XCTAssertFalse(count.isEmpty, "Table should still exist after SQL injection attempt")
    }

    // MARK: - Results Limit Tests

    func testResultsLimitedTo100() async throws {
        // Request 200 results, but should be capped at 100
        let results = try await searchService.search(query: "a", maxResults: 200)
        XCTAssertLessThanOrEqual(results.count, 100, "Results should be limited to 100")
    }

    func testSmallResultsLimit() async throws {
        let results = try await searchService.search(query: "食", maxResults: 2)
        XCTAssertLessThanOrEqual(results.count, 2, "Should respect small maxResults")
    }

    // MARK: - No Results Tests

    func testNoResultsForInvalidQuery() async throws {
        let results = try await searchService.search(query: "xyzabc123", maxResults: 50)
        XCTAssertTrue(results.isEmpty, "Invalid query should return empty results")
    }

    // MARK: - Mixed Script Tests

    func testMixedScriptQuery() async throws {
        let mixedQuery = "食tab"
        let results = try await searchService.search(query: mixedQuery, maxResults: 50)
        XCTAssertNotNil(results, "Mixed script query should not crash")
    }

    // MARK: - Database Integrity Tests

    func testDatabaseIntegrityWithTestQueue() async throws {
        // Test database integrity directly using the test queue
        let integrityResult = try await dbQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check")
        }
        XCTAssertEqual(integrityResult, "ok", "Test database should pass integrity check")

        // Verify tables exist
        let tablesExist = try await dbQueue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master
                WHERE type='table' AND name IN ('dictionary_entries', 'dictionary_fts', 'word_senses', 'example_sentences')
                """)
            return count == 4
        }
        XCTAssertTrue(tablesExist, "All required tables should exist")
    }
}
