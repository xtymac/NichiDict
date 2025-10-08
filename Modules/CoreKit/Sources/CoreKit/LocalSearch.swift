// Modules/CoreKit/Sources/CoreKit/LocalSearch.swift

import Foundation

public enum LocalSearch {
    public static func search(_ text: String) -> [DictionaryEntry] {
        guard !text.isEmpty else { return [] }

        if text == "勉強" {
            return [
                DictionaryEntry(
                    lemma: "勉強",
                    reading: "べんきょう",
                    pos: "名・サ変",
                    glossZH: "學習、用功"
                )
            ]
        }

        // 其他情况返回空数组
        return []
    }
}
