#!/usr/bin/env python3
"""
Enhanced JMdict import script with variant type support.

This script imports JMdict XML and properly handles variant kanji forms:
- Parses ke_inf tags to determine variant_type (rK, oK, sK, etc.)
- Detects uk (usually kana) from sense misc tags
- Creates separate entries for each kanji variant
- Creates pure kana entries for uk-tagged words

Usage:
    python scripts/import_jmdict_with_variants.py [xml_path] [db_path] [max_entries]

Defaults:
    xml_path: data/JMdict_e
    db_path: data/dictionary_full_multilingual.sqlite
"""

import sqlite3
import sys
import unicodedata
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import xml.etree.ElementTree as ET


# Valid variant types
VALID_VARIANT_TYPES = ['primary', 'uk', 'rK', 'oK', 'sK', 'iK', 'io', 'ateji']


def katakana_to_hiragana(text: str) -> str:
    """Convert katakana to hiragana."""
    result = []
    for char in text:
        code = ord(char)
        if 0x30A0 <= code <= 0x30FF:  # Katakana range
            result.append(chr(code - 0x60))  # Convert to hiragana
        else:
            result.append(char)
    return ''.join(result)


def hiragana_to_romaji(text: str) -> str:
    """Convert hiragana to romaji (simplified)."""
    romaji_map = {
        'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
        'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
        'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
        'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
        'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
        'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
        'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
        'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
        'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
        'わ': 'wa', 'を': 'wo', 'ん': 'n',
        'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
        'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
        'だ': 'da', 'ぢ': 'di', 'づ': 'du', 'で': 'de', 'ど': 'do',
        'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
        'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
        'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
        'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
        'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
        'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
        'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
        'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
        'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
        'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
        'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
        'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
        'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
        'っ': '', 'ー': '-', 'ゃ': 'ya', 'ゅ': 'yu', 'ょ': 'yo',
    }

    result = []
    i = 0
    while i < len(text):
        # Try two-character combinations first
        if i + 1 < len(text):
            combo = text[i:i+2]
            if combo in romaji_map:
                # Handle small tsu (っ) before consonant
                if result and result[-1] == '' and combo in romaji_map:
                    consonant = romaji_map[combo][0] if romaji_map[combo] else ''
                    result[-1] = consonant
                result.append(romaji_map[combo])
                i += 2
                continue

        # Single character
        char = text[i]
        if char in romaji_map:
            result.append(romaji_map[char])
        else:
            result.append(char)
        i += 1

    return ''.join(result)


def parse_ke_inf_variant_type(ke_inf_texts: List[str]) -> Optional[str]:
    """
    Determine variant_type from ke_inf tags.
    Uses English description matching (simple and direct approach).

    Returns: 'rK', 'oK', 'sK', 'iK', 'io', 'ateji', or None
    """
    for text in ke_inf_texts:
        text_lower = text.lower() if text else ''
        if 'rarely used kanji' in text_lower or 'rarely-used kanji' in text_lower:
            return 'rK'
        if 'out-dated kanji' in text_lower or 'outdated kanji' in text_lower:
            return 'oK'
        if 'search-only' in text_lower:
            return 'sK'
        if 'irregular kanji' in text_lower:
            return 'iK'
        if 'irregular okurigana' in text_lower:
            return 'io'
        if 'ateji' in text_lower:
            return 'ateji'
    return None


def has_uk_tag(sense_elems) -> bool:
    """Check if any sense has uk (usually kana) tag."""
    for sense_elem in sense_elems:
        misc_elems = sense_elem.findall('misc')
        for elem in misc_elems:
            if elem.text and 'usually written using kana' in elem.text.lower():
                return True
    return False


def parse_jmdict_entry_with_variants(entry_elem) -> List[Dict]:
    """
    Parse a single JMdict entry, returning multiple entries for each variant.

    For an entry with kanji variants (e.g., きっと with 屹度, 急度):
    - Returns one entry per kanji variant (each with variant_type)
    - If uk tag present, also returns a pure kana entry (variant_type='uk')
    """
    try:
        # Get entry sequence number (JMdict ID)
        ent_seq_elem = entry_elem.find('ent_seq')
        if ent_seq_elem is None:
            return []
        jmdict_id = int(ent_seq_elem.text)

        # Get reading elements (hiragana)
        r_eles = entry_elem.findall('r_ele')
        readings = []
        for r_ele in r_eles:
            reb = r_ele.find('reb')
            if reb is not None and reb.text:
                reading = reb.text
                # Convert katakana to hiragana if needed
                if any('\u30A0' <= c <= '\u30FF' for c in reading):
                    reading = katakana_to_hiragana(reading)
                readings.append(reading)

        if not readings:
            return []

        reading_hiragana = readings[0]

        # Get sense elements (definitions)
        sense_elems = entry_elem.findall('sense')
        senses = []

        for sense_elem in sense_elems:
            # Check for misc tags that indicate non-modern/specialized terms
            misc_elems = sense_elem.findall('misc')
            misc_tags = [elem.text for elem in misc_elems if elem.text]

            # Skip senses with archaic/obsolete markers
            skip_markers = ['archaic', 'obsolete term', 'obscure term', 'rare', 'dated term']
            should_skip = any(
                any(marker in tag.lower() for marker in skip_markers)
                for tag in misc_tags
            )
            if should_skip:
                continue

            # Part of speech
            pos_elems = sense_elem.findall('pos')
            pos_list = [elem.text for elem in pos_elems if elem.text]
            pos = '; '.join(pos_list) if pos_list else 'unknown'

            # English glosses
            glosses_eng = []
            for gloss in sense_elem.findall('gloss'):
                lang = gloss.get('{http://www.w3.org/XML/1998/namespace}lang', 'eng')
                if lang == 'eng' and gloss.text:
                    glosses_eng.append(gloss.text)

            # Chinese glosses (simplified and traditional)
            glosses_chi_simp = []
            glosses_chi_trad = []
            for gloss in sense_elem.findall('gloss'):
                lang = gloss.get('{http://www.w3.org/XML/1998/namespace}lang')
                if gloss.text:
                    if lang == 'chi':
                        glosses_chi_simp.append(gloss.text)
                    elif lang == 'chi-Hant':
                        glosses_chi_trad.append(gloss.text)

            if not glosses_eng:
                continue

            senses.append({
                'pos': pos,
                'glosses_eng': glosses_eng,
                'glosses_chi_simp': glosses_chi_simp,
                'glosses_chi_trad': glosses_chi_trad
            })

        if not senses:
            return []

        # Check for uk (usually kana) tag
        is_uk = has_uk_tag(sense_elems)

        # Collect all entries
        entries = []
        has_primary = False

        # Get kanji elements
        k_eles = entry_elem.findall('k_ele')

        # Process each kanji element as a separate entry
        for k_ele in k_eles:
            keb = k_ele.find('keb')
            if keb is None or not keb.text:
                continue

            headword = keb.text

            # Get ke_inf tags for variant type
            ke_inf_elems = k_ele.findall('ke_inf')
            ke_inf_texts = [elem.text for elem in ke_inf_elems if elem.text]

            # Determine variant type
            variant_type = parse_ke_inf_variant_type(ke_inf_texts)

            # Check for priority markers (common words)
            priorities = [ke_pri.text for ke_pri in k_ele.findall('ke_pri')]

            # If no special variant type, determine based on priority markers
            if variant_type is None:
                variant_type = 'primary'
                has_primary = True

            entries.append({
                'jmdict_id': jmdict_id,
                'headword': headword,
                'reading_hiragana': reading_hiragana,
                'variant_type': variant_type,
                'senses': senses
            })

        # If has uk tag, create a pure kana entry (most preferred form)
        if is_uk:
            # Check if pure kana entry already exists
            pure_kana_exists = any(
                e['headword'] == reading_hiragana
                for e in entries
            )
            if not pure_kana_exists:
                entries.append({
                    'jmdict_id': jmdict_id,
                    'headword': reading_hiragana,  # Pure kana
                    'reading_hiragana': reading_hiragana,
                    'variant_type': 'uk',
                    'senses': senses
                })

        # If no kanji elements and no uk entry, create a basic entry
        if not entries:
            entries.append({
                'jmdict_id': jmdict_id,
                'headword': reading_hiragana,
                'reading_hiragana': reading_hiragana,
                'variant_type': 'primary',
                'senses': senses
            })

        return entries

    except Exception as e:
        print(f"  Error parsing entry: {e}")
        return []


def import_jmdict_with_variants(xml_path: str, db_path: str, max_entries: Optional[int] = None):
    """
    Import JMdict XML with full variant support.

    Uses transaction and clears table to ensure idempotency.
    """
    print(f"\n{'='*60}")
    print(f"JMdict Import with Variant Support")
    print(f"{'='*60}")
    print(f"Source: {xml_path}")
    print(f"Target: {db_path}")
    print()

    conn = sqlite3.connect(db_path)
    conn.execute('PRAGMA foreign_keys = ON')
    cursor = conn.cursor()

    try:
        print("Starting transaction...")
        conn.execute('BEGIN TRANSACTION')

        # Clear existing data (cascade deletes word_senses)
        print("Clearing existing data...")
        cursor.execute('DELETE FROM dictionary_fts')
        cursor.execute('DELETE FROM word_senses')
        cursor.execute('DELETE FROM dictionary_entries')
        cursor.execute("DELETE FROM sqlite_sequence WHERE name='dictionary_entries'")
        cursor.execute("DELETE FROM sqlite_sequence WHERE name='word_senses'")

        print(f"Parsing XML: {xml_path}")

        # Statistics
        stats = {
            'entries': 0,
            'senses': 0,
            'variants': {'primary': 0, 'uk': 0, 'rK': 0, 'oK': 0, 'sK': 0, 'iK': 0, 'io': 0, 'ateji': 0, 'None': 0}
        }

        # Use iterparse to handle large XML file efficiently
        context = ET.iterparse(xml_path, events=('start', 'end'))
        context = iter(context)
        event, root = next(context)

        batch_size = 1000
        jmdict_entry_count = 0

        for event, elem in context:
            if event == 'end' and elem.tag == 'entry':
                jmdict_entry_count += 1
                parsed_entries = parse_jmdict_entry_with_variants(elem)

                for parsed in parsed_entries:
                    try:
                        # Convert reading to romaji
                        romaji = hiragana_to_romaji(parsed['reading_hiragana'])
                        variant_type = parsed.get('variant_type')

                        # Insert dictionary entry with variant_type
                        cursor.execute('''
                            INSERT INTO dictionary_entries (
                                headword, reading_hiragana, reading_romaji,
                                jmdict_id, frequency_rank, variant_type
                            ) VALUES (?, ?, ?, ?, ?, ?)
                        ''', (
                            parsed['headword'],
                            parsed['reading_hiragana'],
                            romaji,
                            parsed['jmdict_id'],
                            None,  # frequency_rank
                            variant_type
                        ))

                        entry_id = cursor.lastrowid

                        # Insert senses
                        for sense_order, sense in enumerate(parsed['senses'], 1):
                            definition_eng = '; '.join(sense['glosses_eng'])
                            definition_chi_simp = '; '.join(sense['glosses_chi_simp']) if sense['glosses_chi_simp'] else None
                            definition_chi_trad = '; '.join(sense['glosses_chi_trad']) if sense['glosses_chi_trad'] else None

                            cursor.execute('''
                                INSERT INTO word_senses (
                                    entry_id, definition_english,
                                    definition_chinese_simplified,
                                    definition_chinese_traditional,
                                    part_of_speech, sense_order
                                ) VALUES (?, ?, ?, ?, ?, ?)
                            ''', (entry_id, definition_eng, definition_chi_simp, definition_chi_trad, sense['pos'], sense_order))

                            stats['senses'] += 1

                        # Insert into FTS index
                        cursor.execute('''
                            INSERT INTO dictionary_fts (rowid, lemma, reading_kana, reading_romaji)
                            VALUES (?, ?, ?, ?)
                        ''', (entry_id, parsed['headword'], parsed['reading_hiragana'], romaji))

                        stats['entries'] += 1
                        stats['variants'][variant_type or 'None'] += 1

                        if stats['entries'] % batch_size == 0:
                            print(f"  Imported {stats['entries']} entries from {jmdict_entry_count} JMdict entries...")

                    except Exception as e:
                        print(f"  Error inserting entry: {e}")

                # Clear processed element to save memory
                elem.clear()
                root.clear()

                if max_entries and stats['entries'] >= max_entries:
                    print(f"  Reached max_entries limit: {max_entries}")
                    break

        # Commit transaction
        print("\nCommitting transaction...")
        conn.commit()

        print(f"\n{'='*60}")
        print(f"Import completed successfully!")
        print(f"{'='*60}")
        print(f"\nStatistics:")
        print(f"  JMdict entries processed: {jmdict_entry_count}")
        print(f"  Dictionary entries created: {stats['entries']}")
        print(f"  Word senses created: {stats['senses']}")
        print(f"\nVariant type distribution:")
        for vtype, count in sorted(stats['variants'].items()):
            if count > 0:
                print(f"  {vtype}: {count}")

    except Exception as e:
        print(f"\nERROR: Import failed: {e}")
        print("Rolling back transaction...")
        conn.rollback()
        raise
    finally:
        conn.close()


def verify_import(db_path: str):
    """Verify the import results."""
    print(f"\n{'='*60}")
    print(f"Verifying import: {db_path}")
    print(f"{'='*60}")

    conn = sqlite3.connect(db_path)

    # Total counts
    cursor = conn.execute("SELECT COUNT(*) FROM dictionary_entries")
    total_entries = cursor.fetchone()[0]
    print(f"\nTotal dictionary entries: {total_entries}")

    cursor = conn.execute("SELECT COUNT(*) FROM word_senses")
    total_senses = cursor.fetchone()[0]
    print(f"Total word senses: {total_senses}")

    # Variant type distribution
    print("\nVariant type distribution:")
    cursor = conn.execute("""
        SELECT COALESCE(variant_type, 'NULL') as vtype, COUNT(*) as count
        FROM dictionary_entries
        GROUP BY variant_type
        ORDER BY count DESC
    """)
    for row in cursor.fetchall():
        print(f"  {row[0]}: {row[1]}")

    # Sample entries for each variant type
    print("\nSample entries by variant type:")
    for vtype in ['uk', 'rK', 'oK', 'primary']:
        if vtype == 'primary':
            cursor = conn.execute("""
                SELECT headword, reading_hiragana, variant_type
                FROM dictionary_entries
                WHERE variant_type = 'primary' OR variant_type IS NULL
                LIMIT 3
            """)
        else:
            cursor = conn.execute("""
                SELECT headword, reading_hiragana, variant_type
                FROM dictionary_entries
                WHERE variant_type = ?
                LIMIT 3
            """, (vtype,))

        samples = cursor.fetchall()
        if samples:
            print(f"\n  {vtype}:")
            for s in samples:
                print(f"    {s[0]} ({s[1]})")

    conn.close()


if __name__ == '__main__':
    # Default paths
    project_root = Path(__file__).parent.parent
    default_xml = project_root / 'data' / 'JMdict_e'
    default_db = project_root / 'data' / 'dictionary_full_multilingual.sqlite'

    xml_path = sys.argv[1] if len(sys.argv) > 1 else str(default_xml)
    db_path = sys.argv[2] if len(sys.argv) > 2 else str(default_db)
    max_entries = int(sys.argv[3]) if len(sys.argv) > 3 else None

    if not Path(xml_path).exists():
        print(f"ERROR: XML file not found: {xml_path}")
        sys.exit(1)

    if not Path(db_path).exists():
        print(f"ERROR: Database not found: {db_path}")
        print("Please run migration script first: python scripts/migrate_add_variant_type.py")
        sys.exit(1)

    import_jmdict_with_variants(xml_path, db_path, max_entries)
    verify_import(db_path)
