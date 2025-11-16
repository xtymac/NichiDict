#!/usr/bin/env python3
"""
Enhanced JMdict import with full multilingual support.

This script imports JMdict XML data with:
- Japanese headwords (kanji + hiragana + romaji)
- Part of speech (Japanese grammar tags)
- Multilingual glosses (English, Simplified Chinese, Traditional Chinese, etc.)
- Example sentences (Japanese-focused)

Single-direction: Japanese → Translations (not reverse dictionary)

Data source: JMdict (EDRDG)
License: CC-BY-SA 4.0
"""

import sqlite3
import xml.etree.ElementTree as ET
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Romaji conversion tables (Hepburn)
HIRAGANA_TO_ROMAJI = {
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
    'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
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
    'っ': '', 'ー': '-'
}

KATAKANA_TO_HIRAGANA = str.maketrans(
    'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲンガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポ',
    'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんがぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽ'
)

# Part of speech mappings (JMdict entity codes to readable labels)
POS_MAPPINGS = {
    '&adj-f;': '形容詞',
    '&adj-i;': 'い形容詞',
    '&adj-ix;': 'い形容詞（特殊）',
    '&adj-kari;': 'かり形容詞',
    '&adj-ku;': 'く形容詞',
    '&adj-na;': 'な形容詞',
    '&adj-nari;': 'なり形容詞',
    '&adj-no;': 'の形容詞',
    '&adj-pn;': '連体詞',
    '&adj-shiku;': 'しく形容詞',
    '&adj-t;': 'たる形容詞',
    '&adv;': '副詞',
    '&adv-to;': '副詞（と）',
    '&aux;': '助動詞',
    '&aux-adj;': '助動詞形容詞',
    '&aux-v;': '助動詞動詞',
    '&conj;': '接続詞',
    '&cop;': 'コピュラ',
    '&ctr;': '助数詞',
    '&exp;': '表現',
    '&int;': '感動詞',
    '&n;': '名詞',
    '&n-adv;': '副詞的名詞',
    '&n-pr;': '固有名詞',
    '&n-pref;': '名詞接頭辞',
    '&n-suf;': '名詞接尾辞',
    '&n-t;': '時を表す名詞',
    '&num;': '数詞',
    '&pn;': '代名詞',
    '&pref;': '接頭辞',
    '&prt;': '助詞',
    '&suf;': '接尾辞',
    '&unc;': '不明',
    '&v1;': '一段動詞',
    '&v1-s;': '一段動詞（特殊）',
    '&v2a-s;': '二段動詞（あ）',
    '&v2b-k;': '二段動詞（ば）',
    '&v2b-s;': '二段動詞（ば特殊）',
    '&v2d-k;': '二段動詞（だ）',
    '&v2d-s;': '二段動詞（だ特殊）',
    '&v2g-k;': '二段動詞（が）',
    '&v2g-s;': '二段動詞（が特殊）',
    '&v2h-k;': '二段動詞（は）',
    '&v2h-s;': '二段動詞（は特殊）',
    '&v2k-k;': '二段動詞（か）',
    '&v2k-s;': '二段動詞（か特殊）',
    '&v2m-k;': '二段動詞（ま）',
    '&v2m-s;': '二段動詞（ま特殊）',
    '&v2n-s;': '二段動詞（な）',
    '&v2r-k;': '二段動詞（ら）',
    '&v2r-s;': '二段動詞（ら特殊）',
    '&v2s-s;': '二段動詞（さ）',
    '&v2t-k;': '二段動詞（た）',
    '&v2t-s;': '二段動詞（た特殊）',
    '&v2w-s;': '二段動詞（わ）',
    '&v2y-k;': '二段動詞（や）',
    '&v2y-s;': '二段動詞（や特殊）',
    '&v2z-s;': '二段動詞（ざ）',
    '&v4b;': '四段動詞（ば）',
    '&v4g;': '四段動詞（が）',
    '&v4h;': '四段動詞（は）',
    '&v4k;': '四段動詞（か）',
    '&v4m;': '四段動詞（ま）',
    '&v4n;': '四段動詞（な）',
    '&v4r;': '四段動詞（ら）',
    '&v4s;': '四段動詞（さ）',
    '&v4t;': '四段動詞（た）',
    '&v5aru;': '五段動詞（ある特殊）',
    '&v5b;': '五段動詞（ば）',
    '&v5g;': '五段動詞（が）',
    '&v5k;': '五段動詞（か）',
    '&v5k-s;': '五段動詞（か特殊）',
    '&v5m;': '五段動詞（ま）',
    '&v5n;': '五段動詞（な）',
    '&v5r;': '五段動詞（ら）',
    '&v5r-i;': '五段動詞（ら特殊）',
    '&v5s;': '五段動詞（さ）',
    '&v5t;': '五段動詞（た）',
    '&v5u;': '五段動詞（わ）',
    '&v5u-s;': '五段動詞（わ特殊）',
    '&v5uru;': '五段動詞（うる）',
    '&vi;': '自動詞',
    '&vk;': 'カ行変格動詞',
    '&vn;': 'ナ行変格動詞',
    '&vr;': 'ラ行変格動詞',
    '&vs;': 'サ行変格動詞',
    '&vs-c;': 'サ行変格動詞（特殊）',
    '&vs-i;': 'サ行変格動詞（する）',
    '&vs-s;': 'サ行変格動詞（する特殊）',
    '&vt;': '他動詞',
    '&vz;': 'ザ行変格動詞',
}

def katakana_to_hiragana(text: str) -> str:
    """Convert katakana to hiragana."""
    return text.translate(KATAKANA_TO_HIRAGANA)

def hiragana_to_romaji(hiragana: str) -> str:
    """Convert hiragana to romaji (Hepburn)."""
    result = []
    i = 0
    while i < len(hiragana):
        # Try two-character combinations first
        if i < len(hiragana) - 1:
            two_char = hiragana[i:i+2]
            if two_char in HIRAGANA_TO_ROMAJI:
                result.append(HIRAGANA_TO_ROMAJI[two_char])
                i += 2
                continue

        # Single character
        char = hiragana[i]
        if char in HIRAGANA_TO_ROMAJI:
            result.append(HIRAGANA_TO_ROMAJI[char])
        else:
            result.append(char)
        i += 1

    return ''.join(result)

def simplify_pos(pos_entity: str) -> str:
    """Convert POS entity code to readable label."""
    return POS_MAPPINGS.get(pos_entity, pos_entity)

def create_database_schema(db_path: str) -> sqlite3.Connection:
    """Create SQLite database with enhanced multilingual schema."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Enable foreign keys
    cursor.execute('PRAGMA foreign_keys = ON')

    # Dictionary entries table (Japanese words)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS dictionary_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            headword TEXT NOT NULL,
            reading_hiragana TEXT NOT NULL,
            reading_romaji TEXT NOT NULL,
            frequency_rank INTEGER,
            pitch_accent TEXT,
            jmdict_id INTEGER,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        )
    ''')

    # Word senses table (definitions in multiple languages)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS word_senses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL,
            definition_english TEXT NOT NULL,
            definition_chinese_simplified TEXT,
            definition_chinese_traditional TEXT,
            part_of_speech TEXT NOT NULL,
            usage_notes TEXT,
            sense_order INTEGER NOT NULL,
            FOREIGN KEY (entry_id) REFERENCES dictionary_entries(id) ON DELETE CASCADE
        )
    ''')

    # Example sentences table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS example_sentences (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sense_id INTEGER NOT NULL,
            japanese_text TEXT NOT NULL,
            english_translation TEXT NOT NULL,
            example_order INTEGER NOT NULL,
            FOREIGN KEY (sense_id) REFERENCES word_senses(id) ON DELETE CASCADE
        )
    ''')

    # FTS5 virtual table for fast search
    cursor.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS dictionary_fts USING fts5(
            lemma,
            reading_kana,
            reading_romaji,
            tokenize='unicode61 remove_diacritics 0'
        )
    ''')

    # Indexes
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_entry_id ON word_senses(entry_id, sense_order)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_sense_id ON example_sentences(sense_id, example_order)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_frequency_rank ON dictionary_entries(frequency_rank)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_jmdict_id ON dictionary_entries(jmdict_id)')

    conn.commit()
    return conn

def parse_jmdict_entry(entry_elem) -> Optional[Dict]:
    """Parse a single JMdict entry with multilingual support."""
    try:
        # Get entry sequence number (JMdict ID)
        ent_seq_elem = entry_elem.find('ent_seq')
        if ent_seq_elem is None:
            return None
        jmdict_id = int(ent_seq_elem.text)

        # Get kanji elements (headwords) - filter out variant-only forms
        k_eles = entry_elem.findall('k_ele')
        headwords = []
        for k_ele in k_eles:
            keb = k_ele.find('keb')
            if keb is not None and keb.text:
                # Check for variant kanji markers that should be filtered out
                # XML parser expands entities to their full text
                ke_inf_elems = k_ele.findall('ke_inf')
                ke_inf_texts = [elem.text for elem in ke_inf_elems if elem.text]

                # Filter out search-only, rare, and old kanji variants
                is_variant_only = any(
                    'search-only kanji form' in text or
                    'rarely-used kanji form' in text or
                    'old or irregular kanji form' in text
                    for text in ke_inf_texts
                )

                # Check if this kanji has priority markers (common words)
                priorities = [ke_pri.text for ke_pri in k_ele.findall('ke_pri')]

                # Include if: has priority markers OR is not a variant-only form
                # This ensures common words are always included, and rare variants are excluded
                if priorities or not is_variant_only:
                    headwords.append(keb.text)

        # Get reading elements
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
            return None

        # Get sense elements (definitions)
        senses = []
        for sense_elem in entry_elem.findall('sense'):
            # Check for misc tags that indicate non-modern/specialized terms
            # Filter out: archaic, obsolete, rare, obscure terms
            misc_elems = sense_elem.findall('misc')
            misc_tags = [elem.text for elem in misc_elems if elem.text]

            # Skip senses with these markers (XML parser expands entities)
            skip_markers = [
                'archaic',           # &arch; - 古語、廃語
                'obsolete term',     # &obs; - 廃語
                'obscure term',      # &obsc; - 罕用語
                'rare',              # &rare; - 稀用語
                'dated term',        # &dated; - 時代遅れ
            ]

            should_skip = any(
                any(marker in tag for marker in skip_markers)
                for tag in misc_tags
            )

            if should_skip:
                continue  # Skip this sense

            # Part of speech
            pos_list = [pos.text for pos in sense_elem.findall('pos')]
            # Simplify POS tags
            pos_simplified = [simplify_pos(p) for p in pos_list]
            pos = '、'.join(pos_simplified) if pos_simplified else '不明'

            # Extract glosses by language
            glosses_eng = []
            glosses_chi_simp = []
            glosses_chi_trad = []

            for gloss in sense_elem.findall('gloss'):
                gloss_text = gloss.text
                if not gloss_text:
                    continue

                # Get language attribute
                lang = gloss.get('{http://www.w3.org/XML/1998/namespace}lang', 'eng')

                if lang == 'eng':
                    glosses_eng.append(gloss_text)
                elif lang == 'chi':
                    # Generic Chinese - treat as simplified
                    glosses_chi_simp.append(gloss_text)
                elif lang == 'zh-Hans' or lang == 'zhs':
                    glosses_chi_simp.append(gloss_text)
                elif lang == 'zh-Hant' or lang == 'zht':
                    glosses_chi_trad.append(gloss_text)

            # Require at least English definition
            if not glosses_eng:
                continue

            senses.append({
                'pos': pos,
                'glosses_eng': glosses_eng,
                'glosses_chi_simp': glosses_chi_simp,
                'glosses_chi_trad': glosses_chi_trad
            })

        if not senses:
            return None

        # Use first headword, or first reading if no kanji
        headword = headwords[0] if headwords else readings[0]
        reading_hiragana = readings[0]

        return {
            'jmdict_id': jmdict_id,
            'headword': headword,
            'reading_hiragana': reading_hiragana,
            'senses': senses
        }
    except Exception as e:
        print(f"  Error parsing entry: {e}")
        return None

def import_jmdict_multilingual(xml_path: str, db_path: str, max_entries: Optional[int] = None):
    """Import JMdict XML with full multilingual support."""
    print(f"Creating database: {db_path}")
    conn = create_database_schema(db_path)
    cursor = conn.cursor()

    print(f"Parsing XML: {xml_path}")

    # Use iterparse to handle large XML file efficiently
    context = ET.iterparse(xml_path, events=('start', 'end'))
    context = iter(context)
    event, root = next(context)

    entry_count = 0
    sense_count = 0
    chi_simp_count = 0
    chi_trad_count = 0
    batch_size = 1000

    for event, elem in context:
        if event == 'end' and elem.tag == 'entry':
            parsed = parse_jmdict_entry(elem)

            if parsed:
                try:
                    # Convert reading to romaji
                    romaji = hiragana_to_romaji(parsed['reading_hiragana'])

                    # Insert dictionary entry
                    cursor.execute('''
                        INSERT INTO dictionary_entries (headword, reading_hiragana, reading_romaji, jmdict_id, frequency_rank)
                        VALUES (?, ?, ?, ?, ?)
                    ''', (parsed['headword'], parsed['reading_hiragana'], romaji, parsed['jmdict_id'], None))

                    entry_id = cursor.lastrowid

                    # Insert senses
                    for sense_order, sense in enumerate(parsed['senses'], 1):
                        definition_eng = '; '.join(sense['glosses_eng'])
                        definition_chi_simp = '; '.join(sense['glosses_chi_simp']) if sense['glosses_chi_simp'] else None
                        definition_chi_trad = '; '.join(sense['glosses_chi_trad']) if sense['glosses_chi_trad'] else None

                        cursor.execute('''
                            INSERT INTO word_senses (
                                entry_id,
                                definition_english,
                                definition_chinese_simplified,
                                definition_chinese_traditional,
                                part_of_speech,
                                sense_order
                            ) VALUES (?, ?, ?, ?, ?, ?)
                        ''', (entry_id, definition_eng, definition_chi_simp, definition_chi_trad, sense['pos'], sense_order))

                        sense_count += 1
                        if definition_chi_simp:
                            chi_simp_count += 1
                        if definition_chi_trad:
                            chi_trad_count += 1

                    # Insert into FTS index
                    cursor.execute('''
                        INSERT INTO dictionary_fts (rowid, lemma, reading_kana, reading_romaji)
                        VALUES (?, ?, ?, ?)
                    ''', (entry_id, parsed['headword'], parsed['reading_hiragana'], romaji))

                    entry_count += 1

                    if entry_count % batch_size == 0:
                        conn.commit()
                        print(f"Imported {entry_count} entries, {sense_count} senses "
                              f"(CN-simp: {chi_simp_count}, CN-trad: {chi_trad_count})...")

                    if max_entries and entry_count >= max_entries:
                        break

                except Exception as e:
                    print(f"  Error inserting entry {parsed.get('jmdict_id')}: {e}")

            # Clear element to free memory
            elem.clear()
            root.clear()

    # Final commit
    conn.commit()

    print(f"\n=== Import Complete ===")
    print(f"Total entries: {entry_count:,}")
    print(f"Total senses: {sense_count:,}")
    print(f"Senses with Chinese (Simplified): {chi_simp_count:,}")
    print(f"Senses with Chinese (Traditional): {chi_trad_count:,}")

    # Verify counts
    cursor.execute('SELECT COUNT(*) FROM dictionary_entries')
    db_entry_count = cursor.fetchone()[0]

    cursor.execute('SELECT COUNT(*) FROM word_senses')
    db_sense_count = cursor.fetchone()[0]

    cursor.execute('SELECT COUNT(*) FROM dictionary_fts')
    fts_count = cursor.fetchone()[0]

    cursor.execute('''
        SELECT COUNT(DISTINCT entry_id)
        FROM word_senses
        WHERE definition_chinese_simplified IS NOT NULL
    ''')
    entries_with_simp = cursor.fetchone()[0]

    cursor.execute('''
        SELECT COUNT(DISTINCT entry_id)
        FROM word_senses
        WHERE definition_chinese_traditional IS NOT NULL
    ''')
    entries_with_trad = cursor.fetchone()[0]

    print(f"\n=== Database Statistics ===")
    print(f"Dictionary entries: {db_entry_count:,}")
    print(f"Word senses: {db_sense_count:,}")
    print(f"FTS index: {fts_count:,}")
    print(f"Entries with Simplified Chinese: {entries_with_simp:,} ({entries_with_simp/db_entry_count*100:.2f}%)")
    print(f"Entries with Traditional Chinese: {entries_with_trad:,} ({entries_with_trad/db_entry_count*100:.2f}%)")

    conn.close()

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Import JMdict XML to SQLite with multilingual support')
    parser.add_argument('xml_file', help='Path to JMdict XML file')
    parser.add_argument('db_file', help='Output SQLite database file')
    parser.add_argument('--max-entries', type=int, help='Maximum number of entries to import (for testing)')

    args = parser.parse_args()

    # Verify input file exists
    xml_path = Path(args.xml_file)
    if not xml_path.exists():
        print(f"Error: XML file not found: {xml_path}")
        sys.exit(1)

    print("=" * 60)
    print("JMdict Multilingual Import")
    print("=" * 60)
    print(f"Source: {args.xml_file}")
    print(f"Target: {args.db_file}")
    if args.max_entries:
        print(f"Limit: {args.max_entries} entries")
    print()

    import_jmdict_multilingual(args.xml_file, args.db_file, args.max_entries)

    print("\n✅ Import completed successfully!")
