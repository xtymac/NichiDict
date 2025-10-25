# 批量例句生成系统

## 📖 概述

批量例句生成系统用于为高频词条预生成AI例句，解决实时生成速度慢的问题。通过离线批处理，常用词可以瞬间显示例句，显著提升用户体验。

## 🎯 核心优势

| 指标 | 实时生成 | 批量预生成 |
|------|----------|-----------|
| **响应时间** | 1-3秒 ⏱️ | <50ms ⚡ |
| **用户体验** | 需要等待 😕 | 瞬间显示 😊 |
| **API成本** | 每次查询 💸 | 一次性 💰 |
| **覆盖范围** | 按需 | 常用词100% |

## 🚀 快速开始

### 方式1：使用便捷脚本（推荐）

```bash
cd scripts
./run_batch_generate.sh
```

脚本会自动:
- ✅ 检测Python环境和依赖
- ✅ 查找数据库文件
- ✅ 提示输入API Key（如果未设置）
- ✅ 交互式配置参数

### 方式2：直接运行Python脚本

```bash
# 基础用法
python3 scripts/batch_generate_examples.py \
  --db /path/to/NichiDict.sqlite \
  --api-key sk-YOUR_OPENAI_KEY

# 高级用法（自定义参数）
python3 scripts/batch_generate_examples.py \
  --db /path/to/NichiDict.sqlite \
  --api-key sk-YOUR_OPENAI_KEY \
  --max-rank 3000 \
  --batch-size 20 \
  --daily-limit 200 \
  --max-examples 3 \
  --model gpt-4o-mini

# 测试模式（不实际生成）
python3 scripts/batch_generate_examples.py \
  --db /path/to/NichiDict.sqlite \
  --dry-run
```

## 📋 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--db` | 必填 | SQLite数据库路径 |
| `--api-key` | 环境变量 | OpenAI API Key |
| `--model` | `gpt-4o-mini` | OpenAI模型（推荐mini版本） |
| `--max-rank` | `5000` | 处理frequency_rank≤此值的词 |
| `--batch-size` | `10` | 每批处理数量 |
| `--daily-limit` | `100` | 每日API调用上限（保护配额） |
| `--max-examples` | `3` | 每个词生成的例句数 |
| `--dry-run` | `False` | 测试模式，不实际执行 |

## 🔄 工作流程

```
┌─────────────────┐
│  查询待处理词条  │  frequency_rank ≤ 5000 且无例句
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  获取词条义项    │  读取 word_senses 表
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  构建AI Prompt  │  包含词条+义项信息
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ 调用OpenAI API  │  gpt-4o-mini（便宜快速）
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ 解析JSON响应     │  提取examples数组
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ 写入数据库       │  插入example_sentences表
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ 更新进度状态     │  保存到.batch_generate_state.json
└─────────────────┘
```

## 💾 数据库表结构

### example_sentences 表

```sql
CREATE TABLE example_sentences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sense_id INTEGER NOT NULL,           -- 关联到word_senses.id
    japanese_text TEXT NOT NULL,         -- 日语例句
    english_translation TEXT NOT NULL,   -- 英文翻译
    example_order INTEGER NOT NULL,      -- 排序序号
    FOREIGN KEY (sense_id) REFERENCES word_senses(id) ON DELETE CASCADE
);

CREATE INDEX idx_sense_id ON example_sentences(sense_id, example_order);
```

## 📊 智能策略

### 1. 优先级排序

脚本按以下优先级处理词条：
1. **频率排名** (frequency_rank ASC) - 最常用的词优先
2. **词条ID** (id ASC) - 相同频率时按ID顺序

### 2. 断点续传

- 进度保存在 `.batch_generate_state.json`
- 记录 `last_processed_id`，中断后从上次位置继续
- 每处理一个词立即保存状态

### 3. 配额保护

- **每日限额**: 默认100次API调用/天
- **自动重置**: 每天0点重置计数
- **优雅停止**: 达到限额后自动停止，不会超额

### 4. 义项分配策略

```python
# 如果词条只有1个义项 → 所有例句归该义项
if len(senses) == 1:
    all_examples_to_sense[0]

# 如果词条有多个义项 → 循环分配例句
else:
    example[0] → sense[0]
    example[1] → sense[1]
    example[2] → sense[2]
    example[3] → sense[0]  # 循环
    ...
```

## 🔍 状态文件

### .batch_generate_state.json

```json
{
  "date": "2025-10-20",
  "api_calls_today": 47,
  "last_processed_id": 2341
}
```

- `date`: 当前日期（用于每日重置）
- `api_calls_today`: 今日已用API次数
- `last_processed_id`: 上次处理到的词条ID

### batch_generate_log_YYYYMMDD_HHMMSS.json

每次运行结束后生成详细日志：

```json
{
  "stats": {
    "total_entries": 50,
    "processed": 45,
    "skipped": 2,
    "failed": 3,
    "examples_generated": 135,
    "api_calls": 45,
    "start_time": "2025-10-20T10:30:00"
  },
  "state": {
    "date": "2025-10-20",
    "api_calls_today": 45,
    "last_processed_id": 2500
  },
  "config": {
    "db_path": "/path/to/dict.sqlite",
    "model": "gpt-4o-mini",
    "max_rank": 5000,
    "batch_size": 50,
    "max_examples": 3
  }
}
```

## 📈 使用场景

### 场景1：首次批量生成

```bash
# 为Top 5000常用词生成例句
python3 scripts/batch_generate_examples.py \
  --db dict.sqlite \
  --max-rank 5000 \
  --daily-limit 200
```

**预计**：
- 总词条: ~5000个
- 每天处理: 200个
- 完成时间: ~25天
- 生成例句: ~15,000个

### 场景2：增量更新

```bash
# 继续上次未完成的任务
python3 scripts/batch_generate_examples.py \
  --db dict.sqlite
```

自动从 `last_processed_id` 继续处理。

### 场景3：扩大覆盖范围

```bash
# 处理Top 10000词
python3 scripts/batch_generate_examples.py \
  --db dict.sqlite \
  --max-rank 10000 \
  --daily-limit 300
```

### 场景4：定时任务（夜间批处理）

使用crontab定时执行：

```bash
# 编辑crontab
crontab -e

# 添加任务：每天凌晨2点运行
0 2 * * * cd /path/to/NichiDict/scripts && ./run_batch_generate.sh >> /tmp/batch_generate.log 2>&1
```

## 💰 成本估算

基于 OpenAI gpt-4o-mini 定价（2025年10月）：

| 指标 | 数值 |
|------|------|
| 输入Token价格 | $0.150 / 1M tokens |
| 输出Token价格 | $0.600 / 1M tokens |
| 平均每个词消耗 | ~1000 tokens |
| **Top 5000词总成本** | **~$3-5 USD** 💰 |
| **Top 10000词总成本** | **~$6-10 USD** 💰 |

**结论**：成本极低，一次性投入即可永久享受瞬时体验！

## 🛠️ 故障排除

### 问题1：API调用失败

```
❌ API调用失败: Error code: 429 - Rate limit reached
```

**解决**：
- 降低 `--batch-size`（减少并发）
- 增加脚本中的 `time.sleep()`间隔
- 检查API配额是否充足

### 问题2：数据库锁定

```
❌ 数据库插入失败: database is locked
```

**解决**：
- 确保没有其他进程在读写数据库
- 关闭正在运行的App
- 使用 `--dry-run` 测试不写数据库

### 问题3：JSON解析失败

```
❌ API返回格式错误
```

**解决**：
- 检查Prompt格式是否正确
- 查看日志中的原始响应
- 尝试切换模型（如 `gpt-4o`）

### 问题4：缺少依赖

```
❌ ImportError: No module named 'openai'
```

**解决**：
```bash
pip3 install openai
```

## 📝 最佳实践

### 1. 分阶段处理

```bash
# 阶段1: Top 1000（最高频）
python3 batch_generate_examples.py --db dict.sqlite --max-rank 1000

# 阶段2: Top 3000
python3 batch_generate_examples.py --db dict.sqlite --max-rank 3000

# 阶段3: Top 5000
python3 batch_generate_examples.py --db dict.sqlite --max-rank 5000
```

### 2. 使用测试模式验证

```bash
# 先测试（不实际生成）
python3 batch_generate_examples.py --db dict.sqlite --dry-run --batch-size 5

# 确认无误后正式运行
python3 batch_generate_examples.py --db dict.sqlite
```

### 3. 设置合理的daily-limit

```bash
# 保守策略（每天50个词，节省成本）
--daily-limit 50

# 平衡策略（每天100个词，默认值）
--daily-limit 100

# 激进策略（每天200个词，快速完成）
--daily-limit 200
```

### 4. 监控进度

```bash
# 实时查看日志
tail -f batch_generate_log_*.json

# 检查状态文件
cat .batch_generate_state.json
```

## 🔐 安全建议

1. **API Key保护**：不要提交到Git
   ```bash
   echo ".batch_generate_state.json" >> .gitignore
   echo "batch_generate_log_*.json" >> .gitignore
   ```

2. **环境变量方式**（推荐）：
   ```bash
   export OPENAI_API_KEY="sk-your-key"
   python3 batch_generate_examples.py --db dict.sqlite
   ```

3. **配额监控**：定期检查OpenAI账户余额

## 🎉 效果验证

生成完成后，验证效果：

```bash
# 检查生成的例句数
sqlite3 dict.sqlite "SELECT COUNT(*) FROM example_sentences;"

# 查看某个词的例句
sqlite3 dict.sqlite "
SELECT e.headword, ex.japanese_text, ex.english_translation
FROM dictionary_entries e
JOIN word_senses ws ON e.id = ws.entry_id
JOIN example_sentences ex ON ws.id = ex.sense_id
WHERE e.headword = '行く'
ORDER BY ex.example_order;
"
```

预期结果：
```
行く  学校に行く。  I go to school.
行く  明日、映画を見に行く。  I will go to see a movie tomorrow.
行く  駅まで歩いて行く。  I walk to the station.
```

---

## 📞 支持

遇到问题？查看：
1. 日志文件: `batch_generate_log_*.json`
2. 状态文件: `.batch_generate_state.json`
3. 脚本源码: `batch_generate_examples.py` (有详细注释)

**Version**: 1.0.0
**Last Updated**: 2025-10-20
