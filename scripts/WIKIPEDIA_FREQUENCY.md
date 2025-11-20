# Wikipedia 词频导入指南

## 概述

本指南说明如何从日语维基百科提取词频数据，以提升词典的词频覆盖率。

## 为什么需要 Wikipedia 词频？

目前数据库使用 JMdict 词频数据，覆盖率约 14%（30,102 / 213,733 词条）。导入 Wikipedia 词频后：
- 覆盖率可提升至 30-40%
- 更好地覆盖现代词汇、新词、专有名词
- 补充 JMdict 缺失的常用词

## 优缺点分析

**优点**：
- 免费、开源
- 数据新鲜（维基百科持续更新）
- 覆盖现代口语和网络用语
- 可自行生成和定制

**缺点**：
- 数据质量不如 BCCWJ（权威语料库）
- 需要下载和处理大文件（~2-3 GB）
- 处理时间较长（视语料大小而定）

## 前置要求

### 1. 安装 MeCab（日语分词工具）

```bash
# macOS
brew install mecab
brew install mecab-ipadic
pip3 install mecab-python3

# 验证安装
echo "日本語を勉強しています" | mecab
```

预期输出：
```
日本    名詞,固有名詞,地域,国,*,*,日本,ニホン,ニホン
語      名詞,一般,*,*,*,*,語,ゴ,ゴ
を      助詞,格助詞,一般,*,*,*,を,ヲ,ヲ
...
```

### 2. 下载日语维基百科数据

有两种选择：

#### 选项 A: 完整语料（推荐用于最佳覆盖率）

```bash
cd ~/Downloads

# 下载最新的日语维基百科 dump（约 2-3 GB 压缩后）
curl -O https://dumps.wikimedia.org/jawiki/latest/jawiki-latest-pages-articles.xml.bz2

# 解压（解压后约 8-10 GB）
bunzip2 jawiki-latest-pages-articles.xml.bz2
```

#### 选项 B: 抽样语料（快速测试）

```bash
# 只下载维基百科的一部分用于测试
curl -O https://dumps.wikimedia.org/jawiki/latest/jawiki-latest-pages-articles1.xml.bz2
bunzip2 jawiki-latest-pages-articles1.xml.bz2
```

### 3. 提取纯文本

维基百科 dump 是 XML 格式，需要提取纯文本：

```bash
# 安装 wikiextractor
pip3 install wikiextractor

# 提取文本（输出到 wiki_text/ 目录）
wikiextractor -o wiki_text --json --no-templates ~/Downloads/jawiki-latest-pages-articles.xml

# 合并所有文本文件
find wiki_text -name 'wiki_*' -exec cat {} \; > wiki_combined.txt

# 检查文件大小
ls -lh wiki_combined.txt
```

## 使用方法

### 步骤 1: 处理维基百科文本并生成词频数据

```bash
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict"

# 处理完整语料（可能需要 30-60 分钟）
python3 scripts/import_wikipedia_frequency.py process ~/Downloads/wiki_combined.txt

# 或者只处理前 100,000 行进行测试（约 5-10 分钟）
python3 scripts/import_wikipedia_frequency.py process ~/Downloads/wiki_combined.txt 100000
```

这个步骤会：
1. 使用 MeCab 对文本进行分词
2. 统计每个词的出现频率
3. 生成 `frequencies.json` 文件

预期输出：
```
📖 Processing Wikipedia dump: wiki_combined.txt
  Processed 10,000 lines, 5,234 unique words
  Processed 20,000 lines, 8,456 unique words
  ...
✅ Processed 100,000 lines
   Found 25,678 unique words

💾 Saving frequencies to: frequencies.json
✅ Saved 25,678 word frequencies

📊 Top 20 most frequent words:
  1. する (する) - 12,345 occurrences
  2. ある (ある) - 10,234 occurrences
  3. 日本 (にほん) - 8,765 occurrences
  ...
```

### 步骤 2: 导入词频数据到数据库

```bash
# 使用 'min' 策略（推荐）：保留 JMdict 和 Wikipedia 中较高的优先级
python3 scripts/import_wikipedia_frequency.py import frequencies.json min

# 或使用 'skip' 策略：只填充没有词频的词条
python3 scripts/import_wikipedia_frequency.py import frequencies.json skip

# 或使用 'replace' 策略：用 Wikipedia 词频替换所有现有词频（不推荐）
python3 scripts/import_wikipedia_frequency.py import frequencies.json replace
```

预期输出：
```
📊 Importing frequencies from: frequencies.json
   Target database: NichiDict/Resources/seed.sqlite
   Merge strategy: min
   Loaded 25,678 frequency entries

💾 Creating backup: seed.sqlite.wiki_backup

📈 Database statistics:
   Total entries: 213,733
   Entries with frequency: 30,102 (14.1%)

✅ Import complete!
   Updated entries: 15,234
   New frequencies: 12,456
   Skipped: 0
   Not found in dict: 10,444

📊 Final coverage:
   Entries with frequency: 42,558 (19.9%)
   Improvement: +12,456 entries (+5.8%)
```

### 步骤 3: 重建 FTS 索引

```bash
# 重建搜索索引
python3 scripts/rebuild_fts_index.py
```

### 步骤 4: 验证导入

```bash
# 检查词频覆盖率
sqlite3 "NichiDict/Resources/seed.sqlite" \
  "SELECT
     COUNT(*) as total,
     SUM(CASE WHEN frequency_rank IS NOT NULL THEN 1 ELSE 0 END) as with_freq,
     ROUND(100.0 * SUM(CASE WHEN frequency_rank IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) as coverage
   FROM dictionary_entries;"

# 检查 "今日" 相关词条的词频
sqlite3 "NichiDict/Resources/seed.sqlite" \
  "SELECT headword, reading_hiragana, frequency_rank
   FROM dictionary_entries
   WHERE headword LIKE '今日%'
   ORDER BY COALESCE(frequency_rank, 999999) ASC
   LIMIT 10;"
```

预期结果：
```
# 覆盖率
total    with_freq  coverage
213733   42558      19.92

# "今日" 相关词条
今日       きょう         101
今日は     きょうは       201
今日中     きょうじゅう   5234
今日では   きょうでは     8765
今日イチ   きょういち     [NULL]  ← 维基百科也没有这个俚语
```

### 步骤 5: 重新构建应用

```bash
# 清理并重新构建
cd NichiDict
xcodebuild clean build \
  -project NichiDict.xcodeproj \
  -scheme NichiDict \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max'
```

## 词频排名系统

脚本使用以下排名系统来合并 JMdict 和 Wikipedia 词频：

| 数据源 | 排名范围 | 优先级 | 说明 |
|--------|----------|--------|------|
| JMdict Tier 1 (news1, ichi1, spec1, gai1) | 1-1000 | 最高 | 最权威的常用词 |
| Wikipedia Rank 1-1000 | 1001-2000 | 高 | 维基百科高频词 |
| JMdict Tier 2 (news2, ichi2, spec2, gai2) | 1001-5000 | 中高 | JMdict 常用词 |
| Wikipedia Rank 1001-10000 | 2001-11000 | 中 | 维基百科中频词 |
| JMdict Tier 3 (nf01-nf24) | 5001-20000 | 中低 | JMdict 中频词 |
| Wikipedia Rank 10001+ | 11001+ | 低 | 维基百科低频词 |

**合并策略说明**：

- **min（推荐）**: 使用最小的 rank 值（优先级更高）
  - 例如：JMdict rank=500, Wikipedia rank=1500 → 最终 rank=500
  - 保留了 JMdict 的权威性，同时补充 Wikipedia 数据

- **skip**: 只填充没有词频的词条
  - 有 JMdict 词频的词条保持不变
  - 只为缺失词频的词条添加 Wikipedia 数据

- **replace**: 用 Wikipedia 词频替换所有现有词频
  - 不推荐：会覆盖 JMdict 权威数据

## 预期效果

导入 Wikipedia 词频后，搜索结果排序会进一步优化：

**搜索 "今日" 的结果排序**：

| 词条 | 导入前 | 导入后 | 说明 |
|------|--------|--------|------|
| 今日 (きょう) | 1 (JMdict rank=101) | 1 (rank=101) | 保持不变，JMdict 优先 |
| 今日は (きょうは) | 2 (JMdict rank=201) | 2 (rank=201) | 保持不变 |
| 今日中 (きょうじゅう) | 5 (无词频) | 3 (Wiki rank=5234) | 提升，获得词频 |
| 今日では (きょうでは) | 6 (无词频) | 4 (Wiki rank=8765) | 提升，获得词频 |
| 今日イチ (きょういち) | 4 (无词频，按时间排序) | 5 (无词频) | 下降，因为其他词获得了词频 |

## 故障排除

### 错误：MeCab 未安装

```bash
❌ MeCab not installed!

Install with:
  brew install mecab
  brew install mecab-ipadic
  pip3 install mecab-python3
```

**解决方法**：按照提示安装 MeCab。

### 错误：找不到维基百科文件

```bash
❌ File not found: wiki.txt
```

**解决方法**：检查文件路径，确保已下载并提取维基百科文本。

### 警告：很多词未找到

```
Not found in dict: 10,444
```

**原因**：
1. 维基百科包含专有名词（人名、地名）不在词典中
2. 维基百科可能包含错误分词
3. 维基百科包含外来语、缩写等特殊词汇

**这是正常的**：通常 30-40% 的维基百科词汇不在词典中。

### 处理太慢

**优化方法**：
1. 先用少量数据测试（如 100,000 行）
2. 使用更快的机器
3. 考虑使用 PyPy 替代 CPython：
   ```bash
   brew install pypy3
   pypy3 scripts/import_wikipedia_frequency.py process wiki.txt
   ```

## 进阶用法

### 只处理高频词

如果只想导入最常用的词（减少处理时间）：

```python
# 修改 import_wikipedia_frequency.py 第 159 行
# 只保存 Top 10,000 词
for rank, ((surface, reading), count) in enumerate(sorted_words[:10000], start=1):
    frequencies[f"{surface}_{reading}"] = {
        'surface': surface,
        'reading': reading,
        'count': count,
        'rank': rank
    }
```

### 合并多个数据源

```bash
# 1. 导入 JMdict 词频
python3 scripts/import_frequency_data.py ~/Downloads/JMdict_e

# 2. 导入 Wikipedia 词频（使用 min 策略）
python3 scripts/import_wikipedia_frequency.py import frequencies.json min

# 3. 如果有其他语料，继续导入
python3 scripts/import_custom_frequency.py import custom_freq.json min
```

### 定期更新

维基百科每月更新，可以定期重新导入：

```bash
#!/bin/bash
# update_wiki_freq.sh

# 下载最新 dump
curl -O https://dumps.wikimedia.org/jawiki/latest/jawiki-latest-pages-articles.xml.bz2
bunzip2 jawiki-latest-pages-articles.xml.bz2

# 提取文本
wikiextractor -o wiki_text --json --no-templates jawiki-latest-pages-articles.xml
find wiki_text -name 'wiki_*' -exec cat {} \; > wiki_combined.txt

# 处理并导入
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict"
python3 scripts/import_wikipedia_frequency.py process ~/Downloads/wiki_combined.txt
python3 scripts/import_wikipedia_frequency.py import frequencies.json min
python3 scripts/rebuild_fts_index.py

# 清理临时文件
rm -rf ~/Downloads/wiki_text ~/Downloads/wiki_combined.txt
```

## 与 BCCWJ 对比

| 特性 | Wikipedia | BCCWJ |
|------|-----------|-------|
| 成本 | 免费 | 需要申请授权 |
| 数据量 | 数百万词条 | 1 亿词（标准） |
| 覆盖率 | 20-30% | 40-60% |
| 数据质量 | 良好 | 权威 |
| 现代词汇 | 优秀 | 一般（数据较旧） |
| 处理难度 | 中等 | 复杂 |
| 更新频率 | 每月 | 不更新 |

**建议**：
- **快速启动**：使用 Wikipedia
- **追求权威**：申请 BCCWJ
- **最佳方案**：JMdict + Wikipedia + BCCWJ（分层合并）

## 参考资料

- [维基百科 Dump 下载](https://dumps.wikimedia.org/jawiki/)
- [MeCab 官网](https://taku910.github.io/mecab/)
- [WikiExtractor](https://github.com/attardi/wikiextractor)
- [BCCWJ 申请](https://chunagon.ninjal.ac.jp/)

## 下一步

完成 Wikipedia 词频导入后：
1. 测试搜索功能，验证排序是否改善
2. 考虑添加更多数据源（BCCWJ、Aozora 等）
3. 定期更新词频数据（建议每 3-6 个月）
4. 监控词频覆盖率，目标是 40-50%
