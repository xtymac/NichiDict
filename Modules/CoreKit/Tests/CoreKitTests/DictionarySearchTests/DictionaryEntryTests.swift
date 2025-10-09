import XCTest
@preconcurrency import GRDB
@testable import CoreKit

final class DictionaryEntryTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    
    override func setUp() async throws {
        guard let dbURL = Bundle.module.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        dbQueue = try DatabaseManager.testQueue(at: dbURL.path)
    }
    
    func testFetchDictionaryEntry() async throws {
        let entry = try await dbQueue.read { db in
            try DictionaryEntry.fetchOne(db, id: 1)
        }
        
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.headword, "食べる")
        XCTAssertEqual(entry?.readingHiragana, "たべる")
        XCTAssertEqual(entry?.readingRomaji, "taberu")
        XCTAssertEqual(entry?.frequencyRank, 100)
        XCTAssertEqual(entry?.pitchAccent, "た↓べる")
    }
    
    func testDecodeDictionaryEntry() async throws {
        let entries = try await dbQueue.read { db in
            try DictionaryEntry.fetchAll(db)
        }
        
        XCTAssertEqual(entries.count, 5)
        XCTAssert(entries.allSatisfy { !$0.headword.isEmpty })
        XCTAssert(entries.allSatisfy { !$0.readingHiragana.isEmpty })
        XCTAssert(entries.allSatisfy { !$0.readingRomaji.isEmpty })
    }
    
    func testDictionaryEntryEquality() {
        let entry1 = DictionaryEntry(
            id: 1,
            headword: "食べる",
            readingHiragana: "たべる",
            readingRomaji: "taberu",
            frequencyRank: 100,
            pitchAccent: "た↓べる",
            createdAt: 0,
            senses: []
        )
        
        let entry2 = DictionaryEntry(
            id: 1,
            headword: "食べる",
            readingHiragana: "たべる",
            readingRomaji: "taberu",
            frequencyRank: 100,
            pitchAccent: "た↓べる",
            createdAt: 0,
            senses: []
        )
        
        XCTAssertEqual(entry1, entry2)
        XCTAssertEqual(entry1.hashValue, entry2.hashValue)
    }
    
    func testFetchMultipleEntries() async throws {
        let entries = try await dbQueue.read { db in
            try DictionaryEntry
                .order(Column("frequency_rank"))
                .limit(3)
                .fetchAll(db)
        }
        
        XCTAssertEqual(entries.count, 3)
        // Verify sorted by frequency (lower rank = more common)
        if entries.count >= 2 {
            let firstRank = entries[0].frequencyRank ?? Int.max
            let secondRank = entries[1].frequencyRank ?? Int.max
            XCTAssertLessThanOrEqual(firstRank, secondRank)
        }
    }
}
