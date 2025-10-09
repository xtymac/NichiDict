import XCTest
@preconcurrency import GRDB
@testable import CoreKit

final class WordSenseTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    
    override func setUp() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        dbQueue = try DatabaseManager.testQueue(at: dbURL.path)
    }
    
    func testFetchWordSensesForEntry() async throws {
        let senses = try await dbQueue.read { db in
            try WordSense
                .filter(Column("entry_id") == 1)
                .order(Column("sense_order"))
                .fetchAll(db)
        }
        
        XCTAssertGreaterThan(senses.count, 0)
        XCTAssertEqual(senses[0].entryId, 1)
        XCTAssertEqual(senses[0].definitionEnglish, "to eat")
        XCTAssertEqual(senses[0].partOfSpeech, "ichidan verb,transitive")
    }
    
    func testWordSenseRelationship() async throws {
        let sense = try await dbQueue.read { db in
            try WordSense.fetchOne(db, id: 1)
        }
        
        XCTAssertNotNil(sense)
        XCTAssertEqual(sense?.entryId, 1)
    }
    
    func testDecodeWordSense() async throws {
        let senses = try await dbQueue.read { db in
            try WordSense.fetchAll(db)
        }
        
        XCTAssertEqual(senses.count, 5)
        XCTAssert(senses.allSatisfy { !$0.definitionEnglish.isEmpty })
        XCTAssert(senses.allSatisfy { $0.senseOrder >= 1 })
    }
}
