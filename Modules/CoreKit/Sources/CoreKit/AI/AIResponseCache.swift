import Foundation
import CryptoKit

/// AI响应缓存服务
/// 提供内存和磁盘两级缓存，加速重复查询
public actor AIResponseCache {
    public static let shared = AIResponseCache()

    // MARK: - Configuration

    private let maxMemoryCacheSize = 100  // 内存最多缓存100条
    private let maxDiskCacheSize = 1000   // 磁盘最多缓存1000条
    private let cacheExpirationDays = 7   // 缓存7天后过期

    // MARK: - Storage

    /// 内存缓存 (LRU)
    private var memoryCache: [String: CachedResponse] = [:]
    private var accessOrder: [String] = []  // LRU访问顺序

    /// 磁盘缓存目录
    private let diskCacheURL: URL

    // MARK: - Models

    private struct CachedResponse: Codable {
        let query: String
        let response: Data
        let timestamp: Date
        let provider: String  // "openai" or "anthropic"

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 7 * 24 * 3600  // 7天
        }
    }

    // MARK: - Initialization

    private init() {
        // 创建缓存目录
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = cacheDir.appendingPathComponent("AIResponseCache", isDirectory: true)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // 启动时清理过期缓存
        Task {
            await cleanExpiredCache()
        }
    }

    // MARK: - Public Methods

    /// 获取缓存的响应
    /// - Parameter query: 查询文本
    /// - Returns: 缓存的响应数据，如果未命中或已过期则返回nil
    public func get(for query: String) -> Data? {
        let key = cacheKey(for: query)

        // 1. 先查内存缓存
        if let cached = memoryCache[key] {
            if !cached.isExpired {
                // 更新LRU顺序
                updateAccessOrder(for: key)
                return cached.response
            } else {
                // 过期，从内存中移除
                memoryCache.removeValue(forKey: key)
                accessOrder.removeAll { $0 == key }
            }
        }

        // 2. 查磁盘缓存
        let fileURL = diskCacheURL.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedResponse.self, from: data) else {
            return nil
        }

        if !cached.isExpired {
            // 加载到内存缓存
            set(cached.response, for: query, provider: cached.provider)
            return cached.response
        } else {
            // 过期，删除文件
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// 缓存响应
    /// - Parameters:
    ///   - response: AI响应数据
    ///   - query: 查询文本
    ///   - provider: AI提供商（"openai" 或 "anthropic"）
    public func set(_ response: Data, for query: String, provider: String) {
        let key = cacheKey(for: query)
        let cached = CachedResponse(
            query: query,
            response: response,
            timestamp: Date(),
            provider: provider
        )

        // 1. 保存到内存
        memoryCache[key] = cached
        updateAccessOrder(for: key)

        // 2. 如果内存缓存已满，移除最久未使用的
        if memoryCache.count > maxMemoryCacheSize, let oldest = accessOrder.first {
            memoryCache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }

        // 3. 异步保存到磁盘
        Task {
            await saveToDisk(cached, key: key)
        }
    }

    /// 清除所有缓存
    public func clearAll() {
        memoryCache.removeAll()
        accessOrder.removeAll()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    /// 获取缓存统计信息
    public func getStats() -> (memoryCount: Int, diskCount: Int, diskSize: Int64) {
        let diskCount = (try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil))?.count ?? 0

        let diskSize = (try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + Int64(size)
        } ?? 0

        return (memoryCache.count, diskCount, diskSize)
    }

    // MARK: - Private Methods

    /// 生成缓存key (使用SHA256哈希)
    private func cacheKey(for query: String) -> String {
        let data = Data(query.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 更新LRU访问顺序
    private func updateAccessOrder(for key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    /// 保存到磁盘
    private func saveToDisk(_ cached: CachedResponse, key: String) {
        let fileURL = diskCacheURL.appendingPathComponent(key)
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: fileURL)
        }

        // 检查磁盘缓存大小，超过限制时清理旧文件
        Task {
            await cleanOldCacheIfNeeded()
        }
    }

    /// 清理过期缓存
    private func cleanExpiredCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let now = Date()
        for file in files {
            if let data = try? Data(contentsOf: file),
               let cached = try? JSONDecoder().decode(CachedResponse.self, from: data),
               now.timeIntervalSince(cached.timestamp) > Double(cacheExpirationDays * 24 * 3600) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// 如果磁盘缓存超过限制，删除最旧的文件
    private func cleanOldCacheIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return
        }

        if files.count <= maxDiskCacheSize {
            return
        }

        // 按创建时间排序
        let sortedFiles = files.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 < date2
        }

        // 删除最旧的文件直到满足限制
        let toDelete = files.count - maxDiskCacheSize
        for file in sortedFiles.prefix(toDelete) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
