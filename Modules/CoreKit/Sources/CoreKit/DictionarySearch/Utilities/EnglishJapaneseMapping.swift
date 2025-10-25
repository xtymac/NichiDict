import Foundation

/// Mapping of common English words to their canonical native Japanese equivalents
/// Used to prioritize native Japanese terms over katakana loanwords in reverse search
public struct EnglishJapaneseMapping {

    /// Core mappings: English word → canonical Japanese headword
    /// These represent the most "dictionary-standard" Japanese equivalents
    private static let coreNativeMap: [String: Set<String>] = [
        // Celestial & nature
        "star": ["星", "恒星"],
        "moon": ["月"],
        "sun": ["太陽", "日"],
        "sky": ["空"],
        "earth": ["地球", "土"],

        // Common verbs
        "go": ["行く", "往く"],
        "come": ["来る"],
        "eat": ["食べる", "食う"],
        "drink": ["飲む"],
        "see": ["見る"],
        "look": ["見る", "観る"],
        "hear": ["聞く"],
        "speak": ["話す"],
        "say": ["言う"],
        "think": ["思う", "考える"],
        "know": ["知る"],
        "do": ["する", "やる"],
        "make": ["作る", "造る"],
        "give": ["与える", "あげる"],
        "take": ["取る"],
        "walk": ["歩く"],
        "run": ["走る"],
        "read": ["読む"],
        "write": ["書く"],

        // People & roles
        "actor": ["俳優"],
        "actress": ["女優"],
        "person": ["人", "者"],
        "student": ["学生"],
        "teacher": ["教師", "先生"],

        // Language & communication
        "language": ["言語", "語"],
        "word": ["言葉", "単語"],
        "sentence": ["文", "文章"],

        // Abstract concepts
        "love": ["愛"],
        "life": ["生活", "人生"],
        "death": ["死"],
        "time": ["時間"],
        "day": ["日", "昼"],
        "night": ["夜"],

        // Common nouns
        "water": ["水"],
        "fire": ["火"],
        "wind": ["風"],
        "mountain": ["山"],
        "river": ["川"],
        "sea": ["海"],
        "tree": ["木"],
        "flower": ["花"],
        "book": ["本"],
        "house": ["家"],
        "room": ["部屋"],
        "door": ["戸", "扉"],
        "window": ["窓"],
        "hand": ["手"],
        "foot": ["足"],
        "head": ["頭"],
        "eye": ["目"],
        "ear": ["耳"],
        "mouth": ["口"],
    ]

    /// Semantic hints extracted from parenthetical queries
    /// Example: "japanese (language)" → hint = "language"
    public static func extractSemanticHint(from query: String) -> String? {
        // Match pattern: word (hint)
        let pattern = #"\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) else {
            return nil
        }

        if let range = Range(match.range(at: 1), in: query) {
            return String(query[range]).lowercased().trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Extract the base word from a query (removing parenthetical hints)
    /// Example: "japanese (language)" → "japanese"
    public static func extractBaseWord(from query: String) -> String {
        // Remove anything in parentheses and surrounding whitespace
        let pattern = #"\s*\([^)]*\)\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return query
        }

        let range = NSRange(query.startIndex..., in: query)
        let result = regex.stringByReplacingMatches(in: query, range: range, withTemplate: "")
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Check if a given Japanese headword is a core native equivalent for an English query
    public static func isCoreNativeEquivalent(headword: String, forEnglishWord englishWord: String) -> Bool {
        let lowerEnglish = englishWord.lowercased()
        guard let canonicalHeadwords = coreNativeMap[lowerEnglish] else {
            return false
        }
        return canonicalHeadwords.contains(headword)
    }

    /// Get canonical native Japanese headwords for an English word
    public static func canonicalHeadwords(forEnglishWord englishWord: String) -> Set<String>? {
        return coreNativeMap[englishWord.lowercased()]
    }

    /// Check if query contains parenthetical semantic hint
    public static func hasParenthetical(_ query: String) -> Bool {
        return query.contains("(") && query.contains(")")
    }
}
