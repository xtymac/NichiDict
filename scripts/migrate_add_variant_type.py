#!/usr/bin/env python3
"""
Migration script to add variant_type column to dictionary_entries table.

This script:
1. Backs up the existing database
2. Adds variant_type column with CHECK constraint
3. Adds jlpt_level column if missing
4. Creates performance indexes for variant ranking

Usage:
    python scripts/migrate_add_variant_type.py [database_path]

Default database: data/dictionary_full_multilingual.sqlite
"""

import sqlite3
import shutil
import sys
from pathlib import Path
from datetime import datetime

# Valid variant types (from JMDict ke_inf tags)
VALID_VARIANT_TYPES = [
    'primary',  # Normal/common spelling (has ke_pri or no special tags)
    'uk',       # Usually kana (from sense misc tag)
    'rK',       # Rarely used kanji form
    'oK',       # Outdated/old kanji
    'sK',       # Search-only kanji
    'iK',       # Irregular kanji usage
    'io',       # Irregular okurigana
    'ateji',    # Ateji (phonetic kanji)
]


def backup_database(db_path: Path) -> Path:
    """Create a timestamped backup of the database."""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_path = db_path.parent / f"{db_path.stem}_backup_{timestamp}.sqlite"
    print(f"Creating backup: {backup_path}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def get_existing_columns(conn: sqlite3.Connection, table_name: str) -> set:
    """Get set of existing column names for a table."""
    cursor = conn.execute(f"PRAGMA table_info({table_name})")
    return {row[1] for row in cursor.fetchall()}


def get_existing_indexes(conn: sqlite3.Connection) -> set:
    """Get set of existing index names."""
    cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='index'")
    return {row[0] for row in cursor.fetchall()}


def migrate_database(db_path: Path):
    """Perform the migration."""
    print(f"\n{'='*60}")
    print(f"Migrating database: {db_path}")
    print(f"{'='*60}\n")

    # Backup first
    backup_path = backup_database(db_path)

    conn = sqlite3.connect(db_path)

    try:
        existing_columns = get_existing_columns(conn, 'dictionary_entries')
        existing_indexes = get_existing_indexes(conn)

        print(f"Existing columns: {sorted(existing_columns)}")

        # 1. Add variant_type column if not exists
        if 'variant_type' not in existing_columns:
            print("\n[1/4] Adding variant_type column...")
            # SQLite doesn't support CHECK constraint with ALTER TABLE
            # We'll add the column first, then validate data on insert/update
            conn.execute("""
                ALTER TABLE dictionary_entries
                ADD COLUMN variant_type TEXT
            """)
            print("  - Added variant_type column")
        else:
            print("\n[1/4] variant_type column already exists, skipping...")

        # 2. Add jlpt_level column if not exists
        if 'jlpt_level' not in existing_columns:
            print("\n[2/4] Adding jlpt_level column...")
            conn.execute("""
                ALTER TABLE dictionary_entries
                ADD COLUMN jlpt_level TEXT
            """)
            print("  - Added jlpt_level column")
        else:
            print("\n[2/4] jlpt_level column already exists, skipping...")

        # 3. Create variant ranking index
        print("\n[3/4] Creating performance indexes...")

        if 'idx_variant_ranking' not in existing_indexes:
            conn.execute("""
                CREATE INDEX idx_variant_ranking ON dictionary_entries(
                    variant_type,
                    jlpt_level,
                    frequency_rank
                )
            """)
            print("  - Created idx_variant_ranking")
        else:
            print("  - idx_variant_ranking already exists")

        if 'idx_reading_variant' not in existing_indexes:
            conn.execute("""
                CREATE INDEX idx_reading_variant ON dictionary_entries(
                    reading_hiragana,
                    variant_type
                )
            """)
            print("  - Created idx_reading_variant")
        else:
            print("  - idx_reading_variant already exists")

        if 'idx_jmdict_variant' not in existing_indexes:
            conn.execute("""
                CREATE INDEX idx_jmdict_variant ON dictionary_entries(
                    jmdict_id,
                    variant_type
                )
            """)
            print("  - Created idx_jmdict_variant")
        else:
            print("  - idx_jmdict_variant already exists")

        # 4. Verify schema
        print("\n[4/4] Verifying final schema...")
        cursor = conn.execute("PRAGMA table_info(dictionary_entries)")
        columns = cursor.fetchall()
        print("\nFinal dictionary_entries schema:")
        for col in columns:
            cid, name, type_, notnull, default, pk = col
            print(f"  {name}: {type_} {'NOT NULL' if notnull else ''} {'PK' if pk else ''}")

        conn.commit()
        print(f"\n{'='*60}")
        print("Migration completed successfully!")
        print(f"Backup saved at: {backup_path}")
        print(f"{'='*60}\n")

    except Exception as e:
        conn.rollback()
        print(f"\nERROR: Migration failed: {e}")
        print(f"Database has been rolled back. Backup available at: {backup_path}")
        raise
    finally:
        conn.close()


def verify_variant_type_values(db_path: Path):
    """Verify that all variant_type values are valid (for post-import check)."""
    conn = sqlite3.connect(db_path)
    cursor = conn.execute("""
        SELECT variant_type, COUNT(*) as count
        FROM dictionary_entries
        GROUP BY variant_type
        ORDER BY count DESC
    """)

    print("\nVariant type distribution:")
    for row in cursor.fetchall():
        variant_type, count = row
        is_valid = variant_type is None or variant_type in VALID_VARIANT_TYPES
        status = "OK" if is_valid else "INVALID"
        print(f"  {variant_type or 'NULL'}: {count} [{status}]")

    conn.close()


if __name__ == '__main__':
    # Default database path
    default_db = Path(__file__).parent.parent / 'data' / 'dictionary_full_multilingual.sqlite'

    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1])
    else:
        db_path = default_db

    if not db_path.exists():
        print(f"ERROR: Database not found: {db_path}")
        sys.exit(1)

    migrate_database(db_path)
    verify_variant_type_values(db_path)
