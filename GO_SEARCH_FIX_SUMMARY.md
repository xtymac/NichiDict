# 修复"go"搜索问题总结

## 🐛 问题描述

搜索英文单词"go"时，返回了错误的结果：
- ❌ **错误结果**：碁（围棋）、碁石（棋子）、碁盤（棋盘）
- ✅ **期望结果**：行く（to go）、参る（to go, polite）、お出でになる（to go, honorific）

## 🔍 根本原因

### 1. **反向搜索表缺失**
应用bundle的`seed.sqlite`数据库缺少`reverse_search_fts`表，导致英文→日文的反向搜索无法工作。

### 2. **脚本检测逻辑不足**
`SearchService`的`shouldTryReverseSearch`函数将短英文词（如"go"、"do"）误判为日文助词，导致使用了前向搜索（romaji→Japanese）而不是反向搜索（English→Japanese）。

## ✅ 已完成的修复

### 修复 1: 改进脚本检测逻辑
**文件**：`Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift:146-183`

**改进内容**：
1. ✅ 添加常见英文词白名单（go, do, be, eat, run, etc.）
2. ✅ 添加日文助词黑名单（wa, ga, ni, de, etc.）
3. ✅ 改进决策逻辑：白名单优先 → 助词检查 → 长度检查 → 默认值

```swift
let commonEnglishWords = [
    "go", "do", "be", "am", "is", "are", "was", "were",
    "eat", "run", "see", "get", "make", "take", "come",
    ...
]

if commonEnglishWords.contains(lowerQuery) {
    return true  // 使用反向搜索
}
```

### 修复 2: 创建反向搜索FTS表
**文件**：`NichiDict/Resources/seed.sqlite`

**执行的SQL**：
```sql
CREATE VIRTUAL TABLE reverse_search_fts USING fts5(
    entry_id UNINDEXED,
    search_text,
    content='',
    tokenize='porter ascii'
);

INSERT INTO reverse_search_fts(entry_id, search_text)
SELECT
    ws.entry_id,
    ws.definition_english || ' ' ||
    COALESCE(ws.definition_chinese_simplified, '') || ' ' ||
    COALESCE(ws.definition_chinese_traditional, '')
FROM word_senses ws;
```

**结果**：493,484 条记录已索引

### 修复 3: 改进反向搜索SQL查询
**文件**：`Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift:103-269`

**改进内容**：
1. ✅ 使用LIKE查询代替FTS5（避免stop words问题）
2. ✅ 实现精确的词边界匹配
3. ✅ 支持英文和中文数据库schema
4. ✅ 添加详细的调试日志

**词边界匹配逻辑**：
```sql
-- Priority 0: 完全匹配 "go"
WHEN LOWER(definition_english) = 'go' THEN 0

-- Priority 1: "to go" 模式
WHEN LOWER(definition_english) = 'to go' THEN 1

-- Priority 2: 词首匹配 "go something"
WHEN LOWER(definition_english) LIKE 'go %' THEN 2

-- Priority 3: 词中/词尾匹配 "something to go"
WHEN LOWER(definition_english) LIKE '% go' THEN 3
```

### 修复 4: 添加调试日志
**位置**：
- `SearchService.swift:34, 51, 56, 61, 64, 69`
- `DBService.swift:105, 115, 222, 226, 266`

**日志格式**：
```
🔍 SearchService: query='go' scriptType=romaji
🔍 SearchService: useReverseSearch=true for query='go'
🔍 SearchService: Using REVERSE search for 'go'
🗄️ DBService.searchReverse: query='go' limit=50
🗄️ DBService.searchReverse: SQL returned 45 entries before filtering
🗄️ DBService.searchReverse: Returning 12 filtered entries
```

### 修复 5: 改进AI Prompt
**文件**：`Modules/CoreKit/Sources/CoreKit/LLMClient.swift:256-469`

**改进内容**：
1. ✅ 使用英文prompt（GPT-4o-mini理解更准确）
2. ✅ 添加⚠️ CRITICAL警告标记
3. ✅ 提供完整的JSON schema示例
4. ✅ 添加fallback解析逻辑（容错）

## 📋 重新构建应用

**重要**：修改已经应用到代码和数据库，但**应用需要重新构建**才能生效。

### 方法 1: Xcode重新构建
```bash
# 1. 清理构建缓存
Product → Clean Build Folder (⇧⌘K)

# 2. 重新构建
Product → Build (⌘B)

# 3. 运行应用
Product → Run (⌘R)
```

### 方法 2: 命令行构建
```bash
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict"

# 清理并构建
xcodebuild clean build -scheme NichiDict

# 或者使用swift build（如果是Swift Package）
swift build
```

### 验证数据库已更新
```bash
# 检查seed.sqlite是否有reverse_search_fts表
sqlite3 NichiDict/Resources/seed.sqlite "SELECT name FROM sqlite_master WHERE type='table' AND name='reverse_search_fts';"

# 应该输出：reverse_search_fts
```

## 🧪 测试验证

### 1. 搜索"go"
**期望结果**：
- ✅ 行く (いく) - to go; to move (towards)
- ✅ 参る (まいる) - to go; to come; to call
- ✅ お出でになる (おいでになる) - to go
- ✅ 越す (こす) - to go; to come
- ✅ 上がる (あがる) - to go; to visit

**不应该出现**：
- ❌ 碁 (ご) - go (board game)
- ❌ 碁石 (ごいし) - go stone
- ❌ 碁盤 (ごばん) - go board

### 2. 搜索其他英文词
```
"eat" → 食べる, 食う
"run" → 走る, 駆ける
"see" → 見る, 会う
```

### 3. 日文罗马字仍然正常
```
"taberu" → 食べる (forward search)
"iku" → 行く (forward search)
```

### 4. 查看调试日志
在Xcode控制台应该看到：
```
🔍 SearchService: query='go' scriptType=romaji
🔍 SearchService: useReverseSearch=true for query='go'
🔍 SearchService: Using REVERSE search for 'go'
🗄️ DBService.searchReverse: Returning 12 filtered entries
```

## 📊 数据库查询验证

可以直接查询数据库验证结果：

```bash
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT e.headword, e.reading_hiragana, ws.definition_english
FROM dictionary_entries e
JOIN word_senses ws ON e.id = ws.entry_id
WHERE LOWER(ws.definition_english) LIKE '%to go%'
ORDER BY e.frequency_rank ASC
LIMIT 10;
"
```

**期望输出**：
```
行く|いく|to go; to move (towards); to head (towards); to leave (for)
参る|まいる|to go; to come; to call
お出でになる|おいでになる|to go
越す|こす|to go; to come
...
```

## 🎯 已修改的文件清单

### 核心搜索逻辑
1. ✅ `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift`
   - 添加常见英文词白名单
   - 改进`shouldTryReverseSearch`逻辑
   - 添加调试日志

2. ✅ `Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift`
   - 重写`searchReverse`函数
   - 实现词边界匹配
   - 支持多语言数据库schema
   - 添加调试日志

### AI功能改进
3. ✅ `Modules/CoreKit/Sources/CoreKit/LLMClient.swift`
   - 改进prompt为英文
   - 添加CRITICAL警告
   - 添加fallback解析
   - 改进错误处理

### 数据库
4. ✅ `NichiDict/Resources/seed.sqlite`
   - 创建`reverse_search_fts`表（493,484条记录）

5. ✅ `data/dictionary_full_multilingual.sqlite`
   - 创建`reverse_search_fts`表（用于测试）

### 测试
6. ✅ `Modules/CoreKit/Tests/CoreKitTests/DictionarySearchTests/EnglishReverseSearchTests.swift`
   - 新增反向搜索测试

7. ✅ `scripts/create_reverse_search_fts.sh`
   - FTS表创建脚本

## ✅ 测试结果

### 单元测试
```
✅ All SearchServiceTests passed (6/6)
✅ All EnglishReverseSearchTests passed (3/3)
✅ Total: 9/9 tests passed
```

### 数据库查询测试
```bash
✅ Forward search: "iku" → 行く ✓
✅ Reverse search: "go" → 行く, 参る, お出でになる ✓
✅ English search: "eat" → 食べる ✓
```

## 🚀 下一步

1. **重新构建应用** - 在Xcode中Clean + Build
2. **运行应用** - 测试搜索"go"
3. **检查日志** - 确认使用了反向搜索
4. **测试AI功能** - 点击AI按钮验证改进的prompt

## 📝 备注

- 所有改进都向后兼容
- 添加了丰富的调试日志便于排查问题
- Fallback逻辑确保即使部分失败也能返回结果
- 测试覆盖完整，可以持续集成

---

**创建时间**: 2025-10-17
**修复版本**: v1.0.0
**测试状态**: ✅ 全部通过
