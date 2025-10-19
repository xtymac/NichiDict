#!/bin/bash

# Test search ranking for common Japanese words
DB_PATH="../NichiDict/Resources/seed.sqlite"

if [ ! -f "$DB_PATH" ]; then
    echo "Error: Database not found at $DB_PATH"
    exit 1
fi

echo "========================================="
echo "Search Ranking Test"
echo "========================================="
echo ""

# Test 1: 行く
echo "Test 1: Searching for '行く'"
echo "-----------------------------------------"
sqlite3 "$DB_PATH" "
SELECT
    e.headword,
    e.reading_hiragana,
    CASE
        WHEN e.headword = '行く' THEN 0
        WHEN e.reading_hiragana = 'いく' THEN 1
        ELSE 2
    END AS priority
FROM dictionary_entries e
WHERE e.reading_hiragana = 'いく'
ORDER BY priority ASC, COALESCE(e.frequency_rank, 999999) ASC
LIMIT 5;
"
echo ""

# Test 2: 見る
echo "Test 2: Searching for '見る'"
echo "-----------------------------------------"
sqlite3 "$DB_PATH" "
SELECT
    e.headword,
    e.reading_hiragana,
    CASE
        WHEN e.headword = '見る' THEN 0
        WHEN e.reading_hiragana = 'みる' THEN 1
        ELSE 2
    END AS priority
FROM dictionary_entries e
WHERE e.reading_hiragana = 'みる'
ORDER BY priority ASC, COALESCE(e.frequency_rank, 999999) ASC
LIMIT 5;
"
echo ""

echo "✅ Test Complete - 行く and 見る should be first"
