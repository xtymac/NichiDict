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
    public var jlptLevel: String?         // JLPT级别（从本地数据库查询后补充）

    public init(headword: String, reading: String, romaji: String?, partOfSpeech: String,
                accent: String?, senses: [LLMSense], grammar: LLMGrammar?,
                examples: [LLMExample]?, related: LLMRelated?, jlptLevel: String? = nil) {
        self.headword = headword
        self.reading = reading
        self.romaji = romaji
        self.partOfSpeech = partOfSpeech
        self.accent = accent
        self.senses = senses
        self.grammar = grammar
        self.examples = examples
        self.related = related
        self.jlptLevel = jlptLevel
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

public struct LLMExample: Codable, Hashable, Sendable {
    public let japanese: String    // 日语例句
    public let chinese: String?    // 中文翻译（可选，仅中文用户生成）
    public let english: String     // 英文翻译

    public init(japanese: String, chinese: String? = nil, english: String) {
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
    public let entries: [LLMDictEntry]?       // 词条（最多top_k个，句子查询时可选）
    public let sentenceAnalysis: LLMSentenceAnalysis?  // 句子解析（仅句子查询）

    public init(queryType: LLMQueryType, entries: [LLMDictEntry]?, sentenceAnalysis: LLMSentenceAnalysis?) {
        self.queryType = queryType
        self.entries = entries
        self.sentenceAnalysis = sentenceAnalysis
    }
}

public struct LLMSentenceAnalysis: Codable, Hashable {
    public let original: String                     // 原句
    public let translation: LLMTranslation          // 翻译（中英）
    public let wordBreakdown: [LLMWordBreakdown]?   // 逐词解析（可选）
    public let grammarPoints: [LLMGrammarPoint]?    // 语法点（可选）
    public let examples: [LLMExample]?              // 例句（可选）

    public init(original: String, translation: LLMTranslation,
                wordBreakdown: [LLMWordBreakdown]?, grammarPoints: [LLMGrammarPoint]?,
                examples: [LLMExample]? = nil) {
        self.original = original
        self.translation = translation
        self.wordBreakdown = wordBreakdown
        self.grammarPoints = grammarPoints
        self.examples = examples
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
    public let reading: String?        // 读音（可选，如标点符号可能为null）
    public let meaning: String         // 词义
    public let grammaticalRole: String // 语法作用

    public init(word: String, reading: String?, meaning: String, grammaticalRole: String) {
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
    case gemini(model: String)      // 例: "gemini-2.0-flash-exp" / "gemini-1.5-flash"
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

    // Clear all caches (for debugging or when language changes)
    public func clearAllCaches() {
        print("🗑️ Clearing all AI caches...")
        memCache.removeAllObjects()

        // Clear disk cache
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCacheDir, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            print("✅ All caches cleared (\(files.count) disk files removed)")
        } catch {
            print("⚠️ Error clearing disk cache: \(error)")
        }
    }

    // MARK: 對外主方法
    @discardableResult
    public func translateExplain(sentence: String,
                                 locale: String = "zh",
                                 useCache: Bool = true,
                                 onPartialResult: (@Sendable (String) -> Void)? = nil) async throws -> LLMResult {

        guard let _ = apiKey, let provider = provider else {
            throw LLMError.notConfigured
        }

        // 命中快取
        let key = cacheKey(sentence: sentence, provider: provider, locale: locale)
        print("🔑 Cache key calculation:")
        print("   - sentence: \(sentence)")
        print("   - provider: \(providerIdentifier(provider))")
        print("   - locale: \(locale)")
        print("   - version: v3")
        print("   - resulting key: \(key)")

        if useCache, let cached: LLMResult = loadCache(for: key) {
            print("✅ Cache HIT - returning cached result")
            print("   ⚠️ If content is wrong language, the app may need a clean restart")
            return cached
        }
        print("❌ Cache MISS - will request AI")

        // 配額判斷
        try checkDailyQuota()

        // 組裝提示（要求返回 JSON）
        let prompt = buildPrompt(sentence: sentence, locale: locale)
        print("📤 Sending AI request with locale: \(locale)")
        print("📝 Prompt length: \(prompt.count) characters")

        // 發送請求（添加性能监控）
        let startTime = Date()
        let result: LLMResult
        switch provider {
        case .openAI(let model):
            result = try await requestOpenAI(model: model, prompt: prompt)
        case .anthropic(let model):
            result = try await requestAnthropic(model: model, prompt: prompt)
        case .gemini(let model):
            // 如果提供了回调，使用流式响应
            if let callback = onPartialResult {
                result = try await requestGeminiStreaming(model: model, prompt: prompt, onPartialResult: callback)
            } else {
                result = try await requestGemini(model: model, prompt: prompt)
            }
        }
        let duration = Date().timeIntervalSince(startTime)
        print("✅ AI response received in \(String(format: "%.2f", duration))s")

        // 寫入快取 + 計數
        saveCache(result, for: key)
        increaseDailyCount()

        return result
    }

    public func generateExamples(for entry: DictionaryEntry,
                                 senses providedSenses: [WordSense]? = nil,
                                 locale: String = Locale.current.identifier,
                                 maxExamples: Int = 3,
                                 useCache: Bool = true) async throws -> [LLMExample] {
        guard let _ = apiKey, let provider = provider else {
            throw LLMError.notConfigured
        }

        let senses = (providedSenses ?? entry.senses).filter { !$0.definitionEnglish.isEmpty }
        guard !senses.isEmpty else {
            return []
        }

        // Extract existing offline examples to avoid duplication
        let existingExamples = senses.flatMap { $0.examples.map { $0.japaneseText } }
        print("📝 Found \(existingExamples.count) existing offline examples for \(entry.headword)")
        if !existingExamples.isEmpty {
            print("   Existing: \(existingExamples.prefix(3).joined(separator: " | "))")
        }

        let key = cacheKeyForExamples(
            entryID: entry.id,
            provider: provider,
            locale: locale,
            maxExamples: maxExamples,
            senses: senses
        )

        if useCache, let cached: ExampleResponse = loadCache(for: key) {
            return cached.examples
        }

        try checkDailyQuota()

        let prompt = buildExamplePrompt(
            entry: entry,
            senses: senses,
            locale: locale,
            maxExamples: maxExamples,
            existingExamples: existingExamples
        )

        let responseData: Data
        switch provider {
        case .openAI(let model):
            responseData = try await requestOpenAIContent(model: model, prompt: prompt)
        case .anthropic(let model):
            responseData = try await requestAnthropicContent(model: model, prompt: prompt)
        case .gemini(let model):
            responseData = try await requestGeminiContent(model: model, prompt: prompt)
        }

        let response: ExampleResponse
        do {
            response = try JSONDecoder().decode(ExampleResponse.self, from: responseData)
        } catch {
            let raw = String(data: responseData, encoding: .utf8) ?? ""
            throw LLMError.decodeFailed("例句解析失败: \(error.localizedDescription)\n\(raw.prefix(200))")
        }

        saveCache(response, for: key)
        increaseDailyCount()

        return response.examples
    }

    // MARK: Prompt
    private func buildPrompt(sentence: String, locale: String) -> String {
        // Detect user's primary language from locale
        let isChineseUser = locale.hasPrefix("zh")
        let primaryLanguage = isChineseUser ? "Chinese (Simplified)" : "English"
        let secondaryLanguage = isChineseUser ? "English" : "Chinese (Simplified)"

        print("🌍 Building prompt for locale: \(locale)")
        print("🌍 Primary language: \(primaryLanguage)")
        print("🌍 Secondary language: \(secondaryLanguage)")

        return """
        You are a professional Japanese dictionary system. Map user input (Chinese/English/Japanese) to the most appropriate Japanese dictionary entries.

        ⚠️ CRITICAL LANGUAGE REQUIREMENT ⚠️
        The user's system language is: \(primaryLanguage)
        YOU MUST write ALL explanations, meanings, grammatical roles, and descriptions in \(primaryLanguage).
        DO NOT use \(secondaryLanguage) for explanatory content.

        Specifically:
        - In "wordBreakdown" array: "meaning" and "grammaticalRole" MUST be in \(primaryLanguage)
        - In "grammarPoints" array: "meaning" and "explanation" MUST be in \(primaryLanguage)
        - Only the "translation" object should contain both languages

        Example: If primaryLanguage is English, write "money" not "钱", write "noun" not "名词"

        CRITICAL: You MUST return valid JSON that EXACTLY matches the schema below. Do not add any text before or after the JSON.

        ## Step 1: Determine Query Type
        - If input contains periods/question marks/exclamation marks OR has many spaces OR length>12 with multiple word forms → queryType: "sentence"
        - Otherwise → queryType: "word"
        - If cannot identify → queryType: "notFound"

        ## Step 2: Response Rules
        - Primary language: Japanese definitions
        - User's primary language: \(primaryLanguage) (use this for main explanations in "meaning", "explanation", and "grammaticalRole" fields)
        - User's secondary language: \(secondaryLanguage) (use this for the corresponding field)
        - Provide translations in both \(primaryLanguage) and \(secondaryLanguage)
        - No redundancy: merge same meanings/POS/definitions
        - Max 3 senses per entry, 2-3 examples per word
        - For sentence analysis: provide 2-3 similar example sentences in the "examples" array
        - Use「(推定)」for uncertain information
        - For Chinese/English input (e.g., "noon", "eat"), map to Japanese entries (e.g., 「正午」「昼」「食べる」「食う」)
        - **CRITICAL FOR SENTENCE MODE**: If input is in English/Chinese, FIRST translate to Japanese, then analyze the Japanese sentence
        - **In sentence mode, "original" field MUST be the Japanese sentence** (translated if needed)
        - **wordBreakdown MUST break down the JAPANESE words**, not the input language
        - IMPORTANT: In wordBreakdown, use \(primaryLanguage) for "meaning" and "grammaticalRole" fields
        - IMPORTANT: In grammarPoints, use \(primaryLanguage) for "meaning" and "explanation" fields

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
        Example for \(primaryLanguage) users:
        {
          "queryType": "sentence",
          "sentenceAnalysis": {
            "original": "今日は雨が降りそうです。",
            "translation": {
              "chinese": "\(isChineseUser ? "今天好像要下雨。" : "It looks like it will rain today.")",
              "english": "\(isChineseUser ? "It looks like it will rain today." : "今天好像要下雨。")"
            },
            "wordBreakdown": [
              {
                "word": "今日",
                "reading": "きょう",
                "meaning": "\(primaryLanguage == "English" ? "today" : "今天")",
                "grammaticalRole": "\(primaryLanguage == "English" ? "time noun" : "時間名詞")"
              },
              {
                "word": "は",
                "reading": "は",
                "meaning": "\(primaryLanguage == "English" ? "(topic marker)" : "（主题标记）")",
                "grammaticalRole": "\(primaryLanguage == "English" ? "particle" : "係助詞")"
              },
              {
                "word": "雨",
                "reading": "あめ",
                "meaning": "\(primaryLanguage == "English" ? "rain" : "雨")",
                "grammaticalRole": "\(primaryLanguage == "English" ? "noun" : "名詞")"
              }
            ],
            "grammarPoints": [
              {
                "pattern": "そうです",
                "reading": "そうです",
                "meaning": "\(primaryLanguage == "English" ? "looks like; seems" : "样态推测")",
                "explanation": "\(primaryLanguage == "English" ? "Expresses conjecture based on visual appearance or situation" : "表示根据外观或样子进行推测")"
              }
            ],
            "examples": [
              {
                "japanese": "明日は晴れそうです。",
                "chinese": "明天好像会晴天。",
                "english": "It looks like it will be sunny tomorrow."
              },
              {
                "japanese": "この本は面白そうです。",
                "chinese": "这本书看起来很有趣。",
                "english": "This book looks interesting."
              }
            ]
          }
        }

        CRITICAL: Use \(primaryLanguage) for "meaning", "grammaticalRole", and "explanation" fields in wordBreakdown and grammarPoints!

        ## 5) 未収録模式 JSON 结构 - IMPORTANT: Provide internet-based explanation
        When queryType is "notFound", you should:
        1. Use your knowledge (including internet sources) to provide the best explanation
        2. If it's a real Japanese word/phrase not in the dictionary, explain its meaning, usage, and origin
        3. If it's a typo or non-existent word, suggest corrections and explain why
        4. Provide definitions in BOTH Japanese and user's language (\(primaryLanguage))

        Example for a word not in dictionary:
        {
          "queryType": "notFound",
          "entries": [
            {
              "headword": "{input as-is}",
              "reading": "{inferred reading in hiragana}",
              "romaji": "{romaji if applicable}",
              "partOfSpeech": "{inferred part of speech, or '未収録語' if unknown}",
              "accent": null,
              "senses": [
                {
                  "definition": "{Japanese explanation based on your knowledge}",
                  "chinese": "{Chinese translation if primaryLanguage is Chinese}",
                  "english": "{English explanation if primaryLanguage is English}"
                }
              ],
              "grammar": null,
              "examples": [
                {
                  "japanese": "{example sentence if known}",
                  "chinese": "{Chinese translation}",
                  "english": "{English translation}"
                }
              ],
              "related": {
                "synonym": "{similar words if any}",
                "antonym": null,
                "derived": "{possible corrections or related forms}"
              }
            }
          ]
        }

        CRITICAL for notFound mode:
        - DO NOT just return "未收录/Not found" - provide actual explanations from your knowledge
        - If it's internet slang, explain its origin and meaning
        - If it's a proper noun, explain what it refers to
        - If it's a typo, suggest the correct form in "derived" field
        - Use \(primaryLanguage) for all explanations

        ## MANDATORY REQUIREMENTS
        ⚠️ CRITICAL - Your response MUST be valid JSON ONLY. No explanations, no markdown, no prefix/suffix.
        ⚠️ CRITICAL - Use ENGLISH punctuation ONLY in JSON structure: colons (:), commas (,), quotes ("). NEVER use Chinese punctuation (：、，、。).
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

        ========================================
        FINAL REMINDER FOR THIS REQUEST:
        - User system language: \(primaryLanguage)
        - ALL "meaning" fields in wordBreakdown: MUST be in \(primaryLanguage)
        - ALL "grammaticalRole" fields in wordBreakdown: MUST be in \(primaryLanguage)
        - ALL "meaning" fields in grammarPoints: MUST be in \(primaryLanguage)
        - ALL "explanation" fields in grammarPoints: MUST be in \(primaryLanguage)

        If \(primaryLanguage) is "English": use "money" not "钱", use "noun" not "名詞", use "particle" not "助詞"
        If \(primaryLanguage) is "Chinese (Simplified)": use "钱" not "money", use "名詞" not "noun"
        ========================================

        User Query: \(sentence)

        Response (JSON only, no other text):
        """
    }

    private func buildExamplePrompt(entry: DictionaryEntry,
                                    senses: [WordSense],
                                    locale: String,
                                    maxExamples: Int,
                                    existingExamples: [String] = []) -> String {
        let definitions = senses.prefix(5)
            .enumerated()
            .map { index, sense in
                let chinese = sense.definitionChineseSimplified ?? sense.definitionChineseTraditional ?? ""
                return "\(index + 1). \(sense.definitionEnglish) | JP: \(sense.partOfSpeech) | CN: \(chinese)"
            }
            .joined(separator: "\n")

        // Determine if user is Chinese speaker
        let isChineseUser = locale.hasPrefix("zh")

        // Build schema and instructions based on user's language
        let jsonSchema: String
        let translationInstruction: String

        if isChineseUser {
            // Chinese users: generate both chinese and english
            let chineseType = locale.lowercased().contains("hant") ? "Traditional Chinese" : "Simplified Chinese"
            jsonSchema = """
            {"examples":[{"japanese":"...", "chinese":"...", "english":"..."}]}
            """
            translationInstruction = """
            4. Use \(chineseType) for the chinese field. Keep english field in natural English.
            """
        } else {
            // Non-Chinese users: only generate english (no chinese field)
            jsonSchema = """
            {"examples":[{"japanese":"...", "english":"..."}]}
            """
            translationInstruction = """
            4. Keep english field in natural English. Do NOT include a chinese field.
            """
        }

        // Build existing examples warning if any
        let existingExamplesWarning: String
        if !existingExamples.isEmpty {
            let examplesList = existingExamples.map { "  - \($0)" }.joined(separator: "\n")
            existingExamplesWarning = """

            ⚠️ CRITICAL: The following example sentences ALREADY EXIST for this word.
            You MUST generate COMPLETELY DIFFERENT examples with DIFFERENT sentence patterns:
            \(examplesList)

            Requirements for NEW examples:
            - Use DIFFERENT grammar structures (e.g., if existing uses 'は〜です', try 'を〜する', 'が〜ある', questions, negative forms, etc.)
            - Use DIFFERENT verb forms and particles
            - Use DIFFERENT contexts and scenarios
            - Must be clearly distinguishable from existing examples
            - Ensure variety in sentence endings (avoid repeating です/ます/だ if already used)
            """
        } else {
            existingExamplesWarning = ""
        }

        return """
        You are an expert Japanese language tutor. Generate natural example sentences for a dictionary entry.

        Entry:
        - Headword: \(entry.headword)
        - Reading: \(entry.readingHiragana)
        - Romaji: \(entry.readingRomaji)
        - Core meanings:
        \(definitions)\(existingExamplesWarning)

        Requirements:
        1. Produce up to \(maxExamples) natural Japanese sentences (15-35 characters) that demonstrate typical usage in daily life. Each sentence MUST include the headword or its conjugated/inflected form once.
        2. Keep sentences simple and practical. Avoid uncommon idioms or archaic grammar.
        3. Ensure variety in grammar patterns: use different sentence types (declarative, question, negative, past tense, polite/casual forms, etc.)
        4. Return JSON ONLY with schema:
           \(jsonSchema)
        \(translationInstruction)
        6. Avoid romaji, avoid placeholders, avoid line breaks inside fields.

        Respond with JSON only.
        """
    }

    // MARK: OpenAI 請求
    private func requestOpenAI(model: String, prompt: String) async throws -> LLMResult {
        let content = try await requestOpenAIContent(model: model, prompt: prompt)

        // 清洗 JSON：替换中文标点为英文标点
        let cleanedContent = sanitizeJSON(content)

        do {
            return try JSONDecoder().decode(LLMResult.self, from: cleanedContent)
        } catch let primaryError {
            // Log the actual response for debugging
            let responseText = String(data: cleanedContent, encoding: .utf8) ?? "Unable to decode response"
            print("⚠️ Primary JSON Decode Failed. Attempting fallback parsing...")
            print("📄 Response was: \(responseText)")
            print("❌ Error: \(primaryError)")

            // FALLBACK: Try to parse partial/malformed JSON
            if let fallbackResult = tryFallbackParsing(content: cleanedContent, originalQuery: prompt) {
                print("✅ Fallback parsing succeeded")
                return fallbackResult
            }

            throw LLMError.decodeFailed("AI返回格式错误。\n原始响应: \(responseText.prefix(200))...\n错误: \(primaryError.localizedDescription)")
        }
    }

    private func requestOpenAIContent(model: String, prompt: String) async throws -> Data {
        guard let apiKey = apiKey else { throw LLMError.notConfigured }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30  // 30秒超时（适应真机网络环境）
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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

        struct Choice: Decodable { let message: Msg }
        struct Msg: Decodable { let content: String }
        struct OpenAIResp: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(OpenAIResp.self, from: data)
        guard let content = decoded.choices.first?.message.content.data(using: .utf8) else {
            throw LLMError.emptyResponse
        }
        return content
    }

    // MARK: Anthropic 請求（Claude）
    private func requestAnthropic(model: String, prompt: String) async throws -> LLMResult {
        let content = try await requestAnthropicContent(model: model, prompt: prompt)

        // 清洗 JSON：替换中文标点为英文标点
        let cleanedContent = sanitizeJSON(content)

        do {
            return try JSONDecoder().decode(LLMResult.self, from: cleanedContent)
        } catch let primaryError {
            let responseText = String(data: cleanedContent, encoding: .utf8) ?? "Unable to decode response"
            print("⚠️ Primary JSON Decode Failed (Anthropic). Attempting fallback parsing...")
            print("📄 Response was: \(responseText)")
            print("❌ Error: \(primaryError)")

            if let fallbackResult = tryFallbackParsing(content: cleanedContent, originalQuery: prompt) {
                print("✅ Fallback parsing succeeded")
                return fallbackResult
            }

            throw LLMError.decodeFailed("AI返回格式错误 (Anthropic)。\n原始响应: \(responseText.prefix(200))...\n错误: \(primaryError.localizedDescription)")
        }
    }

    private func requestAnthropicContent(model: String, prompt: String) async throws -> Data {
        guard let apiKey = apiKey else { throw LLMError.notConfigured }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10  // 10秒超时
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

        struct Block: Decodable { let text: String? }
        struct Message: Decodable { let content: [Block] }
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        let jsonText = decoded.content.compactMap { $0.text }.joined()
        guard let jsonData = jsonText.data(using: .utf8) else { throw LLMError.emptyResponse }
        return jsonData
    }

    // MARK: Gemini 請求（Google）

    // 非流式请求（保留用于兼容性）
    private func requestGemini(model: String, prompt: String) async throws -> LLMResult {
        let content = try await requestGeminiContent(model: model, prompt: prompt)

        // 清洗 JSON：替换中文标点为英文标点
        let cleanedContent = sanitizeJSON(content)

        do {
            let result = try JSONDecoder().decode(LLMResult.self, from: cleanedContent)
            return result
        } catch let primaryError {
            // 备用解析
            let responseText = String(data: cleanedContent, encoding: .utf8) ?? "无法解码"
            print("⚠️ Gemini JSON解析失败")
            print("========== FULL GEMINI RESPONSE ==========")
            print(responseText)
            print("==========================================")

            // 打印详细的解码错误
            if let decodingError = primaryError as? DecodingError {
                print("🔍 Decoding Error Details:")
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   Missing key: \(key.stringValue)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .valueNotFound(let type, let context):
                    print("   Value not found for type: \(type)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .typeMismatch(let type, let context):
                    print("   Type mismatch for: \(type)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .dataCorrupted(let context):
                    print("   Data corrupted")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                @unknown default:
                    print("   Unknown decoding error: \(decodingError)")
                }
            }

            throw LLMError.decodeFailed("AI返回格式错误 (Gemini)。\n原始响应: \(responseText.prefix(200))...\n错误: \(primaryError.localizedDescription)")
        }
    }

    // 流式请求（逐步返回结果）
    private func requestGeminiStreaming(
        model: String,
        prompt: String,
        onPartialResult: @escaping @Sendable (String) -> Void
    ) async throws -> LLMResult {
        guard let apiKey = apiKey else { throw LLMError.notConfigured }

        print("🔵 Gemini Streaming: Starting request to \(model)")
        print("📝 Prompt length: \(prompt.count) characters")
        let requestStartTime = Date()

        // Gemini Streaming API endpoint
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?key=\(apiKey)&alt=sse")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [[
                "parts": [[
                    "text": "You must respond with valid JSON only, no markdown code blocks.\n\n\(prompt)"
                ]]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 2048,  // Needs to be large enough for full sentence analysis
                "responseMimeType": "application/json"
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🌐 Sending streaming request to Gemini...")
        // 使用 URLSession 的 bytes 流式接收
        let (bytes, response) = try await URLSession.shared.bytes(for: req)

        let networkTime = Date().timeIntervalSince(requestStartTime)
        print("✅ Network connection established in \(String(format: "%.2f", networkTime))s")

        guard let http = response as? HTTPURLResponse else { throw LLMError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.httpError(http.statusCode, "Streaming request failed")
        }

        var accumulatedText = ""
        var eventData = ""
        var chunkCount = 0
        let firstChunkTime = Date()

        print("📡 Waiting for first chunk from Gemini...")
        // 逐行读取 SSE (Server-Sent Events) 流
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                eventData = String(line.dropFirst(6)) // 移除 "data: " 前缀

                // 解析每个事件
                if let data = eventData.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {

                    accumulatedText += text
                    chunkCount += 1

                    if chunkCount == 1 {
                        let ttfb = Date().timeIntervalSince(requestStartTime)
                        print("⚡️ First chunk received in \(String(format: "%.2f", ttfb))s (TTFB)")
                    }

                    // 调用回调，通知 UI 更新
                    await MainActor.run {
                        onPartialResult(accumulatedText)
                    }

                    if chunkCount % 5 == 0 {  // 每5个chunk打印一次
                        print("📦 Chunk #\(chunkCount): \(accumulatedText.count) chars total")
                    }
                }
            }
        }

        let duration = Date().timeIntervalSince(requestStartTime)
        print("✅ Streaming complete: \(chunkCount) chunks, \(accumulatedText.count) chars in \(String(format: "%.2f", duration))s")

        // 解析最终的完整 JSON
        guard let jsonData = accumulatedText.data(using: .utf8) else {
            throw LLMError.emptyResponse
        }

        let cleanedContent = sanitizeJSON(jsonData)

        do {
            let result = try JSONDecoder().decode(LLMResult.self, from: cleanedContent)
            return result
        } catch let primaryError {
            let responseText = String(data: cleanedContent, encoding: .utf8) ?? "无法解码"
            print("⚠️ Gemini Streaming JSON解析失败")
            print("========== FULL GEMINI STREAMING RESPONSE ==========")
            print(responseText)
            print("===================================================")

            // 打印详细的解码错误
            if let decodingError = primaryError as? DecodingError {
                print("🔍 Decoding Error Details:")
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   Missing key: \(key.stringValue)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .valueNotFound(let type, let context):
                    print("   Value not found for type: \(type)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .typeMismatch(let type, let context):
                    print("   Type mismatch for: \(type)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .dataCorrupted(let context):
                    print("   Data corrupted")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                @unknown default:
                    print("   Unknown decoding error: \(decodingError)")
                }
            }

            throw LLMError.decodeFailed("AI返回格式错误 (Gemini Streaming)。\n原始响应: \(responseText.prefix(200))...\n错误: \(primaryError.localizedDescription)")
        }
    }

    private func requestGeminiContent(model: String, prompt: String) async throws -> Data {
        guard let apiKey = apiKey else { throw LLMError.notConfigured }

        print("🔵 Gemini API: Starting request to \(model)")
        let requestStartTime = Date()

        // Gemini API endpoint
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30  // 30秒超时
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [[
                "parts": [[
                    "text": "You must respond with valid JSON only, no markdown code blocks.\n\n\(prompt)"
                ]]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 2048,  // Needs to be large enough for full sentence analysis
                "responseMimeType": "application/json"  // 强制 JSON 输出
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🔵 Gemini API: Request prepared, sending...")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let networkDuration = Date().timeIntervalSince(requestStartTime)
        print("🔵 Gemini API: Network response received in \(String(format: "%.2f", networkDuration))s")
        guard let http = resp as? HTTPURLResponse else { throw LLMError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(http.statusCode, msg)
        }

        // 解析 Gemini 响应格式
        struct Part: Decodable { let text: String }
        struct Content: Decodable { let parts: [Part] }
        struct Candidate: Decodable {
            let content: Content
            let finishReason: String?
        }
        struct GeminiResponse: Decodable { let candidates: [Candidate] }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let firstCandidate = decoded.candidates.first,
              let jsonText = firstCandidate.content.parts.first?.text else {
            throw LLMError.emptyResponse
        }

        // Check if response was complete
        if let finishReason = firstCandidate.finishReason {
            print("🔍 Gemini finishReason: \(finishReason)")
            if finishReason != "STOP" && finishReason != "FINISH" {
                print("⚠️ Warning: Response may be incomplete (finishReason: \(finishReason))")
            }
        }

        print("📏 JSON text length: \(jsonText.count) characters")

        guard let jsonData = jsonText.data(using: .utf8) else { throw LLMError.emptyResponse }
        return jsonData
    }

    private struct ExampleResponse: Codable {
        let examples: [LLMExample]
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
        // v3: Enhanced notFound mode with internet-based explanations (2025-10-22)
        let raw = "\(sentence)|\(providerIdentifier(provider))|\(locale)|v3"
        let digest = Insecure.MD5.hash(data: raw.data(using: .utf8)!)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func cacheKeyForExamples(entryID: Int,
                                     provider: LLMProvider,
                                     locale: String,
                                     maxExamples: Int,
                                     senses: [WordSense]) -> String {
        let senseFingerprint = senses
            .map { sense in
                [
                    sense.definitionEnglish,
                    sense.definitionChineseSimplified ?? "",
                    sense.definitionChineseTraditional ?? "",
                    sense.partOfSpeech
                ].joined(separator: "|")
            }
            .joined(separator: ";")

        let raw = "examples|\(entryID)|\(senseFingerprint)|\(locale)|\(maxExamples)|\(providerIdentifier(provider))|v1"
        let digest = Insecure.MD5.hash(data: raw.data(using: .utf8)!)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func cacheURL(for key: String) -> URL {
        diskCacheDir.appendingPathComponent("\(key).json")
    }

    private func saveCache<T: Encodable>(_ value: T, for key: String) {
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

    private func providerIdentifier(_ provider: LLMProvider) -> String {
        switch provider {
        case .openAI(let model):
            return "openai:\(model)"
        case .anthropic(let model):
            return "anthropic:\(model)"
        case .gemini(let model):
            return "gemini:\(model)"
        }
    }

    /// 清洗 JSON 数据：将中文标点替换为英文标点
    /// Sanitize JSON data: replace Chinese punctuation with English punctuation
    private func sanitizeJSON(_ data: Data) -> Data {
        guard var jsonString = String(data: data, encoding: .utf8) else {
            print("⚠️ Unable to decode JSON string")
            return data
        }

        var replacementCount = 0

        // 在 JSON 结构层面（字段名、冒号、逗号）替换中文标点为英文标点
        // 但保留字符串值内部的标点（避免破坏日语/中文文本内容）

        var insideString = false
        var escaped = false
        var result = ""

        for char in jsonString {
            if escaped {
                // 转义字符后的字符，直接添加
                result.append(char)
                escaped = false
                continue
            }

            if char == "\\" {
                // 转义字符
                escaped = true
                result.append(char)
                continue
            }

            if char == "\"" {
                // 引号切换字符串状态
                insideString.toggle()
                result.append(char)
                continue
            }

            // 在字符串外部（JSON 结构部分）替换中文标点
            if !insideString {
                switch char {
                case "：":
                    result.append(":")
                    replacementCount += 1
                case "，":
                    result.append(",")
                    replacementCount += 1
                case "。":
                    result.append(".")
                    replacementCount += 1
                case "｛":
                    result.append("{")
                    replacementCount += 1
                case "｝":
                    result.append("}")
                    replacementCount += 1
                case "［":
                    result.append("[")
                    replacementCount += 1
                case "］":
                    result.append("]")
                    replacementCount += 1
                default:
                    result.append(char)
                }
            } else {
                // 在字符串内部，保留原样（包括中文标点）
                result.append(char)
            }
        }

        if replacementCount > 0 {
            print("🧹 JSON Sanitized: Replaced \(replacementCount) Chinese punctuation marks")
            print("📝 Original: \(jsonString.prefix(200))...")
            print("📝 Cleaned:  \(result.prefix(200))...")
        }

        return result.data(using: .utf8) ?? data
    }
}
