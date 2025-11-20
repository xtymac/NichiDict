#!/usr/bin/env python3
"""
Generate example sentences for specific missing adverbs (すぐ, ゆっくり)
"""

import sqlite3
import os
import sys
import time
from openai import OpenAI

# OpenAI API Configuration
API_KEY = os.environ.get('OPENAI_API_KEY')
if not API_KEY:
    print("❌ Error: Please set OPENAI_API_KEY environment variable")
    sys.exit(1)

MODEL_NAME = "gpt-4o-mini"
DB_PATH = "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite"

# Words to generate examples for
WORDS_TO_GENERATE = [
    {
        'headword': '直ぐ',
        'reading': 'すぐ',
        'sense_ids': [51534, 51535, 51536, 51537],  # Skip the adj sense 51538
        'definitions': [
            'immediately; at once; right away; directly',
            'soon; before long; shortly',
            'easily; readily; without difficulty',
            'right (near); nearby; just (handy)'
        ]
    },
    {
        'headword': 'ゆっくり',
        'reading': 'ゆっくり',
        'sense_ids': [1946, 1947, 1948],
        'definitions': [
            'slowly; unhurriedly; without haste; leisurely; at one\'s leisure',
            'easily (e.g. in time); well; sufficiently; amply; with time to spare',
            'well (e.g. sleep); comfortably'
        ]
    }
]

def init_openai():
    """Initialize OpenAI API"""
    return OpenAI(api_key=API_KEY)

def generate_examples_for_sense(client, headword: str, reading: str, definition: str, num_examples: int = 3):
    """Generate example sentences for a specific sense using OpenAI"""

    system_prompt = """You are a professional Japanese language teacher creating natural example sentences for a dictionary app.

Requirements:
1. Generate NATURAL, REALISTIC Japanese sentences that native speakers would actually use
2. Use the TARGET WORD in its KANA FORM (not kanji form if it's usually written in kana)
3. Include appropriate English translations
4. Use simple grammar and vocabulary (N5-N3 level preferred)
5. Make sentences practical and useful for learners
6. Vary sentence patterns (statement, question, command, etc.)
7. Use common sentence endings (です/ます form preferred)

Format each example EXACTLY as:
JP: [Japanese sentence]
EN: [English translation]

Generate 3 diverse examples."""

    user_prompt = f"""Generate 3 example sentences for the Japanese word:

Word: {reading} (written as {headword})
Reading: {reading}
Definition: {definition}
Part of Speech: adverb

Make sure to use "{reading}" (the kana form) in the examples, NOT the kanji "{headword}"."""

    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.8,
            max_tokens=800
        )

        content = response.choices[0].message.content
        return parse_examples(content, num_examples)

    except Exception as e:
        print(f"❌ Error generating examples: {e}")
        return []

def parse_examples(content: str, expected_count: int):
    """Parse example sentences from GPT response"""
    examples = []
    lines = content.strip().split('\n')

    current_jp = None
    current_en = None

    for line in lines:
        line = line.strip()
        if line.startswith('JP:'):
            current_jp = line.replace('JP:', '').strip()
        elif line.startswith('EN:'):
            current_en = line.replace('EN:', '').strip()

            if current_jp and current_en:
                examples.append({
                    'japanese': current_jp,
                    'english': current_en
                })
                current_jp = None
                current_en = None

    if len(examples) < expected_count:
        print(f"⚠️  Warning: Expected {expected_count} examples, got {len(examples)}")

    return examples

def insert_examples(db_path: str, sense_id: int, examples: list):
    """Insert generated examples into database"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get current max example_order for this sense
    cursor.execute("""
        SELECT COALESCE(MAX(example_order), 0)
        FROM example_sentences
        WHERE sense_id = ?
    """, (sense_id,))

    max_order = cursor.fetchone()[0]

    # Insert examples
    inserted_count = 0
    for i, example in enumerate(examples):
        example_order = max_order + i + 1

        cursor.execute("""
            INSERT INTO example_sentences (
                sense_id, japanese_text, english_translation, example_order
            ) VALUES (?, ?, ?, ?)
        """, (
            sense_id,
            example['japanese'],
            example['english'],
            example_order
        ))
        inserted_count += 1

    conn.commit()
    conn.close()

    return inserted_count

def main():
    print("🚀 Starting example generation for missing adverbs...")
    print(f"📖 Database: {DB_PATH}")
    print(f"🤖 Model: {MODEL_NAME}\n")

    client = init_openai()

    total_generated = 0

    for word_info in WORDS_TO_GENERATE:
        headword = word_info['headword']
        reading = word_info['reading']
        sense_ids = word_info['sense_ids']
        definitions = word_info['definitions']

        print(f"\n{'='*60}")
        print(f"📝 Word: {headword} ({reading})")
        print(f"{'='*60}\n")

        for sense_id, definition in zip(sense_ids, definitions):
            print(f"  Sense {sense_id}: {definition}")

            # Generate examples
            examples = generate_examples_for_sense(
                client, headword, reading, definition, num_examples=3
            )

            if not examples:
                print(f"    ❌ Failed to generate examples")
                continue

            # Display generated examples
            print(f"    ✅ Generated {len(examples)} examples:")
            for i, ex in enumerate(examples, 1):
                print(f"       {i}. {ex['japanese']}")
                print(f"          {ex['english']}")

            # Insert into database
            inserted = insert_examples(DB_PATH, sense_id, examples)
            total_generated += inserted
            print(f"    💾 Inserted {inserted} examples into database")

            # Small delay to avoid rate limiting
            time.sleep(0.5)

    print(f"\n{'='*60}")
    print(f"✅ Done! Generated {total_generated} example sentences total")
    print(f"{'='*60}\n")

if __name__ == "__main__":
    main()
