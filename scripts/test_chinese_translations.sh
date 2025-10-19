#!/bin/bash
# Test script to verify Chinese translations in the dictionary database
# Usage: ./test_chinese_translations.sh [database_path]

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default database path
DB_PATH="${1:-../data/dictionary_full.sqlite}"

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}Error: Database not found at $DB_PATH${NC}"
    echo "Usage: $0 [database_path]"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Chinese Translation Test Report${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Test 1: Overall statistics
echo -e "${YELLOW}📊 Test 1: Overall Statistics${NC}"
echo "-----------------------------------"

total_entries=$(sqlite3 "$DB_PATH" "SELECT COUNT(DISTINCT id) FROM dictionary_entries;")
entries_with_chinese=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(DISTINCT entry_id)
    FROM word_senses
    WHERE definition_chinese_simplified IS NOT NULL
    OR definition_chinese_traditional IS NOT NULL;
")
total_senses=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM word_senses;")
senses_with_chinese=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM word_senses
    WHERE definition_chinese_simplified IS NOT NULL
    OR definition_chinese_traditional IS NOT NULL;
")

echo "Total dictionary entries: $total_entries"
echo "Entries with Chinese: $entries_with_chinese"
coverage=$(awk "BEGIN {printf \"%.2f\", ($entries_with_chinese/$total_entries)*100}")
echo -e "Coverage: ${GREEN}${coverage}%${NC}"
echo ""
echo "Total word senses: $total_senses"
echo "Senses with Chinese: $senses_with_chinese"
echo ""

# Test 2: Sample common words
echo -e "${YELLOW}📝 Test 2: Common Words Test${NC}"
echo "-----------------------------------"

test_words=("食べる" "今日" "学校" "日本" "勉強" "行く" "来る" "見る" "水")

for word in "${test_words[@]}"; do
    result=$(sqlite3 "$DB_PATH" "
        SELECT
            e.headword,
            e.reading_hiragana,
            s.definition_english,
            s.definition_chinese_simplified
        FROM dictionary_entries e
        JOIN word_senses s ON e.id = s.entry_id
        WHERE e.headword = '$word'
        AND s.definition_chinese_simplified IS NOT NULL
        LIMIT 1;
    " 2>/dev/null)

    if [ -n "$result" ]; then
        IFS='|' read -r headword reading english chinese <<< "$result"
        echo -e "${GREEN}✓${NC} $headword ($reading)"
        echo "  EN: $english"
        echo "  ZH: $chinese"
        echo ""
    else
        echo -e "${RED}✗${NC} $word - No Chinese translation"
        echo ""
    fi
done

# Test 3: Simplified vs Traditional Chinese
echo -e "${YELLOW}🔤 Test 3: Simplified vs Traditional Chinese${NC}"
echo "-----------------------------------"

entries_with_simplified=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM word_senses
    WHERE definition_chinese_simplified IS NOT NULL
    AND definition_chinese_simplified != '';
")

entries_with_traditional=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM word_senses
    WHERE definition_chinese_traditional IS NOT NULL
    AND definition_chinese_traditional != '';
")

entries_with_both=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM word_senses
    WHERE definition_chinese_simplified IS NOT NULL
    AND definition_chinese_traditional IS NOT NULL;
")

echo "Entries with Simplified Chinese: $entries_with_simplified"
echo "Entries with Traditional Chinese: $entries_with_traditional"
echo "Entries with both: $entries_with_both"
echo ""

# Sample entry with both
echo "Example entry with both forms:"
sqlite3 "$DB_PATH" "
    SELECT
        e.headword,
        s.definition_chinese_simplified,
        s.definition_chinese_traditional
    FROM dictionary_entries e
    JOIN word_senses s ON e.id = s.entry_id
    WHERE s.definition_chinese_simplified IS NOT NULL
    AND s.definition_chinese_traditional IS NOT NULL
    LIMIT 1;
" | while IFS='|' read -r headword simplified traditional; do
    echo "  Word: $headword"
    echo "  Simplified: $simplified"
    echo "  Traditional: $traditional"
done
echo ""

# Test 4: Top 10 most translated words
echo -e "${YELLOW}🌟 Test 4: Top 10 Entries (by frequency)${NC}"
echo "-----------------------------------"

sqlite3 "$DB_PATH" "
    SELECT
        e.headword,
        e.reading_hiragana,
        e.frequency_rank,
        s.definition_chinese_simplified
    FROM dictionary_entries e
    JOIN word_senses s ON e.id = s.entry_id
    WHERE s.definition_chinese_simplified IS NOT NULL
    AND e.frequency_rank IS NOT NULL
    ORDER BY e.frequency_rank ASC
    LIMIT 10;
" | while IFS='|' read -r headword reading freq chinese; do
    echo -e "${GREEN}#${freq}${NC} $headword ($reading)"
    echo "     $chinese"
done
echo ""

# Test 5: Part of speech distribution
echo -e "${YELLOW}📚 Test 5: Part of Speech Distribution${NC}"
echo "-----------------------------------"

sqlite3 "$DB_PATH" "
    SELECT
        s.part_of_speech,
        COUNT(*) as count
    FROM word_senses s
    WHERE s.definition_chinese_simplified IS NOT NULL
    GROUP BY s.part_of_speech
    ORDER BY count DESC
    LIMIT 10;
" | while IFS='|' read -r pos count; do
    echo "$count entries: $pos"
done
echo ""

# Test 6: Search functionality test
echo -e "${YELLOW}🔍 Test 6: Search Functionality${NC}"
echo "-----------------------------------"

echo "Testing FTS5 search with Chinese translations:"
search_term="たべる"
echo "Search term: $search_term"
echo ""

sqlite3 "$DB_PATH" "
    SELECT
        e.headword,
        e.reading_hiragana,
        s.definition_english,
        s.definition_chinese_simplified
    FROM dictionary_entries e
    JOIN word_senses s ON e.id = s.entry_id
    JOIN dictionary_fts fts ON e.id = fts.rowid
    WHERE dictionary_fts MATCH '$search_term'
    AND s.definition_chinese_simplified IS NOT NULL
    LIMIT 5;
" | while IFS='|' read -r headword reading english chinese; do
    echo -e "${GREEN}→${NC} $headword ($reading)"
    echo "   EN: $english"
    echo "   ZH: $chinese"
    echo ""
done

# Test 7: Data quality check
echo -e "${YELLOW}✓ Test 7: Data Quality Check${NC}"
echo "-----------------------------------"

# Check for empty Chinese translations
empty_chinese=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM word_senses
    WHERE (definition_chinese_simplified IS NOT NULL AND definition_chinese_simplified = '')
    OR (definition_chinese_traditional IS NOT NULL AND definition_chinese_traditional = '');
")

echo "Empty Chinese translations: $empty_chinese"

# Check for very long translations (possible data issues)
long_translations=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM word_senses
    WHERE LENGTH(definition_chinese_simplified) > 200;
")

echo "Very long translations (>200 chars): $long_translations"

# Check for Chinese translations with only English text
non_chinese=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM word_senses
    WHERE definition_chinese_simplified IS NOT NULL
    AND definition_chinese_simplified NOT GLOB '*[一-龥]*'
    AND definition_chinese_simplified NOT GLOB '*[ぁ-ん]*'
    AND LENGTH(definition_chinese_simplified) > 0;
")

echo "Entries without Chinese characters: $non_chinese"
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ "$entries_with_chinese" -gt 0 ]; then
    echo -e "${GREEN}✓ Chinese translations are present${NC}"
    echo -e "${GREEN}✓ $entries_with_chinese entries have Chinese definitions${NC}"
    echo -e "${GREEN}✓ Coverage: ${coverage}% of total entries${NC}"
    echo ""
    echo -e "${YELLOW}Recommendation:${NC}"
    if (( $(echo "$coverage < 5.0" | bc -l) )); then
        echo "  Coverage is low. Consider importing more Chinese dictionary sources."
    else
        echo "  Coverage is good for initial release. Can be improved with additional sources."
    fi
else
    echo -e "${RED}✗ No Chinese translations found${NC}"
    echo "  Please run: python3 scripts/import_chinese_translations.py"
fi

echo ""
echo -e "${BLUE}Test completed!${NC}"
