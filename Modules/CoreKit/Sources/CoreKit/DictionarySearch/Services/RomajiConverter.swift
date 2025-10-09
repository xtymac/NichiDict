import Foundation

public struct RomajiConverter {
    // Hepburn romanization table (basic subset)
    private static let kanaToRomaji: [String: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "wo", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "っ": ""  // Small tsu (gemination)
    ]
    
    // Kunrei-shiki to Hepburn normalization
    private static let kunreiToHepburn: [String: String] = [
        "si": "shi", "ti": "chi", "tu": "tsu", "hu": "fu",
        "zi": "ji", "di": "ji", "du": "zu"
    ]
    
    /// Convert hiragana to Hepburn romaji
    public static func toRomaji(_ kana: String) -> String {
        var result = ""
        var index = kana.startIndex

        while index < kana.endIndex {
            let char = String(kana[index])

            // Handle small tsu (gemination) - double the next consonant
            if char == "っ" {
                // Look ahead to next character
                let nextIndex = kana.index(after: index)
                if nextIndex < kana.endIndex {
                    let nextChar = String(kana[nextIndex])
                    if let nextRomaji = kanaToRomaji[nextChar], !nextRomaji.isEmpty {
                        // Double the first consonant
                        result += String(nextRomaji.first!)
                    }
                }
            } else {
                result += kanaToRomaji[char] ?? char
            }

            index = kana.index(after: index)
        }

        return result
    }
    
    /// Normalize Kunrei-shiki input to Hepburn for search
    public static func normalizeForSearch(_ input: String) -> String {
        var normalized = input.lowercased()
        
        // Replace Kunrei-shiki with Hepburn
        for (kunrei, hepburn) in kunreiToHepburn {
            normalized = normalized.replacingOccurrences(of: kunrei, with: hepburn)
        }
        
        // Normalize long vowels (oo -> ou, etc.)
        normalized = normalized.replacingOccurrences(of: "oo", with: "ou")
        
        return normalized
    }
}
