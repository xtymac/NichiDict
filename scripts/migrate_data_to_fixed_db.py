#!/usr/bin/env python3
"""
Migrate example sentences, JLPT levels, and frequency data from old database
to the new fixed database (with 學生 filtered out).
"""

import sqlite3
import sys
from pathlib import Path

def migrate_data(old_db_path: str, new_db_path: str):
    """Migrate data from old database to new database."""

    print(f"📚 Migrating data from old database to new database...")
    print(f"  Old DB: {old_db_path}")
    print(f"  New DB: {new_db_path}")

    # Connect to both databases
    old_conn = sqlite3.connect(old_db_path)
    new_conn = sqlite3.connect(new_db_path)

    old_cursor = old_conn.cursor()
    new_cursor = new_conn.cursor()

    # Step 1: Add jlpt_level column to new database if it doesn't exist
    print("\n1️⃣ Adding jlpt_level column to new database...")
    try:
        new_cursor.execute("ALTER TABLE dictionary_entries ADD COLUMN jlpt_level TEXT")
        new_conn.commit()
        print("  ✅ Added jlpt_level column")
    except sqlite3.OperationalError as e:
        if "duplicate column" in str(e).lower():
            print("  ℹ️  jlpt_level column already exists")
        else:
            raise

    # Step 2: Migrate frequency_rank and jlpt_level based on jmdict_id + headword match
    print("\n2️⃣ Migrating frequency_rank and jlpt_level...")

    # Get all entries from old database with their data
    old_cursor.execute("""
        SELECT jmdict_id, headword, frequency_rank, jlpt_level
        FROM dictionary_entries
        WHERE jmdict_id IS NOT NULL
    """)
    old_entries = old_cursor.fetchall()

    updated_count = 0
    for jmdict_id, headword, freq_rank, jlpt_level in old_entries:
        # Update matching entry in new database
        new_cursor.execute("""
            UPDATE dictionary_entries
            SET frequency_rank = COALESCE(frequency_rank, ?),
                jlpt_level = ?
            WHERE jmdict_id = ? AND headword = ?
        """, (freq_rank, jlpt_level, jmdict_id, headword))

        if new_cursor.rowcount > 0:
            updated_count += 1

    new_conn.commit()
    print(f"  ✅ Updated {updated_count:,} entries with frequency/JLPT data")

    # Step 3: Migrate example sentences
    print("\n3️⃣ Migrating example sentences...")

    # First, we need to map old entry IDs to new entry IDs based on jmdict_id + headword
    print("  📋 Building entry ID mapping...")
    old_cursor.execute("""
        SELECT id, jmdict_id, headword
        FROM dictionary_entries
        WHERE jmdict_id IS NOT NULL
    """)
    old_id_map = {}  # old_id -> (jmdict_id, headword)
    for old_id, jmdict_id, headword in old_cursor.fetchall():
        old_id_map[old_id] = (jmdict_id, headword)

    # Get new entry IDs
    new_cursor.execute("""
        SELECT id, jmdict_id, headword
        FROM dictionary_entries
        WHERE jmdict_id IS NOT NULL
    """)
    new_id_map = {}  # (jmdict_id, headword) -> new_id
    for new_id, jmdict_id, headword in new_cursor.fetchall():
        new_id_map[(jmdict_id, headword)] = new_id

    print(f"  ℹ️  Old database: {len(old_id_map):,} entries")
    print(f"  ℹ️  New database: {len(new_id_map):,} entries")

    # Migrate example sentences
    # Note: We need to map through word_senses since examples are linked to senses
    print("  📝 Migrating example sentences...")

    # Get all example sentences from old database with their entry context
    old_cursor.execute("""
        SELECT
            es.id,
            es.sense_id,
            es.japanese_text,
            es.english_translation,
            es.example_order,
            ws.entry_id,
            ws.sense_order,
            e.jmdict_id,
            e.headword
        FROM example_sentences es
        JOIN word_senses ws ON es.sense_id = ws.id
        JOIN dictionary_entries e ON ws.entry_id = e.id
        WHERE e.jmdict_id IS NOT NULL
        ORDER BY es.id
    """)

    examples_migrated = 0
    examples_skipped = 0

    for row in old_cursor.fetchall():
        (ex_id, old_sense_id, jp_text, en_text, ex_order,
         old_entry_id, sense_order, jmdict_id, headword) = row

        # Find corresponding new entry
        new_entry_id = new_id_map.get((jmdict_id, headword))
        if not new_entry_id:
            examples_skipped += 1
            continue

        # Find corresponding new sense
        new_cursor.execute("""
            SELECT id FROM word_senses
            WHERE entry_id = ? AND sense_order = ?
        """, (new_entry_id, sense_order))

        result = new_cursor.fetchone()
        if not result:
            examples_skipped += 1
            continue

        new_sense_id = result[0]

        # Check if example already exists
        new_cursor.execute("""
            SELECT 1 FROM example_sentences
            WHERE sense_id = ? AND japanese_text = ? AND english_translation = ?
        """, (new_sense_id, jp_text, en_text))

        if new_cursor.fetchone():
            continue  # Skip duplicate

        # Insert example
        new_cursor.execute("""
            INSERT INTO example_sentences (sense_id, japanese_text, english_translation, example_order)
            VALUES (?, ?, ?, ?)
        """, (new_sense_id, jp_text, en_text, ex_order))

        examples_migrated += 1

        if examples_migrated % 1000 == 0:
            new_conn.commit()
            print(f"    Migrated {examples_migrated:,} examples...")

    new_conn.commit()

    print(f"  ✅ Migrated {examples_migrated:,} example sentences")
    print(f"  ⚠️  Skipped {examples_skipped:,} examples (entry not found in new DB)")

    # Step 4: Verify migration
    print("\n4️⃣ Verifying migration...")

    new_cursor.execute("SELECT COUNT(*) FROM example_sentences")
    new_example_count = new_cursor.fetchone()[0]

    new_cursor.execute("SELECT COUNT(*) FROM dictionary_entries WHERE jlpt_level IS NOT NULL")
    jlpt_count = new_cursor.fetchone()[0]

    new_cursor.execute("SELECT COUNT(*) FROM dictionary_entries WHERE frequency_rank IS NOT NULL")
    freq_count = new_cursor.fetchone()[0]

    print(f"  📊 New database statistics:")
    print(f"    - Example sentences: {new_example_count:,}")
    print(f"    - Entries with JLPT level: {jlpt_count:,}")
    print(f"    - Entries with frequency rank: {freq_count:,}")

    # Close connections
    old_conn.close()
    new_conn.close()

    print("\n✅ Migration completed successfully!")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python3 migrate_data_to_fixed_db.py <old_db_path> <new_db_path>")
        sys.exit(1)

    old_db = sys.argv[1]
    new_db = sys.argv[2]

    # Verify files exist
    if not Path(old_db).exists():
        print(f"Error: Old database not found: {old_db}")
        sys.exit(1)

    if not Path(new_db).exists():
        print(f"Error: New database not found: {new_db}")
        sys.exit(1)

    print("=" * 60)
    print("Database Migration Tool")
    print("=" * 60)
    print()

    migrate_data(old_db, new_db)
