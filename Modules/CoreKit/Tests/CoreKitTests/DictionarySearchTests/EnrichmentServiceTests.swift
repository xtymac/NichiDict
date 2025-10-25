import Foundation
import XCTest
@testable import CoreKit

final class EnrichmentServiceTests: XCTestCase {
    func testExamplesAreCachedInMemory() async throws {
        let provider = StubExampleGenerator()
        let service = EnrichmentService { entry, _, _, _, _ in
            try await provider.generate(for: entry)
        }
        let entry = sampleEntry()

        let first = try await service.examples(for: entry, maxExamples: 2, forceRefresh: false, locale: Locale(identifier: "zh-Hans"))
        let second = try await service.examples(for: entry, maxExamples: 2, forceRefresh: false, locale: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(first, second)
        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testForceRefreshBypassesCache() async throws {
        let provider = StubExampleGenerator()
        let service = EnrichmentService { entry, _, _, _, _ in
            try await provider.generate(for: entry)
        }
        let entry = sampleEntry()

        _ = try await service.examples(for: entry)
        _ = try await service.examples(for: entry, forceRefresh: true)

        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 2)
    }

    private func sampleEntry() -> DictionaryEntry {
        let sense = WordSense(
            id: 1,
            entryId: 1,
            definitionEnglish: "to go",
            definitionChineseSimplified: "去",
            definitionChineseTraditional: "去",
            partOfSpeech: "verb",
            usageNotes: nil,
            senseOrder: 0
        )

        return DictionaryEntry(
            id: 1,
            headword: "行く",
            readingHiragana: "いく",
            readingRomaji: "iku",
            frequencyRank: nil,
            pitchAccent: nil,
            createdAt: 0,
            senses: [sense]
        )
    }
}

private actor StubExampleGenerator {
    private(set) var callCount = 0

    func generate(for entry: DictionaryEntry) async throws -> [LLMExample] {
        callCount += 1
        return [
            LLMExample(japanese: "\(entry.headword)に行く。", chinese: "去\(entry.headword)", english: "go to \(entry.headword)")
        ]
    }
}
