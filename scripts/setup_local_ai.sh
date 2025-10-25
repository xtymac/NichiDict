#!/bin/bash
# 安装和配置本地AI模型（Ollama + Qwen2.5）

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}📦 本地AI模型安装向导${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查是否已安装Ollama
if command -v ollama &> /dev/null; then
    echo -e "${GREEN}✅ Ollama 已安装${NC}"
    ollama --version
else
    echo -e "${YELLOW}📥 正在安装 Ollama...${NC}"
    echo ""
    echo "请访问: https://ollama.com/download"
    echo "或运行以下命令:"
    echo ""
    echo "  curl -fsSL https://ollama.com/install.sh | sh"
    echo ""
    read -p "已完成安装？按回车继续... " -r
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🤖 下载AI模型${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "推荐模型选择:"
echo ""
echo "1. qwen2.5:7b (推荐) - 7GB，速度快，质量好"
echo "2. qwen2.5:14b - 14GB，质量更好，速度中等"
echo "3. qwen2.5:1.5b - 1.5GB，最快，质量稍弱"
echo ""
read -p "请选择模型 (1/2/3, 默认1): " choice
choice=${choice:-1}

case $choice in
    1)
        MODEL="qwen2.5:7b"
        ;;
    2)
        MODEL="qwen2.5:14b"
        ;;
    3)
        MODEL="qwen2.5:1.5b"
        ;;
    *)
        MODEL="qwen2.5:7b"
        ;;
esac

echo ""
echo -e "${GREEN}下载模型: $MODEL${NC}"
echo -e "${YELLOW}⚠️  首次下载需要一些时间，请耐心等待...${NC}"
echo ""

ollama pull $MODEL

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🧪 测试模型${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "测试日语例句生成..."
ollama run $MODEL "Generate one simple Japanese sentence using the word 行く (iku, to go). Return JSON format: {\"japanese\":\"...\",\"english\":\"...\",\"chinese\":\"...\"}" | head -20

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ 安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "使用方法:"
echo ""
echo "1. 启动Ollama服务（如果未自动启动）:"
echo "   ollama serve"
echo ""
echo "2. 运行批量生成（使用本地模型）:"
echo "   python3 batch_generate_examples_local.py --db dict.sqlite --model $MODEL"
echo ""
echo "3. 查看模型列表:"
echo "   ollama list"
echo ""
echo -e "${GREEN}享受免费的本地AI！ 🎉${NC}"
