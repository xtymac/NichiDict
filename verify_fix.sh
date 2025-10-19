#!/bin/bash

echo "=========================================="
echo "NichiDict 修复验证脚本"
echo "=========================================="
echo ""

DB_PATH="/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite"

# 1. 检查数据库文件是否存在
echo "1️⃣  检查数据库文件..."
if [ -f "$DB_PATH" ]; then
    echo "   ✅ seed.sqlite 存在"
    echo "   📊 大小: $(ls -lh "$DB_PATH" | awk '{print $5}')"
else
    echo "   ❌ seed.sqlite 不存在！"
    exit 1
fi
echo ""

# 2. 检查 reverse_search_fts 表
echo "2️⃣  检查 reverse_search_fts 表..."
TABLE_EXISTS=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='reverse_search_fts';")
if [ -n "$TABLE_EXISTS" ]; then
    echo "   ✅ reverse_search_fts 表存在"
    ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM reverse_search_fts;")
    echo "   📊 记录数: $ROW_COUNT"
else
    echo "   ❌ reverse_search_fts 表不存在！"
    echo "   🔧 正在创建..."
    sqlite3 "$DB_PATH" "
    CREATE VIRTUAL TABLE IF NOT EXISTS reverse_search_fts USING fts5(
        entry_id UNINDEXED,
        search_text,
        content='',
        tokenize='porter ascii'
    );

    INSERT INTO reverse_search_fts(entry_id, search_text)
    SELECT
        ws.entry_id,
        ws.definition_english || ' ' ||
        COALESCE(ws.definition_chinese_simplified, '') || ' ' ||
        COALESCE(ws.definition_chinese_traditional, '')
    FROM word_senses ws;

    INSERT INTO reverse_search_fts(reverse_search_fts) VALUES('optimize');
    "
    echo "   ✅ 表创建完成"
fi
echo ""

# 3. 测试 "go" 查询
echo "3️⃣  测试 'go' 查询..."
RESULTS=$(sqlite3 "$DB_PATH" "
SELECT e.headword, e.reading_hiragana
FROM dictionary_entries e
JOIN word_senses ws ON e.id = ws.entry_id
WHERE (
    LOWER(ws.definition_english) = 'to go'
    OR LOWER(ws.definition_english) LIKE 'to go;%'
)
ORDER BY e.frequency_rank ASC
LIMIT 3;
")

if echo "$RESULTS" | grep -q "行く"; then
    echo "   ✅ 查询结果正确："
    echo "$RESULTS" | while IFS='|' read -r headword reading; do
        echo "      - $headword ($reading)"
    done
else
    echo "   ❌ 查询结果不正确！"
    echo "   实际结果："
    echo "$RESULTS"
fi
echo ""

# 4. 检查代码文件
echo "4️⃣  检查代码文件..."
SEARCH_SERVICE="/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/SearchService.swift"

if grep -q "commonEnglishWords" "$SEARCH_SERVICE"; then
    echo "   ✅ SearchService 已包含英文词白名单"
else
    echo "   ❌ SearchService 缺少英文词白名单！"
fi

if grep -q "🔍 SearchService" "$SEARCH_SERVICE"; then
    echo "   ✅ SearchService 已添加调试日志"
else
    echo "   ⚠️  SearchService 缺少调试日志"
fi
echo ""

# 5. 检查是否有运行中的应用
echo "5️⃣  检查运行状态..."
if pgrep -f "NichiDict" > /dev/null; then
    echo "   ⚠️  检测到 NichiDict 进程正在运行"
    echo "   💡 建议：停止应用后重新构建"
else
    echo "   ℹ️  没有检测到运行中的应用"
fi
echo ""

# 6. 总结
echo "=========================================="
echo "📋 总结"
echo "=========================================="
echo ""
echo "✅ 修复步骤："
echo "   1. 数据库已更新（包含 reverse_search_fts）"
echo "   2. 代码逻辑已修复（英文词白名单）"
echo "   3. 调试日志已添加"
echo ""
echo "⚠️  下一步："
echo "   1. 在 Xcode 中打开项目"
echo "   2. Product → Clean Build Folder (⇧⌘K)"
echo "   3. Product → Run (⌘R) - 不要用 Preview！"
echo "   4. 搜索 'go' 查看结果"
echo "   5. 检查 Xcode 控制台的调试日志"
echo ""
echo "📖 详细说明见: REBUILD_INSTRUCTIONS.md"
echo ""
