#!/bin/bash
# Test reverse search functionality (English/Chinese → Japanese)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

DB_PATH="${1:-../data/dictionary_full.sqlite}"

if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}Error: Database not found at $DB_PATH${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Reverse Search Test (English/Chinese → Japanese)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if reverse_search_fts exists
has_reverse=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM sqlite_master
    WHERE type='table' AND name='reverse_search_fts';
")

if [ "$has_reverse" = "0" ]; then
    echo -e "${RED}✗ reverse_search_fts table not found!${NC}"
    echo "Please run: python3 scripts/add_reverse_search_index.py"
    exit 1
fi

echo -e "${GREEN}✓ reverse_search_fts table exists${NC}"
echo ""

# Test cases
echo -e "${YELLOW}Test 1: English → Japanese${NC}"
echo "-----------------------------------"

test_english_queries=("eat" "school" "study" "water" "afternoon")

for query in "${test_english_queries[@]}"; do
    echo -e "${CYAN}Query: '$query'${NC}"
    result=$(sqlite3 "$DB_PATH" "
        SELECT
            e.headword,
            e.reading_hiragana,
            s.definition_english
        FROM reverse_search_fts r
        JOIN word_senses s ON r.sense_id = s.id
        JOIN dictionary_entries e ON r.entry_id = e.id
        WHERE reverse_search_fts MATCH 'definition_english:$query'
        ORDER BY e.frequency_rank ASC
        LIMIT 3;
    " 2>/dev/null)

    if [ -n "$result" ]; then
        while IFS='|' read -r headword reading english; do
            echo -e "  ${GREEN}→${NC} $headword ($reading)"
            echo -e "     $english"
        done <<< "$result"
    else
        echo -e "  ${RED}No results${NC}"
    fi
    echo ""
done

echo -e "${YELLOW}Test 2: Chinese → Japanese${NC}"
echo "-----------------------------------"

test_chinese_queries=("下午" "学习" "学校" "水" "吃")

for query in "${test_chinese_queries[@]}"; do
    echo -e "${CYAN}Query: '$query'${NC}"
    result=$(sqlite3 "$DB_PATH" "
        SELECT
            e.headword,
            e.reading_hiragana,
            s.definition_chinese_simplified
        FROM reverse_search_fts r
        JOIN word_senses s ON r.sense_id = s.id
        JOIN dictionary_entries e ON r.entry_id = e.id
        WHERE reverse_search_fts MATCH 'definition_chinese:$query'
        ORDER BY e.frequency_rank ASC
        LIMIT 3;
    " 2>/dev/null)

    if [ -n "$result" ]; then
        while IFS='|' read -r headword reading chinese; do
            echo -e "  ${GREEN}→${NC} $headword ($reading)"
            echo -e "     中文: $chinese"
        done <<< "$result"
    else
        echo -e "  ${RED}No results${NC}"
    fi
    echo ""
done

echo -e "${YELLOW}Test 3: Statistics${NC}"
echo "-----------------------------------"

total_indexed=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM reverse_search_fts;")
with_english=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM reverse_search_fts
    WHERE definition_english != '';
")
with_chinese=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM reverse_search_fts
    WHERE definition_chinese != '';
")

echo "Total senses indexed: $total_indexed"
echo "With English definitions: $with_english"
echo "With Chinese definitions: $with_chinese"
echo ""

# Test wildcard search
echo -e "${YELLOW}Test 4: Wildcard Search${NC}"
echo "-----------------------------------"

echo -e "${CYAN}Query: 'eat*' (prefix search)${NC}"
result=$(sqlite3 "$DB_PATH" "
    SELECT
        e.headword,
        e.reading_hiragana,
        s.definition_english
    FROM reverse_search_fts r
    JOIN word_senses s ON r.sense_id = s.id
    JOIN dictionary_entries e ON r.entry_id = e.id
    WHERE reverse_search_fts MATCH 'definition_english:eat*'
    ORDER BY e.frequency_rank ASC
    LIMIT 5;
" 2>/dev/null)

count=0
while IFS='|' read -r headword reading english; do
    echo -e "  ${GREEN}[$((++count))]${NC} $headword ($reading) - $english"
done <<< "$result"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Reverse search tests complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
