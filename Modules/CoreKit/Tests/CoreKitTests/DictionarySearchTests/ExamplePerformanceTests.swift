import Foundation
import XCTest
@preconcurrency import GRDB
@testable import CoreKit

/// 测试例句生成性能
/// Tests the performance of example sentence generation
final class ExamplePerformanceTests: XCTestCase {
    var searchService: SearchService!
    var dbQueue: DatabaseQueue!

    override func setUp() async throws {
        try await super.setUp()

        guard let dbURL = Bundle.module.url(forResource: "seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }

        dbQueue = try DatabaseManager.testQueue(at: dbURL.path)
        let dbService = DBService(dbQueue: dbQueue)
        searchService = SearchService(dbService: dbService)
    }

    override func tearDown() async throws {
        searchService = nil
        dbQueue = nil
        try await super.tearDown()
    }

    // MARK: - 覆盖率测试

    func testTop1000Coverage() async throws {
        // 测试 Top 1000 词条的例句覆盖率
        let count = try await dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT e.id)
                FROM dictionary_entries e
                JOIN word_senses ws ON e.id = ws.entry_id
                JOIN example_sentences ex ON ws.id = ex.sense_id
                WHERE e.id <= 1000
            """) ?? 0
        }

        print("📊 Top 1000 词条中有例句: \(count) 个")
        XCTAssertGreaterThan(count, 900, "至少 90% 的 Top 1000 词条应该有例句")
    }

    // MARK: - 质量测试

    func testExampleQuality() async throws {
        // 测试常用词的例句质量
        let testWords = ["お金", "お母さん", "お茶"]

        for word in testWords {
            let results = try await searchService.search(query: word, maxResults: 10)

            XCTAssertFalse(results.isEmpty, "\(word) 应该有搜索结果")

            if let firstResult = results.first {
                let entry = firstResult.entry
                XCTAssertFalse(entry.senses.isEmpty, "\(word) 应该有义项")

                let hasExamples = entry.senses.contains { !$0.examples.isEmpty }
                print("📖 \(word): \(hasExamples ? "✅ 有例句" : "⚠️ 无例句")")

                if hasExamples {
                    // 检查例句格式
                    for sense in entry.senses {
                        for example in sense.examples {
                            XCTAssertFalse(example.japaneseText.isEmpty, "日语例句不应为空")
                            XCTAssertFalse(example.englishTranslation.isEmpty, "英语翻译不应为空")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 性能测试

    func testSearchPerformanceWithExamples() async throws {
        // 测试有例句词条的查询性能
        let wordsWithExamples = ["お金", "お母さん", "お茶"]

        let startTime = Date()

        for word in wordsWithExamples {
            _ = try await searchService.search(query: word, maxResults: 10)
        }

        let duration = Date().timeIntervalSince(startTime)
        let avgTime = duration / Double(wordsWithExamples.count)

        print("⚡ 平均查询时间 (有例句): \(String(format: "%.0fms", avgTime * 1000))")
        XCTAssertLessThan(avgTime, 0.5, "查询应该在 500ms 内完成")
    }

    func testBatchExampleRetrieval() async throws {
        // 测试批量例句检索
        struct ExampleRow: Decodable, FetchableRecord {
            let headword: String
            let japanese_text: String
            let english_translation: String
        }

        let examples = try await dbQueue.read { db in
            try ExampleRow.fetchAll(db, sql: """
                SELECT
                    e.headword,
                    ex.japanese_text,
                    ex.english_translation
                FROM dictionary_entries e
                JOIN word_senses ws ON e.id = ws.entry_id
                JOIN example_sentences ex ON ws.id = ex.sense_id
                WHERE e.id <= 100
                LIMIT 50
            """)
        }

        print("📦 批量检索例句数: \(examples.count)")
        XCTAssertGreaterThan(examples.count, 10, "应该能检索到一些例句")

        // 检查例句质量
        for example in examples.prefix(5) {
            print("   • \(example.japanese_text)")
            XCTAssertFalse(example.japanese_text.isEmpty)
            XCTAssertFalse(example.english_translation.isEmpty)
        }
    }

    // MARK: - 统计测试

    func testExampleStatistics() async throws {
        // 生成例句统计报告
        let (entriesWithExamples, totalExamples) = try await dbQueue.read { db in
            let entries = try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT e.id)
                FROM dictionary_entries e
                JOIN word_senses ws ON e.id = ws.entry_id
                JOIN example_sentences ex ON ws.id = ex.sense_id
                WHERE e.id <= 1000
            """) ?? 0

            let total = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM example_sentences ex
                JOIN word_senses ws ON ex.sense_id = ws.id
                JOIN dictionary_entries e ON ws.entry_id = e.id
                WHERE e.id <= 1000
            """) ?? 0

            return (entries, total)
        }

        let avgPerEntry = entriesWithExamples > 0 ? Double(totalExamples) / Double(entriesWithExamples) : 0

        print("\n📊 例句统计 (Top 1000):")
        print("   词条数: \(entriesWithExamples)")
        print("   例句总数: \(totalExamples)")
        print("   平均每词: \(String(format: "%.1f", avgPerEntry)) 个")

        XCTAssertGreaterThan(entriesWithExamples, 900, "应该有超过 900 个词条有例句")
        XCTAssertGreaterThan(totalExamples, 2700, "应该有超过 2700 个例句")
    }
}
