#!/bin/bash
# 批量生成例句 - 完整版（循环直到完成所有 1000 个词条）
# Complete batch example generation - Loop until all 1000 entries done

cd "$(dirname "$0")/.."

# Check if API key is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "❌ Error: OPENAI_API_KEY not set"
    echo ""
    echo "Please set your OpenAI API key:"
    echo "  export OPENAI_API_KEY='sk-proj-...'"
    echo ""
    exit 1
fi

echo "🚀 批量例句生成器 - 完整运行模式"
echo "使用模型: gpt-4o-mini"
echo "目标: Top 1000 词条"
echo "模式: 循环运行直到全部完成"
echo "预计时间: ~1-2 小时"
echo "预计成本: ~$0.60-1.00"
echo ""

# 循环运行直到完成
ITERATION=1
while true; do
    echo ""
    echo "========== 第 $ITERATION 轮 =========="

    # Run batch generation
    python3 scripts/batch_generate_examples.py \
        --db "data/dictionary_full_multilingual.sqlite" \
        --max-rank 1000 \
        --batch-size 100 \
        --daily-limit 100000 \
        --model gpt-4o-mini

    # 检查是否还有未完成的词条
    REMAINING=$(sqlite3 data/dictionary_full_multilingual.sqlite "
        SELECT COUNT(*) FROM dictionary_entries e
        WHERE e.id <= 1000
          AND NOT EXISTS (
              SELECT 1 FROM word_senses ws
              JOIN example_sentences ex ON ws.id = ex.sense_id
              WHERE ws.entry_id = e.id
          )
    ")

    echo ""
    echo "剩余词条: $REMAINING"

    if [ "$REMAINING" -eq 0 ]; then
        echo ""
        echo "🎉 所有 1000 个词条已完成！"
        break
    fi

    ITERATION=$((ITERATION + 1))
    sleep 2
done

echo ""
echo "✅ 批量生成完成！"
echo ""
echo "查看结果:"
echo "  - 状态文件: .batch_generate_state.json"
echo "  - 日志文件: batch_generate_log_*.json"
echo ""

# 显示最终统计
TOTAL_EXAMPLES=$(sqlite3 data/dictionary_full_multilingual.sqlite "SELECT COUNT(*) FROM example_sentences")
TOTAL_ENTRIES=$(sqlite3 data/dictionary_full_multilingual.sqlite "SELECT COUNT(DISTINCT e.id) FROM dictionary_entries e JOIN word_senses ws ON e.id = ws.entry_id JOIN example_sentences ex ON ws.id = ex.sense_id WHERE e.id <= 1000")

echo "📊 最终统计:"
echo "  - 完成词条: $TOTAL_ENTRIES"
echo "  - 生成例句: $TOTAL_EXAMPLES"
echo ""
echo "数据库已更新: data/dictionary_full_multilingual.sqlite"
