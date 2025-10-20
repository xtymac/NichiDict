# JMdict 多语言导入 - 快速参考

## 🚀 快速开始

```bash
# 一键测试（推荐）
./scripts/test_multilingual_import.sh

# 手动测试导入（1000条）
python3 scripts/import_jmdict_multilingual.py \
    data/JMdict_e \
    data/dictionary_test_multilingual.sqlite \
    --max-entries 1000

# 完整导入
python3 scripts/import_jmdict_multilingual.py \
    data/JMdict_e \
    data/dictionary_full_multilingual.sqlite
```

## 📊 支持的语言

| 语言 | 字段名 | JMdict代码 |
|------|--------|-----------|
| 英文 | `definition_english` | eng |
| 简体中文 | `definition_chinese_simplified` | chi, zh-Hans, zhs |
| 繁体中文 | `definition_chinese_traditional` | zh-Hant, zht |

## 🎯 核心功能

✅ 单向导入：日语 → 多语言翻译
✅ 日语主词（表记 + 假名 + 罗马音）
✅ 词性标注（日语标签，如：五段動詞、な形容詞）
✅ 多语言释义（英文、简中、繁中）
✅ JMdict ID 追溯
✅ FTS5 全文搜索

## 📝 常用查询

```sql
-- 查找词条
SELECT e.headword, e.reading_hiragana, s.definition_english, s.definition_chinese_simplified
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE e.headword = '食べる';

-- FTS搜索
SELECT e.headword, e.reading_hiragana
FROM dictionary_fts fts
JOIN dictionary_entries e ON fts.rowid = e.id
WHERE dictionary_fts MATCH 'tabe*';

-- 统计
SELECT
    COUNT(*) as total,
    COUNT(DISTINCT CASE WHEN definition_chinese_simplified IS NOT NULL THEN entry_id END) as with_chinese
FROM word_senses;
```

## ⚙️ 词性映射示例

| 代码 | 日语 | 说明 |
|------|------|------|
| &v5r; | 五段動詞（ら） | Godan verb -ru |
| &v1; | 一段動詞 | Ichidan verb |
| &adj-i; | い形容詞 | I-adjective |
| &adj-na; | な形容詞 | Na-adjective |
| &n; | 名詞 | Noun |

完整映射见脚本 `POS_MAPPINGS`。

## 📈 性能指标

| 操作 | 数据 | 时间 | 大小 |
|------|------|------|------|
| 测试导入 | 1,000条 | <1分钟 | ~400KB |
| 完整导入 | ~190,000条 | 10-15分钟 | ~90MB |

## 📚 文档

- **详细指南**：[JMDICT_MULTILINGUAL_IMPORT_GUIDE.md](../JMDICT_MULTILINGUAL_IMPORT_GUIDE.md)
- **完成总结**：[MULTILINGUAL_IMPORT_SUMMARY.md](../MULTILINGUAL_IMPORT_SUMMARY.md)

## 🐛 故障排除

### 找不到 JMdict 文件

```bash
cd data
wget http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
gunzip JMdict_e.gz
```

### 数据库损坏

```bash
rm data/dictionary_test_multilingual.sqlite
python3 scripts/import_jmdict_multilingual.py data/JMdict_e data/dictionary_test_multilingual.sqlite --max-entries 1000
```

## 📄 许可证

使用 JMdict 数据需遵守 CC-BY-SA 4.0 许可证。
详见：http://www.edrdg.org/

---

**快速开始**：`./scripts/test_multilingual_import.sh`
