import Foundation

extension String {
    /// Convert katakana to hiragana
    /// データ → でーた
    func katakanaToHiragana() -> String {
        return self.map { char -> Character in
            guard let scalar = char.unicodeScalars.first else { return char }
            let value = scalar.value

            // Katakana range: U+30A1 to U+30F6
            // Hiragana range: U+3041 to U+3096
            // Offset: 0x60
            if value >= 0x30A1 && value <= 0x30F6 {
                if let hiraganaScalar = UnicodeScalar(value - 0x60) {
                    return Character(hiraganaScalar)
                }
            }

            return char
        }.map { String($0) }.joined()
    }
}
