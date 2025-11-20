-- Test search ranking with frequency data
-- This script simulates search queries and shows how results would be ranked

.mode column
.headers on

-- Test 1: Search for "する" (should show exact match first)
SELECT '=== Test 1: する ===' as test;
SELECT
    headword,
    reading_hiragana,
    frequency_rank,
    jlpt_level,
    CASE
        WHEN headword = 'する' THEN 'exact'
        WHEN headword LIKE 'する%' THEN 'prefix'
        ELSE 'contains'
    END as match_type,
    -- Simulate relevance score
    CASE
        WHEN headword = 'する' THEN 80
        WHEN headword LIKE 'する%' THEN 15
        ELSE 4
    END +
    CASE jlpt_level
        WHEN 'N5' THEN 10
        WHEN 'N4' THEN 7
        WHEN 'N3' THEN 4
        WHEN 'N2' THEN 2
        ELSE 0
    END +
    CASE
        WHEN frequency_rank <= 10 THEN 12
        WHEN frequency_rank <= 30 THEN 9
        WHEN frequency_rank <= 50 THEN 7
        WHEN frequency_rank <= 200 THEN 5
        WHEN frequency_rank <= 1000 THEN 4
        WHEN frequency_rank <= 5000 THEN 3
        ELSE 0
    END as relevance_score
FROM dictionary_entries
WHERE headword LIKE '%する%'
ORDER BY relevance_score DESC, frequency_rank ASC
LIMIT 10;

-- Test 2: Search for "好き" (common word with derivatives)
SELECT '' as blank;
SELECT '=== Test 2: 好き ===' as test;
SELECT
    headword,
    reading_hiragana,
    frequency_rank,
    jlpt_level,
    CASE
        WHEN headword = '好き' THEN 'exact'
        WHEN headword LIKE '好き%' THEN 'prefix'
        ELSE 'contains'
    END as match_type,
    -- Simulate relevance score
    CASE
        WHEN headword = '好き' THEN 80
        WHEN headword LIKE '好き%' THEN 15
        ELSE 4
    END +
    CASE jlpt_level
        WHEN 'N5' THEN 10
        WHEN 'N4' THEN 7
        WHEN 'N3' THEN 4
        WHEN 'N2' THEN 2
        ELSE 0
    END +
    CASE
        WHEN frequency_rank <= 10 THEN 12
        WHEN frequency_rank <= 30 THEN 9
        WHEN frequency_rank <= 50 THEN 7
        WHEN frequency_rank <= 200 THEN 5
        WHEN frequency_rank <= 1000 THEN 4
        WHEN frequency_rank <= 5000 THEN 3
        ELSE 0
    END as relevance_score
FROM dictionary_entries
WHERE headword LIKE '%好き%' OR reading_hiragana LIKE '%すき%'
ORDER BY relevance_score DESC, frequency_rank ASC
LIMIT 10;

-- Test 3: Search for "行く" (common verb)
SELECT '' as blank;
SELECT '=== Test 3: 行く ===' as test;
SELECT
    headword,
    reading_hiragana,
    frequency_rank,
    jlpt_level,
    CASE
        WHEN headword = '行く' THEN 'exact'
        WHEN headword LIKE '行く%' THEN 'prefix'
        ELSE 'contains'
    END as match_type
FROM dictionary_entries
WHERE headword LIKE '%行く%' OR reading_hiragana LIKE '%いく%'
ORDER BY
    CASE WHEN headword = '行く' THEN 0 ELSE 1 END,
    frequency_rank ASC NULLS LAST
LIMIT 10;

-- Test 4: Show frequency distribution summary
SELECT '' as blank;
SELECT '=== Frequency Distribution ===' as test;
SELECT
    CASE
        WHEN frequency_rank IS NULL THEN 'No frequency'
        WHEN frequency_rank <= 10 THEN '1-10 (超高频)'
        WHEN frequency_rank <= 100 THEN '11-100 (高频)'
        WHEN frequency_rank <= 500 THEN '101-500 (中高频)'
        WHEN frequency_rank <= 2000 THEN '501-2000 (中频)'
        ELSE '>2000 (低频)'
    END as frequency_range,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM dictionary_entries), 2) as percentage
FROM dictionary_entries
GROUP BY frequency_range
ORDER BY MIN(COALESCE(frequency_rank, 999999));
