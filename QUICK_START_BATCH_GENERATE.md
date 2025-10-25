# 🚀 批量例句生成 - 30秒快速开始

## 问题
所有词的例句都要AI实时生成，速度慢（1-3秒） 😕

## 解决方案
批量预生成常用词例句，瞬间显示（<50ms） 😊

## 立即开始

```bash
cd scripts
./run_batch_generate.sh
```

根据提示操作即可！

## 效果对比

| 指标 | 实时生成 | 批量预生成 |
|------|---------|-----------|
| 速度 | 1-3秒 | <50ms |
| 体验 | 😕 | 😊 ⭐⭐⭐⭐⭐ |
| 成本 | 持续 | 一次$3-5 |

## 推荐配置

```bash
# Top 5000词（标准覆盖）
--max-rank 5000
--daily-limit 100
--max-examples 3
```

**预计**：50天完成，成本$3-5，生成15,000个例句

## 关键特性

- ✅ 断点续传（随时中断，下次继续）
- ✅ 配额保护（每日限额，防止超支）
- ✅ 智能优先级（高频词优先）
- ✅ 详细日志（完整追踪）
- ✅ 测试模式（先验证再运行）

## 查看详细文档

- 完整指南: `docs/BATCH_EXAMPLE_GENERATION.md`
- 快速参考: `scripts/README_BATCH_GENERATE.md`
- 实施总结: `EXAMPLE_GENERATION_SOLUTION.md`

## 监控进度

```bash
# 查看状态
cat .batch_generate_state.json

# 查看日志
ls -lt batch_generate_log_*.json | head -1 | xargs cat
```

## 验证效果

```bash
# 检查生成的例句数
sqlite3 dict.sqlite "SELECT COUNT(*) FROM example_sentences;"

# 查看某个词的例句
sqlite3 dict.sqlite "
SELECT e.headword, ex.japanese_text, ex.english_translation
FROM dictionary_entries e
JOIN word_senses ws ON e.id = ws.entry_id
JOIN example_sentences ex ON ws.id = ex.sense_id
WHERE e.headword = '行く';
"
```

---

**就这么简单！现在就开始吧！** 🎉
