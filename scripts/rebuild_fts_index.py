#!/usr/bin/env python3
"""
Rebuild FTS (Full-Text Search) indexes after database modifications.

After deduplication or other database changes, the FTS indexes may be out of sync
with the main tables. This script rebuilds all FTS indexes to ensure consistency.

Usage:
    python3 scripts/rebuild_fts_index.py [path/to/seed.sqlite]
"""

import sqlite3
import sys
from pathlib import Path

def check_sync_status(conn):
    """Check if FTS indexes are in sync with main tables."""
    cursor = conn.cursor()

    # Check dictionary_fts sync
    cursor.execute('SELECT COUNT(*) FROM dictionary_entries')
    entries_count = cursor.fetchone()[0]

    cursor.execute('SELECT COUNT(*) FROM dictionary_fts')
    fts_count = cursor.fetchone()[0]

    print(f"\n📊 Current Status:")
    print(f"   dictionary_entries: {entries_count:,} rows")
    print(f"   dictionary_fts:     {fts_count:,} rows")

    if entries_count == fts_count:
        print("   ✅ Indexes are in sync")
        return True
    else:
        diff = fts_count - entries_count
        print(f"   ⚠️  Out of sync by {diff:,} rows")
        return False

def rebuild_dictionary_fts(conn):
    """Rebuild the dictionary_fts index."""
    print("\n🔨 Rebuilding dictionary_fts index...")
    cursor = conn.cursor()

    # Drop existing FTS table
    print("   Dropping old FTS table...")
    cursor.execute('DROP TABLE IF EXISTS dictionary_fts')

    # Recreate FTS table
    print("   Creating new FTS table...")
    cursor.execute('''
        CREATE VIRTUAL TABLE dictionary_fts USING fts5(
            headword,
            reading_hiragana,
            reading_romaji,
            content='dictionary_entries',
            content_rowid='id'
        )
    ''')

    # Populate FTS table
    print("   Populating FTS index...")
    cursor.execute('''
        INSERT INTO dictionary_fts(rowid, headword, reading_hiragana, reading_romaji)
        SELECT id, headword, reading_hiragana, reading_romaji
        FROM dictionary_entries
    ''')

    rows = cursor.rowcount
    print(f"   ✅ Indexed {rows:,} entries")

    conn.commit()

def rebuild_reverse_search_fts(conn):
    """Rebuild the reverse_search_fts index (English/Chinese → Japanese)."""
    print("\n🔨 Rebuilding reverse_search_fts index...")
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute('''
        SELECT COUNT(*) FROM sqlite_master
        WHERE type='table' AND name='reverse_search_fts'
    ''')

    if cursor.fetchone()[0] == 0:
        print("   ⚠️  reverse_search_fts does not exist, skipping")
        return

    # Drop existing FTS table
    print("   Dropping old FTS table...")
    cursor.execute('DROP TABLE IF EXISTS reverse_search_fts')

    # Recreate FTS table
    print("   Creating new FTS table...")
    cursor.execute('''
        CREATE VIRTUAL TABLE reverse_search_fts USING fts5(
            definition_english,
            definition_chinese_simplified,
            definition_chinese_traditional,
            entry_id UNINDEXED
        )
    ''')

    # Populate FTS table from word_senses
    print("   Populating FTS index...")
    cursor.execute('''
        INSERT INTO reverse_search_fts(definition_english, definition_chinese_simplified, definition_chinese_traditional, entry_id)
        SELECT definition_english, definition_chinese_simplified, definition_chinese_traditional, entry_id
        FROM word_senses
        WHERE entry_id IN (SELECT id FROM dictionary_entries)
    ''')

    rows = cursor.rowcount
    print(f"   ✅ Indexed {rows:,} senses")

    conn.commit()

def optimize_indexes(conn):
    """Optimize FTS indexes for better performance."""
    print("\n⚡ Optimizing FTS indexes...")
    cursor = conn.cursor()

    try:
        cursor.execute("INSERT INTO dictionary_fts(dictionary_fts) VALUES('optimize')")
        print("   ✅ Optimized dictionary_fts")
    except Exception as e:
        print(f"   ⚠️  Could not optimize dictionary_fts: {e}")

    try:
        cursor.execute("INSERT INTO reverse_search_fts(reverse_search_fts) VALUES('optimize')")
        print("   ✅ Optimized reverse_search_fts")
    except Exception as e:
        print(f"   ⚠️  Could not optimize reverse_search_fts: {e}")

    conn.commit()

def vacuum_database(conn):
    """Vacuum the database to reclaim space."""
    print("\n🧹 Vacuuming database...")

    # Get size before
    cursor = conn.cursor()
    cursor.execute("SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
    size_before = cursor.fetchone()[0]

    conn.execute('VACUUM')

    # Get size after
    cursor.execute("SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
    size_after = cursor.fetchone()[0]

    saved = size_before - size_after
    print(f"   Before: {size_before / 1024 / 1024:.2f} MB")
    print(f"   After:  {size_after / 1024 / 1024:.2f} MB")
    if saved > 0:
        print(f"   Saved:  {saved / 1024 / 1024:.2f} MB")

def main():
    # Parse arguments
    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1])
    else:
        db_path = Path(__file__).parent.parent / "NichiDict" / "Resources" / "seed.sqlite"

    if not db_path.exists():
        print(f"❌ Database not found: {db_path}")
        print("\nUsage:")
        print("  python3 rebuild_fts_index.py [path/to/seed.sqlite]")
        sys.exit(1)

    print("=" * 60)
    print("FTS Index Rebuild")
    print("=" * 60)

    # Create backup
    backup_path = db_path.with_suffix('.sqlite.fts_backup')
    print(f"\n💾 Creating backup: {backup_path.name}")
    import shutil
    shutil.copy2(db_path, backup_path)
    print(f"   Backup saved")

    # Connect to database
    conn = sqlite3.connect(db_path)

    try:
        # Check current sync status
        is_synced = check_sync_status(conn)

        if is_synced:
            print("\n✅ FTS indexes are already in sync!")
            response = input("\nRebuild anyway? (yes/no): ")
            if response.lower() not in ['yes', 'y']:
                print("❌ Cancelled")
                return

        # Rebuild indexes
        rebuild_dictionary_fts(conn)
        rebuild_reverse_search_fts(conn)

        # Optimize
        optimize_indexes(conn)

        # Final verification
        print("\n" + "=" * 60)
        print("Verification")
        print("=" * 60)
        check_sync_status(conn)

        # Vacuum
        vacuum_database(conn)

        print("\n" + "=" * 60)
        print("✅ FTS Index Rebuild Complete!")
        print("=" * 60)
        print("\nNext steps:")
        print("  1. Restart your app")
        print("  2. Try searching to verify everything works")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        print(f"\nYou can restore from backup:")
        print(f"  cp '{backup_path}' '{db_path}'")
        sys.exit(1)
    finally:
        conn.close()

if __name__ == '__main__':
    main()
