# Wikipedia 词频导入 - 快速开始

## 最简单的方法（推荐初次使用）

### 1. 安装依赖（5 分钟）

```bash
# 安装 MeCab 日语分词工具
brew install mecab mecab-ipadic
pip3 install mecab-python3

# 安装 WikiExtractor
pip3 install wikiextractor

# 验证安装
echo "日本語" | mecab
```

### 2. 下载并处理维基百科数据（15-30 分钟）

```bash
# 切换到下载目录
cd ~/Downloads

# 下载维基百科数据（约 2-3 GB，可能需要 10-15 分钟）
curl -O https://dumps.wikimedia.org/jawiki/latest/jawiki-latest-pages-articles1.xml.bz2

# 解压（约 1-2 分钟）
bunzip2 jawiki-latest-pages-articles1.xml.bz2

# 提取纯文本（约 5-10 分钟）
wikiextractor -o wiki_text --json --no-templates jawiki-latest-pages-articles1.xml

# 合并所有文本
find wiki_text -name 'wiki_*' -exec cat {} \; > wiki_combined.txt

# 检查文件（应该有几百 MB）
ls -lh wiki_combined.txt
```

### 3. 生成词频数据（10-20 分钟）

```bash
# 切换到项目目录
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict"

# 处理文本并生成词频（只处理前 10 万行以加快速度）
python3 scripts/import_wikipedia_frequency.py process ~/Downloads/wiki_combined.txt 100000
```

**预期输出**：
```
📖 Processing Wikipedia dump: wiki_combined.txt
  Processed 10,000 lines, 5,234 unique words
  Processed 20,000 lines, 8,456 unique words
  ...
✅ Processed 100,000 lines
   Found 25,678 unique words
✅ Saved 25,678 word frequencies
```

### 4. 导入到数据库（1-2 分钟）

```bash
# 使用 'min' 策略保留 JMdict 优先级
python3 scripts/import_wikipedia_frequency.py import frequencies.json min
```

**预期输出**：
```
📊 Importing frequencies from: frequencies.json
💾 Creating backup: seed.sqlite.wiki_backup

✅ Import complete!
   Updated entries: 15,234
   New frequencies: 12,456

📊 Final coverage:
   Entries with frequency: 42,558 (19.9%)
   Improvement: +12,456 entries (+5.8%)
```

### 5. 重建索引（1-2 分钟）

```bash
python3 scripts/rebuild_fts_index.py
```

当提示 "Rebuild anyway?" 时，输入 `yes`。

### 6. 验证结果

```bash
# 检查词频覆盖率
sqlite3 "NichiDict/Resources/seed.sqlite" \
  "SELECT COUNT(*) as total,
          SUM(CASE WHEN frequency_rank IS NOT NULL THEN 1 ELSE 0 END) as with_freq,
          ROUND(100.0 * SUM(CASE WHEN frequency_rank IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) as coverage_pct
   FROM dictionary_entries;"
```

**预期输出**：
```
total    with_freq  coverage_pct
213733   42558      19.9
```

### 7. 重新构建应用

```bash
cd NichiDict
xcodebuild clean build \
  -project NichiDict.xcodeproj \
  -scheme NichiDict \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max'
```

## 完成！

现在搜索 "今日" 应该会看到：
1. **今日** (きょう) - JMdict freq=101
2. **今日は** (きょうは) - JMdict freq=201
3. **今日中** (きょうじゅう) - Wiki freq ✨ **新增**
4. **今日では** (きょうでは) - Wiki freq ✨ **新增**
5. **今日イチ** (きょういち) - 无词频（俚语）

## 清理临时文件

```bash
# 删除维基百科文件（可以节省几 GB 空间）
rm -rf ~/Downloads/wiki_text
rm ~/Downloads/wiki_combined.txt
rm ~/Downloads/jawiki-latest-pages-articles1.xml

# 保留 frequencies.json 以便将来重新导入
# rm frequencies.json
```

## 进阶选项

### 选项 1: 处理更多数据以提高覆盖率

```bash
# 下载完整维基百科（约 20-30 GB 解压后）
curl -O https://dumps.wikimedia.org/jawiki/latest/jawiki-latest-pages-articles.xml.bz2

# 处理全部数据（可能需要 1-2 小时）
python3 scripts/import_wikipedia_frequency.py process ~/Downloads/wiki_combined.txt
```

预期覆盖率：30-40%（vs. 快速方法的 20%）

### 选项 2: 只导入高频词

如果只想要最常用的词：

```bash
# 编辑 import_wikipedia_frequency.py
# 在第 159 行附近，将：
#   for rank, ((surface, reading), count) in enumerate(sorted_words, start=1):
# 改为：
#   for rank, ((surface, reading), count) in enumerate(sorted_words[:5000], start=1):
```

这样只导入前 5000 个最常用词。

## 故障排除

### MeCab 安装失败

```bash
# 尝试重新安装
brew reinstall mecab mecab-ipadic
pip3 uninstall mecab-python3
pip3 install mecab-python3 --no-cache-dir
```

### 下载很慢

```bash
# 使用镜像站点或者先下载到其他地方再传输
# 也可以只下载部分数据：
curl -O https://dumps.wikimedia.org/jawiki/latest/jawiki-latest-pages-articles1.xml.bz2
```

### 处理时间太长

使用更少的行数进行测试：
```bash
# 只处理 1 万行（约 1-2 分钟）
python3 scripts/import_wikipedia_frequency.py process ~/Downloads/wiki_combined.txt 10000
```

## 下一步

1. ✅ 测试搜索功能，验证词频排序是否改善
2. 📊 监控词频覆盖率（目标 40-50%）
3. 🔄 考虑定期更新（每 3-6 个月）
4. 📚 如需更高质量数据，考虑申请 [BCCWJ 授权](https://chunagon.ninjal.ac.jp/)

## 完整文档

详细说明请参考：[WIKIPEDIA_FREQUENCY.md](./WIKIPEDIA_FREQUENCY.md)
