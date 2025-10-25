#!/bin/bash
# 批量生成例句 - 便捷启动脚本
# Convenience script for batch example generation

cd "$(dirname "$0")/.."

# Check if API key is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "❌ Error: OPENAI_API_KEY not set"
    echo ""
    echo "Please set your OpenAI API key:"
    echo "  export OPENAI_API_KEY='sk-proj-...'"
    echo ""
    echo "Or add to ~/.zshrc for permanent setup:"
    echo "  echo 'export OPENAI_API_KEY=\"your-key\"' >> ~/.zshrc"
    echo "  source ~/.zshrc"
    echo ""
    echo "Get your API key at: https://platform.openai.com/api-keys"
    exit 1
fi

echo "🚀 批量例句生成器 - Batch Example Generator"
echo "使用模型: gpt-4o-mini"
echo "目标: Top 1000 词条"
echo "一次性完成所有词条"
echo "预计时间: ~1-2 小时"
echo "预计成本: ~$0.60-1.00"
echo ""

# Run batch generation - 一次性完成所有
python3 scripts/batch_generate_examples.py \
    --db "data/dictionary_full_multilingual.sqlite" \
    --max-rank 1000 \
    --batch-size 50 \
    --daily-limit 10000 \
    --model gpt-4o-mini

echo ""
echo "✅ 批量生成完成！"
echo ""
echo "查看结果:"
echo "  - 状态文件: .batch_generate_state.json"
echo "  - 日志文件: batch_generate_log_*.json"
echo ""
echo "数据库已更新: data/dictionary_full_multilingual.sqlite"
