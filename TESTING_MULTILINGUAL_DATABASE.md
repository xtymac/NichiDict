# 多语言数据库测试指南

## ✅ 导入成功！

```
✅ 词条数：427,460
✅ 义项数：493,484
✅ FTS索引：427,460
✅ 数据库大小：127 MB
✅ 完整性检查：通过
```

## 🧪 测试步骤

### 第1步：基础查询测试

#### 测试常用词

```bash
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/data"
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on
.width 15 15 25 50

-- 查询"食べる"
SELECT
    e.headword as 見出し語,
    e.reading_hiragana as 読み,
    s.part_of_speech as 品詞,
    s.definition_english as 定義
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE e.headword = '食べる'
LIMIT 5;
EOF
```

**预期结果**：应该显示"食べる"的多个义项

#### 测试词性标注

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on

-- 检查词性是否为可读的日语标签
SELECT DISTINCT part_of_speech
FROM word_senses
LIMIT 20;
EOF
```

**预期结果**：应该看到如下标签：
- `一段動詞、他動詞`
- `五段動詞（ら）`
- `名詞`
- `な形容詞`

**❌ 不应该看到**：`&v1;`、`&v5r;` 这样的代码

### 第2步：FTS全文搜索测试

#### 测试罗马音搜索

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on
.width 15 15 50

-- 搜索 "tabe*"
SELECT
    e.headword,
    e.reading_hiragana,
    s.definition_english
FROM dictionary_fts fts
JOIN dictionary_entries e ON fts.rowid = e.id
JOIN word_senses s ON e.id = s.entry_id
WHERE dictionary_fts MATCH 'tabe*'
AND s.sense_order = 1
LIMIT 10;
EOF
```

**预期结果**：应该找到 `食べる` 等以 "tabe" 开头的词

#### 测试假名搜索

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on

-- 搜索 "たべ*"
SELECT
    e.headword,
    e.reading_hiragana
FROM dictionary_fts fts
JOIN dictionary_entries e ON fts.rowid = e.id
WHERE dictionary_fts MATCH 'たべ*'
LIMIT 10;
EOF
```

### 第3步：词性分布统计

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on

-- 最常见的词性（前20）
SELECT
    part_of_speech,
    COUNT(*) as count
FROM word_senses
GROUP BY part_of_speech
ORDER BY count DESC
LIMIT 20;
EOF
```

**预期结果**：应该看到词性的分布情况

### 第4步：JMdict ID 验证

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on

-- 检查 JMdict ID
SELECT
    id,
    jmdict_id,
    headword,
    reading_hiragana
FROM dictionary_entries
WHERE jmdict_id IS NOT NULL
LIMIT 10;
EOF
```

**预期结果**：所有词条都应该有 JMdict ID

### 第5步：性能测试

#### 搜索速度测试

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.timer on

-- 测试FTS搜索性能
SELECT COUNT(*)
FROM dictionary_fts
WHERE dictionary_fts MATCH 'suru*';

-- 测试精确查询性能
SELECT COUNT(*)
FROM dictionary_entries
WHERE headword = '食べる';
EOF
```

**预期结果**：
- FTS搜索：< 100ms
- 精确查询：< 10ms

### 第6步：数据抽样验证

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode list
.separator " | "
.headers on

-- 随机抽样10个词条
SELECT
    e.headword,
    e.reading_hiragana,
    s.part_of_speech,
    substr(s.definition_english, 1, 40)
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE s.sense_order = 1
ORDER BY RANDOM()
LIMIT 10;
EOF
```

**检查**：
- ✅ 见出し語是否正确（日语）
- ✅ 读音是否为平假名
- ✅ 品词是否可读（日语标签）
- ✅ 定义是否为英文

## 📱 应用集成测试

### 步骤1：替换应用数据库

```bash
# 备份当前数据库
cp "NichiDict/Resources/seed.sqlite" "NichiDict/Resources/seed.sqlite.backup"

# 使用新数据库
cp "data/dictionary_full_multilingual.sqlite" "NichiDict/Resources/seed.sqlite"
```

### 步骤2：重新构建应用

```bash
cd NichiDict
xcodebuild -scheme NichiDict -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### 步骤3：应用内测试

启动应用后，测试以下功能：

#### ✅ 搜索功能
- [ ] 输入 "tabe" - 应该显示 `食べる`
- [ ] 输入 "たべる" - 应该显示 `食べる`
- [ ] 输入 "食べる" - 应该显示完整词条

#### ✅ 词条显示
- [ ] 点击 `食べる`
- [ ] 检查：
  - 见出し語：`食べる`
  - 读音：`たべる [taberu]`
  - 品词标签：`一段動詞、他動詞`（蓝色胶囊）
  - 定义：英文释义正确显示

#### ✅ 多义项显示
- [ ] 搜索有多个义项的词（如 `行く`、`来る`）
- [ ] 检查：
  - 义项编号：1. 2. 3.
  - 每个义项有独立的品词标签
  - 定义清晰分隔

#### ✅ 性能测试
- [ ] 搜索响应速度快（< 100ms）
- [ ] 滚动流畅
- [ ] 无明显卡顿

## 🔍 高级测试

### 测试多变体词条

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on
.width 15 15 50

-- 查找同一个读音的多个表记
SELECT
    headword,
    reading_hiragana,
    COUNT(*) as variant_count
FROM dictionary_entries
GROUP BY reading_hiragana
HAVING COUNT(*) > 5
ORDER BY variant_count DESC
LIMIT 10;
EOF
```

### 测试长词条

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on

-- 最长的见出し語
SELECT
    headword,
    LENGTH(headword) as len,
    reading_hiragana
FROM dictionary_entries
ORDER BY len DESC
LIMIT 10;
EOF
```

### 测试特殊字符

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on

-- 包含特殊符号的词条
SELECT headword, reading_hiragana
FROM dictionary_entries
WHERE headword LIKE '%・%'
   OR headword LIKE '%〜%'
   OR headword LIKE '%＝%'
LIMIT 10;
EOF
```

## 📊 数据质量检查

### 检查缺失数据

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.mode column
.headers on

-- 检查是否有空的必填字段
SELECT
    'Missing headword' as Issue,
    COUNT(*) as Count
FROM dictionary_entries
WHERE headword IS NULL OR headword = ''
UNION ALL
SELECT
    'Missing reading',
    COUNT(*)
FROM dictionary_entries
WHERE reading_hiragana IS NULL OR reading_hiragana = ''
UNION ALL
SELECT
    'Missing definition',
    COUNT(*)
FROM word_senses
WHERE definition_english IS NULL OR definition_english = '';
EOF
```

**预期结果**：所有计数应为 0

### 检查数据一致性

```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
-- FTS索引与词条表是否同步
SELECT
    'Entries' as Table,
    COUNT(*) as Count
FROM dictionary_entries
UNION ALL
SELECT
    'FTS Index',
    COUNT(*)
FROM dictionary_fts;
EOF
```

**预期结果**：两个数字应该相同（427,460）

## ✅ 测试检查清单

完成以下测试后打勾：

### 数据库测试
- [ ] 基础查询测试通过
- [ ] FTS搜索功能正常
- [ ] 词性显示为日语标签（非代码）
- [ ] JMdict ID 存在
- [ ] 性能满足要求（搜索 < 100ms）
- [ ] 数据抽样正确
- [ ] 无缺失必填字段
- [ ] FTS索引同步

### 应用测试
- [ ] 数据库替换成功
- [ ] 应用构建成功
- [ ] 搜索功能正常（日语、假名、罗马音）
- [ ] 词条详情正确显示
- [ ] 品词标签可读
- [ ] 多义项正确显示
- [ ] 性能流畅

### 边界情况
- [ ] 多变体词条正常
- [ ] 长词条正常
- [ ] 特殊字符正常

## 🐛 常见问题排查

### 问题1：搜索无结果

**检查**：
```bash
sqlite3 dictionary_full_multilingual.sqlite "SELECT COUNT(*) FROM dictionary_fts;"
```

如果返回0，FTS索引可能损坏，需要重新导入。

### 问题2：词性显示为代码

**检查**：
```bash
sqlite3 dictionary_full_multilingual.sqlite "SELECT part_of_speech FROM word_senses LIMIT 1;"
```

如果看到 `&v5r;`，说明使用了旧版导入脚本。

### 问题3：应用构建失败

**检查**：
```bash
# 确认数据库存在
ls -lh "NichiDict/Resources/seed.sqlite"

# 确认数据库可读
sqlite3 "NichiDict/Resources/seed.sqlite" "SELECT COUNT(*) FROM dictionary_entries;"
```

### 问题4：搜索很慢

**检查索引**：
```bash
sqlite3 dictionary_full_multilingual.sqlite << 'EOF'
.schema dictionary_fts
SELECT * FROM sqlite_master WHERE type='index';
EOF
```

## 📈 性能基准

| 操作 | 预期时间 | 实际时间 | 状态 |
|------|---------|---------|------|
| 启动应用 | < 1s | ___ | ___ |
| 首次搜索 | < 200ms | ___ | ___ |
| 后续搜索 | < 100ms | ___ | ___ |
| 打开词条 | < 50ms | ___ | ___ |
| 滚动列表 | 60fps | ___ | ___ |

## 🎉 测试完成

如果所有测试通过，恭喜！你的多语言数据库已经可以投入使用了。

### 下一步建议

1. **补充中文翻译**（可选）
   ```bash
   python3 scripts/import_chinese_translations.py
   ```

2. **添加音调数据**（未来）
   - 集成 OJAD 数据

3. **添加例句**（未来）
   - 集成 Tatoeba 数据

4. **用户测试**
   - 收集真实用户反馈
   - 调整UI显示

---

**测试时间**：2025-10-16
**数据库版本**：v2.0 (Multilingual)
**状态**：✅ 准备测试
