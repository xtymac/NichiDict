# N5 例句生成 - 测试计划

## 📊 生成完成统计

### 数据概览
- ✅ N5 单词数：**1,734** 个
- ✅ N5 sense 总数：**4,996** 个
- ✅ 有例句的 sense：**4,993** 个
- ✅ 覆盖率：**99.94%**
- ✅ 生成例句总数：**9,995** 条
- ✅ 平均每个 sense：**2.0** 条例句

### 生成信息
- 使用模型：OpenAI GPT-4o-mini
- 生成日期：2025-10-29
- 实际成本：约 $0.90 USD

---

## 🧪 测试计划

### 第一部分：数据完整性测试

#### 1.1 数据库完整性检查

**目标**：验证所有例句数据正确保存到数据库

**测试步骤**：
```bash
cd /Users/mac/Maku\ Box\ Dropbox/Maku\ Box/Project/NichiDict

# 测试 1: 检查 N5 例句总数
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT COUNT(*) as n5_examples
FROM example_sentences
WHERE sense_id IN (
  SELECT s.id FROM word_senses s
  JOIN dictionary_entries d ON s.entry_id = d.id
  WHERE d.jlpt_level = 'N5'
);"
```

**预期结果**：返回 ~9,995 条例句

---

#### 1.2 覆盖率检查

**目标**：确认几乎所有 N5 sense 都有例句

**测试步骤**：
```bash
# 测试 2: 检查没有例句的 N5 sense
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT
  d.headword,
  s.definition_english,
  d.jlpt_level
FROM dictionary_entries d
JOIN word_senses s ON s.entry_id = d.id
WHERE d.jlpt_level = 'N5'
  AND s.id NOT IN (SELECT sense_id FROM example_sentences WHERE sense_id IS NOT NULL)
LIMIT 10;"
```

**预期结果**：返回 0-3 个缺失例句的 sense（< 0.1%）

---

#### 1.3 数据字段完整性

**目标**：检查例句的所有字段是否完整

**测试步骤**：
```bash
# 测试 3: 检查空字段
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT
  COUNT(*) FILTER (WHERE japanese_text IS NULL OR japanese_text = '') as empty_japanese,
  COUNT(*) FILTER (WHERE english_translation IS NULL OR english_translation = '') as empty_english,
  COUNT(*) FILTER (WHERE chinese_translation IS NULL OR chinese_translation = '') as empty_chinese
FROM example_sentences
WHERE sense_id IN (
  SELECT s.id FROM word_senses s
  JOIN dictionary_entries d ON s.entry_id = d.id
  WHERE d.jlpt_level = 'N5'
);"
```

**预期结果**：
- empty_japanese: 0
- empty_english: 0
- empty_chinese: 0-50（部分可能为空是正常的）

---

### 第二部分：内容质量测试

#### 2.1 随机抽样质量检查

**目标**：人工检查随机例句的质量

**测试步骤**：
```bash
# 测试 4: 随机抽取 20 条例句
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT
  d.headword,
  d.reading_hiragana,
  d.jlpt_level,
  e.japanese_text,
  e.chinese_translation,
  e.english_translation
FROM example_sentences e
JOIN word_senses s ON e.sense_id = s.id
JOIN dictionary_entries d ON s.entry_id = d.id
WHERE d.jlpt_level = 'N5'
ORDER BY RANDOM()
LIMIT 20;"
```

**人工验证标准**：
- ✅ 日语句子语法正确
- ✅ 句子长度适中（15-30字符）
- ✅ 使用 N5 级别语法（です/ます体）
- ✅ 中英文翻译准确
- ✅ 句子包含目标词汇
- ✅ 场景符合日常生活

---

#### 2.2 特定词汇检查

**目标**：检查高频词汇的例句质量

**测试步骤**：
```bash
# 测试 5: 检查常见N5词汇的例句
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT
  d.headword,
  d.reading_hiragana,
  e.japanese_text,
  e.chinese_translation
FROM example_sentences e
JOIN word_senses s ON e.sense_id = s.id
JOIN dictionary_entries d ON s.entry_id = d.id
WHERE d.jlpt_level = 'N5'
  AND d.headword IN ('食べる', '行く', '見る', '聞く', '話す', '書く', '読む', '飲む')
ORDER BY d.headword, e.example_order;"
```

**预期结果**：每个常见词汇应有 2-6 条例句

---

#### 2.3 句子长度分布

**目标**：验证句子长度符合 N5 标准

**测试步骤**：
```bash
# 测试 6: 统计句子长度分布
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT
  CASE
    WHEN LENGTH(japanese_text) < 10 THEN '<10字符'
    WHEN LENGTH(japanese_text) BETWEEN 10 AND 20 THEN '10-20字符'
    WHEN LENGTH(japanese_text) BETWEEN 21 AND 30 THEN '21-30字符'
    WHEN LENGTH(japanese_text) > 30 THEN '>30字符'
  END as length_range,
  COUNT(*) as count
FROM example_sentences
WHERE sense_id IN (
  SELECT s.id FROM word_senses s
  JOIN dictionary_entries d ON s.entry_id = d.id
  WHERE d.jlpt_level = 'N5'
)
GROUP BY length_range;"
```

**预期结果**：大多数例句应在 10-30 字符范围内

---

### 第三部分：应用层测试

#### 3.1 iOS App 集成测试

**目标**：验证例句在 iOS 应用中正确显示

**测试步骤**：
1. 启动 NichiDict iOS 应用
2. 搜索 N5 词汇（如：食べる）
3. 点击词条查看详情
4. 向下滚动到"例句"部分

**验证点**：
- ✅ 例句正确显示
- ✅ 日语、中文、英文都正确显示
- ✅ 例句按 example_order 排序
- ✅ 例句中目标词汇有高亮显示（如果实现了）
- ✅ 字体大小适中，易读

---

#### 3.2 搜索功能测试

**目标**：验证带有例句的词汇可以正常搜索

**测试步骤**：
1. 在搜索框输入 N5 词汇
2. 查看搜索结果
3. 点击进入词条详情

**验证点**：
- ✅ N5 标签正确显示（绿色）
- ✅ 词条包含例句
- ✅ 搜索性能正常（无延迟）

---

#### 3.3 离线功能测试

**目标**：确认例句在离线模式下可用

**测试步骤**：
1. 开启飞行模式
2. 打开 NichiDict 应用
3. 搜索并查看 N5 词汇例句

**验证点**：
- ✅ 离线模式下例句正常显示
- ✅ 无网络错误提示

---

### 第四部分：性能测试

#### 4.1 数据库查询性能

**目标**：验证例句查询不影响应用性能

**测试步骤**：
```bash
# 测试 7: 测试查询速度
time sqlite3 NichiDict/Resources/seed.sqlite "
SELECT * FROM example_sentences
WHERE sense_id IN (
  SELECT id FROM word_senses WHERE entry_id = 1234
);"
```

**预期结果**：查询时间 < 10ms

---

#### 4.2 应用启动时间

**目标**：确认增加例句后应用启动不变慢

**测试步骤**：
1. 完全关闭应用
2. 重新启动应用
3. 记录启动时间

**预期结果**：启动时间与之前相比无明显增加（< 500ms 差异）

---

### 第五部分：边界情况测试

#### 5.1 特殊字符处理

**目标**：验证特殊字符正确处理

**测试步骤**：
```bash
# 测试 8: 检查包含特殊字符的例句
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT japanese_text
FROM example_sentences
WHERE sense_id IN (
  SELECT s.id FROM word_senses s
  JOIN dictionary_entries d ON s.entry_id = d.id
  WHERE d.jlpt_level = 'N5'
)
AND (
  japanese_text LIKE '%「%' OR
  japanese_text LIKE '%」%' OR
  japanese_text LIKE '%？%' OR
  japanese_text LIKE '%！%'
)
LIMIT 10;"
```

**验证点**：
- ✅ 特殊字符正确存储
- ✅ 特殊字符在应用中正确显示

---

#### 5.2 长句子处理

**目标**：验证较长例句的显示

**测试步骤**：
```bash
# 测试 9: 查找最长的例句
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT
  d.headword,
  LENGTH(e.japanese_text) as length,
  e.japanese_text
FROM example_sentences e
JOIN word_senses s ON e.sense_id = s.id
JOIN dictionary_entries d ON s.entry_id = d.id
WHERE d.jlpt_level = 'N5'
ORDER BY length DESC
LIMIT 5;"
```

**验证点**：
- ✅ 长句子在应用中不会被截断
- ✅ UI 布局不会因长句子而错乱

---

#### 5.3 多义词例句区分

**目标**：验证多义词的不同 sense 有不同例句

**测试步骤**：
```bash
# 测试 10: 检查多义词的例句
sqlite3 NichiDict/Resources/seed.sqlite "
SELECT
  d.headword,
  s.id as sense_id,
  s.definition_english,
  e.japanese_text
FROM dictionary_entries d
JOIN word_senses s ON d.id = s.entry_id
JOIN example_sentences e ON s.id = e.sense_id
WHERE d.jlpt_level = 'N5'
  AND d.id IN (
    SELECT entry_id FROM word_senses
    GROUP BY entry_id HAVING COUNT(*) > 3
  )
ORDER BY d.headword, s.id, e.example_order
LIMIT 20;"
```

**验证点**：
- ✅ 不同 sense 的例句体现不同含义
- ✅ 例句正确关联到对应的 sense

---

## 📋 测试执行清单

### 自动化测试（SQL脚本）
- [ ] 测试 1: N5 例句总数验证
- [ ] 测试 2: 覆盖率检查
- [ ] 测试 3: 数据字段完整性
- [ ] 测试 4: 随机抽样质量（人工）
- [ ] 测试 5: 特定词汇检查
- [ ] 测试 6: 句子长度分布
- [ ] 测试 7: 查询性能测试
- [ ] 测试 8: 特殊字符处理
- [ ] 测试 9: 长句子处理
- [ ] 测试 10: 多义词例句区分

### 应用层测试（iOS）
- [ ] 3.1 iOS App 集成测试
- [ ] 3.2 搜索功能测试
- [ ] 3.3 离线功能测试
- [ ] 4.2 应用启动时间测试

---

## 🐛 问题追踪

### 发现的问题
_在此记录测试中发现的任何问题_

| 测试编号 | 问题描述 | 严重程度 | 状态 | 备注 |
|---------|---------|---------|------|------|
|         |         |         |      |      |

### 问题严重程度定义
- **P0 - 阻塞**：必须立即修复，影响核心功能
- **P1 - 严重**：需要尽快修复，影响用户体验
- **P2 - 一般**：可以稍后修复，影响较小
- **P3 - 轻微**：可选修复，不影响使用

---

## 📊 测试报告模板

### 执行日期
- 开始时间：____年____月____日 ____:____
- 结束时间：____年____月____日 ____:____
- 测试人员：________________

### 测试结果汇总
- 通过测试：____ / 14
- 失败测试：____ / 14
- 阻塞测试：____ / 14
- 测试覆盖率：____%

### 总体评估
- [ ] ✅ 通过 - 可以发布
- [ ] ⚠️  通过（有轻微问题）- 可以发布，但需记录问题
- [ ] ❌ 不通过 - 需要修复后重新测试

### 备注
_在此记录任何额外的观察、建议或问题_

---

## 🚀 后续计划

### 短期计划（本周）
- [ ] 执行完整测试计划
- [ ] 修复发现的任何问题
- [ ] 在 iOS 模拟器中验证
- [ ] 在真机上测试

### 中期计划（本月）
- [ ] 为 N4 级别生成例句
- [ ] 为 N3 级别生成例句
- [ ] 优化例句显示 UI

### 长期计划（未来）
- [ ] 为 N2 和 N1 生成例句
- [ ] 添加例句收藏功能
- [ ] 添加例句朗读功能
- [ ] 用户自定义例句功能

---

## 📝 附录

### A. 快速测试脚本

创建一个便捷的测试脚本：

```bash
#!/bin/bash
# N5例句快速测试脚本

DB_PATH="../NichiDict/Resources/seed.sqlite"

echo "======================================"
echo "N5 例句测试脚本"
echo "======================================"

echo ""
echo "1. 例句总数："
sqlite3 $DB_PATH "
SELECT COUNT(*)
FROM example_sentences
WHERE sense_id IN (
  SELECT s.id FROM word_senses s
  JOIN dictionary_entries d ON s.entry_id = d.id
  WHERE d.jlpt_level = 'N5'
);"

echo ""
echo "2. 覆盖率："
sqlite3 $DB_PATH "
SELECT
  ROUND(CAST(COUNT(DISTINCT CASE WHEN e.id IS NOT NULL THEN s.id END) AS FLOAT) / COUNT(DISTINCT s.id) * 100, 2) || '%' as coverage
FROM dictionary_entries d
JOIN word_senses s ON s.entry_id = d.id
LEFT JOIN example_sentences e ON e.sense_id = s.id
WHERE d.jlpt_level = 'N5';"

echo ""
echo "3. 缺失例句的词条："
sqlite3 $DB_PATH "
SELECT COUNT(*)
FROM word_senses s
JOIN dictionary_entries d ON s.entry_id = d.id
WHERE d.jlpt_level = 'N5'
  AND s.id NOT IN (SELECT sense_id FROM example_sentences WHERE sense_id IS NOT NULL);"

echo ""
echo "4. 随机抽样 5 条例句："
sqlite3 -column -header $DB_PATH "
SELECT
  d.headword as 单词,
  e.japanese_text as 日语例句,
  e.chinese_translation as 中文翻译
FROM example_sentences e
JOIN word_senses s ON e.sense_id = s.id
JOIN dictionary_entries d ON s.entry_id = d.id
WHERE d.jlpt_level = 'N5'
ORDER BY RANDOM()
LIMIT 5;"

echo ""
echo "======================================"
echo "测试完成！"
echo "======================================"
```

保存为 `test_n5_examples.sh` 并运行：
```bash
cd /Users/mac/Maku\ Box\ Dropbox/Maku\ Box/Project/NichiDict/scripts
chmod +x test_n5_examples.sh
./test_n5_examples.sh
```

---

**创建日期**：2025-10-29
**版本**：1.0
**作者**：Claude Code