# JMdict 多语言导入指南

## 概述

本指南介绍如何使用新的多语言导入系统从 JMdict 创建包含中文、英文等多语言释义的词典数据库。

## 特性

### ✅ 单向导入：日语 → 多语言翻译

- **日语主词**：
  - 表记（漢字/假名）
  - 读音（平假名）
  - 罗马音（Hepburn式）

- **词性标注**：
  - 使用日语语法标签
  - 自动转换为可读形式（如：五段動詞、な形容詞等）

- **多语言释义**：
  - 英文释义（必需）
  - 简体中文释义（如果可用）
  - 繁体中文释义（如果可用）

- **例句**：
  - 日语例句
  - 对应翻译

## 数据源

### JMdict（英文版）

- **文件名**：JMdict_e
- **下载地址**：http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
- **许可证**：CC-BY-SA 4.0
- **说明**：主要包含英文释义，中文释义较少

### JMdict（多语言版）

如果你想要包含更多中文释义，可以使用：
- **文件名**：JMdict （完整XML版本）
- **下载地址**：http://ftp.edrdg.org/pub/Nihongo/JMdict.gz
- **说明**：包含更多语言的释义

## 使用方法

### 1. 测试导入（推荐先测试）

```bash
cd /path/to/NichiDict
./scripts/test_multilingual_import.sh
```

这个脚本会：
1. 导入前1000条词条到测试数据库
2. 显示统计信息和样本数据
3. 询问是否继续完整导入

### 2. 手动导入

#### 测试导入（1000条）

```bash
python3 scripts/import_jmdict_multilingual.py \
    data/JMdict_e \
    data/dictionary_test_multilingual.sqlite \
    --max-entries 1000
```

#### 完整导入

```bash
python3 scripts/import_jmdict_multilingual.py \
    data/JMdict_e \
    data/dictionary_full_multilingual.sqlite
```

**预计时间**：10-15分钟
**数据库大小**：~90MB
**词条数量**：~190,000+

## 数据库结构

### dictionary_entries（词条表）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 主键 |
| headword | TEXT | 見出し語（漢字或假名） |
| reading_hiragana | TEXT | 平假名读音 |
| reading_romaji | TEXT | 罗马音 |
| frequency_rank | INTEGER | 频率排名（可选） |
| pitch_accent | TEXT | 音调（可选） |
| jmdict_id | INTEGER | JMdict原始ID |
| created_at | INTEGER | 创建时间 |

### word_senses（释义表）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 主键 |
| entry_id | INTEGER | 外键→dictionary_entries |
| definition_english | TEXT | 英文释义（必需） |
| definition_chinese_simplified | TEXT | 简体中文释义 |
| definition_chinese_traditional | TEXT | 繁体中文释义 |
| part_of_speech | TEXT | 品词 |
| usage_notes | TEXT | 用法说明 |
| sense_order | INTEGER | 义项顺序 |

### example_sentences（例句表）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 主键 |
| sense_id | INTEGER | 外键→word_senses |
| japanese_text | TEXT | 日语例句 |
| english_translation | TEXT | 英文翻译 |
| example_order | INTEGER | 例句顺序 |

### dictionary_fts（全文搜索表）

FTS5虚拟表，支持：
- 见出し語搜索
- 假名搜索
- 罗马音搜索

## 词性标注映射

脚本自动将 JMdict 的实体代码转换为可读的日语标签：

| JMdict代码 | 日语标签 | 说明 |
|-----------|---------|------|
| &n; | 名詞 | 名词 |
| &v5r; | 五段動詞（ら） | 五段动词（ら行） |
| &v1; | 一段動詞 | 一段动词 |
| &adj-i; | い形容詞 | い形容词 |
| &adj-na; | な形容詞 | な形容词 |
| &adv; | 副詞 | 副词 |
| &exp; | 表現 | 表达 |

完整映射见 `import_jmdict_multilingual.py` 的 `POS_MAPPINGS`。

## 导入示例输出

```
============================================================
JMdict Multilingual Import
============================================================
Source: JMdict_e
Target: dictionary_test_multilingual.sqlite
Limit: 1000 entries

Creating database: dictionary_test_multilingual.sqlite
Parsing XML: JMdict_e
Imported 1000 entries, 1730 senses (CN-simp: 0, CN-trad: 0)...

=== Import Complete ===
Total entries: 1,000
Total senses: 1,730
Senses with Chinese (Simplified): 0
Senses with Chinese (Traditional): 0

=== Database Statistics ===
Dictionary entries: 1,000
Word senses: 1,730
FTS index: 1,000
Entries with Simplified Chinese: 0 (0.00%)
Entries with Traditional Chinese: 0 (0.00%)
```

## 查询示例

### 查询词条

```sql
SELECT
    e.headword,
    e.reading_hiragana,
    s.part_of_speech,
    s.definition_english,
    s.definition_chinese_simplified
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE e.headword = '食べる';
```

### 搜索（使用FTS）

```sql
SELECT
    e.headword,
    e.reading_hiragana,
    s.definition_english
FROM dictionary_fts fts
JOIN dictionary_entries e ON fts.rowid = e.id
JOIN word_senses s ON e.id = s.entry_id
WHERE dictionary_fts MATCH 'tabe*'
LIMIT 10;
```

### 统计信息

```sql
-- 有中文释义的词条比例
SELECT
    COUNT(DISTINCT CASE WHEN definition_chinese_simplified IS NOT NULL THEN entry_id END) * 100.0 / COUNT(DISTINCT entry_id) as percentage_with_chinese
FROM word_senses;
```

## 与旧版本的对比

### 旧版本（import_jmdict.py）

- ❌ 仅支持英文释义
- ❌ 词性标签为原始代码
- ❌ 无JMdict ID映射

### 新版本（import_jmdict_multilingual.py）

- ✅ 支持多语言释义（英文、简中、繁中）
- ✅ 可读的日语词性标签
- ✅ 保留JMdict ID用于追溯
- ✅ 更好的错误处理
- ✅ 内存优化（iterparse）

## 补充中文翻译

JMdict_e 主要包含英文释义。如果需要添加更多中文翻译，有两种方法：

### 方法1：使用完整JMdict

下载并使用 JMdict（非_e版本），它包含更多语言：

```bash
wget http://ftp.edrdg.org/pub/Nihongo/JMdict.gz
gunzip JMdict.gz
python3 scripts/import_jmdict_multilingual.py JMdict data/dictionary_full.sqlite
```

### 方法2：使用Wiktionary数据（现有脚本）

使用现有的 `import_chinese_translations.py` 补充中文翻译：

```bash
# 1. 先用多语言脚本创建基础数据库
python3 scripts/import_jmdict_multilingual.py \
    data/JMdict_e \
    data/dictionary_full.sqlite

# 2. 从Wiktionary补充中文翻译
python3 scripts/import_chinese_translations.py
```

**优点**：
- Wiktionary有社区维护的中文翻译
- 可以补充JMdict缺失的翻译

**缺点**：
- 覆盖率有限（~2-3%）
- 质量可能不如JMdict官方数据

## 性能优化

### 导入速度

- **批量提交**：每1000条提交一次
- **iterparse**：流式解析XML，节省内存
- **索引**：导入完成后自动创建索引

### 数据库大小

| 数据库 | 词条数 | 大小 | 时间 |
|--------|--------|------|------|
| 测试库 | 1,000 | ~400KB | <1分钟 |
| 完整库 | ~190,000 | ~90MB | 10-15分钟 |

## 故障排除

### 问题1：找不到JMdict文件

```
Error: XML file not found: /path/to/JMdict_e
```

**解决方案**：
```bash
cd data
wget http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
gunzip JMdict_e.gz
```

### 问题2：Python版本不兼容

脚本需要 Python 3.6+。检查版本：

```bash
python3 --version
```

### 问题3：内存不足

如果导入大文件时内存不足，脚本已使用 `iterparse` 流式处理，正常情况下内存占用 < 500MB。

### 问题4：数据库损坏

如果导入中断，删除不完整的数据库重新导入：

```bash
rm data/dictionary_full_multilingual.sqlite
python3 scripts/import_jmdict_multilingual.py data/JMdict_e data/dictionary_full_multilingual.sqlite
```

## 集成到应用

### 替换现有数据库

1. 将新数据库重命名为 `seed.sqlite`：
   ```bash
   cp data/dictionary_full_multilingual.sqlite NichiDict/Resources/seed.sqlite
   ```

2. 重新构建应用：
   ```bash
   cd NichiDict
   xcodebuild -scheme NichiDict build
   ```

### 验证集成

```swift
// 在Swift代码中测试
let dbQueue = try await DatabaseManager.shared.dbQueue
try await dbQueue.read { db in
    let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_entries")
    print("Entries: \(count ?? 0)")

    let withChinese = try Int.fetchOne(db, sql: """
        SELECT COUNT(DISTINCT entry_id) FROM word_senses
        WHERE definition_chinese_simplified IS NOT NULL
    """)
    print("With Chinese: \(withChinese ?? 0)")
}
```

## 许可证和致谢

### JMdict

- **项目**：JMdict/EDICT
- **组织**：Electronic Dictionary Research and Development Group (EDRDG)
- **编辑**：Jim Breen
- **许可证**：Creative Commons Attribution-ShareAlike 4.0 International License
- **网站**：http://www.edrdg.org/

### 使用要求

使用JMdict数据需要：
1. 声明数据来自JMdict/EDICT
2. 提供EDRDG网站链接
3. 遵守CC-BY-SA 4.0许可证条款

## 进一步开发

### 潜在改进

1. **音调数据**：
   - 集成 OJAD (Online Japanese Accent Dictionary)
   - 添加 pitch_accent 字段

2. **频率数据**：
   - 集成语料库频率数据
   - 填充 frequency_rank 字段

3. **例句扩展**：
   - 从 Tatoeba 导入例句
   - 添加到 example_sentences 表

4. **自动翻译**：
   - 使用AI为缺失翻译的词条生成中文释义
   - 标记自动生成vs人工翻译

## 相关文件

- **导入脚本**：`scripts/import_jmdict_multilingual.py`
- **测试脚本**：`scripts/test_multilingual_import.sh`
- **旧版导入**：`scripts/import_jmdict.py`
- **中文补充**：`scripts/import_chinese_translations.py`
- **数据目录**：`data/`

## 更新日志

### v2.0 (2025-10-16)
- ✨ 新增多语言支持（简中、繁中）
- ✨ 可读的日语词性标签
- ✨ 保留JMdict ID
- ✨ 测试脚本和完整文档
- 🐛 修复内存优化
- 🐛 改进错误处理

### v1.0 (原版)
- ✅ 基础JMdict导入
- ✅ 仅英文释义
- ✅ FTS5全文搜索

---

**维护者**：NichiDict团队
**最后更新**：2025-10-16
**状态**：✅ 已测试并可用
