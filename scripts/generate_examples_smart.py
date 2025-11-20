#!/usr/bin/env python3
"""
Smart Example Generation Script (OpenAI GPT-4o-mini)
- Checks existing offline examples before generation
- Ensures generated examples don't duplicate offline examples
- Adds variety and diversity to existing examples
"""

import sqlite3
import os
import sys
import time
import json
import re
from typing import List, Tuple, Dict
from openai import OpenAI

# OpenAI API Configuration
API_KEY = os.environ.get('OPENAI_API_KEY')
if not API_KEY:
    print("❌ Error: Please set OPENAI_API_KEY environment variable")
    sys.exit(1)
MODEL_NAME = "gpt-4o-mini"

# Database path
DB_PATH = "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite"

# Processing parameters
BATCH_SIZE = 20  # Process N words per batch
EXAMPLES_PER_WORD = 3  # Generate 3 examples per word
DELAY_BETWEEN_BATCHES = 0.5  # Delay between batches (seconds)
MAX_EXAMPLES_TOTAL = 5  # Maximum total examples per word (offline + generated)

def init_openai():
    """Initialize OpenAI API"""
    client = OpenAI(api_key=API_KEY)
    return client

def get_existing_examples(db_path: str, sense_id: int) -> List[str]:
    """Get existing example sentences for a sense"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT japanese_text
        FROM example_sentences
        WHERE sense_id = ?
        ORDER BY example_order
    """, (sense_id,))

    examples = [row[0] for row in cursor.fetchall()]
    conn.close()

    return examples

def calculate_similarity(text1: str, text2: str) -> float:
    """
    Calculate similarity between two sentences (0-1).
    Uses simple pattern matching.
    """
    # Normalize
    t1 = re.sub(r'\s+', '', text1)
    t2 = re.sub(r'\s+', '', text2)

    # If identical, return 1.0
    if t1 == t2:
        return 1.0

    # Check common substrings
    max_len = max(len(t1), len(t2))
    if max_len == 0:
        return 0.0

    # Simple similarity: count matching characters
    matches = sum(1 for a, b in zip(t1, t2) if a == b)
    similarity = matches / max_len

    # Also check for common patterns
    # If both end with same pattern, increase similarity
    common_endings = ['です。', 'ます。', 'だ。', 'ません。', 'ました。']
    for ending in common_endings:
        if text1.endswith(ending) and text2.endswith(ending):
            similarity += 0.2
            break

    return min(1.0, similarity)

def is_duplicate(new_sentence: str, existing_sentences: List[str], threshold: float = 0.7) -> bool:
    """Check if a new sentence is too similar to existing ones"""
    for existing in existing_sentences:
        if calculate_similarity(new_sentence, existing) >= threshold:
            return True
    return False

def get_words_for_generation(db_path: str, limit: int) -> List[Tuple]:
    """
    Get words that need more examples.
    Prioritize words with few or no examples.
    Returns: [(entry_id, headword, reading_hiragana, reading_romaji, sense_id, definition_english, existing_count), ...]
    """
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get words ordered by JLPT level and example count
    cursor.execute(f"""
        SELECT DISTINCT
            d.id as entry_id,
            d.headword,
            d.reading_hiragana,
            d.reading_romaji,
            s.id as sense_id,
            s.definition_english,
            COALESCE(s.definition_chinese_simplified, s.definition_chinese_traditional, '') as definition_chinese,
            COUNT(e.id) as example_count
        FROM dictionary_entries d
        JOIN word_senses s ON d.id = s.entry_id
        LEFT JOIN example_sentences e ON s.id = e.sense_id
        WHERE d.jlpt_level IS NOT NULL AND d.jlpt_level != ''
        GROUP BY s.id
        HAVING example_count < {MAX_EXAMPLES_TOTAL}
        ORDER BY
            CASE d.jlpt_level
                WHEN 'N5' THEN 1
                WHEN 'N4' THEN 2
                WHEN 'N3' THEN 3
                WHEN 'N2' THEN 4
                WHEN 'N1' THEN 5
                ELSE 6
            END,
            example_count ASC,
            CASE
                WHEN d.frequency_rank IS NOT NULL AND d.frequency_rank > 0 THEN d.frequency_rank
                ELSE 999999
            END
        LIMIT {limit}
    """)

    words = cursor.fetchall()
    conn.close()

    return words

def generate_examples_for_word(client, word: Tuple, existing_examples: List[str]) -> Tuple[int, List[Dict]]:
    """
    Generate example sentences for a word, avoiding duplication with existing examples.
    Returns: (sense_id, [example1, example2, example3])
    """
    entry_id, headword, reading_hiragana, reading_romaji, sense_id, def_en, def_cn, existing_count = word

    # Calculate how many examples to generate
    examples_needed = min(EXAMPLES_PER_WORD, MAX_EXAMPLES_TOTAL - existing_count)

    if examples_needed <= 0:
        return (sense_id, [])

    # Build prompt with existing examples context
    existing_context = ""
    if existing_examples:
        existing_context = f"""
IMPORTANT: The following example sentences ALREADY EXIST for this word.
You MUST generate DIFFERENT examples with DIFFERENT sentence patterns:
{chr(10).join(f'- {ex}' for ex in existing_examples)}

Requirements for NEW examples:
- Use DIFFERENT grammar structures than the existing examples
- Use DIFFERENT verb forms, particles, and sentence endings
- Cover DIFFERENT usage scenarios
- Must be clearly distinguishable from existing examples
"""

    prompt = f"""Generate {examples_needed} natural Japanese example sentences for this word.

Word: {headword}
Reading: {reading_hiragana} ({reading_romaji})
Meaning: {def_en}
{f'中文: {def_cn}' if def_cn else ''}

{existing_context}

General Requirements:
1. Generate {examples_needed} natural Japanese sentences (15-35 characters each)
2. Each sentence must demonstrate typical usage in daily life
3. Keep sentences simple and practical
4. Include the word '{headword}' or its conjugated form
5. Ensure variety in grammar patterns (declarative, question, negative, past tense, etc.)

Return ONLY a JSON object with this schema:
{{"examples":[
  {{"japanese":"...", "english":"..."}},
  {{"japanese":"...", "english":"..."}}
]}}

Respond with JSON only."""

    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": "You are a Japanese language expert. Generate natural, diverse example sentences that don't duplicate existing patterns."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.8,  # Higher temperature for more variety
            max_tokens=500
        )

        response_text = response.choices[0].message.content.strip()

        # Clean markdown code blocks
        if response_text.startswith("```json"):
            response_text = response_text[7:]
        if response_text.startswith("```"):
            response_text = response_text[3:]
        if response_text.endswith("```"):
            response_text = response_text[:-3]
        response_text = response_text.strip()

        # Parse JSON
        data = json.loads(response_text)
        examples = data.get("examples", [])

        # Filter out duplicates
        filtered_examples = []
        for example in examples:
            japanese = example.get("japanese", "")
            if japanese and not is_duplicate(japanese, existing_examples):
                filtered_examples.append(example)
            else:
                print(f"      ⚠️  Filtered duplicate: {japanese[:30]}...")

        return (sense_id, filtered_examples)

    except Exception as e:
        print(f"    ❌ {headword} generation failed: {str(e)[:100]}")
        return (sense_id, [])

def generate_examples_for_batch(client, db_path: str, words: List[Tuple]) -> Dict[int, List[Dict]]:
    """
    Generate examples for a batch of words
    Returns: {sense_id: [example1, example2, example3], ...}
    """
    if not words:
        return {}

    results = {}

    for word in words:
        _, headword, reading_hiragana, _, sense_id, _, _, existing_count = word

        # Get existing examples
        existing_examples = get_existing_examples(db_path, sense_id)

        sense_id, examples = generate_examples_for_word(client, word, existing_examples)

        if examples:
            results[sense_id] = examples
            print(f"    ✅ {headword} ({reading_hiragana}): {len(examples)} new examples (had {existing_count} existing)")
        else:
            if existing_count > 0:
                print(f"    ⏭️  {headword}: skipped (already has {existing_count} examples)")
            else:
                print(f"    ⚠️  {headword}: generation failed")

    return results

def insert_examples(db_path: str, examples_by_sense: Dict[int, List[Dict]]):
    """Insert generated examples into database"""
    if not examples_by_sense:
        return 0

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    total_inserted = 0

    try:
        for sense_id, examples in examples_by_sense.items():
            # Get current max order
            cursor.execute("""
                SELECT COALESCE(MAX(example_order), 0)
                FROM example_sentences
                WHERE sense_id = ?
            """, (sense_id,))
            max_order = cursor.fetchone()[0]

            for idx, example in enumerate(examples, max_order + 1):
                japanese = example.get("japanese", "")
                english = example.get("english", "")

                if not japanese or not english:
                    continue

                cursor.execute("""
                    INSERT INTO example_sentences
                    (sense_id, japanese_text, english_translation, example_order)
                    VALUES (?, ?, ?, ?)
                """, (sense_id, japanese, english, idx))
                total_inserted += 1

        conn.commit()

    except Exception as e:
        conn.rollback()
        print(f"    ❌ Database insert failed: {e}")
    finally:
        conn.close()

    return total_inserted

def main():
    """Main entry point"""
    print("=" * 60)
    print("Smart Example Generation (with Duplicate Detection)")
    print("=" * 60)

    # Parse command line arguments
    limit = 100  # Default
    if len(sys.argv) > 1:
        try:
            limit = int(sys.argv[1])
        except ValueError:
            print(f"Invalid number: {sys.argv[1]}")
            sys.exit(1)

    print(f"\nProcessing up to {limit} words that need more examples...")

    # Get words
    words = get_words_for_generation(DB_PATH, limit)
    total = len(words)

    if total == 0:
        print("✅ All words have enough examples!")
        return

    print(f"\n📊 Words needing examples: {total}")
    print(f"📊 Estimated examples to generate: ~{total * 2} (varies by existing count)")
    print(f"📊 Estimated batches: {(total + BATCH_SIZE - 1) // BATCH_SIZE}")

    # Estimate cost
    input_tokens = total * 250  # Higher due to existing examples context
    output_tokens = total * 300
    cost = (input_tokens / 1_000_000 * 0.150) + (output_tokens / 1_000_000 * 0.600)
    print(f"💰 Estimated cost: ${cost:.2f} USD")
    print(f"⏱️  Estimated time: {total / 40:.1f} minutes")

    # Confirm
    print(f"\n⚠️  Ready to generate. This will use API quota.")
    print(f"Press Ctrl+C to cancel, or wait 5 seconds to start...")
    try:
        time.sleep(5)
    except KeyboardInterrupt:
        print("\n❌ Cancelled")
        sys.exit(0)

    # Initialize OpenAI
    client = init_openai()

    # Batch processing
    processed_count = 0
    total_examples_inserted = 0
    batch_num = 0

    for i in range(0, total, BATCH_SIZE):
        batch = words[i:i + BATCH_SIZE]
        batch_num += 1

        print(f"\n🔄 Processing batch {batch_num}/{(total + BATCH_SIZE - 1) // BATCH_SIZE} "
              f"(words {i+1}-{min(i+BATCH_SIZE, total)}/{total})")

        # Generate examples
        examples_by_sense = generate_examples_for_batch(client, DB_PATH, batch)

        # Insert into database
        if examples_by_sense:
            inserted = insert_examples(DB_PATH, examples_by_sense)
            total_examples_inserted += inserted
            processed_count += len(examples_by_sense)

        # Delay between batches
        if i + BATCH_SIZE < total:
            time.sleep(DELAY_BETWEEN_BATCHES)

    print(f"\n{'='*60}")
    print(f"✅ Generation complete!")
    print(f"📊 Words processed: {processed_count}/{total}")
    print(f"📊 New examples inserted: {total_examples_inserted}")
    print(f"{'='*60}")

if __name__ == '__main__':
    main()
