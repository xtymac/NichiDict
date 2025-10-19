# 从旧版迁移到多语言版本

## 概述

本文档指导如何从旧的单语言导入系统迁移到新的多语言系统。

## 版本对比

### 旧版本（v1.0）

**文件**：`import_jmdict.py`

**特点**：
- ✅ 基础 JMdict 导入
- ✅ 英文释义
- ✅ FTS5 搜索
- ❌ 仅英文
- ❌ 词性代码（如 `&v5r;, &vt;`）
- ❌ 无 JMdict ID

**数据库结构**：
```sql
CREATE TABLE word_senses (
    id INTEGER PRIMARY KEY,
    entry_id INTEGER,
    definition_english TEXT NOT NULL,  -- 仅此一种语言
    part_of_speech TEXT,               -- 原始代码
    ...
);
```

### 新版本（v2.0）

**文件**：`import_jmdict_multilingual.py`

**特点**：
- ✅ 多语言释义（英文 + 简中 + 繁中）
- ✅ 可读的日语词性标签
- ✅ JMdict ID 追溯
- ✅ 优化的性能
- ✅ 完整文档
- ✅ 自动化测试

**数据库结构**：
```sql
CREATE TABLE word_senses (
    id INTEGER PRIMARY KEY,
    entry_id INTEGER,
    definition_english TEXT NOT NULL,
    definition_chinese_simplified TEXT,    -- ✨ 新增
    definition_chinese_traditional TEXT,   -- ✨ 新增
    part_of_speech TEXT,                   -- 可读的日语
    ...
);

CREATE TABLE dictionary_entries (
    ...
    jmdict_id INTEGER,  -- ✨ 新增：追溯到JMdict
    ...
);
```

## 迁移步骤

### 方案A：完全替换（推荐）

适合：全新开始，不需要保留旧数据

```bash
# 1. 备份旧数据库（可选）
cp data/dictionary_full.sqlite data/dictionary_full_v1_backup.sqlite

# 2. 测试新导入
./scripts/test_multilingual_import.sh

# 3. 完整导入新数据
python3 scripts/import_jmdict_multilingual.py \
    data/JMdict_e \
    data/dictionary_full_multilingual.sqlite

# 4. 替换应用数据库
cp data/dictionary_full_multilingual.sqlite NichiDict/Resources/seed.sqlite

# 5. 重新构建应用
cd NichiDict
xcodebuild -scheme NichiDict build
```

### 方案B：渐进迁移

适合：需要保留自定义数据或逐步迁移

#### 步骤1：导出旧数据中的自定义内容

```bash
# 导出频率数据（如果有）
sqlite3 data/dictionary_full.sqlite << 'EOF' > old_frequencies.csv
.mode csv
.headers on
SELECT id, headword, frequency_rank
FROM dictionary_entries
WHERE frequency_rank IS NOT NULL;
EOF

# 导出音调数据（如果有）
sqlite3 data/dictionary_full.sqlite << 'EOF' > old_pitch_accents.csv
.mode csv
.headers on
SELECT id, headword, pitch_accent
FROM dictionary_entries
WHERE pitch_accent IS NOT NULL;
EOF
```

#### 步骤2：导入新数据

```bash
python3 scripts/import_jmdict_multilingual.py \
    data/JMdict_e \
    data/dictionary_full_multilingual.sqlite
```

#### 步骤3：合并自定义数据

```python
#!/usr/bin/env python3
"""
合并旧数据库的自定义内容到新数据库
"""
import sqlite3
import csv

# 连接数据库
new_db = sqlite3.connect('data/dictionary_full_multilingual.sqlite')
cursor = new_db.cursor()

# 导入频率数据
with open('old_frequencies.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        cursor.execute('''
            UPDATE dictionary_entries
            SET frequency_rank = ?
            WHERE headword = ?
        ''', (row['frequency_rank'], row['headword']))

# 导入音调数据
with open('old_pitch_accents.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        cursor.execute('''
            UPDATE dictionary_entries
            SET pitch_accent = ?
            WHERE headword = ?
        ''', (row['pitch_accent'], row['headword']))

new_db.commit()
new_db.close()

print("合并完成!")
```

### 方案C：并行运行

适合：测试新版本，保留旧版本作为备份

```bash
# 保留旧数据库
data/dictionary_full.sqlite              # 旧版本

# 新数据库使用不同名称
data/dictionary_full_multilingual.sqlite # 新版本

# 应用可配置使用哪个数据库
```

## 代码迁移

### Swift 代码变更

#### 1. 查询中文释义

**旧代码**：
```swift
struct WordSense {
    let id: Int
    let entryId: Int
    let definitionEnglish: String  // 仅此一项
    let partOfSpeech: String
    // ...
}

// 查询
let sense = try WordSense.fetchOne(db, id: senseId)
print(sense.definitionEnglish)
```

**新代码**：
```swift
struct WordSense {
    let id: Int
    let entryId: Int
    let definitionEnglish: String
    let definitionChineseSimplified: String?    // ✨ 新增
    let definitionChineseTraditional: String?   // ✨ 新增
    let partOfSpeech: String
    // ...
}

// 查询并优先显示中文
let sense = try WordSense.fetchOne(db, id: senseId)

// 根据用户语言偏好选择
let locale = Locale.current.language.languageCode?.identifier ?? "en"
let definition = switch locale {
case "zh":
    sense.definitionChineseSimplified ?? sense.definitionEnglish
case "zh-Hans":
    sense.definitionChineseSimplified ?? sense.definitionEnglish
case "zh-Hant":
    sense.definitionChineseTraditional ?? sense.definitionEnglish
default:
    sense.definitionEnglish
}

print(definition)
```

#### 2. 显示词性标签

**旧代码**：
```swift
// 显示原始代码
Text(sense.partOfSpeech)  // "&v5r;, &vt;"
```

**新代码**：
```swift
// 显示可读的日语标签
Text(sense.partOfSpeech)  // "五段動詞（ら）、他動詞"
    .font(.caption)
    .foregroundStyle(.secondary)
```

#### 3. JMdict ID 追溯

**新功能**：
```swift
// 获取 JMdict ID
let entry = try DictionaryEntry.fetchOne(db, id: entryId)
if let jmdictId = entry.jmdictId {
    print("JMdict ID: \(jmdictId)")
    // 可以链接到在线JMdict
    let url = "https://jisho.org/word/\(entry.headword)"
}
```

### 数据库查询变更

#### 旧查询（仅英文）

```sql
SELECT
    e.headword,
    s.definition_english
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE e.headword = '食べる';
```

#### 新查询（多语言）

```sql
SELECT
    e.headword,
    s.definition_english,
    s.definition_chinese_simplified,
    s.definition_chinese_traditional
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE e.headword = '食べる';
```

#### 智能查询（优先中文）

```sql
SELECT
    e.headword,
    COALESCE(
        s.definition_chinese_simplified,
        s.definition_english
    ) as definition
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE e.headword = '食べる';
```

## UI 适配

### 1. 语言切换

添加用户偏好设置：

```swift
enum DefinitionLanguage: String, CaseIterable {
    case english = "English"
    case chineseSimplified = "简体中文"
    case chineseTraditional = "繁體中文"
    case auto = "自动"
}

@AppStorage("preferredDefinitionLanguage")
private var preferredLanguage: DefinitionLanguage = .auto
```

### 2. 多语言显示

```swift
VStack(alignment: .leading, spacing: 4) {
    // 主要定义（根据偏好）
    Text(primaryDefinition)
        .font(.body)

    // 次要定义（其他语言）
    if let secondaryDef = secondaryDefinition {
        Text(secondaryDef)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
```

### 3. 词性标签样式

```swift
// 旧版：代码形式
Text("&v5r;, &vt;")
    .font(.caption)

// 新版：日语标签
Text("五段動詞（ら）、他動詞")
    .font(.caption)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.blue.opacity(0.1))
    .foregroundStyle(.blue)
    .clipShape(Capsule())
```

## 测试计划

### 1. 数据完整性测试

```sql
-- 验证记录数
SELECT 'Old DB' as db, COUNT(*) as count FROM old_db.dictionary_entries
UNION ALL
SELECT 'New DB', COUNT(*) FROM new_db.dictionary_entries;

-- 抽样对比
SELECT
    o.headword,
    o.reading_hiragana,
    o.definition_english as old_def,
    n.definition_english as new_def
FROM old_db.dictionary_entries o
JOIN new_db.dictionary_entries n ON o.headword = n.headword
LIMIT 100;
```

### 2. 功能测试

- [ ] 搜索功能正常（日语、假名、罗马音）
- [ ] 多语言释义正确显示
- [ ] 词性标签可读（非代码）
- [ ] FTS搜索速度无明显变化
- [ ] 详情页面正确渲染
- [ ] 语言切换功能正常

### 3. 性能测试

```swift
// 测试查询速度
let startTime = Date()
let results = try searchService.search(query: "食べる", maxResults: 50)
let elapsed = Date().timeIntervalSince(startTime)
print("Search took \(elapsed)s")

// 应该 < 100ms
assert(elapsed < 0.1, "Search too slow")
```

## 回滚计划

如果新版本有问题，可以快速回滚：

```bash
# 1. 恢复旧数据库
cp data/dictionary_full_v1_backup.sqlite NichiDict/Resources/seed.sqlite

# 2. 重新构建
cd NichiDict
xcodebuild -scheme NichiDict build

# 3. 验证应用正常工作
```

## 常见问题

### Q1：新数据库比旧的大吗？

**A**：略大（~10-15%），因为增加了中文字段和 JMdict ID。

| 版本 | 大小 |
|------|------|
| 旧版本 | ~80MB |
| 新版本 | ~90MB |

### Q2：中文释义覆盖率如何？

**A**：取决于 JMdict 版本：

| 版本 | 中文释义覆盖率 |
|------|---------------|
| JMdict_e | ~5-10% |
| JMdict (完整) | ~15-20% |
| + Wiktionary | ~20-25% |

### Q3：性能有变化吗？

**A**：查询速度基本相同，因为：
- FTS索引结构未变
- 主要查询路径相同
- 新字段只在需要时读取

### Q4：可以只导入某些语言吗？

**A**：可以修改脚本，注释掉不需要的语言：

```python
# 只保留英文和简体中文
if lang == 'eng':
    glosses_eng.append(gloss_text)
elif lang in ('chi', 'zh-Hans', 'zhs'):
    glosses_chi_simp.append(gloss_text)
# elif lang in ('zh-Hant', 'zht'):  # 注释掉繁体
#     glosses_chi_trad.append(gloss_text)
```

### Q5：如何补充缺失的中文翻译？

**A**：三种方法：

1. **使用完整 JMdict**（非_e版本）
2. **Wiktionary 补充**（现有脚本）
3. **AI 生成**（需实现）

## 技术支持

### 文档

- [多语言导入指南](JMDICT_MULTILINGUAL_IMPORT_GUIDE.md)
- [完成总结](MULTILINGUAL_IMPORT_SUMMARY.md)
- [快速参考](scripts/README_MULTILINGUAL.md)

### 脚本

- 测试脚本：`./scripts/test_multilingual_import.sh`
- 导入脚本：`scripts/import_jmdict_multilingual.py`
- 旧版脚本：`scripts/import_jmdict.py`（保留）

### 问题报告

如遇问题，请提供：
1. 使用的 JMdict 版本（_e 或完整版）
2. 导入日志（`scripts/multilingual_import_test.log`）
3. 数据库统计（见下方）

```bash
# 生成诊断信息
sqlite3 data/dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on

SELECT 'Table' as Type, 'Count' as Value
UNION ALL
SELECT 'Entries', COUNT(*) FROM dictionary_entries
UNION ALL
SELECT 'Senses', COUNT(*) FROM word_senses
UNION ALL
SELECT 'With Chinese', COUNT(DISTINCT entry_id) FROM word_senses
  WHERE definition_chinese_simplified IS NOT NULL
    OR definition_chinese_traditional IS NOT NULL;
EOF
```

## 检查清单

迁移完成后，验证以下内容：

- [ ] 旧数据库已备份
- [ ] 新数据库导入成功
- [ ] 词条数量匹配（±5%可接受）
- [ ] 抽样检查数据正确
- [ ] Swift 代码已更新
- [ ] UI 适配多语言显示
- [ ] 搜索功能正常
- [ ] 性能无明显下降
- [ ] 用户测试通过
- [ ] 回滚计划就绪

## 总结

✅ **推荐方案**：方案A（完全替换）

**原因**：
- 新数据库完全兼容旧结构
- 只是增加了字段，不影响现有功能
- 词性标签更可读
- 有 JMdict ID 追溯
- 为未来多语言扩展打基础

**迁移时间**：
- 导入新数据：10-15分钟
- 代码适配：1-2小时
- 测试验证：2-3小时
- **总计**：~半天

**风险**：低
- 保留旧数据库备份
- 可快速回滚
- 渐进式适配代码

---

**开始迁移**：`./scripts/test_multilingual_import.sh`
