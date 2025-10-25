# 批量例句生成系统 - 快速开始指南

## 🚀 30秒快速开始

```bash
# 1. 进入scripts目录
cd scripts

# 2. 运行便捷脚本
./run_batch_generate.sh

# 3. 根据提示操作
#    - 会自动检测数据库
#    - 会提示输入API Key（如果未设置）
#    - 选择测试模式或生产模式
```

## 📖 这是什么？

**问题**：词典中每个词都需要实时调用AI生成例句，速度很慢（1-3秒/词）

**解决方案**：批量预生成常用词的例句，存入数据库

**效果对比**：

| 维度 | 实时生成 | 批量预生成 |
|------|----------|-----------|
| 响应速度 | 1-3秒 ⏱️ | <50ms ⚡ |
| 用户体验 | 😕 需要等待 | 😊 瞬间显示 |
| API调用 | 每次查询 | 一次性 |
| 成本 | 持续产生 | 一次性~$5 |

## 📁 文件说明

```
scripts/
├── batch_generate_examples.py    # 核心脚本（Python）
├── run_batch_generate.sh         # 便捷启动脚本（推荐）
└── README_BATCH_GENERATE.md      # 本文件

生成的文件:
├── .batch_generate_state.json    # 进度状态文件
└── batch_generate_log_*.json     # 运行日志
```

## 🎯 使用场景

### 场景1：首次运行（推荐）

```bash
./run_batch_generate.sh
```

选择 **测试模式（y）** 先验证，确认无误后再选 **生产模式（n）**

### 场景2：定制参数

```bash
python3 batch_generate_examples.py \
  --db /path/to/dict.sqlite \
  --api-key sk-YOUR_KEY \
  --max-rank 5000 \      # Top 5000词
  --batch-size 10 \      # 每批10个
  --daily-limit 100      # 每天100个
```

### 场景3：继续上次任务

```bash
# 脚本会自动从上次中断的地方继续
python3 batch_generate_examples.py --db dict.sqlite
```

### 场景4：定时任务（夜间处理）

```bash
# 添加到crontab
crontab -e

# 每天凌晨2点自动运行
0 2 * * * cd /path/to/scripts && ./run_batch_generate.sh
```

## 🔑 API Key 配置

### 方法1：环境变量（推荐）

```bash
export OPENAI_API_KEY="sk-your-key-here"
python3 batch_generate_examples.py --db dict.sqlite
```

### 方法2：命令行参数

```bash
python3 batch_generate_examples.py \
  --db dict.sqlite \
  --api-key sk-your-key-here
```

### 方法3：交互式输入

```bash
# 运行 run_batch_generate.sh 会提示输入
./run_batch_generate.sh
```

## 📊 预期效果

### 处理Top 5000词

- **总词条**: ~5000个
- **每天处理**: 100个（默认限额）
- **完成时间**: ~50天
- **生成例句**: ~15,000个
- **总成本**: ~$3-5 USD

### 处理Top 1000词（快速验证）

- **总词条**: ~1000个
- **每天处理**: 100个
- **完成时间**: ~10天
- **生成例句**: ~3,000个
- **总成本**: ~$0.6-1 USD

## ⚙️ 核心参数

| 参数 | 默认值 | 说明 | 调优建议 |
|------|--------|------|----------|
| `--max-rank` | 5000 | 处理的词频范围 | 先从1000开始 |
| `--batch-size` | 10 | 每批数量 | 保持默认即可 |
| `--daily-limit` | 100 | 每日API上限 | 可调至200加速 |
| `--max-examples` | 3 | 每词例句数 | 3个足够 |

## 🔍 监控进度

### 查看实时状态

```bash
cat .batch_generate_state.json
```

输出示例：
```json
{
  "date": "2025-10-20",
  "api_calls_today": 47,
  "last_processed_id": 2341
}
```

### 查看详细日志

```bash
# 查看最新日志
ls -lt batch_generate_log_*.json | head -1 | xargs cat
```

## 🐛 故障排除

### 问题1：找不到openai包

```bash
pip3 install openai
```

### 问题2：数据库锁定

关闭所有正在运行的App，然后重试。

### 问题3：API超额

修改 `--daily-limit` 降低每日调用量，或等待第二天重置。

### 问题4：没有词条需要处理

可能原因：
- 所有词都已有例句 ✅
- frequency_rank数据缺失（检查数据库）
- max_rank设置太小

验证：
```bash
sqlite3 dict.sqlite "
SELECT COUNT(*) FROM dictionary_entries WHERE frequency_rank <= 5000;
"
```

## 📈 性能优化

### 提速策略

```bash
# 1. 增加每日限额
--daily-limit 200

# 2. 使用更快的网络环境

# 3. 分时段运行（避开高峰期）
```

### 成本优化

```bash
# 1. 使用mini模型（已默认）
--model gpt-4o-mini

# 2. 降低每词例句数
--max-examples 2

# 3. 只处理高频词
--max-rank 3000
```

## 📖 完整文档

详细文档请查看：
```
docs/BATCH_EXAMPLE_GENERATION.md
```

包含：
- 详细工作流程图
- 数据库表结构
- 智能策略说明
- 成本详细估算
- 最佳实践指南
- 安全建议

## ✅ 验证生成效果

生成完成后，验证：

```bash
# 1. 检查总数
sqlite3 dict.sqlite "SELECT COUNT(*) FROM example_sentences;"

# 2. 查看示例
sqlite3 dict.sqlite "
SELECT e.headword, ex.japanese_text, ex.english_translation
FROM dictionary_entries e
JOIN word_senses ws ON e.id = ws.entry_id
JOIN example_sentences ex ON ws.id = ex.sense_id
WHERE e.headword = '行く'
LIMIT 3;
"
```

预期输出：
```
行く|学校に行く。|I go to school.
行く|明日、映画を見に行く。|I will go to see a movie tomorrow.
行く|駅まで歩いて行く。|I walk to the station.
```

## 🎉 完成后

批量生成完成后：
1. ✅ 常用词瞬间显示例句
2. ✅ 用户无需等待
3. ✅ API成本一次性
4. ✅ 体验显著提升

罕见词（frequency_rank > 5000）仍会实时生成，但这类词查询频率低，对整体体验影响小。

---

## 🆘 需要帮助？

1. 查看详细文档：`docs/BATCH_EXAMPLE_GENERATION.md`
2. 检查日志文件：`batch_generate_log_*.json`
3. 查看脚本源码：`batch_generate_examples.py`（有详细注释）

**Happy Generating! 🚀**
