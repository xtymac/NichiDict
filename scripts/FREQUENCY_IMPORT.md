# 词频数据导入指南

## 概述

本指南说明如何从 JMdict 数据源导入词频数据，以改善搜索结果的排序。

## 为什么需要词频数据？

目前数据库中只有 3 个词条（する、くる、いる）有词频数据，其余 42 万+ 词条的 `frequency_rank` 字段为 NULL。这导致搜索结果排序主要依赖：
- 创建时间 (created_at)
- JLPT 等级
- 其他启发式规则

导入词频数据后，常用词（如"今日"、"今日は"）会自动排在前面，不常用的词（如"今日イチ"）会排在后面。

## 数据来源

### 选项 1: JMdict 频度标记（推荐）

**优点**：
- 免费、开源（CC-BY-SA 4.0）
- 已包含在 JMdict 数据中
- 覆盖约 20-30% 的词条
- 分层标记系统（news1, ichi1, spec1, gai1, nf01-nf48）

**数据来源**：
- JMdict 官网：http://www.edrdg.org/jmdict/edict_doc.html
- 直接下载：http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz

**频度标记说明**：
```
news1, news2 - 出现在《每日新闻》
ichi1, ichi2 - 出现在《一万語語彙分類集》
spec1, spec2 - 常用词（不在其他列表中）
gai1, gai2   - 常用外来语
nf01-nf48    - 词频排名（数字越小越常用）
```

### 选项 2: BCCWJ 语料库

**优点**：
- 最权威的日语词频数据
- 1 亿词规模
- 涵盖书面语的各个领域

**缺点**：
- 需要申请授权
- 数据处理较复杂

**申请地址**：https://chunagon.ninjal.ac.jp/

### 选项 3: Wikipedia 词频

**优点**：
- 免费
- 较新的词汇覆盖好
- 可自行生成

**数据来源**：
- 日语维基百科 dump：https://dumps.wikimedia.org/jawiki/

## 使用方法

### 步骤 1: 下载 JMdict

```bash
cd ~/Downloads
curl -O http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
gunzip JMdict_e.gz
```

### 步骤 2: 运行导入脚本

```bash
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict"

# 导入词频数据
python3 scripts/import_frequency_data.py ~/Downloads/JMdict_e
```

脚本会：
1. 解析 JMdict XML 文件
2. 提取所有 `<ke_pri>` 和 `<re_pri>` 标记
3. 将标记转换为数值排名（1-100000）
4. 更新数据库中的 `frequency_rank` 字段

### 步骤 3: 验证导入

```bash
# 检查数据库中有词频数据的词条数量
sqlite3 "NichiDict/Resources/seed.sqlite" \
  "SELECT COUNT(*) as with_freq FROM dictionary_entries WHERE frequency_rank IS NOT NULL;"

# 检查高频词排名
sqlite3 "NichiDict/Resources/seed.sqlite" \
  "SELECT headword, reading_hiragana, frequency_rank
   FROM dictionary_entries
   WHERE frequency_rank IS NOT NULL
   ORDER BY frequency_rank LIMIT 20;"
```

### 步骤 4: 重新构建应用

```bash
# 重新构建 app
xcodebuild -project NichiDict/NichiDict.xcodeproj \
  -scheme NichiDict \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
```

## 词频排名系统

脚本使用分层排名系统：

| 层级 | 标记 | 排名范围 | 说明 |
|------|------|----------|------|
| Tier 1 | news1, ichi1, spec1, gai1 | 1-1000 | 最常用词 |
| Tier 2 | news2, ichi2, spec2, gai2 | 1001-5000 | 常用词 |
| Tier 3 | nf01-nf24 | 5001-20000 | 中频词 |
| Tier 4 | nf25-nf48 | 20001-50000 | 低频词 |

**示例**：
- "する" (news1, ichi1) → rank: 1
- "今日" (news1, ichi1, nf01) → rank: 1
- "今日は" (spec1) → rank: 201
- "今日イチ" (无标记) → rank: NULL

## 预期效果

导入词频后，搜索"今日"的结果排序：

**之前**：
1. 今日 (N5, exact match)
2. 今日は (N3)
3. 今日では
4. 今日イチ ← 因为 created_at 排在这里
5. 今日た

**之后**：
1. 今日 (N5, exact match, freq=1)
2. 今日は (N3, freq=201)
3. 今日では (freq=5000+)
4. 今日中に (如果有频度标记)
5. 今日イチ (无频度标记，排在最后)

## 故障排除

### 错误：找不到 JMdict_e.xml

```bash
# 检查文件路径
ls -lh ~/Downloads/JMdict_e
```

### 错误：数据库文件不存在

```bash
# 检查数据库路径
ls -lh "NichiDict/Resources/seed.sqlite"
```

### 警告：没有找到频度数据

检查 XML 文件是否正确解压：
```bash
head -20 ~/Downloads/JMdict_e
```

应该看到类似这样的内容：
```xml
<?xml version="1.0" encoding="UTF-8"?>
...
<entry>
  <ent_seq>1000000</ent_seq>
  <k_ele>
    <keb>明白</keb>
    <ke_pri>news1</ke_pri>
    ...
```

## 后续优化

### 1. 合并多个数据源

如果想要更全面的词频覆盖，可以考虑：
- JMdict 频度标记（基础，~30% 覆盖）
- Wikipedia 词频（补充现代词汇）
- BCCWJ（最权威，需要授权）

### 2. 自定义词频提取

如果有自己的语料库，可以修改脚本：
1. 分词（使用 MeCab）
2. 统计词频
3. 映射到数据库词条
4. 更新 frequency_rank

### 3. 定期更新

JMdict 每月更新，可以定期重新导入：
```bash
# 设置 cron job 每月更新
0 0 1 * * /path/to/update_frequency.sh
```

## 参考资料

- JMdict 官方文档：http://www.edrdg.org/jmdict/edict_doc.html
- JMdict 授权：CC-BY-SA 4.0
- BCCWJ：https://chunagon.ninjal.ac.jp/
- Wikipedia dumps：https://dumps.wikimedia.org/jawiki/
