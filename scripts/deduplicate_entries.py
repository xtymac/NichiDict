#!/usr/bin/env python3
"""
Remove duplicate dictionary entries from the database.

The database currently has duplicate entries where the same word (same headword + reading)
appears twice with the same jmdict_id. This script keeps the entry with the lower id
(created earlier) and removes duplicates.

Usage:
    python3 scripts/deduplicate_entries.py [path/to/seed.sqlite]
"""

import sqlite3
import sys
from pathlib import Path
from typing import Dict, List, Tuple

def find_duplicates(db_path: Path) -> List[Tuple[str, str, int, List[int]]]:
    """
    Find duplicate entries in the database.

    Returns:
        List of (headword, reading, jmdict_id, [duplicate_ids])
    """
    print(f"🔍 Analyzing database: {db_path}")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Find entries that appear more than once with same headword, reading, and jmdict_id
    cursor.execute('''
        SELECT headword, reading_hiragana, jmdict_id, GROUP_CONCAT(id) as ids, COUNT(*) as count
        FROM dictionary_entries
        GROUP BY headword, reading_hiragana, jmdict_id
        HAVING count > 1
        ORDER BY count DESC, headword
    ''')

    duplicates = []
    total_duplicate_entries = 0

    for row in cursor.fetchall():
        headword, reading, jmdict_id, ids_str, count = row
        ids = [int(x) for x in ids_str.split(',')]
        duplicates.append((headword, reading, jmdict_id, ids))
        total_duplicate_entries += count - 1  # -1 because we keep one

    conn.close()

    print(f"📊 Found {len(duplicates)} unique words with duplicates")
    print(f"   Total duplicate entries to remove: {total_duplicate_entries}")

    return duplicates

def remove_duplicates(db_path: Path, duplicates: List[Tuple[str, str, int, List[int]]], dry_run: bool = False):
    """
    Remove duplicate entries, keeping the one with the lowest id.

    Args:
        db_path: Path to database
        duplicates: List of duplicate entries
        dry_run: If True, only show what would be deleted without actually deleting
    """
    if not duplicates:
        print("✅ No duplicates found!")
        return

    if dry_run:
        print("\n🔍 DRY RUN - No changes will be made")
    else:
        print("\n🗑️  Removing duplicate entries...")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    removed_count = 0

    for headword, reading, jmdict_id, ids in duplicates:
        # Keep the entry with the lowest id (oldest entry)
        keep_id = min(ids)
        remove_ids = [x for x in ids if x != keep_id]

        if dry_run:
            print(f"  Would remove: {headword} ({reading}) - IDs {remove_ids} (keep {keep_id})")
        else:
            # Remove duplicates
            placeholders = ','.join(['?' for _ in remove_ids])
            cursor.execute(f'''
                DELETE FROM dictionary_entries
                WHERE id IN ({placeholders})
            ''', remove_ids)

            removed_count += len(remove_ids)

            if removed_count % 1000 == 0:
                print(f"  Removed {removed_count} entries...")

    if not dry_run:
        conn.commit()
        print(f"\n✅ Removed {removed_count} duplicate entries")

        # Verify results
        cursor.execute('SELECT COUNT(*) FROM dictionary_entries')
        total_after = cursor.fetchone()[0]

        cursor.execute('''
            SELECT COUNT(*)
            FROM (
                SELECT headword, reading_hiragana, jmdict_id, COUNT(*) as count
                FROM dictionary_entries
                GROUP BY headword, reading_hiragana, jmdict_id
                HAVING count > 1
            )
        ''')
        remaining_duplicates = cursor.fetchone()[0]

        print(f"📊 Database now has {total_after} entries")
        print(f"   Remaining duplicates: {remaining_duplicates}")

    conn.close()

def vacuum_database(db_path: Path):
    """
    Vacuum the database to reclaim space after deletions.
    """
    print("\n🧹 Vacuuming database to reclaim space...")

    conn = sqlite3.connect(db_path)

    # Get size before
    cursor = conn.cursor()
    cursor.execute("SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
    size_before = cursor.fetchone()[0]

    # Vacuum
    conn.execute('VACUUM')

    # Get size after
    cursor.execute("SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
    size_after = cursor.fetchone()[0]

    conn.close()

    saved = size_before - size_after
    print(f"✅ Database compacted")
    print(f"   Before: {size_before / 1024 / 1024:.2f} MB")
    print(f"   After:  {size_after / 1024 / 1024:.2f} MB")
    print(f"   Saved:  {saved / 1024 / 1024:.2f} MB")

def main():
    # Parse arguments
    dry_run = '--dry-run' in sys.argv

    # Default database path
    if len(sys.argv) > 1 and not sys.argv[1].startswith('--'):
        db_path = Path(sys.argv[1])
    else:
        db_path = Path(__file__).parent.parent / "NichiDict" / "Resources" / "seed.sqlite"

    if not db_path.exists():
        print(f"❌ Database not found: {db_path}")
        print("\nUsage:")
        print("  python3 deduplicate_entries.py [path/to/seed.sqlite] [--dry-run]")
        sys.exit(1)

    print("=" * 60)
    print("Dictionary Entry Deduplication")
    print("=" * 60)

    # Create backup
    if not dry_run:
        backup_path = db_path.with_suffix('.sqlite.backup')
        print(f"\n💾 Creating backup: {backup_path.name}")
        import shutil
        shutil.copy2(db_path, backup_path)
        print(f"   Backup saved (restore with: cp {backup_path} {db_path})")

    # Find duplicates
    duplicates = find_duplicates(db_path)

    if not duplicates:
        print("\n✅ No duplicates found! Database is clean.")
        return

    # Show examples
    print("\n📋 Sample duplicates:")
    for i, (headword, reading, jmdict_id, ids) in enumerate(duplicates[:5]):
        print(f"  {i+1}. {headword} ({reading}) - {len(ids)} copies (IDs: {ids})")

    if len(duplicates) > 5:
        print(f"  ... and {len(duplicates) - 5} more")

    # Remove duplicates
    if dry_run:
        remove_duplicates(db_path, duplicates, dry_run=True)
        print("\n💡 Run without --dry-run to actually remove duplicates")
    else:
        print("\n⚠️  This will permanently delete duplicate entries!")
        response = input("Continue? (yes/no): ")

        if response.lower() in ['yes', 'y']:
            remove_duplicates(db_path, duplicates, dry_run=False)
            vacuum_database(db_path)
            print("\n✅ Deduplication complete!")
        else:
            print("❌ Cancelled")

if __name__ == '__main__':
    main()
