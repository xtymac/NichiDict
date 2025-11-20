#!/usr/bin/env python3
"""
Import word frequency data from Japanese Wikipedia.

This script:
1. Processes Wikipedia text dumps
2. Uses MeCab for tokenization
3. Calculates word frequencies
4. Maps to dictionary entries and updates frequency_rank

Usage:
    # Process Wikipedia dump
    python3 scripts/import_wikipedia_frequency.py process wiki.txt

    # Import frequencies to database
    python3 scripts/import_wikipedia_frequency.py import frequencies.json
"""

import sqlite3
import json
import sys
import re
from pathlib import Path
from collections import Counter
from typing import Dict, Tuple, Optional

try:
    import MeCab
except ImportError:
    print("❌ MeCab not installed!")
    print("\nInstall with:")
    print("  brew install mecab")
    print("  brew install mecab-ipadic")
    print("  pip3 install mecab-python3")
    sys.exit(1)

def clean_text(text: str) -> str:
    """Remove Wikipedia markup and clean text."""
    # Remove HTML tags
    text = re.sub(r'<[^>]+>', '', text)

    # Remove Wikipedia templates {{...}}
    text = re.sub(r'\{\{[^}]*\}\}', '', text)

    # Remove Wikipedia links [[...]]
    text = re.sub(r'\[\[([^|\]]*\|)?([^\]]*)\]\]', r'\2', text)

    # Remove URLs
    text = re.sub(r'https?://[^\s]+', '', text)

    # Remove file references
    text = re.sub(r'(File|ファイル):[^\s]+', '', text)

    return text

def tokenize_with_mecab(text: str, mecab: MeCab.Tagger) -> list:
    """
    Tokenize text using MeCab and extract (surface, reading) pairs.

    Returns:
        List of (surface, reading, pos) tuples
    """
    tokens = []

    # Parse text
    node = mecab.parseToNode(text)

    while node:
        # Skip BOS/EOS markers
        if node.feature.split(',')[0] not in ['BOS/EOS']:
            surface = node.surface
            features = node.feature.split(',')

            # Get part of speech
            pos = features[0] if len(features) > 0 else ''

            # Get reading (usually in features[7])
            reading = features[7] if len(features) > 7 and features[7] != '*' else surface

            # Convert katakana reading to hiragana
            reading_hiragana = katakana_to_hiragana(reading)

            # Only include content words (nouns, verbs, adjectives, adverbs)
            if pos in ['名詞', '動詞', '形容詞', '副詞']:
                # Skip single-character particles and symbols
                if len(surface) > 1 or pos in ['動詞', '形容詞']:
                    tokens.append((surface, reading_hiragana, pos))

        node = node.next

    return tokens

def katakana_to_hiragana(text: str) -> str:
    """Convert katakana to hiragana."""
    result = []
    for char in text:
        code = ord(char)
        # Katakana range: 0x30A0-0x30FF
        # Hiragana range: 0x3040-0x309F
        if 0x30A0 <= code <= 0x30FF:
            result.append(chr(code - 0x60))
        else:
            result.append(char)
    return ''.join(result)

def process_wikipedia_dump(wiki_file: Path, output_file: Path, max_lines: Optional[int] = None):
    """
    Process Wikipedia dump and calculate word frequencies.

    Args:
        wiki_file: Path to Wikipedia text file
        output_file: Path to save frequency data (JSON)
        max_lines: Maximum number of lines to process (None = all)
    """
    print(f"📖 Processing Wikipedia dump: {wiki_file}")

    # Initialize MeCab
    try:
        mecab = MeCab.Tagger()
    except Exception as e:
        print(f"❌ Failed to initialize MeCab: {e}")
        sys.exit(1)

    # Count word occurrences
    word_counts = Counter()
    lines_processed = 0

    with open(wiki_file, 'r', encoding='utf-8') as f:
        for line in f:
            lines_processed += 1

            if max_lines and lines_processed > max_lines:
                break

            # Progress indicator
            if lines_processed % 10000 == 0:
                print(f"  Processed {lines_processed:,} lines, {len(word_counts):,} unique words")

            # Clean text
            text = clean_text(line.strip())
            if not text:
                continue

            # Tokenize
            tokens = tokenize_with_mecab(text, mecab)

            # Count (surface, reading) pairs
            for surface, reading, pos in tokens:
                key = (surface, reading)
                word_counts[key] += 1

    print(f"\n✅ Processed {lines_processed:,} lines")
    print(f"   Found {len(word_counts):,} unique words")

    # Convert to frequency ranks
    # Sort by count (descending) and assign ranks
    sorted_words = sorted(word_counts.items(), key=lambda x: x[1], reverse=True)

    # Helper function to clean strings with invalid Unicode
    def clean_string(s: str) -> str:
        """Remove surrogate characters that can't be encoded in JSON."""
        return s.encode('utf-8', errors='ignore').decode('utf-8', errors='ignore')

    frequencies = {}
    for rank, ((surface, reading), count) in enumerate(sorted_words, start=1):
        # Clean strings to avoid encoding errors
        clean_surface = clean_string(surface)
        clean_reading = clean_string(reading)

        # Skip entries with empty strings after cleaning
        if not clean_surface or not clean_reading:
            continue

        frequencies[f"{clean_surface}_{clean_reading}"] = {
            'surface': clean_surface,
            'reading': clean_reading,
            'count': count,
            'rank': rank
        }

    # Save to JSON
    print(f"\n💾 Saving frequencies to: {output_file}")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(frequencies, f, ensure_ascii=False, indent=2)

    print(f"✅ Saved {len(frequencies):,} word frequencies")

    # Show top 20
    print("\n📊 Top 20 most frequent words:")
    for i, ((surface, reading), count) in enumerate(sorted_words[:20], 1):
        print(f"  {i:2d}. {surface} ({reading}) - {count:,} occurrences")

def import_frequencies_to_database(freq_file: Path, db_path: Path, merge_strategy: str = 'min'):
    """
    Import Wikipedia frequencies to database.

    Args:
        freq_file: Path to frequencies JSON file
        db_path: Path to database
        merge_strategy: How to merge with existing JMdict frequencies
                       'min': Use minimum rank (higher priority)
                       'replace': Replace existing frequencies
                       'skip': Skip entries with existing frequencies
    """
    print(f"📊 Importing frequencies from: {freq_file}")
    print(f"   Target database: {db_path}")
    print(f"   Merge strategy: {merge_strategy}")

    # Load frequencies
    with open(freq_file, 'r', encoding='utf-8') as f:
        frequencies = json.load(f)

    print(f"   Loaded {len(frequencies):,} frequency entries")

    # Connect to database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get database statistics
    cursor.execute('SELECT COUNT(*) FROM dictionary_entries')
    total_entries = cursor.fetchone()[0]

    cursor.execute('SELECT COUNT(*) FROM dictionary_entries WHERE frequency_rank IS NOT NULL')
    existing_freq = cursor.fetchone()[0]

    print(f"\n📈 Database statistics:")
    print(f"   Total entries: {total_entries:,}")
    print(f"   Entries with frequency: {existing_freq:,} ({existing_freq*100/total_entries:.1f}%)")

    # Update frequencies
    updated = 0
    new_freq = 0
    skipped = 0
    not_found = 0

    # Convert Wikipedia ranks to our ranking system
    # Wikipedia rank 1-10000 → our rank 1001-11000 (to preserve JMdict tier 1 priority)
    # This ensures JMdict news1/ichi1 still rank highest
    WIKI_RANK_OFFSET = 1000

    for key, data in frequencies.items():
        surface = data['surface']
        reading = data['reading']
        wiki_rank = data['rank'] + WIKI_RANK_OFFSET

        # Find matching entry
        cursor.execute('''
            SELECT id, frequency_rank
            FROM dictionary_entries
            WHERE headword = ? AND reading_hiragana = ?
            LIMIT 1
        ''', (surface, reading))

        result = cursor.fetchone()

        if not result:
            not_found += 1
            continue

        entry_id, current_rank = result

        # Determine new rank based on merge strategy
        new_rank = None

        if merge_strategy == 'replace':
            new_rank = wiki_rank
        elif merge_strategy == 'skip':
            if current_rank is None:
                new_rank = wiki_rank
            else:
                skipped += 1
                continue
        elif merge_strategy == 'min':
            # Use minimum rank (higher priority)
            if current_rank is None:
                new_rank = wiki_rank
            else:
                new_rank = min(current_rank, wiki_rank)

        if new_rank is not None:
            cursor.execute('''
                UPDATE dictionary_entries
                SET frequency_rank = ?
                WHERE id = ?
            ''', (new_rank, entry_id))

            updated += 1
            if current_rank is None:
                new_freq += 1

    conn.commit()

    # Get final statistics
    cursor.execute('SELECT COUNT(*) FROM dictionary_entries WHERE frequency_rank IS NOT NULL')
    final_freq = cursor.fetchone()[0]

    conn.close()

    print(f"\n✅ Import complete!")
    print(f"   Updated entries: {updated:,}")
    print(f"   New frequencies: {new_freq:,}")
    print(f"   Skipped: {skipped:,}")
    print(f"   Not found in dict: {not_found:,}")
    print(f"\n📊 Final coverage:")
    print(f"   Entries with frequency: {final_freq:,} ({final_freq*100/total_entries:.1f}%)")
    print(f"   Improvement: +{final_freq - existing_freq:,} entries (+{(final_freq - existing_freq)*100/total_entries:.1f}%)")

def main():
    if len(sys.argv) < 3:
        print("Usage:")
        print("  # Step 1: Process Wikipedia dump")
        print("  python3 import_wikipedia_frequency.py process wiki.txt [max_lines]")
        print("")
        print("  # Step 2: Import to database")
        print("  python3 import_wikipedia_frequency.py import frequencies.json [merge_strategy]")
        print("")
        print("Merge strategies: min (default), replace, skip")
        sys.exit(1)

    command = sys.argv[1]

    if command == 'process':
        # Process Wikipedia dump
        wiki_file = Path(sys.argv[2])
        if not wiki_file.exists():
            print(f"❌ File not found: {wiki_file}")
            sys.exit(1)

        max_lines = int(sys.argv[3]) if len(sys.argv) > 3 else None
        output_file = Path('frequencies.json')

        process_wikipedia_dump(wiki_file, output_file, max_lines)

    elif command == 'import':
        # Import frequencies to database
        freq_file = Path(sys.argv[2])
        if not freq_file.exists():
            print(f"❌ File not found: {freq_file}")
            sys.exit(1)

        merge_strategy = sys.argv[3] if len(sys.argv) > 3 else 'min'

        db_path = Path(__file__).parent.parent / "NichiDict" / "Resources" / "seed.sqlite"
        if not db_path.exists():
            print(f"❌ Database not found: {db_path}")
            sys.exit(1)

        # Create backup
        backup_path = db_path.with_suffix('.sqlite.wiki_backup')
        print(f"\n💾 Creating backup: {backup_path.name}")
        import shutil
        shutil.copy2(db_path, backup_path)

        import_frequencies_to_database(freq_file, db_path, merge_strategy)

        print("\n🎯 Next steps:")
        print("  1. Rebuild FTS indexes: python3 scripts/rebuild_fts_index.py")
        print("  2. Rebuild app: xcodebuild clean build")

    else:
        print(f"❌ Unknown command: {command}")
        print("Valid commands: process, import")
        sys.exit(1)

if __name__ == '__main__':
    main()
