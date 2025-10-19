#!/bin/bash
#
# Test script for multilingual JMdict import
# Tests with a small subset of data first
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
JMDICT_XML="$DATA_DIR/JMdict_e"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}JMdict Multilingual Import Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check if JMdict file exists
if [ ! -f "$JMDICT_XML" ]; then
    echo -e "${YELLOW}Error: JMdict file not found at $JMDICT_XML${NC}"
    echo "Please download JMdict_e from: http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found JMdict file: $JMDICT_XML"
echo

# Test 1: Import first 1000 entries
echo -e "${BLUE}Test 1: Importing first 1000 entries...${NC}"
TEST_DB="$DATA_DIR/dictionary_test_multilingual.sqlite"

# Remove old test database
rm -f "$TEST_DB"

python3 "$SCRIPT_DIR/import_jmdict_multilingual.py" \
    "$JMDICT_XML" \
    "$TEST_DB" \
    --max-entries 1000

echo
echo -e "${GREEN}✓${NC} Test import completed"
echo

# Test 2: Query the database
echo -e "${BLUE}Test 2: Querying test data...${NC}"
echo

# Check specific words with Chinese translations
sqlite3 "$TEST_DB" <<EOF
.mode column
.headers on

-- Check entry count
SELECT 'Total Entries' as Metric, COUNT(*) as Count FROM dictionary_entries
UNION ALL
SELECT 'Total Senses', COUNT(*) FROM word_senses
UNION ALL
SELECT 'With Chinese (Simp)', COUNT(DISTINCT entry_id) FROM word_senses WHERE definition_chinese_simplified IS NOT NULL
UNION ALL
SELECT 'With Chinese (Trad)', COUNT(DISTINCT entry_id) FROM word_senses WHERE definition_chinese_traditional IS NOT NULL;

-- Sample entries
.print ""
.print "Sample entries with multilingual definitions:"
.print "=============================================="

SELECT
    e.headword as 見出し語,
    e.reading_hiragana as 読み,
    s.part_of_speech as 品詞,
    s.definition_english as English,
    CASE
        WHEN s.definition_chinese_simplified IS NOT NULL
        THEN substr(s.definition_chinese_simplified, 1, 30) || '...'
        ELSE NULL
    END as 簡体中文
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE s.definition_chinese_simplified IS NOT NULL
LIMIT 10;
EOF

echo
echo -e "${GREEN}✓${NC} Test query completed"
echo

# Ask user if they want to import full database
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Test completed successfully!${NC}"
echo
echo "Would you like to import the FULL JMdict database?"
echo "(This will take ~10-15 minutes and create a ~90MB database)"
echo
read -p "Import full database? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    FULL_DB="$DATA_DIR/dictionary_full_multilingual.sqlite"

    echo
    echo -e "${BLUE}Starting full import...${NC}"
    echo

    # Backup existing full database if it exists
    if [ -f "$FULL_DB" ]; then
        BACKUP="$DATA_DIR/dictionary_full_multilingual_backup_$(date +%Y%m%d_%H%M%S).sqlite"
        echo -e "${YELLOW}Backing up existing database to:${NC}"
        echo "  $BACKUP"
        mv "$FULL_DB" "$BACKUP"
        echo
    fi

    # Import full database
    python3 "$SCRIPT_DIR/import_jmdict_multilingual.py" \
        "$JMDICT_XML" \
        "$FULL_DB"

    echo
    echo -e "${GREEN}✓${NC} Full import completed!"
    echo
    echo "Database location: $FULL_DB"
    echo

    # Show final statistics
    echo -e "${BLUE}Final Statistics:${NC}"
    sqlite3 "$FULL_DB" <<EOF
.mode column
.headers on

SELECT
    'Entries' as Type,
    COUNT(*) as Count,
    printf('%.2f MB', (SELECT page_count * page_size / 1024.0 / 1024.0 FROM pragma_page_count(), pragma_page_size())) as 'DB Size'
FROM dictionary_entries
UNION ALL
SELECT 'Senses', COUNT(*), '' FROM word_senses
UNION ALL
SELECT 'With Chinese', COUNT(DISTINCT entry_id), '' FROM word_senses WHERE definition_chinese_simplified IS NOT NULL OR definition_chinese_traditional IS NOT NULL;
EOF

    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Full import completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo
    echo "Skipping full import. Test database available at:"
    echo "  $TEST_DB"
fi

echo
echo "Done!"
