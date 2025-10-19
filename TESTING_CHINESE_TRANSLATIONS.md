# Testing Chinese Translations - User Guide

本指南提供多种方法来测试和验证中文翻译功能。

## 测试工具

### 1. 完整测试报告 (`test_chinese_translations.sh`)

**用途**: 全面检查数据库中的中文翻译，包括统计、质量检查、常见词测试等。

**运行方法**:
```bash
cd scripts
./test_chinese_translations.sh
```

**使用自定义数据库路径**:
```bash
./test_chinese_translations.sh /path/to/custom/database.sqlite
```

**测试内容**:
- ✅ 整体统计（覆盖率、总数）
- ✅ 常见词测试（食べる、今日、学校等）
- ✅ 简体/繁体中文分布
- ✅ 高频词前10名
- ✅ 词性分布
- ✅ FTS5搜索功能
- ✅ 数据质量检查

**示例输出**:
```
========================================
  Chinese Translation Test Report
========================================

📊 Test 1: Overall Statistics
-----------------------------------
Total dictionary entries: 213730
Entries with Chinese: 4349
Coverage: 2.03%

📝 Test 2: Common Words Test
-----------------------------------
✓ 食べる (たべる)
  EN: to eat
  ZH: 喫; 食; 召; 頂

✓ 今日 (きょう)
  EN: today; this day
  ZH: 今天
```

---

### 2. 交互式查询工具 (`query_word.sh`)

**用途**: 快速查询单个单词的详细信息和中文翻译。

**单次查询模式**:
```bash
cd scripts
./query_word.sh "食べる"
```

**交互模式**:
```bash
./query_word.sh
```

进入交互模式后，可以连续输入多个单词：
```
Query> 食べる
[显示结果]

Query> 勉強
[显示结果]

Query> quit
Goodbye!
```

**支持的输入格式**:
- 汉字: `食べる`
- 平假名: `たべる`
- 罗马字: `taberu`

**示例输出**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Search: 食べる
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1] 食べる (たべる)
    Romaji: taberu

    Ichidan verb, transitive verb
    EN: to eat
    ZH: 喫; 食; 召; 頂

    Ichidan verb, transitive verb
    EN: to live on (e.g. a salary)
    ZH: 喫; 食; 召; 頂

─────────────────────────────────────────

Found 1 result(s)
```

---

### 3. 直接SQL查询

**用途**: 自定义查询，深入探索数据。

**基本查询**:
```bash
sqlite3 data/dictionary_full.sqlite
```

**常用SQL示例**:

#### 查询特定单词的中文翻译
```sql
SELECT
    e.headword,
    e.reading_hiragana,
    s.definition_english,
    s.definition_chinese_simplified
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE e.headword = '食べる';
```

#### 统计中文翻译覆盖率
```sql
SELECT
    COUNT(DISTINCT entry_id) as entries_with_chinese,
    (SELECT COUNT(*) FROM dictionary_entries) as total_entries,
    ROUND(100.0 * COUNT(DISTINCT entry_id) / (SELECT COUNT(*) FROM dictionary_entries), 2) as coverage_percent
FROM word_senses
WHERE definition_chinese_simplified IS NOT NULL;
```

#### 查找所有动词的中文翻译
```sql
SELECT
    e.headword,
    e.reading_hiragana,
    s.part_of_speech,
    s.definition_chinese_simplified
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE s.part_of_speech LIKE '%verb%'
AND s.definition_chinese_simplified IS NOT NULL
LIMIT 20;
```

#### 查找最常用的有中文翻译的词
```sql
SELECT
    e.headword,
    e.reading_hiragana,
    e.frequency_rank,
    s.definition_chinese_simplified
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE s.definition_chinese_simplified IS NOT NULL
AND e.frequency_rank IS NOT NULL
ORDER BY e.frequency_rank ASC
LIMIT 50;
```

---

## 在App中测试

### 1. 查看中文翻译

**步骤**:
1. 启动App
2. 在搜索栏输入日文单词（例如：`食べる`）
3. 点击搜索结果进入详情页
4. 查看定义部分，中文翻译会显示在英文下方

**显示格式**:
```
Ichidan verb, transitive

1. to eat
   喫; 食; 召; 頂

2. to live on (e.g. a salary)
   喫; 食; 召; 頂
```

### 2. 语言切换测试

**简体中文用户**:
- 系统语言设置为简体中文
- App会优先显示简体中文翻译

**繁体中文用户**:
- 系统语言设置为繁体中文（台湾/香港）
- App会优先显示繁体中文翻译（如果有）
- 如果没有繁体，会回退到简体

**测试步骤**:
1. 进入 设置 > 通用 > 语言与地区
2. 修改首选语言顺序
3. 重启App
4. 验证显示的中文形式

---

## 推荐测试词汇列表

### 高频常用词（应该有中文）
```
食べる (eat)
今日 (today)
学校 (school)
勉強 (study)
行く (go)
来る (come)
見る (see/watch)
水 (water)
人 (person)
時間 (time)
```

### JLPT N5 基础词汇
```
私 (I/me)
あなた (you)
これ (this)
それ (that)
何 (what)
いつ (when)
どこ (where)
誰 (who)
どう (how)
なぜ (why)
```

### 动词测试
```
する (do)
ある (exist/have)
いる (exist/be)
なる (become)
言う (say)
思う (think)
分かる (understand)
書く (write)
読む (read)
聞く (listen/hear)
```

---

## 故障排查

### 问题1: 没有中文翻译显示

**检查清单**:
1. ✓ 数据库是否包含中文数据？
   ```bash
   ./scripts/test_chinese_translations.sh
   ```

2. ✓ App是否使用了最新的数据库？
   ```bash
   ls -lh NichiDict/Resources/seed.sqlite
   # 应该显示 ~62MB
   ```

3. ✓ 该词条是否有中文翻译？
   ```bash
   ./scripts/query_word.sh "单词"
   ```

### 问题2: 构建后中文不显示

**解决方法**:
1. 清理构建缓存
   ```bash
   cd NichiDict
   xcodebuild clean
   ```

2. 重新构建
   ```bash
   xcodebuild -project NichiDict.xcodeproj -scheme NichiDict build
   ```

3. 验证资源文件被正确打包
   ```bash
   # 检查build输出中是否包含seed.sqlite
   ```

### 问题3: 覆盖率低

**当前状态**: ~2% 覆盖率（4,349 / 213,730 词条）

**改进方法**:
1. 导入更多中文词典源
2. 使用AI翻译补充（仅当本地无匹配时）
3. 接受社区贡献

---

## 数据质量指标

### 良好状态的标准
- ✅ 无空的中文翻译字段
- ✅ 中文翻译包含中文字符
- ✅ 翻译长度合理（<200字符）
- ✅ 常用词有翻译（JLPT N5-N3）
- ✅ 高频词有翻译（frequency_rank < 5000）

### 监控命令
```bash
# 运行完整测试报告
./scripts/test_chinese_translations.sh

# 查看数据质量部分
# Test 7: Data Quality Check
```

---

## 持续集成建议

### 自动化测试脚本
```bash
#!/bin/bash
# ci_test_chinese.sh

# 运行测试
./scripts/test_chinese_translations.sh > test_report.txt

# 检查最低覆盖率 (例如 2%)
coverage=$(grep "Coverage:" test_report.txt | grep -oE '[0-9.]+')
if (( $(echo "$coverage < 2.0" | bc -l) )); then
    echo "Error: Coverage too low ($coverage%)"
    exit 1
fi

echo "✓ Chinese translation tests passed"
exit 0
```

---

## 更多资源

### 相关文档
- [CHINESE_TRANSLATION_REPORT.md](CHINESE_TRANSLATION_REPORT.md) - 完整实现报告
- [DICTIONARY_IMPORT_REPORT.md](DICTIONARY_IMPORT_REPORT.md) - JMdict导入文档
- [scripts/import_chinese_translations.py](scripts/import_chinese_translations.py) - 导入脚本

### 数据来源
- **Wiktionary**: https://kaikki.org/dictionary/Japanese/
- **License**: CC-BY-SA 4.0

### 技术支持
如遇到问题，请检查：
1. 数据库完整性: `sqlite3 data/dictionary_full.sqlite "PRAGMA integrity_check;"`
2. FTS5索引: `sqlite3 data/dictionary_full.sqlite "SELECT COUNT(*) FROM dictionary_fts;"`
3. 构建日志中的错误信息

---

**Happy Testing! 🎉**
