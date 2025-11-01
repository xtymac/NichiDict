#!/bin/bash
# N5例句快速测试脚本

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# 数据库路径
DB_PATH="$PROJECT_ROOT/NichiDict/Resources/seed.sqlite"

# 检查数据库是否存在
if [ ! -f "$DB_PATH" ]; then
    echo "❌ 错误：找不到数据库文件"
    echo "预期路径：$DB_PATH"
    exit 1
fi

echo "======================================"
echo "N5 例句测试脚本"
echo "======================================"

echo ""
echo "1. 例句总数："
sqlite3 "$DB_PATH" <<'SQL'
SELECT COUNT(*)
FROM example_sentences
WHERE sense_id IN (
  SELECT s.id FROM word_senses s
  JOIN dictionary_entries d ON s.entry_id = d.id
  WHERE d.jlpt_level = 'N5'
);
SQL

echo ""
echo "2. 覆盖率："
sqlite3 "$DB_PATH" <<'SQL'
SELECT
  ROUND(CAST(COUNT(DISTINCT CASE WHEN e.id IS NOT NULL THEN s.id END) AS FLOAT) / COUNT(DISTINCT s.id) * 100, 2) || '%' as coverage
FROM dictionary_entries d
JOIN word_senses s ON s.entry_id = d.id
LEFT JOIN example_sentences e ON e.sense_id = s.id
WHERE d.jlpt_level = 'N5';
SQL

echo ""
echo "3. 缺失例句的词条："
sqlite3 "$DB_PATH" <<'SQL'
SELECT COUNT(*)
FROM word_senses s
JOIN dictionary_entries d ON s.entry_id = d.id
WHERE d.jlpt_level = 'N5'
  AND s.id NOT IN (SELECT sense_id FROM example_sentences WHERE sense_id IS NOT NULL);
SQL

echo ""
echo "4. 句子长度分布："
sqlite3 -column -header "$DB_PATH" <<'SQL'
SELECT
  CASE
    WHEN LENGTH(japanese_text) < 10 THEN '<10字符'
    WHEN LENGTH(japanese_text) BETWEEN 10 AND 20 THEN '10-20字符'
    WHEN LENGTH(japanese_text) BETWEEN 21 AND 30 THEN '21-30字符'
    WHEN LENGTH(japanese_text) > 30 THEN '>30字符'
  END as 长度范围,
  COUNT(*) as 数量,
  ROUND(CAST(COUNT(*) AS FLOAT) / (SELECT COUNT(*) FROM example_sentences WHERE sense_id IN (SELECT s.id FROM word_senses s JOIN dictionary_entries d ON s.entry_id = d.id WHERE d.jlpt_level = 'N5')) * 100, 1) || '%' as 占比
FROM example_sentences
WHERE sense_id IN (
  SELECT s.id FROM word_senses s
  JOIN dictionary_entries d ON s.entry_id = d.id
  WHERE d.jlpt_level = 'N5'
)
GROUP BY 长度范围
ORDER BY MIN(LENGTH(japanese_text));
SQL

echo ""
echo "5. 随机抽样 5 条例句："
echo "----------------------------------------"
sqlite3 "$DB_PATH" <<'SQL'
SELECT
  '单词: ' || d.headword || ' (' || d.reading_hiragana || ')',
  '日语: ' || e.japanese_text,
  '中文: ' || COALESCE(e.chinese_translation, '(无)'),
  '英语: ' || e.english_translation,
  '---'
FROM example_sentences e
JOIN word_senses s ON e.sense_id = s.id
JOIN dictionary_entries d ON s.entry_id = d.id
WHERE d.jlpt_level = 'N5'
ORDER BY RANDOM()
LIMIT 5;
SQL

echo ""
echo "======================================"
echo "测试完成！"
echo "======================================"