#!/usr/bin/env python3
"""
Import example sentences from Tatoeba database.

Priority order:
1. Real corpus (Tatoeba) - filter difficult/unnatural sentences, prioritize short everyday sentences
2. If <1 example found, will need to auto-generate
"""

import sqlite3
import csv
import re
from collections import defaultdict
from pathlib import Path
import sys

# Configuration
TATOEBA_DIR = Path(__file__).parent.parent / "data" / "tatoeba"
DB_PATH = Path(__file__).parent.parent / "NichiDict" / "Resources" / "seed.sqlite"

# Sentence filtering criteria
MIN_LENGTH = 5      # Minimum characters (excluding spaces)
MAX_LENGTH = 50     # Maximum characters for everyday sentences
PRIORITY_MAX_LENGTH = 30  # Prioritize sentences shorter than this

class TatoebaImporter:
    def __init__(self):
        self.db = sqlite3.connect(str(DB_PATH))
        self.cursor = self.db.cursor()

        # Load Japanese sentences
        print("Loading Japanese sentences...")
        self.jpn_sentences = {}  # {id: text}
        self.load_sentences('jpn')

        # Load English sentences
        print("Loading English sentences...")
        self.eng_sentences = {}  # {id: text}
        self.load_sentences('eng')

        # Load sentence links
        print("Loading sentence links...")
        self.links = defaultdict(list)  # {jpn_id: [eng_id1, eng_id2, ...]}
        self.load_links()

        # Load dictionary entries
        print("Loading dictionary entries...")
        self.entries = self.load_dictionary_entries()

    def load_sentences(self, lang):
        """Load sentences for a specific language."""
        sentences_file = TATOEBA_DIR / "sentences.csv"
        target_dict = self.jpn_sentences if lang == 'jpn' else self.eng_sentences

        with open(sentences_file, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter='\t')
            for row in reader:
                if len(row) >= 3 and row[1] == lang:
                    sentence_id = int(row[0])
                    text = row[2].strip()
                    target_dict[sentence_id] = text

        print(f"  Loaded {len(target_dict)} {lang} sentences")

    def load_links(self):
        """Load translation links between sentences."""
        links_file = TATOEBA_DIR / "links.csv"

        with open(links_file, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter='\t')
            for row in reader:
                if len(row) >= 2:
                    id1, id2 = int(row[0]), int(row[1])

                    # Check if id1 is Japanese and id2 is English
                    if id1 in self.jpn_sentences and id2 in self.eng_sentences:
                        self.links[id1].append(id2)
                    # Check if id1 is English and id2 is Japanese
                    elif id1 in self.eng_sentences and id2 in self.jpn_sentences:
                        self.links[id2].append(id1)

        print(f"  Found {len(self.links)} Japanese sentences with English translations")

    def load_dictionary_entries(self):
        """Load all dictionary entries with their headwords and readings."""
        self.cursor.execute("""
            SELECT id, headword, reading_hiragana, jlpt_level, frequency_rank
            FROM dictionary_entries
            ORDER BY
                CASE jlpt_level
                    WHEN 'N5' THEN 1
                    WHEN 'N4' THEN 2
                    WHEN 'N3' THEN 3
                    WHEN 'N2' THEN 4
                    WHEN 'N1' THEN 5
                    ELSE 6
                END,
                CASE
                    WHEN frequency_rank IS NOT NULL AND frequency_rank > 0 THEN frequency_rank
                    ELSE 999999
                END,
                LENGTH(headword)
        """)

        entries = []
        for row in self.cursor.fetchall():
            entries.append({
                'id': row[0],
                'headword': row[1],
                'reading': row[2],
                'jlpt_level': row[3],
                'frequency_rank': row[4]
            })

        print(f"  Loaded {len(entries)} dictionary entries")
        return entries

    def filter_sentence(self, text):
        """
        Filter sentence based on quality criteria.
        Returns priority score (higher is better) or None if sentence should be rejected.
        """
        # Remove whitespace for length calculation
        text_no_space = re.sub(r'\s+', '', text)
        length = len(text_no_space)

        # Reject if too short or too long
        if length < MIN_LENGTH or length > MAX_LENGTH:
            return None

        # Reject if contains non-Japanese characters (except common punctuation)
        if not re.match(r'^[ぁ-んァ-ヶー一-龯々〆〤、。！？「」『』（）\s]+$', text):
            return None

        # Reject if sentence doesn't end with proper punctuation
        if not re.search(r'[。！？]$', text):
            return None

        # Calculate priority score
        score = 100

        # Prioritize shorter sentences
        if length <= PRIORITY_MAX_LENGTH:
            score += (PRIORITY_MAX_LENGTH - length) * 2
        else:
            score -= (length - PRIORITY_MAX_LENGTH)

        # Penalize sentences with rare kanji
        rare_kanji = re.findall(r'[㐀-䶵]', text)  # CJK Extension A and beyond
        score -= len(rare_kanji) * 10

        # Prefer sentences with common particles (natural sentence markers)
        common_particles = ['は', 'が', 'を', 'に', 'で', 'と', 'から', 'まで', 'より']
        for particle in common_particles:
            if particle in text:
                score += 5

        return score

    def extract_sentence_pattern(self, text, headword, reading):
        """
        Extract a simplified sentence pattern to detect similarity.
        Replace the target word with WORD and normalize the structure.
        """
        # Replace the headword/reading with a placeholder
        pattern = text.replace(headword, 'WORD').replace(reading, 'WORD')

        # Simplify by removing some particles but keeping sentence structure markers
        # Keep: は が を に で と た だ です ます etc.
        # This helps identify sentences like "私はWORDです" vs "WORDを食べる"

        return pattern

    def calculate_diversity_score(self, candidates):
        """
        Reorder candidates to maximize diversity.
        Penalize sentences with similar patterns.
        """
        if not candidates:
            return []

        selected = []
        remaining = candidates.copy()

        # Always take the highest scoring sentence first
        selected.append(remaining.pop(0))

        # For subsequent sentences, balance score with diversity
        while remaining and len(selected) < 3:
            best_idx = 0
            best_diversity_score = -999999

            for idx, candidate in enumerate(remaining):
                # Base score from quality
                diversity_score = candidate['score']

                # Check similarity with already selected sentences
                for selected_sent in selected:
                    similarity_penalty = self.calculate_similarity_penalty(
                        candidate['japanese'],
                        selected_sent['japanese'],
                        candidate.get('headword', ''),
                        candidate.get('reading', '')
                    )
                    diversity_score -= similarity_penalty

                if diversity_score > best_diversity_score:
                    best_diversity_score = diversity_score
                    best_idx = idx

            selected.append(remaining.pop(best_idx))

        return selected

    def calculate_similarity_penalty(self, text1, text2, headword, reading):
        """
        Calculate how similar two sentences are.
        Higher penalty = more similar.
        """
        penalty = 0

        # Extract patterns
        pattern1 = self.extract_sentence_pattern(text1, headword, reading)
        pattern2 = self.extract_sentence_pattern(text2, headword, reading)

        # If patterns are identical, heavy penalty
        if pattern1 == pattern2:
            return 1000

        # Check for similar endings (like "です。" "ます。" "だ。")
        endings = ['です。', 'ます。', 'だ。', 'ません。', 'ました。', 'でした。']
        text1_ending = None
        text2_ending = None

        for ending in endings:
            if text1.endswith(ending):
                text1_ending = ending
            if text2.endswith(ending):
                text2_ending = ending

        # If both end with same ending, add penalty
        if text1_ending and text1_ending == text2_ending:
            penalty += 50

        # Check for similar structure words
        structure_words = ['は', 'が', 'を', 'に', 'で', 'と', 'から', 'まで']
        common_structures = 0

        for word in structure_words:
            if word in text1 and word in text2:
                common_structures += 1

        # More common structures = more similar
        if common_structures >= 3:
            penalty += 30

        # Check if both sentences start similarly (first 2-3 characters)
        if len(text1) >= 3 and len(text2) >= 3:
            # Extract first non-word part
            start1 = text1.replace(headword, '').replace(reading, '')[:3]
            start2 = text2.replace(headword, '').replace(reading, '')[:3]
            if start1 == start2 and start1:
                penalty += 40

        return penalty

    def find_examples_for_entry(self, entry):
        """Find suitable example sentences for a dictionary entry."""
        headword = entry['headword']
        reading = entry['reading']

        candidates = []

        # Search for sentences containing the headword or reading
        for jpn_id, jpn_text in self.jpn_sentences.items():
            # Skip if no English translation
            if jpn_id not in self.links:
                continue

            # Check if sentence contains the word
            if headword not in jpn_text and reading not in jpn_text:
                continue

            # Filter sentence
            score = self.filter_sentence(jpn_text)
            if score is None:
                continue

            # Get English translation (use the first one)
            eng_id = self.links[jpn_id][0]
            eng_text = self.eng_sentences.get(eng_id, '')

            if not eng_text:
                continue

            candidates.append({
                'japanese': jpn_text,
                'english': eng_text,
                'score': score,
                'headword': headword,
                'reading': reading
            })

        # Sort by score first
        candidates.sort(key=lambda x: x['score'], reverse=True)

        # Apply diversity scoring to select best diverse examples
        diverse_examples = self.calculate_diversity_score(candidates)

        # Remove headword/reading from result (not needed in DB)
        for ex in diverse_examples:
            ex.pop('headword', None)
            ex.pop('reading', None)

        return diverse_examples

    def import_examples(self, max_entries=None):
        """Import examples for all dictionary entries."""

        # Get all word senses
        self.cursor.execute("""
            SELECT id, entry_id
            FROM word_senses
            ORDER BY entry_id, sense_order
        """)
        senses = {row[1]: row[0] for row in self.cursor.fetchall()}  # {entry_id: first_sense_id}

        entries_to_process = self.entries[:max_entries] if max_entries else self.entries

        total_examples = 0
        entries_with_examples = 0

        for i, entry in enumerate(entries_to_process, 1):
            entry_id = entry['id']

            # Get first sense_id for this entry
            sense_id = senses.get(entry_id)
            if not sense_id:
                continue

            # Find examples
            examples = self.find_examples_for_entry(entry)

            if examples:
                # Insert examples
                for order, example in enumerate(examples, 1):
                    self.cursor.execute("""
                        INSERT INTO example_sentences
                        (sense_id, japanese_text, english_translation, example_order)
                        VALUES (?, ?, ?, ?)
                    """, (sense_id, example['japanese'], example['english'], order))
                    total_examples += 1

                entries_with_examples += 1

            # Progress update
            if i % 1000 == 0:
                print(f"  Processed {i}/{len(entries_to_process)} entries, "
                      f"{entries_with_examples} with examples, "
                      f"{total_examples} total examples")
                self.db.commit()

        # Final commit
        self.db.commit()

        print(f"\nImport complete!")
        print(f"  Total entries processed: {len(entries_to_process)}")
        print(f"  Entries with examples: {entries_with_examples}")
        print(f"  Total examples imported: {total_examples}")
        print(f"  Coverage: {entries_with_examples / len(entries_to_process) * 100:.1f}%")

    def close(self):
        """Close database connection."""
        self.db.close()

def main():
    """Main entry point."""
    print("=" * 60)
    print("Tatoeba Example Sentence Importer")
    print("=" * 60)
    print()

    # Parse command line arguments
    max_entries = None
    if len(sys.argv) > 1:
        try:
            max_entries = int(sys.argv[1])
            print(f"Processing first {max_entries} entries only (test mode)")
        except ValueError:
            print(f"Invalid number: {sys.argv[1]}")
            sys.exit(1)

    try:
        importer = TatoebaImporter()
        importer.import_examples(max_entries=max_entries)
        importer.close()
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
