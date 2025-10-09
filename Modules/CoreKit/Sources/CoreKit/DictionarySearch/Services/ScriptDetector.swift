import Foundation

public enum ScriptType {
    case kanji
    case hiragana
    case katakana
    case romaji
    case mixed
}

public struct ScriptDetector {
    public static func detect(_ text: String) -> ScriptType {
        let scalars = text.unicodeScalars
        
        var hasKanji = false
        var hasHiragana = false
        var hasKatakana = false
        var hasRomaji = false
        
        for scalar in scalars {
            switch scalar.value {
            case 0x4E00...0x9FFF:  // CJK Unified Ideographs
                hasKanji = true
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
        
        // Determine dominant script type
        let scriptCount = [hasKanji, hasHiragana, hasKatakana, hasRomaji].filter { $0 }.count
        
        if scriptCount > 1 {
            return .mixed
        } else if hasKanji {
            return .kanji
        } else if hasHiragana {
            return .hiragana
        } else if hasKatakana {
            return .katakana
        } else if hasRomaji {
            return .romaji
        } else {
            return .mixed  // Default for unknown/empty
        }
    }
}
