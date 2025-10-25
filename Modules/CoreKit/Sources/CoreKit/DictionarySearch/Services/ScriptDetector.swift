import Foundation

public enum ScriptType: Sendable {
    case kanji           // Pure kanji (likely Chinese input)
    case hiragana        // Pure hiragana (Japanese)
    case katakana        // Pure katakana (Japanese)
    case romaji          // Latin alphabet (could be romaji or English)
    case mixed           // Mixed scripts (Japanese with kanji+kana)
    case japaneseKanji   // Kanji that's likely Japanese (based on context)
}

public struct ScriptDetector {
    public static func detect(_ text: String) -> ScriptType {
        let scalars = text.unicodeScalars

        var hasKanji = false
        var hasHiragana = false
        var hasKatakana = false
        var hasRomaji = false
        var kanjiCount = 0

        for scalar in scalars {
            switch scalar.value {
            case 0x4E00...0x9FFF:  // CJK Unified Ideographs
                hasKanji = true
                kanjiCount += 1
            case 0x3040...0x309F:  // Hiragana
                hasHiragana = true
            case 0x30A0...0x30FF:  // Katakana
                hasKatakana = true
            case 0x0041...0x005A,  // A-Z
                 0x0061...0x007A:  // a-z
                hasRomaji = true
            default:
                break
            }
        }

        // Mixed kanji + kana = definitely Japanese
        if hasKanji && (hasHiragana || hasKatakana) {
            return .mixed
        }

        // Pure romaji (no CJK characters)
        if hasRomaji && !hasKanji && !hasHiragana && !hasKatakana {
            return .romaji
        }

        // Pure hiragana = Japanese
        if hasHiragana && !hasKanji && !hasKatakana && !hasRomaji {
            return .hiragana
        }

        // Pure katakana = Japanese
        if hasKatakana && !hasKanji && !hasHiragana && !hasRomaji {
            return .katakana
        }

        // Pure kanji - need to distinguish Japanese kanji words vs Chinese
        if hasKanji && !hasHiragana && !hasKatakana && !hasRomaji {
            // Short kanji words (1-3 characters) are more likely Japanese vocabulary
            // Common Japanese words: 行く(2), 見る(2), 食べる(3), 飲む(2)
            // Longer pure kanji (4+) more likely Chinese input
            if kanjiCount <= 3 {
                return .japaneseKanji  // Likely Japanese kanji word
            } else {
                return .kanji  // Likely Chinese input
            }
        }

        return .mixed  // Default for unknown/empty
    }
}
