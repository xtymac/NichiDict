#!/usr/bin/env python3
"""
Import word frequency data from JMdict XML file.

JMdict contains frequency priority markers:
- news1, news2: Appears in Mainichi Shimbun
- ichi1, ichi2: Appears in Ichimango goi bunruishuu
- spec1, spec2: Common words not covered by other markers
- gai1, gai2: Common loanwords
- nf01-nf48: Frequency ranking

This script extracts these markers and converts them to a numerical frequency_rank.

Usage:
    python3 scripts/import_frequency_data.py path/to/JMdict_e.xml
"""

import sqlite3
import xml.etree.ElementTree as ET
import sys
from pathlib import Path
from typing import Dict, Set, Optional

# Frequency priority to rank mapping
# Lower rank = higher frequency
PRIORITY_RANKS = {
    # Tier 1: Most common words (1-1000)
    'news1': 1,
    'ichi1': 1,
    'spec1': 1,
    'gai1': 1,

    # Tier 2: Common words (1001-5000)
    'news2': 2,
    'ichi2': 2,
    'spec2': 2,
    'gai2': 2,

    # Tier 3: nf01-nf24 (5001-20000)
    **{f'nf{i:02d}': 3 for i in range(1, 25)},

    # Tier 4: nf25-nf48 (20001+)
    **{f'nf{i:02d}': 4 for i in range(25, 49)},
}

def calculate_frequency_rank(priorities: Set[str]) -> Optional[int]:
    """
    Calculate a single frequency rank from multiple priority markers.

    Lower rank number = higher frequency (more common).

    Args:
        priorities: Set of priority markers from JMdict (e.g., {'news1', 'ichi1', 'nf01'})

    Returns:
        Integer rank (1-100000) or None if no priority markers
    """
    if not priorities:
        return None

    # Find the best (lowest) tier
    best_tier = min((PRIORITY_RANKS.get(p, 999) for p in priorities), default=None)

    if best_tier is None:
        return None

    # Convert tier to rank
    # Tier 1: rank 1-1000
    # Tier 2: rank 1001-5000
    # Tier 3: rank 5001-20000
    # Tier 4: rank 20001-50000

    tier_bases = {
        1: 1,
        2: 1001,
        3: 5001,
        4: 20001,
    }

    base_rank = tier_bases.get(best_tier, 50001)

    # Add some variation based on specific markers within tier
    offset = 0
    if 'news1' in priorities:
        offset = 0
    elif 'ichi1' in priorities:
        offset = 100
    elif 'spec1' in priorities:
        offset = 200
    elif 'gai1' in priorities:
        offset = 300
    elif 'news2' in priorities:
        offset = 0
    elif 'ichi2' in priorities:
        offset = 500

    # Extract nf numbers for more precise ranking
    nf_nums = []
    for p in priorities:
        if p.startswith('nf'):
            try:
                num = int(p[2:])
                nf_nums.append(num)
            except ValueError:
                pass

    if nf_nums:
        offset = min(nf_nums) * 100

    return min(base_rank + offset, 100000)

def extract_frequencies_from_jmdict(xml_path: Path) -> Dict[int, int]:
    """
    Extract frequency data from JMdict XML file.

    Returns:
        Dictionary mapping jmdict_id to frequency_rank
    """
    print(f"🔍 Parsing JMdict XML: {xml_path}")

    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except Exception as e:
        print(f"❌ Error parsing XML: {e}")
        sys.exit(1)

    frequencies = {}
    entries_with_freq = 0
    total_entries = 0

    for entry in root.findall('entry'):
        total_entries += 1

        # Get JMdict entry ID
        ent_seq = entry.find('ent_seq')
        if ent_seq is None:
            continue

        jmdict_id = int(ent_seq.text)

        # Collect all priority markers from all k_ele (kanji) and r_ele (reading)
        priorities = set()

        # Get priorities from kanji elements
        for k_ele in entry.findall('k_ele'):
            for ke_pri in k_ele.findall('ke_pri'):
                if ke_pri.text:
                    priorities.add(ke_pri.text)

        # Get priorities from reading elements
        for r_ele in entry.findall('r_ele'):
            for re_pri in r_ele.findall('re_pri'):
                if re_pri.text:
                    priorities.add(re_pri.text)

        # Calculate frequency rank
        if priorities:
            rank = calculate_frequency_rank(priorities)
            if rank is not None:
                frequencies[jmdict_id] = rank
                entries_with_freq += 1

        # Progress indicator
        if total_entries % 10000 == 0:
            print(f"  Processed {total_entries} entries, {entries_with_freq} with frequency data")

    print(f"✅ Found frequency data for {entries_with_freq}/{total_entries} entries")
    return frequencies

def update_database(db_path: Path, frequencies: Dict[int, int]):
    """
    Update frequency_rank in the database based on jmdict_id.
    """
    print(f"\n📊 Updating database: {db_path}")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Update entries with frequency data
    updated = 0
    for jmdict_id, rank in frequencies.items():
        cursor.execute('''
            UPDATE dictionary_entries
            SET frequency_rank = ?
            WHERE jmdict_id = ?
        ''', (rank, jmdict_id))
        updated += cursor.rowcount

    conn.commit()

    # Verify update
    cursor.execute('SELECT COUNT(*) FROM dictionary_entries WHERE frequency_rank IS NOT NULL')
    total_with_freq = cursor.fetchone()[0]

    cursor.execute('SELECT COUNT(*) FROM dictionary_entries')
    total_entries = cursor.fetchone()[0]

    conn.close()

    print(f"✅ Updated {updated} entries")
    print(f"📈 Database now has frequency data for {total_with_freq}/{total_entries} entries")
    print(f"   ({total_with_freq * 100.0 / total_entries:.1f}% coverage)")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 import_frequency_data.py path/to/JMdict_e.xml")
        print("\nDownload JMdict from:")
        print("  http://www.edrdg.org/jmdict/edict_doc.html")
        sys.exit(1)

    xml_path = Path(sys.argv[1])
    if not xml_path.exists():
        print(f"❌ File not found: {xml_path}")
        sys.exit(1)

    # Default database path
    db_path = Path(__file__).parent.parent / "NichiDict" / "Resources" / "seed.sqlite"
    if not db_path.exists():
        print(f"❌ Database not found: {db_path}")
        print("Please specify database path as second argument:")
        print("  python3 import_frequency_data.py JMdict_e.xml path/to/seed.sqlite")
        sys.exit(1)

    print("=" * 60)
    print("JMdict Frequency Data Import")
    print("=" * 60)

    # Extract frequencies from XML
    frequencies = extract_frequencies_from_jmdict(xml_path)

    if not frequencies:
        print("⚠️ No frequency data found in XML file")
        sys.exit(1)

    # Update database
    update_database(db_path, frequencies)

    print("\n✅ Frequency import complete!")
    print("\nNext steps:")
    print("  1. Rebuild your app to use the updated database")
    print("  2. Test search results to verify frequency ranking")

if __name__ == '__main__':
    main()
