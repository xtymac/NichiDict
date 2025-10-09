import XCTest
@preconcurrency import GRDB
@testable import CoreKit

final class DatabaseManagerTests: XCTestCase {
    func testDatabaseInitialization() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        let queue = try DatabaseManager.testQueue(at: dbURL.path)
        
        XCTAssertNotNil(queue)
    }
    
    func testDatabaseReadOnly() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        let queue = try DatabaseManager.testQueue(at: dbURL.path)
        
        // Verify we can read
        let count = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_entries")
        }
        XCTAssertEqual(count, 5)
    }
    
    func testValidateSchema() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        let queue = try DatabaseManager.testQueue(at: dbURL.path)
        let dbService = DBService(dbQueue: queue)
        
        let isValid = try await dbService.validateDatabaseIntegrity()
        
        XCTAssertTrue(isValid)
    }
    
    func testValidateFTSSync() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        let queue = try DatabaseManager.testQueue(at: dbURL.path)
        
        let entryCount = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_entries")
        }
        
        let ftsCount = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_fts")
        }
        
        XCTAssertEqual(entryCount, ftsCount)
    }
}
