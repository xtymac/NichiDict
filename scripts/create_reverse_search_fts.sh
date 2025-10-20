#!/bin/bash

# Script to create reverse_search_fts table for English/Chinese to Japanese search
# This enables bidirectional dictionary search

DB_PATH="../data/dictionary_full_multilingual.sqlite"

echo "Creating reverse_search_fts table..."

sqlite3 "$DB_PATH" <<'EOF'
-- Create reverse search FTS5 table
-- Note: We need to handle stop words properly for short queries like "go", "do", etc.
DROP TABLE IF EXISTS reverse_search_fts;

-- Create FTS5 table with tokenizer that preserves all words (even common ones)
CREATE VIRTUAL TABLE reverse_search_fts USING fts5(
    entry_id UNINDEXED,
    search_text,
    content='',
    tokenize='porter ascii'
);

-- Populate with English and Chinese definitions
INSERT INTO reverse_search_fts(entry_id, search_text)
SELECT
    ws.entry_id,
    ws.definition_english || ' ' ||
    COALESCE(ws.definition_chinese_simplified, '') || ' ' ||
    COALESCE(ws.definition_chinese_traditional, '')
FROM word_senses ws;

-- Optimize the FTS index
INSERT INTO reverse_search_fts(reverse_search_fts) VALUES('optimize');

-- Verify creation
SELECT
    'Table created successfully with ' || COUNT(*) || ' entries' as status
FROM reverse_search_fts;
EOF

echo "✅ Reverse search FTS table created successfully!"
echo ""
echo "Testing with 'go' query:"
sqlite3 "$DB_PATH" "
SELECT de.headword, de.reading_hiragana, ws.definition_english
FROM reverse_search_fts r
JOIN dictionary_entries de ON r.entry_id = de.id
JOIN word_senses ws ON r.entry_id = ws.entry_id
WHERE reverse_search_fts MATCH '\"go\"'
LIMIT 10;
"
