#!/bin/bash
# Interactive word query tool to test Chinese translations
# Usage: ./query_word.sh [word] [database_path]

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

DB_PATH="${2:-../data/dictionary_full.sqlite}"

if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}Error: Database not found at $DB_PATH${NC}"
    exit 1
fi

query_word() {
    local word="$1"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Search: $word${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Query the database
    result=$(sqlite3 "$DB_PATH" "
        SELECT
            e.id,
            e.headword,
            e.reading_hiragana,
            e.reading_romaji,
            e.frequency_rank,
            e.pitch_accent
        FROM dictionary_entries e
        JOIN dictionary_fts fts ON e.id = fts.rowid
        WHERE dictionary_fts MATCH '$word'
        ORDER BY
            CASE
                WHEN e.headword = '$word' THEN 0
                WHEN e.reading_hiragana = '$word' THEN 0
                WHEN e.reading_romaji = '$word' THEN 0
                WHEN e.headword LIKE '$word%' THEN 1
                ELSE 2
            END,
            LENGTH(e.headword) ASC,
            e.frequency_rank ASC
        LIMIT 10;
    " 2>/dev/null)

    if [ -z "$result" ]; then
        echo -e "${RED}✗ No results found for: $word${NC}"
        echo ""
        return
    fi

    # Process results
    local count=0
    while IFS='|' read -r id headword reading romaji freq pitch; do
        count=$((count + 1))

        echo -e "${CYAN}[$count] ${BOLD}$headword${NC} ${YELLOW}($reading)${NC}"
        [ -n "$romaji" ] && echo -e "    Romaji: $romaji"
        [ -n "$pitch" ] && echo -e "    Pitch: $pitch"
        [ -n "$freq" ] && echo -e "    Frequency: #$freq"
        echo ""

        # Get word senses for this entry
        sqlite3 "$DB_PATH" "
            SELECT
                definition_english,
                definition_chinese_simplified,
                definition_chinese_traditional,
                part_of_speech
            FROM word_senses
            WHERE entry_id = $id
            ORDER BY sense_order;
        " | while IFS='|' read -r en_def zh_simp zh_trad pos; do
            echo -e "    ${BLUE}$pos${NC}"
            echo -e "    EN: $en_def"

            if [ -n "$zh_simp" ]; then
                echo -e "    ${GREEN}ZH: $zh_simp${NC}"
            elif [ -n "$zh_trad" ]; then
                echo -e "    ${GREEN}ZH(繁): $zh_trad${NC}"
            else
                echo -e "    ${RED}ZH: (No Chinese translation)${NC}"
            fi
            echo ""
        done

        echo -e "${BLUE}─────────────────────────────────────────${NC}"
        echo ""
    done <<< "$result"

    echo -e "${GREEN}Found $count result(s)${NC}"
    echo ""
}

# Main
if [ -n "$1" ]; then
    # Single query mode
    query_word "$1"
else
    # Interactive mode
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  NichiDict Word Query Tool${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Database: $DB_PATH"
    echo ""
    echo "Enter Japanese word, hiragana, or romaji"
    echo "Type 'quit' or 'exit' to quit"
    echo ""

    while true; do
        echo -n -e "${CYAN}Query> ${NC}"
        read -r word

        # Check for exit commands
        if [ "$word" = "quit" ] || [ "$word" = "exit" ] || [ "$word" = "q" ]; then
            echo "Goodbye!"
            break
        fi

        # Skip empty input
        if [ -z "$word" ]; then
            continue
        fi

        query_word "$word"
    done
fi
