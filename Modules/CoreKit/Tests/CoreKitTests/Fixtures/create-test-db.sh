#!/bin/bash
# Create test SQLite database for unit tests

DB_PATH="./test-seed.sqlite"
rm -f "$DB_PATH"

sqlite3 "$DB_PATH" <<SQL
-- Main tables
CREATE TABLE dictionary_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    headword TEXT NOT NULL,
    reading_hiragana TEXT NOT NULL,
    reading_romaji TEXT NOT NULL,
    frequency_rank INTEGER,
    pitch_accent TEXT,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
);

CREATE TABLE word_senses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL,
    definition_english TEXT NOT NULL,
    part_of_speech TEXT NOT NULL,
    usage_notes TEXT,
    sense_order INTEGER NOT NULL,
    FOREIGN KEY (entry_id) REFERENCES dictionary_entries(id) ON DELETE CASCADE
);

CREATE TABLE example_sentences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sense_id INTEGER NOT NULL,
    japanese_text TEXT NOT NULL,
    english_translation TEXT NOT NULL,
    example_order INTEGER NOT NULL,
    FOREIGN KEY (sense_id) REFERENCES word_senses(id) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX idx_frequency_rank ON dictionary_entries(frequency_rank);
CREATE INDEX idx_entry_id ON word_senses(entry_id, sense_order);
CREATE INDEX idx_sense_id ON example_sentences(sense_id, example_order);

-- Sample data
INSERT INTO dictionary_entries (id, headword, reading_hiragana, reading_romaji, frequency_rank, pitch_accent)
VALUES
    (1, '食べる', 'たべる', 'taberu', 100, 'た↓べる'),
    (2, '桜', 'さくら', 'sakura', 200, NULL),
    (3, '学校', 'がっこう', 'gakkou', 50, 'が↓っこう'),
    (4, 'たべる', 'たべる', 'taberu', 100, NULL),
    (5, '食', 'しょく', 'shoku', 150, NULL);

INSERT INTO word_senses (id, entry_id, definition_english, part_of_speech, sense_order)
VALUES
    (1, 1, 'to eat', 'ichidan verb,transitive', 1),
    (2, 2, 'cherry blossom; cherry tree', 'noun', 1),
    (3, 3, 'school', 'noun', 1),
    (4, 4, 'to eat', 'ichidan verb', 1),
    (5, 5, 'food; meal', 'noun', 1);

INSERT INTO example_sentences (id, sense_id, japanese_text, english_translation, example_order)
VALUES
    (1, 1, '朝ごはんを食べる', 'I eat breakfast', 1),
    (2, 1, '昼ごはんを食べます', 'I will eat lunch', 2),
    (3, 2, '桜が咲いています', 'The cherry blossoms are blooming', 1);

-- FTS5 virtual table with self-contained content
CREATE VIRTUAL TABLE dictionary_fts USING fts5(
    lemma,
    reading_kana,
    reading_romaji,
    tokenize='unicode61 remove_diacritics 0'
);

-- Populate FTS5 table
INSERT INTO dictionary_fts(rowid, lemma, reading_kana, reading_romaji)
SELECT id, headword, reading_hiragana, reading_romaji FROM dictionary_entries;

SQL

echo "✅ Test database created at: $DB_PATH"
