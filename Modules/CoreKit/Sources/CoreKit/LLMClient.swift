//
//  LLMClient.swift
//  CoreKit
//
//  Created by Mac on 2025/10/06.
//

import Foundation
import CryptoKit

// MARK: - 公共模型：AI 返回结构（词典格式）
public struct LLMDictEntry: Codable, Hashable {
    public let headword: String           // 見出し語（日语词条）
    public let reading: String            // 読み（假名）
    public let romaji: String?            // ローマ字（Hepburn）
    public let partOfSpeech: String       // 品詞（動詞・名詞・形容動詞 等）
    public let accent: String?            // アクセント（音调）
    public let senses: [LLMSense]         // 義項（最多3条）
    public let grammar: LLMGrammar?       // 文法・用法
    public let examples: [LLMExample]?    // 用例（可选）
    public let related: LLMRelated?       // 関連語

    public init(headword: String, reading: String, romaji: String?, partOfSpeech: String,
                accent: String?, senses: [LLMSense], grammar: LLMGrammar?,
                examples: [LLMExample]?, related: LLMRelated?) {
        self.headword = headword
        self.reading = reading
        self.romaji = romaji
        self.partOfSpeech = partOfSpeech
        self.accent = accent
        self.senses = senses
        self.grammar = grammar
        self.examples = examples
        self.related = related
    }
}

public struct LLMSense: Codable, Hashable {
    public let definition: String    // 日语释义
    public let chinese: String       // 中文译文
    public let english: String       // 英文译文

    public init(definition: String, chinese: String, english: String) {
        self.definition = definition
        self.chinese = chinese
        self.english = english
    }
}

public struct LLMGrammar: Codable, Hashable {
    public let conjugation: [String]?  // 活用形式
    public let collocation: [String]?  // 常见搭配
    public let honorific: String?      // 敬语形式

    public init(conjugation: [String]?, collocation: [String]?, honorific: String?) {
        self.conjugation = conjugation
        self.collocation = collocation
        self.honorific = honorific
    }
}

public struct LLMRelated: Codable, Hashable {
    public let synonym: String?    // 类义词
    public let antonym: String?    // 反义词
    public let derived: String?    // 派生词

    public init(synonym: String?, antonym: String?, derived: String?) {
        self.synonym = synonym
        self.antonym = antonym
        self.derived = derived
    }
}

public struct LLMExample: Codable, Hashable {
    public let japanese: String    // 日语例句
    public let chinese: String     // 中文翻译
    public let english: String     // 英文翻译

    public init(japanese: String, chinese: String, english: String) {
        self.japanese = japanese
        self.chinese = chinese
        self.english = english
    }
}

// 查询结果类型
public enum LLMQueryType: String, Codable {
    case word           // 单词查询
    case sentence       // 句子解析
    case notFound       // 未收录
}

public struct LLMResult: Codable, Hashable {
    public let queryType: LLMQueryType        // 查询类型
    public let entries: [LLMDictEntry]        // 词条（最多top_k个）
    public let sentenceAnalysis: LLMSentenceAnalysis?  // 句子解析（仅句子查询）

    public init(queryType: LLMQueryType, entries: [LLMDictEntry], sentenceAnalysis: LLMSentenceAnalysis?) {
        self.queryType = queryType
        self.entries = entries
        self.sentenceAnalysis = sentenceAnalysis
    }
}

public struct LLMSentenceAnalysis: Codable, Hashable {
    public let original: String                    // 原句
    public let translation: LLMTranslation         // 翻译（中英）
    public let wordBreakdown: [LLMWordBreakdown]   // 逐词解析
    public let grammarPoints: [LLMGrammarPoint]    // 语法点

    public init(original: String, translation: LLMTranslation,
                wordBreakdown: [LLMWordBreakdown], grammarPoints: [LLMGrammarPoint]) {
        self.original = original
        self.translation = translation
        self.wordBreakdown = wordBreakdown
        self.grammarPoints = grammarPoints
    }
}

public struct LLMTranslation: Codable, Hashable {
    public let chinese: String    // 中文翻译
    public let english: String    // 英文翻译

    public init(chinese: String, english: String) {
        self.chinese = chinese
        self.english = english
    }
}

public struct LLMWordBreakdown: Codable, Hashable {
    public let word: String            // 词
    public let reading: String         // 读音
    public let meaning: String         // 词义
    public let grammaticalRole: String // 语法作用

    public init(word: String, reading: String, meaning: String, grammaticalRole: String) {
        self.word = word
        self.reading = reading
        self.meaning = meaning
        self.grammaticalRole = grammaticalRole
    }
}

public struct LLMGrammarPoint: Codable, Hashable {
    public let pattern: String         // 文法模式
    public let reading: String         // 读音
    public let meaning: String         // 含义
    public let explanation: String     // 详细说明

    public init(pattern: String, reading: String, meaning: String, explanation: String) {
        self.pattern = pattern
        self.reading = reading
        self.meaning = meaning
        self.explanation = explanation
    }
}

// MARK: - Provider 定義
public enum LLMProvider {
    case openAI(model: String)      // 例: "gpt-4o-mini" / "gpt-4.1-mini"
    case anthropic(model: String)   // 例: "claude-3-haiku"
    // 需要可再擴: case google(model: String)
}

// MARK: - 錯誤
public enum LLMError: Error, LocalizedError {
    case notConfigured
    case emptyResponse
    case httpError(Int, String)
    case decodeFailed(String)
    case quotaExceeded

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "LLM 尚未配置 API Key / Provider"
        case .emptyResponse: return "LLM 空回應"
        case .httpError(let code, let msg): return "LLM 請求錯誤 (\(code)): \(msg)"
        case .decodeFailed(let msg): return "解析失敗: \(msg)"
        case .quotaExceeded: return "今日 AI 次數已用完"
        }
    }
}

// MARK: - 客戶端
@MainActor
public final class LLMClient {

    public static let shared = LLMClient()

    private init() {}

    private var apiKey: String?
    private var provider: LLMProvider?

    // 簡單配額控制（試用期保護）
    private let dailyLimitKey = "ai_daily_limit"
    private let dailyDateKey  = "ai_daily_date"

    // 內存 + 磁盤緩存
    private let memCache = NSCache<NSString, NSData>()
    private lazy var diskCacheDir: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LLMCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: 配置
    public func configure(apiKey: String, provider: LLMProvider) {
        self.apiKey = apiKey
        self.provider = provider
    }

    // 可選：調整每日上限（默認 50 次）
    public var dailyLimit: Int = 50

    // MARK: 對外主方法
    @discardableResult
    public func translateExplain(sentence: String,
                                 locale: String = "zh",
                                 useCache: Bool = true) async throws -> LLMResult {

        guard let _ = apiKey, let provider = provider else {
            throw LLMError.notConfigured
        }

        // 命中快取
        let key = cacheKey(sentence: sentence, provider: provider, locale: locale)
        if useCache, let cached: LLMResult = loadCache(for: key) {
            return cached
        }

        // 配額判斷
        try checkDailyQuota()

        // 組裝提示（要求返回 JSON）
        let prompt = buildPrompt(sentence: sentence, locale: locale)

        // 發送請求
        let result: LLMResult
        switch provider {
        case .openAI(let model):
            result = try await requestOpenAI(model: model, prompt: prompt)
        case .anthropic(let model):
            result = try await requestAnthropic(model: model, prompt: prompt)
        }

        // 寫入快取 + 計數
        saveCache(result, for: key)
        increaseDailyCount()

        return result
    }

    // MARK: Prompt
    private func buildPrompt(sentence: String, locale: String) -> String {
        // Note: locale parameter available for future use if needed for localized prompts
        _ = locale

        return """
        You are a professional Japanese dictionary system. Map user input (Chinese/English/Japanese) to the most appropriate Japanese dictionary entries.

        CRITICAL: You MUST return valid JSON that EXACTLY matches the schema below. Do not add any text before or after the JSON.

        ## Step 1: Determine Query Type
        - If input contains periods/question marks/exclamation marks OR has many spaces OR length>12 with multiple word forms → queryType: "sentence"
        - Otherwise → queryType: "word"
        - If cannot identify → queryType: "notFound"

        ## Step 2: Response Rules
        - Primary language: Japanese definitions
        - Provide short Chinese (Simplified) and English translations
        - No redundancy: merge same meanings/POS/definitions
        - Max 3 senses per entry, 2-3 examples
        - Use「(推定)」for uncertain information
        - For Chinese/English input (e.g., "noon", "eat"), map to Japanese entries (e.g., 「正午」「昼」「食べる」「食う」)

        ## Step 3: JSON Schema - Word Mode (MUST FOLLOW EXACTLY)
        {
          "queryType": "word",
          "entries": [
            {
              "headword": "食べる",
              "reading": "たべる",
              "romaji": "taberu",
              "partOfSpeech": "一段動詞・他動",
              "accent": "たべ↘る［1］",
              "senses": [
                {
                  "definition": "口に入れて噛み、飲み込む",
                  "chinese": "吃；进食",
                  "english": "to eat"
                },
                {
                  "definition": "資源や時間を大量に消費する",
                  "chinese": "耗费",
                  "english": "to consume"
                }
              ],
              "grammar": {
                "conjugation": ["食べます", "食べない", "食べた", "食べて"],
                "collocation": ["を食べる", "外で食べる", "偏食をする"],
                "honorific": "召し上がる（尊敬）、いただく（謙譲）"
              },
              "examples": [
                {
                  "japanese": "朝ごはんを食べる。",
                  "chinese": "我吃早饭。",
                  "english": "I eat breakfast."
                }
              ],
              "related": {
                "synonym": "喫する（書）／いただく（謙）",
                "antonym": "断食する",
                "derived": null
              }
            }
          ]
        }

        ## 4) 句子解析模式 JSON 结构
        {
          "queryType": "sentence",
          "sentenceAnalysis": {
            "original": "今日は雨が降りそうです。",
            "translation": {
              "chinese": "今天好像要下雨。",
              "english": "It looks like it will rain today."
            },
            "wordBreakdown": [
              {
                "word": "今日",
                "reading": "きょう",
                "meaning": "今天",
                "grammaticalRole": "時間名詞"
              },
              {
                "word": "は",
                "reading": "は",
                "meaning": "（主题标记）",
                "grammaticalRole": "係助詞"
              }
            ],
            "grammarPoints": [
              {
                "pattern": "そうです",
                "reading": "そうです",
                "meaning": "样态推测",
                "explanation": "表示根据外观或样子进行推测"
              }
            ]
          }
        }

        ## 5) 未収録模式 JSON 结构
        {
          "queryType": "notFound",
          "entries": [
            {
              "headword": "{输入原样}",
              "reading": "(推定)",
              "romaji": null,
              "partOfSpeech": "未収録語",
              "senses": [
                {
                  "definition": "語種：{和語/漢語/外来語(推定)}",
                  "chinese": "未收录",
                  "english": "Not found"
                }
              ],
              "examples": [],
              "related": {
                "synonym": "{近义候选1／候选2}",
                "antonym": null,
                "derived": null
              }
            }
          ]
        }

        ## MANDATORY REQUIREMENTS
        ⚠️ CRITICAL - Your response MUST be valid JSON ONLY. No explanations, no markdown, no prefix/suffix.
        ⚠️ CRITICAL - ALL fields marked as required MUST be present. Use null for optional fields if empty.
        ⚠️ CRITICAL - Field names must match EXACTLY (case-sensitive): "headword", "reading", "romaji", "partOfSpeech", "accent", "senses", "grammar", "examples", "related"

        Quality Rules:
        - Forbidden: duplicate senses, empty definitions, kanji variants only, verbose explanations
        - Required: Each sense has Japanese definition + Chinese + English translation; natural, common examples
        - For multiple candidates: sort by modern usage frequency (common > literary > dialect), max 3 entries
        - sentenceAnalysis field is REQUIRED when queryType is "sentence", but should be null for "word" or "notFound"
        - entries field is REQUIRED for all queryType values

        EXAMPLE 1 - Word Query "go":
        {
          "queryType": "word",
          "entries": [
            {
              "headword": "行く",
              "reading": "いく",
              "romaji": "iku",
              "partOfSpeech": "五段動詞・自動",
              "accent": "い↗く［0］",
              "senses": [
                {
                  "definition": "ある場所から別の場所へ移動する",
                  "chinese": "去；前往",
                  "english": "to go"
                }
              ],
              "grammar": {
                "conjugation": ["行きます", "行かない", "行った", "行って"],
                "collocation": ["へ行く", "に行く", "学校に行く"],
                "honorific": "いらっしゃる（尊敬）、参る（謙譲）"
              },
              "examples": [
                {
                  "japanese": "学校に行く。",
                  "chinese": "去学校。",
                  "english": "I go to school."
                }
              ],
              "related": {
                "synonym": "参る／いらっしゃる",
                "antonym": "来る",
                "derived": null
              }
            }
          ],
          "sentenceAnalysis": null
        }

        EXAMPLE 2 - Sentence Query:
        {
          "queryType": "sentence",
          "entries": [],
          "sentenceAnalysis": {
            "original": "今日は雨が降りそうです。",
            "translation": {
              "chinese": "今天好像要下雨。",
              "english": "It looks like it will rain today."
            },
            "wordBreakdown": [
              {
                "word": "今日",
                "reading": "きょう",
                "meaning": "今天",
                "grammaticalRole": "時間名詞"
              }
            ],
            "grammarPoints": [
              {
                "pattern": "そうです",
                "reading": "そうです",
                "meaning": "样态推测",
                "explanation": "表示根据外观或样子进行推测"
              }
            ]
          }
        }

        User Query: \(sentence)

        Response (JSON only, no other text):
        """
    }

    // MARK: OpenAI 請求
    private func requestOpenAI(model: String, prompt: String) async throws -> LLMResult {
        guard let apiKey = apiKey else { throw LLMError.notConfigured }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // 要求 JSON 輸出，降低字數
        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": "Return JSON only. No prose."],
                ["role": "user", "content": prompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LLMError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(http.statusCode, msg)
        }

        // 解析 OpenAI 回傳
        struct Choice: Decodable { let message: Msg }
        struct Msg: Decodable { let content: String }
        struct OpenAIResp: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(OpenAIResp.self, from: data)
        guard let content = decoded.choices.first?.message.content.data(using: .utf8) else {
            throw LLMError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(LLMResult.self, from: content)
        } catch let primaryError {
            // Log the actual response for debugging
            let responseText = String(data: content, encoding: .utf8) ?? "Unable to decode response"
            print("⚠️ Primary JSON Decode Failed. Attempting fallback parsing...")
            print("📄 Response was: \(responseText)")
            print("❌ Error: \(primaryError)")

            // FALLBACK: Try to parse partial/malformed JSON
            if let fallbackResult = tryFallbackParsing(content: content, originalQuery: prompt) {
                print("✅ Fallback parsing succeeded")
                return fallbackResult
            }

            throw LLMError.decodeFailed("AI返回格式错误。\n原始响应: \(responseText.prefix(200))...\n错误: \(primaryError.localizedDescription)")
        }
    }

    // MARK: Anthropic 請求（Claude）
    private func requestAnthropic(model: String, prompt: String) async throws -> LLMResult {
        guard let apiKey = apiKey else { throw LLMError.notConfigured }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 512,
            "temperature": 0.2,
            "messages": [
                ["role": "user", "content": [
                    ["type":"text", "text":"請只輸出 JSON。\n\(prompt)"]
                ]]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LLMError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(http.statusCode, msg)
        }

        // 解析 Claude 回傳
        struct Block: Decodable { let text: String? }
        struct Message: Decodable { let content: [Block] }
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        let jsonText = decoded.content.compactMap { $0.text }.joined()
        guard let jsonData = jsonText.data(using: .utf8) else { throw LLMError.emptyResponse }

        do {
            return try JSONDecoder().decode(LLMResult.self, from: jsonData)
        } catch let primaryError {
            // Log the actual response for debugging
            let responseText = String(data: jsonData, encoding: .utf8) ?? "Unable to decode response"
            print("⚠️ Primary JSON Decode Failed (Anthropic). Attempting fallback parsing...")
            print("📄 Response was: \(responseText)")
            print("❌ Error: \(primaryError)")

            // FALLBACK: Try to parse partial/malformed JSON
            if let fallbackResult = tryFallbackParsing(content: jsonData, originalQuery: prompt) {
                print("✅ Fallback parsing succeeded")
                return fallbackResult
            }

            throw LLMError.decodeFailed("AI返回格式错误 (Anthropic)。\n原始响应: \(responseText.prefix(200))...\n错误: \(primaryError.localizedDescription)")
        }
    }

    // MARK: Fallback Parsing
    /// Attempt to parse partial or malformed JSON responses
    private func tryFallbackParsing(content: Data, originalQuery: String) -> LLMResult? {
        guard String(data: content, encoding: .utf8) != nil else {
            return nil
        }

        // Try to parse as generic JSON first
        guard let jsonObj = try? JSONSerialization.jsonObject(with: content) as? [String: Any] else {
            return nil
        }

        // Extract queryType
        guard let queryTypeStr = jsonObj["queryType"] as? String,
              let queryType = LLMQueryType(rawValue: queryTypeStr) else {
            // No valid queryType - create a minimal notFound result
            return createMinimalNotFoundResult(query: originalQuery)
        }

        switch queryType {
        case .word, .notFound:
            // Try to extract entries
            if let entriesArray = jsonObj["entries"] as? [[String: Any]] {
                let parsedEntries = entriesArray.compactMap { entryDict -> LLMDictEntry? in
                    return parseEntryDict(entryDict)
                }

                if !parsedEntries.isEmpty {
                    return LLMResult(
                        queryType: queryType,
                        entries: parsedEntries,
                        sentenceAnalysis: nil
                    )
                }
            }

            // Fallback: create minimal entry
            return createMinimalNotFoundResult(query: originalQuery)

        case .sentence:
            // For sentence analysis, require proper structure
            // Don't fallback for sentences - they're too complex
            return nil
        }
    }

    /// Create a minimal "not found" result when parsing fails
    private func createMinimalNotFoundResult(query: String) -> LLMResult {
        let minimalEntry = LLMDictEntry(
            headword: query,
            reading: "(推定)",
            romaji: nil,
            partOfSpeech: "未収録語",
            accent: nil,
            senses: [
                LLMSense(
                    definition: "辞書に収録されていない語",
                    chinese: "词典中未收录",
                    english: "Not found in dictionary"
                )
            ],
            grammar: nil,
            examples: nil,
            related: nil
        )

        return LLMResult(
            queryType: .notFound,
            entries: [minimalEntry],
            sentenceAnalysis: nil
        )
    }

    /// Parse a single entry dictionary with lenient field checking
    private func parseEntryDict(_ dict: [String: Any]) -> LLMDictEntry? {
        // Required fields with defaults
        guard let headword = dict["headword"] as? String else { return nil }

        let reading = dict["reading"] as? String ?? "(不明)"
        let romaji = dict["romaji"] as? String
        let partOfSpeech = dict["partOfSpeech"] as? String ?? "未分類"
        let accent = dict["accent"] as? String

        // Parse senses (required, at least one)
        var senses: [LLMSense] = []
        if let sensesArray = dict["senses"] as? [[String: Any]] {
            senses = sensesArray.compactMap { senseDict in
                guard let definition = senseDict["definition"] as? String,
                      let chinese = senseDict["chinese"] as? String,
                      let english = senseDict["english"] as? String else {
                    return nil
                }
                return LLMSense(definition: definition, chinese: chinese, english: english)
            }
        }

        // If no valid senses, use default
        if senses.isEmpty {
            senses = [LLMSense(
                definition: "定義なし",
                chinese: "无定义",
                english: "No definition available"
            )]
        }

        // Parse optional grammar
        var grammar: LLMGrammar? = nil
        if let grammarDict = dict["grammar"] as? [String: Any] {
            grammar = LLMGrammar(
                conjugation: grammarDict["conjugation"] as? [String],
                collocation: grammarDict["collocation"] as? [String],
                honorific: grammarDict["honorific"] as? String
            )
        }

        // Parse optional examples
        var examples: [LLMExample]? = nil
        if let examplesArray = dict["examples"] as? [[String: Any]] {
            let parsedExamples = examplesArray.compactMap { exDict -> LLMExample? in
                guard let jp = exDict["japanese"] as? String,
                      let cn = exDict["chinese"] as? String,
                      let en = exDict["english"] as? String else {
                    return nil
                }
                return LLMExample(japanese: jp, chinese: cn, english: en)
            }
            examples = parsedExamples.isEmpty ? nil : parsedExamples
        }

        // Parse optional related
        var related: LLMRelated? = nil
        if let relatedDict = dict["related"] as? [String: Any] {
            related = LLMRelated(
                synonym: relatedDict["synonym"] as? String,
                antonym: relatedDict["antonym"] as? String,
                derived: relatedDict["derived"] as? String
            )
        }

        return LLMDictEntry(
            headword: headword,
            reading: reading,
            romaji: romaji,
            partOfSpeech: partOfSpeech,
            accent: accent,
            senses: senses,
            grammar: grammar,
            examples: examples,
            related: related
        )
    }

    // MARK: 簡易配額
    private func checkDailyQuota() throws {
        let today = Self.dayString(Date())
        let defaults = UserDefaults.standard
        if defaults.string(forKey: dailyDateKey) != today {
            defaults.set(today, forKey: dailyDateKey)
            defaults.set(0, forKey: dailyLimitKey)
        }
        let used = defaults.integer(forKey: dailyLimitKey)
        if used >= dailyLimit {
            throw LLMError.quotaExceeded
        }
    }

    private func increaseDailyCount() {
        let defaults = UserDefaults.standard
        let used = defaults.integer(forKey: dailyLimitKey)
        defaults.set(used + 1, forKey: dailyLimitKey)
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: 快取
    private func cacheKey(sentence: String, provider: LLMProvider, locale: String) -> String {
        let raw = "\(sentence)|\(provider)|\(locale)|v1"
        let digest = Insecure.MD5.hash(data: raw.data(using: .utf8)!)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func cacheURL(for key: String) -> URL {
        diskCacheDir.appendingPathComponent("\(key).json")
    }

    private func saveCache(_ value: LLMResult, for key: String) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(value) {
            memCache.setObject(data as NSData, forKey: key as NSString)
            try? data.write(to: cacheURL(for: key), options: .atomic)
        }
    }

    private func loadCache<T: Decodable>(for key: String) -> T? {
        if let data = memCache.object(forKey: key as NSString) as Data? {
            return try? JSONDecoder().decode(T.self, from: data)
        }
        let url = cacheURL(for: key)
        if let data = try? Data(contentsOf: url) {
            memCache.setObject(data as NSData, forKey: key as NSString)
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return nil
    }
}
