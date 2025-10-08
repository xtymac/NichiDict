// Modules/CoreKit/Sources/CoreKit/DictionaryEntry.swift

import Foundation

public struct DictionaryEntry: Sendable, Hashable {
    public let lemma: String
    public let reading: String
    public let pos: String
    public let glossZH: String

    public init(lemma: String, reading: String, pos: String, glossZH: String) {
        self.lemma = lemma
        self.reading = reading
        self.pos = pos
        self.glossZH = glossZH
    }
}
