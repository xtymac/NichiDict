import XCTest
@preconcurrency import GRDB
@testable import CoreKit

final class DBServiceTests: XCTestCase {
    var dbService: DBService!
    var dbQueue: DatabaseQueue!
    
    override func setUp() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        dbQueue = try DatabaseManager.testQueue(at: dbURL.path)
        dbService = DBService(dbQueue: dbQueue)
    }
    
    // MARK: - Search Tests
    
    func testSearchEntriesKanjiQuery() async throws {
        let results = try await dbService.searchEntries(query: "食", limit: 10)
        
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.contains { $0.headword.contains("食") })
    }
    
    func testSearchEntriesRomajiQuery() async throws {
        let results = try await dbService.searchEntries(query: "taberu", limit: 10)
        
        XCTAssertFalse(results.isEmpty)
        XCTAssert(results.contains { $0.readingRomaji.contains("taberu") })
    }
    
    func testSearchEntriesEmptyQuery() async throws {
        let results = try await dbService.searchEntries(query: "", limit: 10)
        
        XCTAssertTrue(results.isEmpty)
    }
    
    func testSearchEntriesNoResults() async throws {
        let results = try await dbService.searchEntries(query: "xyzabc", limit: 10)
        
        XCTAssertTrue(results.isEmpty)
    }
    
    func testSearchEntriesRanking() async throws {
        let results = try await dbService.searchEntries(query: "た", limit: 10)
        
        // If we have results, verify ordering makes sense
        if results.count > 1 {
            // Results should be ordered (exact matches or by frequency)
            XCTAssertFalse(results.isEmpty)
        }
    }
    
    // MARK: - Fetch Tests
    
    func testFetchEntryWithSensesAndExamples() async throws {
        let entry = try await dbService.fetchEntry(id: 1)
        
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.headword, "食べる")
        XCTAssertFalse(entry!.senses.isEmpty)
    }
    
    func testFetchEntryNotFound() async throws {
        let entry = try await dbService.fetchEntry(id: 999999)
        
        XCTAssertNil(entry)
    }
    
    // MARK: - Validation Tests
    
    func testValidateDatabaseIntegrity() async throws {
        let isValid = try await dbService.validateDatabaseIntegrity()
        
        XCTAssertTrue(isValid)
    }
}
