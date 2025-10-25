#!/bin/bash
# 测试例句生成性能
# Test example sentence performance

cd "$(dirname "$0")/.."

DB_PATH="data/dictionary_full_multilingual.sqlite"

echo "======================================"
echo "📊 例句生成性能测试"
echo "======================================"
echo ""

# 测试1: 检查已生成例句的词条数量
echo "1️⃣ 统计已生成例句的词条"
TOTAL_WITH_EXAMPLES=$(sqlite3 "$DB_PATH" "
SELECT COUNT(DISTINCT e.id)
FROM dictionary_entries e
JOIN word_senses ws ON e.id = ws.entry_id
JOIN example_sentences ex ON ws.id = ex.sense_id
WHERE e.id <= 1000;
")

TOTAL_EXAMPLES=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*)
FROM example_sentences ex
JOIN word_senses ws ON ex.sense_id = ws.id
JOIN dictionary_entries e ON ws.entry_id = e.id
WHERE e.id <= 1000;
")

echo "   ✅ Top 1000 词条中有例句: $TOTAL_WITH_EXAMPLES 个"
echo "   ✅ 总例句数: $TOTAL_EXAMPLES 个"
echo "   ✅ 平均每词: $(echo "scale=1; $TOTAL_EXAMPLES / $TOTAL_WITH_EXAMPLES" | bc) 个例句"
echo ""

# 测试2: 随机抽样检查例句质量
echo "2️⃣ 随机抽样检查（5个词条）"
sqlite3 "$DB_PATH" "
SELECT
    '【' || e.headword || '】 ' || e.reading_hiragana as word,
    '   例句: ' || ex.japanese_text as example,
    '   英译: ' || ex.english_translation as translation
FROM dictionary_entries e
JOIN word_senses ws ON e.id = ws.entry_id
JOIN example_sentences ex ON ws.id = ex.sense_id
WHERE e.id <= 1000
ORDER BY RANDOM()
LIMIT 5;
" | while read line; do
    echo "$line"
done
echo ""

# 测试3: 检查常用词
echo "3️⃣ 常用词例句检查"
for word in "お金" "お母さん" "お茶"; do
    echo "   📖 $word:"
    sqlite3 "$DB_PATH" "
    SELECT '      • ' || ex.japanese_text
    FROM dictionary_entries e
    JOIN word_senses ws ON e.id = ws.entry_id
    JOIN example_sentences ex ON ws.id = ex.sense_id
    WHERE e.headword = '$word'
    LIMIT 1;
    "
done
echo ""

# 测试4: 覆盖率统计
echo "4️⃣ 覆盖率统计"
COVERAGE=$(echo "scale=1; $TOTAL_WITH_EXAMPLES * 100 / 1000" | bc)
echo "   📊 Top 1000 覆盖率: $COVERAGE%"
echo ""

echo "======================================"
echo "✅ 测试完成！"
echo "======================================"
echo ""
echo "💡 性能提升预期:"
echo "   • 有例句的词条: <50ms (已缓存)"
echo "   • 无例句的词条: 1-3秒 (需AI生成)"
echo "   • 速度提升: 约60倍 ⚡"
echo ""
echo "📱 下一步："
echo "   1. 将数据库复制到 App: cp data/dictionary_full_multilingual.sqlite NichiDict/Resources/seed.sqlite"
echo "   2. 重新构建 App"
echo "   3. 在真机/模拟器上测试查询速度"
