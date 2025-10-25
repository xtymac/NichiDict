# 例句生成测试指南
Example Sentence Generation - Testing Guide

## 📊 批量生成完成统计

✅ **已完成**: 1000/1000 词条 (100%)
✅ **生成例句**: 3000 个
✅ **成功率**: 100%
✅ **耗时**: ~1 小时
✅ **成本**: ~$0.60-0.80 USD

## 🧪 测试方法

### 1️⃣ 数据库层测试（最快）

运行我们的测试脚本：

```bash
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict"
./scripts/test_example_performance.sh
```

**预期输出**:
```
📊 例句生成性能测试
1️⃣ Top 1000 词条中有例句: 1000 个
   总例句数: 3000 个
   平均每词: 3.0 个例句
2️⃣ 随机抽样检查（5个词条）
   【例句示例】
3️⃣ 常用词例句检查
   📖 お金: お金が足りません。
   📖 お母さん: お母さんが来ました。
4️⃣ 覆盖率: 100.0%
```

### 2️⃣ Swift 单元测试

复制数据库并运行测试：

```bash
# 1. 复制新数据库到测试资源
cp data/dictionary_full_multilingual.sqlite NichiDict/Resources/seed.sqlite

# 2. 运行 Swift 测试
cd Modules/CoreKit
swift test --filter ExamplePerformanceTests
```

**预期结果**:
- ✅ `testTop1000Coverage()` - 覆盖率 > 90%
- ✅ `testExampleQuality()` - 例句质量检查通过
- ✅ `testSearchPerformanceWithExamples()` - 查询时间 < 100ms
- ✅ `testBatchExampleRetrieval()` - 批量检索正常
- ✅ `testExampleStatistics()` - 统计数据正确

### 3️⃣ App 真机测试（推荐）

#### 步骤 1: 更新数据库

```bash
# 复制到 App 资源目录
cp data/dictionary_full_multilingual.sqlite NichiDict/Resources/seed.sqlite
```

#### 步骤 2: 重新构建

```bash
cd NichiDict
xcodebuild -scheme NichiDict -configuration Debug clean build
```

#### 步骤 3: 安装到模拟器/真机

```bash
# 查看可用模拟器
xcrun simctl list devices | grep "iPhone"

# 启动模拟器（例如 iPhone 15 Pro）
xcrun simctl boot "iPhone 15 Pro"

# 安装 App
xcrun simctl install booted path/to/NichiDict.app
```

#### 步骤 4: 性能对比测试

在 App 中搜索以下词条，观察响应时间：

**有例句的词条（应该很快 <50ms）**:
- お金 (money)
- お母さん (mother)
- お茶 (tea)
- お風呂に入る (take a bath)
- お願いします (please)

**预期行为**:
1. 🚀 搜索结果**立即显示**（<50ms）
2. 📝 **直接显示**预生成的 3 个例句
3. ✅ **无需等待** AI 生成

**无例句的词条（ID > 1000）**:
- 一些罕见词条

**预期行为**:
1. ⏱️ 需要等待 1-3 秒
2. 🤖 显示 "Generating examples..." 加载状态
3. 📝 AI 实时生成例句

## 📈 性能提升验证

### 期望指标

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| Top 1000 查询时间 | 1-3秒 | <50ms | **60x** |
| 用户体验 | 等待加载 | 即时显示 | ⚡ |
| API 调用 | 每次查询 | 仅首次 | 💰 |

### 验证清单

- [ ] ✅ 1000 个词条都有例句
- [ ] ✅ 每个词条有 3 个例句
- [ ] ✅ 例句包含原词
- [ ] ✅ 中英翻译完整
- [ ] ✅ 查询速度 < 100ms
- [ ] ✅ 无 AI 等待时间

## 🔍 质量检查

### 随机抽样验证

运行以下 SQL 查看随机例句：

```bash
sqlite3 data/dictionary_full_multilingual.sqlite "
SELECT
    e.headword,
    ex.japanese_text,
    ex.english_translation
FROM dictionary_entries e
JOIN word_senses ws ON e.id = ws.entry_id
JOIN example_sentences ex ON ws.id = ex.sense_id
WHERE e.id <= 1000
ORDER BY RANDOM()
LIMIT 10;
"
```

### 质量标准

每个例句应该：
1. ✅ 包含目标词汇
2. ✅ 长度适中（<25 字符）
3. ✅ 语法自然
4. ✅ 英译准确
5. ✅ 无格式错误

## 🚨 常见问题

### Q1: 例句没有显示？

**检查步骤**:
```bash
# 1. 确认数据库已复制
ls -lh NichiDict/Resources/seed.sqlite

# 2. 检查例句数量
sqlite3 NichiDict/Resources/seed.sqlite "SELECT COUNT(*) FROM example_sentences;"

# 3. 重新构建 App
xcodebuild clean build
```

### Q2: 性能没有提升？

**可能原因**:
- App 使用了旧数据库（未重新构建）
- 查询的词条 ID > 1000（无例句）
- 缓存问题

**解决方法**:
```bash
# 清理并重新安装
xcrun simctl uninstall booted com.yourcompany.NichiDict
# 重新构建和安装
```

### Q3: 如何为更多词条生成例句？

修改脚本参数：

```bash
# 生成 Top 5000 词条
./scripts/run_batch_examples_all.sh --max-rank 5000

# 或编辑 run_batch_examples_all.sh:
# 将 --max-rank 1000 改为 --max-rank 5000
```

## 📊 监控和日志

### 查看生成日志

```bash
# 最新日志
ls -lt batch_generate_log_*.json | head -1 | xargs cat | jq

# 统计信息
cat .batch_generate_state.json
```

### 日志文件位置

- **状态文件**: `.batch_generate_state.json`
- **详细日志**: `batch_generate_log_YYYYMMDD_HHMMSS.json`

## ✅ 验收测试

运行完整的验收测试：

```bash
# 1. 数据库测试
./scripts/test_example_performance.sh

# 2. Swift 单元测试
cd Modules/CoreKit && swift test --filter ExamplePerformanceTests

# 3. App 集成测试（手动）
# - 在 App 中搜索 Top 10 常用词
# - 验证例句立即显示
# - 确认无 AI 等待时间
```

## 🎉 成功标准

全部测试通过后，你应该看到：

1. ✅ **数据完整**: 1000 词条，3000 例句
2. ✅ **质量合格**: 例句自然、翻译准确
3. ✅ **性能提升**: 查询时间从秒级降至毫秒级
4. ✅ **用户体验**: 无需等待 AI 生成

恭喜！例句批量生成和测试全部完成！🚀
