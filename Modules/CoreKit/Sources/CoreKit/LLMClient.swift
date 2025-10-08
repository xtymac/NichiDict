//
//  LLMClient.swift
//  CoreKit
//
//  Created by Mac on 2025/10/06.
//

import Foundation
import CryptoKit

// MARK: - 公共模型：AI 返回结构（固定 JSON 格式）
public struct LLMKeywordEntry: Codable, Hashable {
    public let term: String        // 詞彙
    public let reading: String     // 假名
    public let glossZH: String     // 中文解釋
}

public struct LLMResult: Codable, Hashable {
    public let direct: String      // 直譯
    public let natural: String     // 更自然的譯文
    public let points: [String]    // 語法要點（≤4條）
    public let keywords: [LLMKeywordEntry]
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
        """
        你是日語老師。請用簡短\(locale == "zh" ? "中文" : locale)輸出固定 JSON（不要多餘文字）。
        JSON 結構：
        {
          "direct": "直譯（簡短）",
          "natural": "更自然的譯文（簡短）",
          "points": ["要點1","要點2","要點3","要點4(可省)"],
          "keywords": [
            {"term":"詞彙","reading":"かな","glossZH":"中文解釋"}
          ]
        }
        請特別注意：points 不超過 4 條；關鍵詞按「詞彙（假名）『中文解釋』」含義輸出到 keywords 陣列。
        句子：\(sentence)
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
        } catch {
            throw LLMError.decodeFailed(error.localizedDescription)
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
        } catch {
            throw LLMError.decodeFailed(error.localizedDescription)
        }
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
