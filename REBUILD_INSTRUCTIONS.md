# 🚨 重要：如何正确重新构建和运行应用

## 问题诊断

从截图看，你可能在使用 **SwiftUI Preview** 而不是实际运行的应用。

**SwiftUI Preview 的问题**：
- ❌ 不会重新加载数据库文件
- ❌ 可能使用缓存的旧数据
- ❌ 调试日志不会显示

## ✅ 正确的重新构建步骤

### 步骤 1: 停止所有预览和运行
```
1. 停止 SwiftUI Preview（如果正在使用）
   - 点击预览窗口的 Stop 按钮
   - 或关闭预览面板

2. 停止任何正在运行的应用实例
   - Product → Stop (⌘.)
```

### 步骤 2: 清理构建缓存
```
在 Xcode 中：
Product → Clean Build Folder (⇧⌘K)

或者使用快捷键：Shift + Command + K
```

### 步骤 3: 清理派生数据（推荐）
```
Xcode → Settings → Locations →
点击 Derived Data 路径旁边的箭头 →
删除 NichiDict 文件夹
```

或者命令行：
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/NichiDict-*
```

### 步骤 4: 重新构建
```
Product → Build (⌘B)
```

### 步骤 5: 在真实设备/模拟器上运行
```
⚠️ 重要：不要使用 Preview！

Product → Run (⌘R)

或者点击左上角的 ▶️ 运行按钮
```

## 🔍 验证应用正在运行

### 检查 1: 窗口标题
真实应用的窗口标题应该是独立的，而不是嵌入在 Xcode 中。

### 检查 2: 调试控制台
在 Xcode 底部的控制台（View → Debug Area → Show Debug Area），你应该看到：

```
🔍 SearchService: query='go' scriptType=romaji
🔍 SearchService: useReverseSearch=true for query='go'
🔍 SearchService: Using REVERSE search for 'go'
🗄️ DBService.searchReverse: query='go' limit=50
🗄️ DBService.searchReverse: Returning 12 filtered entries
```

如果看不到这些日志，说明：
- 应用没有真正运行
- 或者你在使用 Preview

### 检查 3: 应用行为
真实应用应该：
- ✅ 搜索"go"返回"行く"、"参る"等
- ✅ AI按钮可以点击并触发请求
- ✅ 有完整的导航和交互

## 📱 针对不同平台

### macOS 应用
```
1. 选择目标设备：My Mac (Designed for iPad) 或 My Mac
2. Product → Run (⌘R)
3. 应用会在 macOS 上启动一个独立窗口
```

### iOS 模拟器
```
1. 选择模拟器：iPhone 15 Pro (或任何 iOS 模拟器)
2. Product → Run (⌘R)
3. 等待模拟器启动
4. 应用会安装到模拟器并自动启动
```

### iOS 真机
```
1. 连接 iPhone/iPad
2. 在设备列表中选择你的设备
3. Product → Run (⌘R)
4. 首次运行需要信任开发者证书
```

## 🐛 如果仍然看到旧结果

### 方案 1: 删除应用并重新安装

#### macOS:
```bash
# 删除应用
rm -rf ~/Library/Developer/Xcode/DerivedData/NichiDict-*/Build/Products/Debug/NichiDict.app

# 删除应用数据
rm -rf ~/Library/Containers/com.yourcompany.NichiDict
rm -rf ~/Library/Caches/com.yourcompany.NichiDict

# 重新构建
xcodebuild -project NichiDict/NichiDict.xcodeproj -scheme NichiDict clean build
```

#### iOS 模拟器:
```bash
# 删除模拟器上的应用
xcrun simctl uninstall booted com.yourcompany.NichiDict

# 重置模拟器（可选，会删除所有数据）
xcrun simctl erase all
```

### 方案 2: 硬编码数据库路径（调试用）

临时修改 `DatabaseManager.swift` 使用开发环境的数据库：

```swift
public var dbQueue: DatabaseQueue {
    get async throws {
        if let queue = _dbQueue {
            return queue
        }

        // 🔧 临时：使用开发环境的数据库
        #if DEBUG
        let dbPath = "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite"
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw DatabaseError.seedDatabaseNotFound
        }
        #else
        guard let dbURL = Bundle.main.url(forResource: "seed", withExtension: "sqlite") else {
            throw DatabaseError.seedDatabaseNotFound
        }
        let dbPath = dbURL.path
        #endif

        // ... 其余代码不变
```

## 📊 验证数据库已正确包含

在运行应用前，验证数据库：

```bash
# 检查 seed.sqlite 是否有 reverse_search_fts 表
sqlite3 "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite" \
  "SELECT name FROM sqlite_master WHERE type='table' AND name='reverse_search_fts';"

# 应该输出：reverse_search_fts

# 检查数据是否正确
sqlite3 "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite" \
  "SELECT COUNT(*) FROM reverse_search_fts;"

# 应该输出：493484

# 测试查询
sqlite3 "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite" \
  "SELECT e.headword, e.reading_hiragana
   FROM dictionary_entries e
   JOIN word_senses ws ON e.id = ws.entry_id
   WHERE LOWER(ws.definition_english) LIKE '%to go%'
   LIMIT 5;"

# 应该输出：
# 行く|いく
# 参る|まいる
# お出でになる|おいでになる
# ...
```

## 🔧 AI 按钮问题

如果 AI 按钮没有反应，检查：

### 1. API Key 是否有效
```bash
curl -s "https://api.openai.com/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"test"}],"max_tokens":10}' \
  | python3 -c "import sys, json; print(json.load(sys.stdin).get('error', 'OK'))"
```

### 2. 网络连接
确保应用有网络访问权限（特别是在 macOS 上）。

### 3. 控制台错误
查看 Xcode 控制台是否有错误信息。

### 4. AI 配置
检查 `NichiDictApp.swift` 中的 API key 是否正确配置。

## ✅ 成功标志

构建并运行成功后，你应该看到：

1. **搜索 "go" 的结果**：
   ```
   行く (いく) - to go
   参る (まいる) - to go; to come
   お出でになる (おいでになる) - to go
   ```

2. **控制台日志**：
   ```
   🔍 SearchService: useReverseSearch=true
   🗄️ DBService.searchReverse: Returning 12 filtered entries
   ```

3. **AI 按钮**：
   - 点击后变为加载状态
   - 返回完整的词条信息（包括例句、语法等）

## 📞 如果还有问题

请提供：
1. Xcode 控制台的完整输出
2. 应用是通过 Run (⌘R) 还是 Preview 运行的
3. 搜索 "go" 时的完整日志
4. Build Settings → Product Bundle Identifier

---

**最后确认**：
- [ ] 已经停止 Preview
- [ ] 已经 Clean Build Folder
- [ ] 使用 Product → Run (⌘R) 运行
- [ ] 在真实设备/模拟器上看到应用窗口
- [ ] 控制台显示调试日志

如果完成以上所有步骤，搜索 "go" 应该就能正常工作了！
