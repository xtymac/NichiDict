#!/usr/bin/env python3
"""
Add reverse search index to support Chinese→Japanese and English→Japanese queries.

This script creates a new FTS5 virtual table that indexes English and Chinese definitions,
allowing users to search for Japanese words using English or Chinese terms.
"""

import sqlite3
import sys
from pathlib import Path

def add_reverse_search_index(db_path):
    """Add FTS5 index for reverse (English/Chinese → Japanese) search."""

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    print("Adding reverse search index...")
    print(f"Database: {db_path}")
    print()

    # Check if reverse search table already exists
    cursor.execute("""
        SELECT name FROM sqlite_master
        WHERE type='table' AND name='reverse_search_fts';
    """)

    if cursor.fetchone():
        print("⚠️  reverse_search_fts table already exists. Dropping and recreating...")
        cursor.execute("DROP TABLE reverse_search_fts;")
        conn.commit()

    # Create reverse search FTS5 table
    print("Creating reverse_search_fts table...")
    cursor.execute("""
        CREATE VIRTUAL TABLE reverse_search_fts USING fts5(
            entry_id UNINDEXED,
            sense_id UNINDEXED,
            definition_english,
            definition_chinese,
            tokenize='unicode61 remove_diacritics 0'
        );
    """)

    print("Populating reverse search index...")

    # Populate the FTS table with definitions
    # We include both English and Chinese (simplified) definitions
    cursor.execute("""
        INSERT INTO reverse_search_fts (entry_id, sense_id, definition_english, definition_chinese)
        SELECT
            entry_id,
            id,
            definition_english,
            COALESCE(definition_chinese_simplified, '')
        FROM word_senses;
    """)

    conn.commit()

    # Get statistics
    cursor.execute("SELECT COUNT(*) FROM reverse_search_fts;")
    total_indexed = cursor.fetchone()[0]

    cursor.execute("""
        SELECT COUNT(*) FROM reverse_search_fts
        WHERE definition_chinese != '';
    """)
    with_chinese = cursor.fetchone()[0]

    print()
    print("=== Index Creation Complete ===")
    print(f"Total senses indexed: {total_indexed:,}")
    print(f"Senses with Chinese: {with_chinese:,}")
    print(f"Coverage: {(with_chinese/total_indexed*100):.2f}%")
    print()

    # Test the index
    print("Testing reverse search index...")
    print()

    # Test English → Japanese
    print("Test 1: English 'eat' → Japanese")
    cursor.execute("""
        SELECT
            e.headword,
            e.reading_hiragana,
            s.definition_english
        FROM reverse_search_fts r
        JOIN word_senses s ON r.sense_id = s.id
        JOIN dictionary_entries e ON r.entry_id = e.id
        WHERE reverse_search_fts MATCH 'definition_english:eat'
        LIMIT 3;
    """)

    for row in cursor.fetchall():
        print(f"  {row[0]} ({row[1]}) - {row[2]}")
    print()

    # Test Chinese → Japanese
    print("Test 2: Chinese '吃' → Japanese")
    cursor.execute("""
        SELECT
            e.headword,
            e.reading_hiragana,
            s.definition_chinese_simplified
        FROM reverse_search_fts r
        JOIN word_senses s ON r.sense_id = s.id
        JOIN dictionary_entries e ON r.entry_id = e.id
        WHERE reverse_search_fts MATCH 'definition_chinese:吃'
        LIMIT 3;
    """)

    for row in cursor.fetchall():
        print(f"  {row[0]} ({row[1]}) - {row[2]}")
    print()

    # Test Chinese phrase
    print("Test 3: Chinese '下午' → Japanese")
    cursor.execute("""
        SELECT
            e.headword,
            e.reading_hiragana,
            s.definition_chinese_simplified
        FROM reverse_search_fts r
        JOIN word_senses s ON r.sense_id = s.id
        JOIN dictionary_entries e ON r.entry_id = e.id
        WHERE reverse_search_fts MATCH 'definition_chinese:下午'
        LIMIT 3;
    """)

    for row in cursor.fetchall():
        print(f"  {row[0]} ({row[1]}) - {row[2]}")
    print()

    print("✓ Reverse search index created successfully!")
    print()
    print("You can now search for Japanese words using:")
    print("  - English definitions (e.g., 'eat', 'school', 'study')")
    print("  - Chinese translations (e.g., '吃', '学校', '学习')")

    conn.close()
    return True

if __name__ == '__main__':
    # Default database path
    data_dir = Path(__file__).parent.parent / 'data'
    db_path = data_dir / 'dictionary_full.sqlite'

    # Allow custom path via command line
    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1])

    if not db_path.exists():
        print(f"Error: Database not found at {db_path}")
        sys.exit(1)

    # Create backup
    import shutil
    backup_path = db_path.parent / f"{db_path.stem}_backup_before_reverse_index{db_path.suffix}"
    print(f"Creating backup: {backup_path.name}")
    shutil.copy2(db_path, backup_path)
    print()

    # Add reverse search index
    try:
        add_reverse_search_index(db_path)
        print()
        print("✓ Database updated successfully!")
        print(f"Backup saved at: {backup_path}")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
