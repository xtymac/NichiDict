import Foundation
@preconcurrency import GRDB

public struct ExampleSentence: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public let id: Int
    public let senseId: Int
    public let japaneseText: String
    public let englishTranslation: String
    public let chineseTranslation: String?  // 中文翻译（可选）
    public let exampleOrder: Int

    public enum Columns: String, ColumnExpression {
        case id
        case senseId = "sense_id"
        case japaneseText = "japanese_text"
        case englishTranslation = "english_translation"
        case chineseTranslation = "chinese_translation"
        case exampleOrder = "example_order"
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case senseId = "sense_id"
        case japaneseText = "japanese_text"
        case englishTranslation = "english_translation"
        case chineseTranslation = "chinese_translation"
        case exampleOrder = "example_order"
    }

    public static let databaseTableName = "example_sentences"
    public static let wordSense = belongsTo(WordSense.self)

    public init(
        id: Int,
        senseId: Int,
        japaneseText: String,
        englishTranslation: String,
        chineseTranslation: String? = nil,
        exampleOrder: Int
    ) {
        self.id = id
        self.senseId = senseId
        self.japaneseText = japaneseText
        self.englishTranslation = englishTranslation
        self.chineseTranslation = chineseTranslation
        self.exampleOrder = exampleOrder
    }
}
