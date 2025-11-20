#!/usr/bin/env python3
"""
Generate example sentences for N4 words that are missing examples.
Uses OpenAI GPT-4o-mini API.
"""

import sqlite3
import os
import sys
import time
import json
from typing import List, Dict, Tuple
from openai import OpenAI

# OpenAI API Configuration
API_KEY = os.environ.get('OPENAI_API_KEY')
if not API_KEY:
    print("❌ Error: Please set OPENAI_API_KEY environment variable")
    print("\nUsage:")
    print("  export OPENAI_API_KEY='your-api-key-here'")
    print("  python3 scripts/generate_n4_missing_examples.py")
    sys.exit(1)

MODEL_NAME = "gpt-4o-mini"

# Database path
DB_PATH = "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite"

# Processing parameters
BATCH_SIZE = 10  # Process N words per batch
EXAMPLES_PER_SENSE = 3  # Generate 3 examples per sense
DELAY_BETWEEN_BATCHES = 1.0  # Delay between batches (seconds)

def init_openai():
    """Initialize OpenAI API"""
    client = OpenAI(api_key=API_KEY)
    return client

def get_n4_missing_senses(db_path: str) -> List[Tuple]:
    """
    Get all N4 word senses that have no examples.
    Returns: [(entry_id, headword, reading_hiragana, sense_id, part_of_speech, definition_english), ...]
    """
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            de.id as entry_id,
            de.headword,
            de.reading_hiragana,
            de.reading_romaji,
            ws.id as sense_id,
            ws.part_of_speech,
            ws.definition_english
        FROM dictionary_entries de
        JOIN word_senses ws ON de.id = ws.entry_id
        LEFT JOIN example_sentences es ON ws.id = es.sense_id
        WHERE de.jlpt_level = 'N4'
        GROUP BY de.id, ws.id
        HAVING COUNT(es.id) = 0
        ORDER BY de.headword, ws.sense_order
    """)

    senses = cursor.fetchall()
    conn.close()

    return senses

def generate_examples_for_sense(client, sense: Tuple) -> Tuple[int, List[Dict]]:
    """
    Generate example sentences for a sense.
    Returns: (sense_id, [example1, example2, example3])
    """
    entry_id, headword, reading_hiragana, reading_romaji, sense_id, pos, definition = sense

    prompt = f"""Generate {EXAMPLES_PER_SENSE} natural Japanese example sentences for this N4 word.

Word: {headword}
Reading: {reading_hiragana} ({reading_romaji})
Part of Speech: {pos}
Meaning: {definition}

Requirements:
1. Generate {EXAMPLES_PER_SENSE} natural Japanese sentences (15-35 characters each)
2. Each sentence must be appropriate for JLPT N4 level (simple and practical)
3. Include the word '{headword}' or its conjugated form
4. Use simple grammar patterns suitable for N4 learners
5. Ensure variety in sentence patterns (statements, questions, etc.)

Return ONLY a JSON object with this schema:
{{"examples":[
  {{"japanese":"...", "english":"..."}},
  {{"japanese":"...", "english":"..."}},
  {{"japanese":"...", "english":"..."}}
]}}

Respond with JSON only."""

    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": "You are a Japanese language expert specializing in JLPT N4 level content. Generate simple, natural example sentences appropriate for intermediate learners."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.7,
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

        return (sense_id, examples)

    except Exception as e:
        print(f"    ❌ {headword} ({reading_hiragana}) generation failed: {str(e)[:100]}")
        return (sense_id, [])

def insert_examples(db_path: str, sense_id: int, examples: List[Dict]) -> int:
    """Insert generated examples into database"""
    if not examples:
        return 0

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    total_inserted = 0

    try:
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
    # Force unbuffered output
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)

    print("=" * 60, flush=True)
    print("N4 Missing Examples Generation", flush=True)
    print("=" * 60, flush=True)

    # Check for --yes flag
    auto_confirm = '--yes' in sys.argv or '-y' in sys.argv

    # Get N4 senses without examples
    senses = get_n4_missing_senses(DB_PATH)
    total_senses = len(senses)

    if total_senses == 0:
        print("✅ All N4 words have examples!")
        return

    print(f"\n📊 N4 senses needing examples: {total_senses}", flush=True)
    print(f"📊 Estimated examples to generate: ~{total_senses * EXAMPLES_PER_SENSE}", flush=True)
    print(f"📊 Estimated batches: {(total_senses + BATCH_SIZE - 1) // BATCH_SIZE}", flush=True)

    # Estimate cost (GPT-4o-mini pricing: $0.150/1M input, $0.600/1M output)
    input_tokens = total_senses * 200
    output_tokens = total_senses * 250
    cost = (input_tokens / 1_000_000 * 0.150) + (output_tokens / 1_000_000 * 0.600)
    print(f"💰 Estimated cost: ${cost:.3f} USD", flush=True)
    print(f"⏱️  Estimated time: {total_senses / 30:.1f} minutes", flush=True)

    # Confirm
    if not auto_confirm:
        print(f"\n⚠️  Ready to generate. This will use OpenAI API quota.")
        try:
            response = input("Continue? (y/n): ")
            if response.lower() != 'y':
                print("❌ Cancelled")
                sys.exit(0)
        except (EOFError, KeyboardInterrupt):
            print("\n❌ Cancelled")
            sys.exit(0)
    else:
        print(f"\n✅ Auto-confirmed (--yes flag)")
        time.sleep(1)

    # Initialize OpenAI
    client = init_openai()

    # Process senses
    processed_count = 0
    total_examples_inserted = 0
    failed_count = 0

    for i, sense in enumerate(senses, 1):
        _, headword, reading_hiragana, _, sense_id, _, definition = sense

        print(f"\n[{i}/{total_senses}] {headword} ({reading_hiragana})", flush=True)
        print(f"  Definition: {definition[:80]}{'...' if len(definition) > 80 else ''}", flush=True)

        # Generate examples
        sense_id, examples = generate_examples_for_sense(client, sense)

        if examples:
            # Insert into database
            inserted = insert_examples(DB_PATH, sense_id, examples)
            total_examples_inserted += inserted
            processed_count += 1
            print(f"  ✅ Generated and inserted {inserted} examples", flush=True)
        else:
            failed_count += 1
            print(f"  ❌ Generation failed", flush=True)

        # Delay between requests
        if i < total_senses:
            time.sleep(0.5)

        # Batch delay
        if i % BATCH_SIZE == 0 and i < total_senses:
            print(f"\n  ⏸️  Batch complete. Waiting {DELAY_BETWEEN_BATCHES}s...")
            time.sleep(DELAY_BETWEEN_BATCHES)

    print(f"\n{'='*60}")
    print(f"✅ Generation complete!")
    print(f"📊 Senses processed: {processed_count}/{total_senses}")
    print(f"📊 Examples inserted: {total_examples_inserted}")
    print(f"❌ Failed: {failed_count}")
    print(f"{'='*60}")

if __name__ == '__main__':
    main()
