import Foundation

public actor EnrichmentService {
    public static let shared = EnrichmentService()

    public typealias ExampleGenerator = @Sendable (_ entry: DictionaryEntry,
                                                   _ senses: [WordSense]?,
                                                   _ localeIdentifier: String,
                                                   _ maxExamples: Int,
                                                   _ useCache: Bool) async throws -> [LLMExample]

    private let exampleGenerator: ExampleGenerator
    private var memoryExamples: [Int: [LLMExample]] = [:]

    public init(generator: ExampleGenerator? = nil) {
        if let generator {
            self.exampleGenerator = generator
        } else {
            self.exampleGenerator = { entry, senses, locale, maxExamples, useCache in
                try await Task { @MainActor in
                    try await LLMClient.shared.generateExamples(
                        for: entry,
                        senses: senses,
                        locale: locale,
                        maxExamples: maxExamples,
                        useCache: useCache
                    )
                }.value
            }
        }
    }

    public func examples(for entry: DictionaryEntry,
                         maxExamples: Int = 3,
                         forceRefresh: Bool = false,
                         locale: Locale = .current) async throws -> [LLMExample] {
        if !forceRefresh, let cached = memoryExamples[entry.id], !cached.isEmpty {
            return cached
        }

        let generated = try await exampleGenerator(
            entry,
            entry.senses,
            locale.identifier,
            maxExamples,
            !forceRefresh
        )

        memoryExamples[entry.id] = generated
        return generated
    }

    public func clearCache() {
        memoryExamples.removeAll()
    }
}
