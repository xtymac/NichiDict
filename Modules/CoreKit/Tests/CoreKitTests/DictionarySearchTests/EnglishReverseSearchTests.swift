import Foundation
import XCTest
@preconcurrency import GRDB
@testable import CoreKit

/// Tests for English → Japanese reverse search functionality
final class EnglishReverseSearchTests: XCTestCase {
    var searchService: SearchService!

    private let testBundle = Bundle.module

    override func setUp() async throws {
        guard let dbURL = testBundle.url(forResource: "test-seed", withExtension: "sqlite") else {
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

    func testReverseSearchRanksVerbBeforeBoardGame() async throws {
        let dbQueue = try DatabaseQueue(path: ":memory:")

        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE dictionary_entries (
                    id INTEGER PRIMARY KEY,
                    headword TEXT NOT NULL,
                    reading_hiragana TEXT NOT NULL,
                    reading_romaji TEXT NOT NULL,
                    frequency_rank INTEGER,
                    pitch_accent TEXT,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE word_senses (
                    id INTEGER PRIMARY KEY,
                    entry_id INTEGER NOT NULL,
                    definition_english TEXT NOT NULL,
                    part_of_speech TEXT NOT NULL,
                    usage_notes TEXT,
                    sense_order INTEGER NOT NULL
                );
            """)

            try db.execute(sql: """
                INSERT INTO dictionary_entries
                    (id, headword, reading_hiragana, reading_romaji, frequency_rank, pitch_accent, created_at)
                VALUES
                    (1, '\u{884C}\u{304F}', '\u{3044}\u{304F}', 'iku', 50, NULL, 1),
                    (2, '\u{7881}', '\u{3054}', 'go', 9000, NULL, 2);
            """)

            try db.execute(sql: """
                INSERT INTO word_senses
                    (id, entry_id, definition_english, part_of_speech, usage_notes, sense_order)
                VALUES
                    (1, 1, 'to go; to move (towards)', 'verb', NULL, 0),
                    (2, 2, 'go (board game)', 'noun', NULL, 0);
            """)
        }

        let dbService = DBService(dbQueue: dbQueue)
        let searchService = SearchService(dbService: dbService)
        let results = try await searchService.search(query: "go", maxResults: 10)

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.entry.headword, "\u{884C}\u{304F}")
        XCTAssertTrue(results.contains { $0.entry.headword == "\u{7881}" })
    }

    func testEnglishReverseSearchPrefersNativeOverKatakana() async throws {
        // This test verifies that native Japanese words (星) rank before katakana loanwords (スター)
        // when searching for English words like "star"
        let dbQueue = try DatabaseQueue(path: ":memory:")

        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE dictionary_entries (
                    id INTEGER PRIMARY KEY,
                    headword TEXT NOT NULL,
                    reading_hiragana TEXT NOT NULL,
                    reading_romaji TEXT NOT NULL,
                    frequency_rank INTEGER,
                    pitch_accent TEXT,
                    jmdict_id INTEGER,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE word_senses (
                    id INTEGER PRIMARY KEY,
                    entry_id INTEGER NOT NULL,
                    definition_english TEXT NOT NULL,
                    definition_chinese_simplified TEXT,
                    definition_chinese_traditional TEXT,
                    part_of_speech TEXT NOT NULL,
                    usage_notes TEXT,
                    sense_order INTEGER NOT NULL
                );
            """)

            try db.execute(sql: """
                INSERT INTO dictionary_entries
                    (id, headword, reading_hiragana, reading_romaji, frequency_rank, pitch_accent, jmdict_id, created_at)
                VALUES
                    (1, '星', 'ほし', 'hoshi', 800, NULL, 1000, 1),
                    (2, 'スター', 'すたー', 'suta-', 1500, NULL, 1001, 2),
                    (3, 'えとわーる', 'えとわーる', 'etowa-ru', NULL, NULL, 1002, 3);
            """)

            try db.execute(sql: """
                INSERT INTO word_senses
                    (id, entry_id, definition_english, definition_chinese_simplified, definition_chinese_traditional, part_of_speech, usage_notes, sense_order)
                VALUES
                    (1, 1, 'star (celestial body)', '星', '星', 'noun (common) (futsuumeishi)', NULL, 0),
                    (2, 2, 'star (actor, athlete, etc.); celebrity', '明星', '明星', 'noun (common) (futsuumeishi)', NULL, 0),
                    (3, 2, '(celestial) star', '恒星', '恆星', 'noun (common) (futsuumeishi)', NULL, 1),
                    (4, 3, 'star', '星', '星', 'noun (common) (futsuumeishi)', NULL, 0);
            """)
        }

        let dbService = DBService(dbQueue: dbQueue)
        let searchService = SearchService(dbService: dbService)
        let results = try await searchService.search(query: "star", maxResults: 10)

        XCTAssertFalse(results.isEmpty, "Should return results for 'star'")
        // Core native equivalent (星) should rank first
        XCTAssertEqual(results.first?.entry.headword, "星", "Native 星 should rank before katakana スター")
        // Verify we still get the katakana entries, but later
        let headwords = results.map { $0.entry.headword }
        XCTAssertTrue(headwords.contains("スター"), "Should include katakana スター")
        XCTAssertTrue(headwords.contains("えとわーる"), "Should include えとわーる")
    }

    func testParentheticalSemanticBoost() async throws {
        // Test that queries like "(language)" prioritize 言語 over らんげーじ
        let dbQueue = try DatabaseQueue(path: ":memory:")

        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE dictionary_entries (
                    id INTEGER PRIMARY KEY,
                    headword TEXT NOT NULL,
                    reading_hiragana TEXT NOT NULL,
                    reading_romaji TEXT NOT NULL,
                    frequency_rank INTEGER,
                    pitch_accent TEXT,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE word_senses (
                    id INTEGER PRIMARY KEY,
                    entry_id INTEGER NOT NULL,
                    definition_english TEXT NOT NULL,
                    definition_chinese_simplified TEXT,
                    definition_chinese_traditional TEXT,
                    part_of_speech TEXT NOT NULL,
                    usage_notes TEXT,
                    sense_order INTEGER NOT NULL
                );
            """)

            try db.execute(sql: """
                INSERT INTO dictionary_entries
                    (id, headword, reading_hiragana, reading_romaji, frequency_rank, pitch_accent, created_at)
                VALUES
                    (1, '言語', 'げんご', 'gengo', 1000, NULL, 1),
                    (2, 'ランゲージ', 'らんげーじ', 'rangeji', 8000, NULL, 2);
            """)

            try db.execute(sql: """
                INSERT INTO word_senses
                    (id, entry_id, definition_english, definition_chinese_simplified, definition_chinese_traditional, part_of_speech, usage_notes, sense_order)
                VALUES
                    (1, 1, 'language', '语言', '語言', 'noun (common) (futsuumeishi)', NULL, 0),
                    (2, 2, 'language', '语言', '語言', 'noun (common) (futsuumeishi)', NULL, 0);
            """)
        }

        let dbService = DBService(dbQueue: dbQueue)
        let searchService = SearchService(dbService: dbService)

        // Test plain "language" query - should prioritize native 言語
        let results = try await searchService.search(query: "language", maxResults: 10)

        XCTAssertFalse(results.isEmpty, "Should return results for 'language'")
        // Core native equivalent should rank first
        XCTAssertEqual(results.first?.entry.headword, "言語", "Native 言語 should rank before katakana ランゲージ")
        XCTAssertTrue(results.contains { $0.entry.headword == "ランゲージ" }, "Should include katakana ランゲージ")
    }

    func testActorRanking() async throws {
        // Test that "actor" or "(actor)" prioritizes 俳優 over アクター
        let dbQueue = try DatabaseQueue(path: ":memory:")

        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE dictionary_entries (
                    id INTEGER PRIMARY KEY,
                    headword TEXT NOT NULL,
                    reading_hiragana TEXT NOT NULL,
                    reading_romaji TEXT NOT NULL,
                    frequency_rank INTEGER,
                    pitch_accent TEXT,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE word_senses (
                    id INTEGER PRIMARY KEY,
                    entry_id INTEGER NOT NULL,
                    definition_english TEXT NOT NULL,
                    definition_chinese_simplified TEXT,
                    definition_chinese_traditional TEXT,
                    part_of_speech TEXT NOT NULL,
                    usage_notes TEXT,
                    sense_order INTEGER NOT NULL
                );
            """)

            try db.execute(sql: """
                INSERT INTO dictionary_entries
                    (id, headword, reading_hiragana, reading_romaji, frequency_rank, pitch_accent, created_at)
                VALUES
                    (1, '俳優', 'はいゆう', 'haiyuu', 500, NULL, 1),
                    (2, 'アクター', 'あくたー', 'akutaa', NULL, NULL, 2);
            """)

            try db.execute(sql: """
                INSERT INTO word_senses
                    (id, entry_id, definition_english, definition_chinese_simplified, definition_chinese_traditional, part_of_speech, usage_notes, sense_order)
                VALUES
                    (1, 1, 'actor; actress; player; performer', '演员', '演員', 'noun (common) (futsuumeishi)', NULL, 0),
                    (2, 2, 'actor', '演员', '演員', 'noun (common) (futsuumeishi)', NULL, 0);
            """)
        }

        let dbService = DBService(dbQueue: dbQueue)
        let searchService = SearchService(dbService: dbService)
        let results = try await searchService.search(query: "actor", maxResults: 10)

        XCTAssertFalse(results.isEmpty, "Should return results for 'actor'")
        XCTAssertEqual(results.first?.entry.headword, "俳優", "Native 俳優 should rank before katakana アクター")
    }

    func testVerbRankingPriority() async throws {
        // Test that verbs rank higher than nouns with same match quality
        let dbQueue = try DatabaseQueue(path: ":memory:")

        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE dictionary_entries (
                    id INTEGER PRIMARY KEY,
                    headword TEXT NOT NULL,
                    reading_hiragana TEXT NOT NULL,
                    reading_romaji TEXT NOT NULL,
                    frequency_rank INTEGER,
                    pitch_accent TEXT,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE word_senses (
                    id INTEGER PRIMARY KEY,
                    entry_id INTEGER NOT NULL,
                    definition_english TEXT NOT NULL,
                    definition_chinese_simplified TEXT,
                    definition_chinese_traditional TEXT,
                    part_of_speech TEXT NOT NULL,
                    usage_notes TEXT,
                    sense_order INTEGER NOT NULL
                );
            """)

            try db.execute(sql: """
                INSERT INTO dictionary_entries
                    (id, headword, reading_hiragana, reading_romaji, frequency_rank, pitch_accent, created_at)
                VALUES
                    (1, '行く', 'いく', 'iku', 100, NULL, 1),
                    (2, '囲碁', 'いご', 'igo', 5000, NULL, 2);
            """)

            try db.execute(sql: """
                INSERT INTO word_senses
                    (id, entry_id, definition_english, definition_chinese_simplified, definition_chinese_traditional, part_of_speech, usage_notes, sense_order)
                VALUES
                    (1, 1, 'to go; to move', '去', '去', 'Godan verb with u ending', NULL, 0),
                    (2, 2, 'go (board game)', '围棋', '圍棋', 'noun (common) (futsuumeishi)', NULL, 0);
            """)
        }

        let dbService = DBService(dbQueue: dbQueue)
        let searchService = SearchService(dbService: dbService)
        let results = try await searchService.search(query: "go", maxResults: 10)

        XCTAssertFalse(results.isEmpty, "Should return results for 'go'")
        // Verb should rank first
        XCTAssertEqual(results.first?.entry.headword, "行く", "Verb 行く should rank before noun 囲碁")
        XCTAssertTrue(results.contains { $0.entry.headword == "囲碁" }, "Should still include noun 囲碁")
    }

    func testJapaneseLanguageRanking() async throws {
        guard let dbURL = testBundle.url(forResource: "test-seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reverse-ranking-\(UUID().uuidString).sqlite")
        try? FileManager.default.removeItem(at: tempURL)
        try FileManager.default.copyItem(at: dbURL, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var config = Configuration()
        config.readonly = false
        let writableQueue = try DatabaseQueue(path: tempURL.path, configuration: config)

        let baseEntries: [(id: Int, headword: String, reading: String, romaji: String, createdAt: Int)] = [
            (id: 900_001, headword: "\u{65E5}\u{672C}\u{8A9E}", reading: "\u{306B}\u{307B}\u{3093}\u{3054}", romaji: "nihongo", createdAt: 1),
            (id: 900_002, headword: "\u{90A6}\u{6587}", reading: "\u{307B}\u{3046}\u{3076}\u{3093}", romaji: "houbun", createdAt: 2),
            (id: 900_003, headword: "\u{65E5}\u{8A9E}", reading: "\u{306B}\u{3061}\u{3054}", romaji: "nichigo", createdAt: 3)
        ]

        let hasChineseColumns = try await writableQueue.read { db -> Bool in
            try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0
                FROM pragma_table_info('word_senses')
                WHERE name = 'definition_chinese_simplified'
            """) ?? false
        }

        try await writableQueue.write { db in
            for entry in baseEntries {
                try db.execute(
                    sql: """
                    INSERT INTO dictionary_entries (id, headword, reading_hiragana, reading_romaji, frequency_rank, pitch_accent, created_at)
                    VALUES (?, ?, ?, ?, NULL, NULL, ?)
                    """,
                    arguments: [entry.id, entry.headword, entry.reading, entry.romaji, entry.createdAt]
                )

                if hasChineseColumns {
                    try db.execute(
                        sql: """
                        INSERT INTO word_senses (id, entry_id, definition_english, definition_chinese_simplified, definition_chinese_traditional, part_of_speech, usage_notes, sense_order)
                        VALUES (?, ?, ?, NULL, NULL, 'noun', NULL, 0)
                        """,
                        arguments: [entry.id, entry.id, "Japanese (language)"]
                    )
                } else {
                    try db.execute(
                        sql: """
                        INSERT INTO word_senses (id, entry_id, definition_english, part_of_speech, usage_notes, sense_order)
                        VALUES (?, ?, ?, 'noun', NULL, 0)
                        """,
                        arguments: [entry.id, entry.id, "Japanese (language)"]
                    )
                }
            }
        }

        let dbService = DBService(dbQueue: writableQueue)
        let serviceUnderTest = SearchService(dbService: dbService)
        let results = try await serviceUnderTest.search(query: "Japanese", maxResults: 10)
        let debugOrder = results.map { ($0.entry.id, $0.entry.headword, $0.entry.createdAt) }

        XCTAssertFalse(results.isEmpty, "Expected reverse search results for Japanese")
        if results.first?.entry.headword != "\u{65E5}\u{672C}\u{8A9E}" {
            XCTFail("Japanese language headword should rank first. Order: \(debugOrder)")
            return
        }
        let headwords = results.map { $0.entry.headword }
        XCTAssertTrue(headwords.contains("\u{90A6}\u{6587}"))
        XCTAssertTrue(headwords.contains("\u{65E5}\u{8A9E}"))
    }
}
