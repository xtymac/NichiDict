#!/usr/bin/env python3
"""
Import Chinese translations from Wiktionary data into the NichiDict database.

This script:
1. Reads Japanese Wiktionary data (ja-extract.jsonl.gz) from kaikki.org
2. Extracts Chinese translations for Japanese words
3. Maps them to existing JMdict entries in our database
4. Adds Chinese definitions to the word_senses table

Data source: https://kaikki.org/dictionary/Japanese/
License: CC-BY-SA 4.0 (same as Wiktionary)
"""

import gzip
import json
import sqlite3
import sys
from pathlib import Path

def normalize_text(text):
    """Normalize text for matching."""
    return text.strip().lower()

def import_chinese_translations(wiktionary_path, db_path, max_entries=None):
    """Import Chinese translations from Wiktionary into database."""

    # Connect to database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check database schema
    cursor.execute("PRAGMA table_info(word_senses)")
    columns = [col[1] for col in cursor.fetchall()]

    # Add Chinese columns if they don't exist
    if 'definition_chinese_simplified' not in columns:
        print("Adding Chinese definition columns to word_senses table...")
        cursor.execute('''
            ALTER TABLE word_senses
            ADD COLUMN definition_chinese_simplified TEXT
        ''')
        cursor.execute('''
            ALTER TABLE word_senses
            ADD COLUMN definition_chinese_traditional TEXT
        ''')
        conn.commit()

    # Build lookup index of our existing entries
    print("Building lookup index of existing entries...")
    cursor.execute('''
        SELECT id, headword, reading_hiragana
        FROM dictionary_entries
    ''')

    # Create multiple lookup strategies
    headword_to_ids = {}  # headword -> [entry_ids]
    reading_to_ids = {}   # reading -> [entry_ids]

    for entry_id, headword, reading in cursor.fetchall():
        if headword:
            headword_norm = normalize_text(headword)
            if headword_norm not in headword_to_ids:
                headword_to_ids[headword_norm] = []
            headword_to_ids[headword_norm].append(entry_id)

        if reading:
            reading_norm = normalize_text(reading)
            if reading_norm not in reading_to_ids:
                reading_to_ids[reading_norm] = []
            reading_to_ids[reading_norm].append(entry_id)

    print(f"Indexed {len(headword_to_ids)} unique headwords and {len(reading_to_ids)} unique readings")

    # Process Wiktionary data
    stats = {
        'total_wikt_entries': 0,
        'entries_with_zh': 0,
        'matched_entries': 0,
        'unmatched_entries': 0,
        'translations_added': 0,
        'senses_updated': 0
    }

    print("Processing Wiktionary data...")
    with gzip.open(wiktionary_path, 'rt', encoding='utf-8') as f:
        for i, line in enumerate(f):
            if max_entries and i >= max_entries:
                break

            if i % 10000 == 0 and i > 0:
                print(f"  Processed {i} entries, matched {stats['matched_entries']}, "
                      f"updated {stats['senses_updated']} senses...")

            entry = json.loads(line)
            stats['total_wikt_entries'] += 1

            # Skip if no translations
            if 'translations' not in entry:
                continue

            word = entry.get('word', '')
            translations = entry['translations']

            # Extract Chinese translations
            zh_translations = []
            zh_simplified = []
            zh_traditional = []

            for trans in translations:
                lang_code = trans.get('lang_code', '')
                trans_word = trans.get('word', '')

                if not trans_word:
                    continue

                if lang_code == 'zh':
                    zh_translations.append(trans_word)
                elif lang_code == 'zh-hans':
                    zh_simplified.append(trans_word)
                elif lang_code == 'zh-hant':
                    zh_traditional.append(trans_word)

            # If we have generic 'zh', treat as simplified
            if zh_translations:
                zh_simplified.extend(zh_translations)

            if not zh_simplified and not zh_traditional:
                continue

            stats['entries_with_zh'] += 1

            # Find matching entries in our database
            word_norm = normalize_text(word)
            matched_ids = set()

            if word_norm in headword_to_ids:
                matched_ids.update(headword_to_ids[word_norm])
            if word_norm in reading_to_ids:
                matched_ids.update(reading_to_ids[word_norm])

            if not matched_ids:
                stats['unmatched_entries'] += 1
                continue

            stats['matched_entries'] += 1

            # Update all matching entries' senses
            simp_text = '; '.join(zh_simplified) if zh_simplified else None
            trad_text = '; '.join(zh_traditional) if zh_traditional else None

            for entry_id in matched_ids:
                # Update all senses for this entry
                if simp_text:
                    cursor.execute('''
                        UPDATE word_senses
                        SET definition_chinese_simplified = ?
                        WHERE entry_id = ?
                        AND (definition_chinese_simplified IS NULL OR definition_chinese_simplified = '')
                    ''', (simp_text, entry_id))
                    stats['senses_updated'] += cursor.rowcount

                if trad_text:
                    cursor.execute('''
                        UPDATE word_senses
                        SET definition_chinese_traditional = ?
                        WHERE entry_id = ?
                        AND (definition_chinese_traditional IS NULL OR definition_chinese_traditional = '')
                    ''', (trad_text, entry_id))

            stats['translations_added'] += len(matched_ids)

            # Commit periodically
            if i % 1000 == 0:
                conn.commit()

    # Final commit
    conn.commit()

    # Print statistics
    print("\n=== Import Statistics ===")
    print(f"Total Wiktionary entries processed: {stats['total_wikt_entries']:,}")
    print(f"Entries with Chinese translations: {stats['entries_with_zh']:,}")
    print(f"Matched to our database: {stats['matched_entries']:,}")
    print(f"Could not match: {stats['unmatched_entries']:,}")
    print(f"Translations added: {stats['translations_added']:,}")
    print(f"Database senses updated: {stats['senses_updated']:,}")

    # Verify results
    cursor.execute('''
        SELECT COUNT(DISTINCT entry_id)
        FROM word_senses
        WHERE definition_chinese_simplified IS NOT NULL
        OR definition_chinese_traditional IS NOT NULL
    ''')
    entries_with_chinese = cursor.fetchone()[0]
    print(f"\nTotal entries now with Chinese: {entries_with_chinese:,}")

    conn.close()
    return stats

if __name__ == '__main__':
    # Paths
    data_dir = Path(__file__).parent.parent / 'data'
    wiktionary_path = data_dir / 'ja-extract.jsonl.gz'
    db_path = data_dir / 'dictionary_full.sqlite'

    # Check files exist
    if not wiktionary_path.exists():
        print(f"Error: Wiktionary data not found at {wiktionary_path}")
        print("Please download from: https://kaikki.org/dictionary/downloads/ja/ja-extract.jsonl.gz")
        sys.exit(1)

    if not db_path.exists():
        print(f"Error: Database not found at {db_path}")
        sys.exit(1)

    print("Starting Chinese translation import...")
    print(f"Wiktionary data: {wiktionary_path}")
    print(f"Database: {db_path}")
    print()

    stats = import_chinese_translations(wiktionary_path, db_path)

    print("\nImport complete!")
