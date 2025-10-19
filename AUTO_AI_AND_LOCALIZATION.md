# AI自动触发与本地化支持功能

## 概述

本次更新实现了两个重要的用户体验改进：

1. **AI自动触发**：当本地词典没有匹配结果时，自动调用AI解释，无需手动点击
2. **本地词条多语言支持**：根据用户系统语言自动显示对应的定义（中文简体/繁体/英文）

## 功能详情

### 1. AI自动触发

#### 实现原理

当用户搜索词条时，系统会：

1. 首先在本地SQLite数据库中搜索
2. 如果找到结果 → 显示本地词条
3. 如果**没有找到任何结果** → 自动触发AI查询

#### 代码实现

**SearchView.swift** - `performSearch()` 方法：

```swift
// 搜索本地数据库
let searchResults = try await searchService.search(
    query: searchQuery,
    maxResults: 50
)

// 更新UI显示结果
await MainActor.run {
    results = searchResults
    groupResults()
    // ...
}

// ⭐️ 自动触发AI（如果本地无结果）
if searchResults.isEmpty {
    await autoTriggerAI(for: searchQuery)
}
```

**autoTriggerAI()** 方法：

```swift
private func autoTriggerAI(for query: String) async {
    guard !aiLoading else { return }

    await MainActor.run {
        aiLoading = true
    }

    defer {
        Task { @MainActor in
            aiLoading = false
        }
    }

    do {
        // 🌍 自动检测系统语言
        let locale = Locale.current.language.languageCode?.identifier ?? "zh"
        let r = try await LLMClient.shared.translateExplain(
            sentence: query,
            locale: locale
        )
        await MainActor.run {
            aiResult = r
            aiError = nil
        }
    } catch {
        await MainActor.run {
            aiError = error.localizedDescription
        }
    }
}
```

#### UI体验

**之前**：
```
[搜索框]
━━━━━━━━━
❌ 没有找到结果

[需要手动点击"AI翻译"按钮]
```

**现在**：
```
[搜索框]
━━━━━━━━━
❌ 没有找到结果

⏳ AI解析中...

[自动显示AI词典结果]
```

### 2. 本地词条多语言支持

#### 数据库字段

WordSense表包含三种语言的定义：

- `definition_english` - 英文定义（必需）
- `definition_chinese_simplified` - 简体中文定义（可选）
- `definition_chinese_traditional` - 繁体中文定义（可选）

#### 智能语言选择

新增 `localizedDefinition()` 方法在 **WordSense.swift**：

```swift
public func localizedDefinition(locale: Locale = .current) -> String {
    let languageCode = locale.language.languageCode?.identifier ?? "en"
    let scriptCode = locale.language.script?.identifier

    // 中文用户
    if languageCode == "zh" {
        if scriptCode == "Hant" {
            // 繁体中文（香港、台湾）
            if let traditionalDef = definitionChineseTraditional, !traditionalDef.isEmpty {
                return traditionalDef
            }
        } else {
            // 简体中文（中国大陆、新加坡）
            if let simplifiedDef = definitionChineseSimplified, !simplifiedDef.isEmpty {
                return simplifiedDef
            }
        }
        // 回退：尝试另一个中文变体
        if let simplifiedDef = definitionChineseSimplified, !simplifiedDef.isEmpty {
            return simplifiedDef
        }
        if let traditionalDef = definitionChineseTraditional, !traditionalDef.isEmpty {
            return traditionalDef
        }
    }

    // 日文用户（优先显示中文而非英文）
    if languageCode == "ja" {
        if let simplifiedDef = definitionChineseSimplified, !simplifiedDef.isEmpty {
            return simplifiedDef
        }
        if let traditionalDef = definitionChineseTraditional, !traditionalDef.isEmpty {
            return traditionalDef
        }
    }

    // 默认：英文
    return definitionEnglish
}
```

#### 语言优先级

| 用户系统语言 | 显示优先级 |
|------------|----------|
| 简体中文 (zh-Hans) | 简体中文 → 繁体中文 → 英文 |
| 繁体中文 (zh-Hant) | 繁体中文 → 简体中文 → 英文 |
| 日文 (ja) | 简体中文 → 繁体中文 → 英文 |
| 英文 (en) 或其他 | 英文 |

#### 应用位置

本地化定义在以下位置自动应用：

1. **搜索结果列表** (SearchView.swift)
   ```swift
   Text(firstSense.localizedDefinition())
   ```

2. **词条详情页** (EntryDetailView.swift)
   ```swift
   Text("\(index + 1). \(sense.localizedDefinition())")
   ```

## 使用示例

### 场景1：搜索本地词典中不存在的词

**用户操作**：
```
搜索："中午"
```

**系统行为**：
1. 在本地数据库搜索"中午" → 未找到精确匹配
2. 自动触发AI查询
3. AI返回日语词条：「正午」「昼」「昼休み」
4. 显示专业词典格式的AI结果

**显示效果**：
```
❌ 没有找到本地结果

📕 词典查询

正午  しょうご  [shōgo]
━━━━━━━━━━━━━━━━━━
[名詞]

1. 正午；中午十二点
2. 中午时分

用例：
  正午に会いましょう
  中午见吧
```

### 场景2：本地词典存在，不同语言显示

**词条**：食う (kuu)

**数据库内容**：
- English: "to eat"
- Chinese Simplified: "吃；食用"
- Chinese Traditional: "吃；食用"

**不同用户看到的内容**：

| 用户系统语言 | 显示的定义 |
|------------|----------|
| 简体中文 🇨🇳 | 吃；食用 |
| 繁体中文 🇹🇼 | 吃；食用 |
| 英文 🇺🇸 | to eat |
| 日文 🇯🇵 | 吃；食用 |

## 技术细节

### AI触发条件

**触发**：
- `searchResults.isEmpty == true`
- 本地数据库返回0条结果

**不触发**：
- 找到至少1条本地结果
- 搜索框为空
- AI已经在加载中

### 性能优化

1. **缓存机制**：AI结果会被缓存（内存+磁盘），相同查询不会重复调用API
2. **异步加载**：AI查询在后台异步执行，不阻塞UI
3. **取消机制**：如果用户快速修改搜索词，会取消之前的搜索任务

### 错误处理

**AI调用失败时**：
```swift
do {
    let r = try await LLMClient.shared.translateExplain(...)
    aiResult = r
} catch {
    aiError = error.localizedDescription
}
```

**可能的错误**：
- `LLMError.notConfigured` - API Key未配置
- `LLMError.quotaExceeded` - 今日配额已用完（默认50次/天）
- `LLMError.httpError` - 网络错误
- `LLMError.decodeFailed` - JSON解析失败

### 语言检测

系统使用 `Locale.current` 自动检测：

```swift
// AI查询时的语言检测
let locale = Locale.current.language.languageCode?.identifier ?? "zh"

// 本地词条的语言检测
sense.localizedDefinition() // 自动使用 Locale.current
```

## 配置选项

### AI配置（LLMClient.swift）

```swift
// 在应用启动时配置
LLMClient.shared.configure(
    apiKey: "your-api-key",
    provider: .openAI(model: "gpt-4o-mini")
)

// 可选：调整每日配额
LLMClient.shared.dailyLimit = 100 // 默认50次
```

### 支持的AI Provider

1. **OpenAI**
   - `gpt-4o-mini` (推荐)
   - `gpt-4.1-mini`
   - 其他支持JSON模式的模型

2. **Anthropic**
   - `claude-3-haiku`
   - `claude-3-sonnet`

## 用户体验提升

### 无缝查询体验

**之前的流程**：
1. 搜索 → 没有结果
2. 看到"没有结果"提示
3. 手动点击"AI翻译"按钮
4. 等待AI结果
5. 查看翻译

**现在的流程**：
1. 搜索 → 自动显示AI结果 ✨

减少了2个用户操作步骤！

### 母语化显示

中国用户、台湾用户、日本用户、英语用户都能看到适合自己语言的定义，无需手动切换。

## 测试建议

### 测试AI自动触发

1. 搜索数据库中不存在的词（如"xyz123"）
2. 确认自动显示AI解释（无需点击按钮）
3. 搜索存在的词（如"食べる"）
4. 确认只显示本地结果（不触发AI）

### 测试多语言显示

1. **简体中文测试**：
   - 系统语言设置为"简体中文"
   - 搜索"食う"
   - 确认定义显示中文

2. **英文测试**：
   - 系统语言设置为"English"
   - 搜索"食う"
   - 确认定义显示英文

3. **繁体中文测试**：
   - 系统语言设置为"繁体中文（台湾）"
   - 搜索有繁体定义的词
   - 确认显示繁体中文

## 总结

这次更新实现了两个核心改进：

✅ **AI自动触发**：本地无结果时自动调用AI，创造无缝查询体验
✅ **智能多语言**：根据用户系统语言自动显示对应定义

这些改进让NichiDict的用户体验更加流畅和本地化，真正做到了"查即所得"和"因地制宜"。
