#!/bin/bash
# 批量生成例句 - 便捷启动脚本

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色输出
RED='\033[0:31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🚀 批量例句生成器${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查Python环境
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ 错误: 未找到 python3${NC}"
    exit 1
fi

# 检查OpenAI包
if ! python3 -c "import openai" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  警告: 未安装 openai 包${NC}"
    echo -e "${YELLOW}   运行: pip3 install openai${NC}"
    read -p "是否现在安装？ (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pip3 install openai
    else
        exit 1
    fi
fi

# 查找数据库文件
DB_PATH=""
if [ -f "$PROJECT_ROOT/NichiDict.sqlite" ]; then
    DB_PATH="$PROJECT_ROOT/NichiDict.sqlite"
elif [ -f "$PROJECT_ROOT/Resources/NichiDict.sqlite" ]; then
    DB_PATH="$PROJECT_ROOT/Resources/NichiDict.sqlite"
elif [ -f "$PROJECT_ROOT/dict.sqlite" ]; then
    DB_PATH="$PROJECT_ROOT/dict.sqlite"
else
    echo -e "${YELLOW}⚠️  未自动找到数据库文件${NC}"
    read -p "请输入数据库路径: " DB_PATH
fi

if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}❌ 数据库文件不存在: $DB_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 数据库: $DB_PATH${NC}"

# 检查API Key
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${YELLOW}⚠️  未设置 OPENAI_API_KEY 环境变量${NC}"
    read -p "请输入 OpenAI API Key: " OPENAI_API_KEY
    export OPENAI_API_KEY
fi

# 参数设置
MAX_RANK="${MAX_RANK:-5000}"
BATCH_SIZE="${BATCH_SIZE:-10}"
DAILY_LIMIT="${DAILY_LIMIT:-100}"
MAX_EXAMPLES="${MAX_EXAMPLES:-3}"
MODEL="${MODEL:-gpt-4o-mini}"

echo ""
echo -e "${GREEN}📝 配置参数:${NC}"
echo "   模型: $MODEL"
echo "   最大频率排名: $MAX_RANK"
echo "   批次大小: $BATCH_SIZE"
echo "   每日限额: $DAILY_LIMIT"
echo "   每词例句数: $MAX_EXAMPLES"
echo ""

# 询问是否测试模式
read -p "是否运行测试模式（不实际生成）？ (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    DRY_RUN="--dry-run"
    echo -e "${YELLOW}🧪 测试模式${NC}"
else
    DRY_RUN=""
    echo -e "${GREEN}🔥 生产模式${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}开始生成...${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 运行脚本
python3 "$SCRIPT_DIR/batch_generate_examples.py" \
    --db "$DB_PATH" \
    --model "$MODEL" \
    --max-rank "$MAX_RANK" \
    --batch-size "$BATCH_SIZE" \
    --daily-limit "$DAILY_LIMIT" \
    --max-examples "$MAX_EXAMPLES" \
    $DRY_RUN

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ 完成！${NC}"
echo -e "${GREEN}========================================${NC}"
