# NichiDict Scripts - Quick Reference

这个目录包含了用于测试和管理字典数据的实用脚本。

## 🚀 快速开始

### 1. 测试中文翻译功能（推荐）

```bash
# 完整测试报告
./test_chinese_translations.sh

# 输出示例：
# - 覆盖率统计
# - 常用词测试
# - 数据质量检查
# - 搜索功能验证
```

### 2. 查询单个单词

```bash
# 单次查询
./query_word.sh "食べる"

# 交互模式（推荐）
./query_word.sh
# 然后输入多个单词查询
```

### 3. 导入新数据

```bash
# 导入JMdict英文词典
python3 import_jmdict.py

# 导入中文翻译（需先下载Wiktionary数据）
python3 import_chinese_translations.py
```

---

## 📋 所有脚本

### Python脚本

| 脚本 | 用途 | 运行时间 | 输入 | 输出 |
|------|------|----------|------|------|
| `import_jmdict.py` | 导入JMdict日英词典 | ~5分钟 | JMdict_e.gz (58MB) | dictionary_full.sqlite (60MB) |
| `import_chinese_translations.py` | 导入中文翻译 | ~3分钟 | ja-extract.jsonl.gz (47MB) | 更新的SQLite数据库 |

### Shell脚本

| 脚本 | 用途 | 模式 | 示例 |
|------|------|------|------|
| `test_chinese_translations.sh` | 全面测试中文翻译 | 单次运行 | `./test_chinese_translations.sh` |
| `query_word.sh` | 查询单词详情 | 单次/交互 | `./query_word.sh 食べる` |
| `test_search_ranking.sh` | 测试搜索排序 | 单次运行 | `./test_search_ranking.sh` |

---

## 🔍 常见使用场景

### 场景1: 验证导入结果

```bash
# 1. 导入中文翻译
python3 import_chinese_translations.py

# 2. 运行测试验证
./test_chinese_translations.sh

# 3. 查询几个常用词确认
./query_word.sh
# 输入: 食べる
# 输入: 勉強
# 输入: quit
```

### 场景2: 调试特定单词

```bash
# 使用查询工具
./query_word.sh "問題的な単词"

# 或使用SQL直接查询
sqlite3 ../data/dictionary_full.sqlite
sqlite> SELECT * FROM dictionary_entries WHERE headword = '単词';
```

### 场景3: 检查数据质量

```bash
# 运行完整测试报告
./test_chinese_translations.sh > report.txt

# 查看关键指标
grep "Coverage:" report.txt
grep "Empty Chinese" report.txt
grep "Entries without Chinese characters" report.txt
```

### 场景4: 性能测试

```bash
# 测试搜索排序性能
./test_search_ranking.sh

# 测试多个常用词
for word in 食べる 行く 来る 見る; do
    echo "Testing: $word"
    time ./query_word.sh "$word" > /dev/null
done
```

---

## ⚙️ 脚本详细说明

### `test_chinese_translations.sh`

**功能**: 7项全面测试
1. 整体统计（覆盖率、总数）
2. 常见词测试（9个常用词）
3. 简体/繁体分布
4. 高频词TOP 10
5. 词性分布
6. FTS5搜索功能
7. 数据质量检查

**选项**:
```bash
# 默认数据库
./test_chinese_translations.sh

# 自定义数据库
./test_chinese_translations.sh /custom/path/db.sqlite
```

**输出解读**:
- ✓ (绿色) = 测试通过
- ✗ (红色) = 测试失败
- Coverage < 2% = 需要导入更多数据
- Empty translations > 0 = 数据质量问题

---

### `query_word.sh`

**功能**: 交互式单词查询

**两种模式**:

1. **单次查询模式**:
   ```bash
   ./query_word.sh "食べる"
   ```

2. **交互模式**:
   ```bash
   ./query_word.sh
   Query> 食べる
   [结果显示]
   Query> たべる
   [结果显示]
   Query> taberu
   [结果显示]
   Query> quit
   ```

**支持的输入**:
- 汉字：`食べる`
- 平假名：`たべる`
- 罗马字：`taberu`

**输出包含**:
- 所有匹配的词条
- 读音（平假名、罗马字）
- 音调、频率
- 所有定义（英文+中文）
- 词性标签

---

### `import_chinese_translations.py`

**功能**: 从Wiktionary导入中文翻译

**前置条件**:
```bash
# 下载Wiktionary数据
cd ../data
curl -L -o ja-extract.jsonl.gz \
  https://kaikki.org/dictionary/downloads/ja/ja-extract.jsonl.gz
```

**运行**:
```bash
python3 import_chinese_translations.py
```

**输出示例**:
```
Starting Chinese translation import...
Building lookup index of existing entries...
Processing Wiktionary data...
  Processed 10000 entries, matched 302...
  ...
=== Import Statistics ===
Matched to our database: 3,512
Total entries now with Chinese: 4,349
```

**注意事项**:
- 处理时间：约3-5分钟
- 内存使用：< 500MB
- 自动创建数据库备份

---

## 🛠️ 故障排查

### 问题：脚本没有执行权限

```bash
chmod +x *.sh
```

### 问题：找不到数据库

```bash
# 检查数据库位置
ls -lh ../data/*.sqlite

# 使用绝对路径
./test_chinese_translations.sh /absolute/path/to/db.sqlite
```

### 问题：Python脚本错误

```bash
# 确认Python版本（需要3.7+）
python3 --version

# 检查依赖
python3 -c "import sqlite3; import gzip; import json"
```

### 问题：中文显示乱码

```bash
# 设置正确的locale
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
```

---

## 📊 输出示例

### `test_chinese_translations.sh` 输出

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

[... 更多测试结果 ...]

========================================
  Summary
========================================

✓ Chinese translations are present
✓ 4349 entries have Chinese definitions
✓ Coverage: 2.03% of total entries
```

### `query_word.sh` 输出

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Search: 食べる
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1] 食べる (たべる)
    Romaji: taberu

    Ichidan verb, transitive verb
    EN: to eat
    ZH: 喫; 食; 召; 頂

─────────────────────────────────────────

Found 1 result(s)
```

---

## 🔗 相关文档

- [../TESTING_CHINESE_TRANSLATIONS.md](../TESTING_CHINESE_TRANSLATIONS.md) - 完整测试指南
- [../CHINESE_TRANSLATION_REPORT.md](../CHINESE_TRANSLATION_REPORT.md) - 实现报告
- [../DICTIONARY_IMPORT_REPORT.md](../DICTIONARY_IMPORT_REPORT.md) - JMdict导入文档

---

## 💡 提示

### 性能优化
- 使用SSD存储数据库可加快查询速度
- 定期运行 `VACUUM` 优化数据库
- 考虑创建额外索引以加快特定查询

### 数据维护
- 定期备份数据库
- 运行完整性检查：`sqlite3 db.sqlite "PRAGMA integrity_check;"`
- 更新Wiktionary数据（每月）

### 最佳实践
- 导入前备份数据库
- 导入后运行测试验证
- 记录每次导入的统计数据
- 使用版本控制追踪数据库变化

---

**需要帮助？** 查看 [TESTING_CHINESE_TRANSLATIONS.md](../TESTING_CHINESE_TRANSLATIONS.md) 获取详细指南。
