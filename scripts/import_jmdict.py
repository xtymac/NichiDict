#!/usr/bin/env python3
"""
Import JMdict XML data into SQLite database for NichiDict
Supports the schema defined in specs/001-offline-dictionary-search/data-model.md
"""

import sqlite3
import xml.etree.ElementTree as ET
import re
import sys
from pathlib import Path

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

def katakana_to_hiragana(text):
    """Convert katakana to hiragana"""
    return text.translate(KATAKANA_TO_HIRAGANA)

def hiragana_to_romaji(hiragana):
    """Convert hiragana to romaji (Hepburn)"""
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

def create_database_schema(db_path):
    """Create SQLite database with NichiDict schema"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Enable foreign keys
    cursor.execute('PRAGMA foreign_keys = ON')

    # Dictionary entries table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS dictionary_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            headword TEXT NOT NULL,
            reading_hiragana TEXT NOT NULL,
            reading_romaji TEXT NOT NULL,
            frequency_rank INTEGER,
            pitch_accent TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        )
    ''')

    # Word senses table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS word_senses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL,
            definition_english TEXT NOT NULL,
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

    # FTS5 virtual table for search
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

    conn.commit()
    return conn

def parse_jmdict_entry(entry_elem):
    """Parse a single JMdict entry element"""
    # Get entry sequence number
    ent_seq = entry_elem.find('ent_seq').text

    # Get kanji elements (headwords)
    k_eles = entry_elem.findall('k_ele')
    headwords = []
    for k_ele in k_eles:
        keb = k_ele.find('keb')
        if keb is not None:
            headwords.append(keb.text)

    # Get reading elements
    r_eles = entry_elem.findall('r_ele')
    readings = []
    for r_ele in r_eles:
        reb = r_ele.find('reb')
        if reb is not None:
            # Convert katakana to hiragana if needed
            reading = reb.text
            if any('\u30A0' <= c <= '\u30FF' for c in reading):
                reading = katakana_to_hiragana(reading)
            readings.append(reading)

    # Get sense elements (definitions)
    senses = []
    for sense_elem in entry_elem.findall('sense'):
        # Part of speech
        pos_list = [pos.text for pos in sense_elem.findall('pos')]
        pos = ', '.join(pos_list) if pos_list else 'unknown'

        # Glosses (English definitions)
        glosses = []
        for gloss in sense_elem.findall('gloss'):
            if gloss.get('{http://www.w3.org/XML/1998/namespace}lang', 'eng') == 'eng':
                glosses.append(gloss.text)

        if glosses:
            senses.append({
                'pos': pos,
                'glosses': glosses
            })

    # Use first headword, or first reading if no kanji
    headword = headwords[0] if headwords else readings[0]
    reading_hiragana = readings[0] if readings else headword

    return {
        'ent_seq': ent_seq,
        'headword': headword,
        'reading_hiragana': reading_hiragana,
        'senses': senses
    }

def import_jmdict(xml_path, db_path, max_entries=None):
    """Import JMdict XML into SQLite database"""
    print(f"Creating database: {db_path}")
    conn = create_database_schema(db_path)
    cursor = conn.cursor()

    print(f"Parsing XML: {xml_path}")

    # Use iterparse to handle large XML file efficiently
    context = ET.iterparse(xml_path, events=('start', 'end'))
    context = iter(context)
    event, root = next(context)

    entry_count = 0
    batch_size = 1000
    entries_batch = []

    for event, elem in context:
        if event == 'end' and elem.tag == 'entry':
            try:
                parsed = parse_jmdict_entry(elem)

                # Convert reading to romaji
                romaji = hiragana_to_romaji(parsed['reading_hiragana'])

                # Insert dictionary entry
                cursor.execute('''
                    INSERT INTO dictionary_entries (headword, reading_hiragana, reading_romaji, frequency_rank)
                    VALUES (?, ?, ?, ?)
                ''', (parsed['headword'], parsed['reading_hiragana'], romaji, None))

                entry_id = cursor.lastrowid

                # Insert senses
                for sense_order, sense in enumerate(parsed['senses'], 1):
                    definition = '; '.join(sense['glosses'])
                    cursor.execute('''
                        INSERT INTO word_senses (entry_id, definition_english, part_of_speech, sense_order)
                        VALUES (?, ?, ?, ?)
                    ''', (entry_id, definition, sense['pos'], sense_order))

                # Insert into FTS index
                cursor.execute('''
                    INSERT INTO dictionary_fts (rowid, lemma, reading_kana, reading_romaji)
                    VALUES (?, ?, ?, ?)
                ''', (entry_id, parsed['headword'], parsed['reading_hiragana'], romaji))

                entry_count += 1

                if entry_count % batch_size == 0:
                    conn.commit()
                    print(f"Imported {entry_count} entries...")

                if max_entries and entry_count >= max_entries:
                    break

            except Exception as e:
                print(f"Error parsing entry {elem.find('ent_seq').text}: {e}")

            # Clear element to free memory
            elem.clear()
            root.clear()

    # Final commit
    conn.commit()

    print(f"\nImport complete!")
    print(f"Total entries: {entry_count}")

    # Verify counts
    cursor.execute('SELECT COUNT(*) FROM dictionary_entries')
    entry_count = cursor.fetchone()[0]

    cursor.execute('SELECT COUNT(*) FROM word_senses')
    sense_count = cursor.fetchone()[0]

    cursor.execute('SELECT COUNT(*) FROM dictionary_fts')
    fts_count = cursor.fetchone()[0]

    print(f"\nDatabase statistics:")
    print(f"  Entries: {entry_count}")
    print(f"  Senses: {sense_count}")
    print(f"  FTS index: {fts_count}")

    conn.close()

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Import JMdict XML to SQLite')
    parser.add_argument('xml_file', help='Path to JMdict XML file')
    parser.add_argument('db_file', help='Output SQLite database file')
    parser.add_argument('--max-entries', type=int, help='Maximum number of entries to import (for testing)')

    args = parser.parse_args()

    import_jmdict(args.xml_file, args.db_file, args.max_entries)
