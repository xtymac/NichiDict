#!/bin/bash

# 例句批量翻译脚本启动器

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🚀 启动例句批量翻译..."
echo ""

# 检查 Python 环境
if ! command -v python3 &> /dev/null; then
    echo "❌ 错误: 未找到 python3"
    exit 1
fi

# 检查并安装依赖
echo "📦 检查依赖..."
pip3 install google-generativeai --quiet || {
    echo "❌ 安装 google-generativeai 失败"
    exit 1
}

echo "✅ 依赖检查完成"
echo ""

# 运行翻译脚本
python3 translate_examples.py

echo ""
echo "✅ 翻译完成！"
