#!/usr/bin/env python3
"""
AI Batch Translation Script - OpenAI GPT-4o mini
Translates English definitions to Chinese using GPT-4o mini
Cost: ~$0.25 for 5000 words (6x cheaper than Claude!)
"""

import sqlite3
import openai
import os
import sys
import time
from typing import List, Dict, Optional

# Configuration
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
MODEL = "gpt-4o-mini"  # Super cheap: $0.150/M input, $0.600/M output
BATCH_SIZE = 100  # Can use larger batches due to lower cost
TOP_N_ENTRIES = 60000  # Translate entries with ID <= 60000 (includes 行く, 見る, etc.)

class TranslationStats:
    def __init__(self):
        self.total = 0
        self.translated = 0
        self.skipped = 0
        self.errors = 0
        self.input_tokens = 0
        self.output_tokens = 0
        self.start_time = time.time()

    def print_progress(self, current):
        elapsed = time.time() - self.start_time
        rate = current / elapsed if elapsed > 0 else 0
        remaining = (self.total - current) / rate if rate > 0 else 0

        print(f"\rProgress: {current}/{self.total} ({current*100//self.total}%) | "
              f"Rate: {rate:.1f}/s | "
              f"ETA: {remaining/60:.1f}min | "
              f"Cost: ${self.estimate_cost():.3f}", end="", flush=True)

    def print_summary(self):
        elapsed = time.time() - self.start_time
        print(f"\n\n{'='*70}")
        print(f"Translation Complete!")
        print(f"{'='*70}")
        print(f"Total senses: {self.total}")
        print(f"Translated: {self.translated}")
        print(f"Skipped (already has Chinese): {self.skipped}")
        print(f"Errors: {self.errors}")
        print(f"Time elapsed: {elapsed/60:.1f} minutes")
        print(f"Input tokens: {self.input_tokens:,}")
        print(f"Output tokens: {self.output_tokens:,}")
        print(f"Final cost: ${self.estimate_cost():.2f}")
        print(f"{'='*70}\n")

    def estimate_cost(self):
        # GPT-4o mini pricing
        input_cost = (self.input_tokens / 1_000_000) * 0.150
        output_cost = (self.output_tokens / 1_000_000) * 0.600
        return input_cost + output_cost

def translate_batch(client: openai.OpenAI, senses: List[Dict]) -> tuple:
    """
    Translate a batch of senses using OpenAI API
    Returns (translations, input_tokens, output_tokens)
    """

    # Build prompt with all senses
    sense_list = []
    for i, sense in enumerate(senses):
        sense_list.append(f"{i+1}. {sense['definition']}")

    prompt = f"""Translate these Japanese dictionary definitions to Simplified Chinese.

Rules:
- Provide ONLY the Chinese translation
- One translation per line, matching the input order
- Be concise and natural
- No numbers, no explanations

English:
{chr(10).join(sense_list)}

Chinese:"""

    try:
        response = client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": "You are a professional Japanese-Chinese translator."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.3,
            max_tokens=1000
        )

        # Parse response
        chinese_text = response.choices[0].message.content.strip()
        translations = [line.strip() for line in chinese_text.split('\n') if line.strip()]

        # Pad with None if needed
        while len(translations) < len(senses):
            translations.append(None)

        return (
            translations[:len(senses)],
            response.usage.prompt_tokens,
            response.usage.completion_tokens
        )

    except Exception as e:
        print(f"\n⚠️  Error: {e}")
        return [None] * len(senses), 0, 0

def main():
    if not OPENAI_API_KEY:
        print("❌ Error: OPENAI_API_KEY not set")
        print("\nPlease set it:")
        print('  export OPENAI_API_KEY="sk-proj-..."')
        print("\nOr add to ~/.zshrc:")
        print('  echo \'export OPENAI_API_KEY="your-key"\' >> ~/.zshrc')
        sys.exit(1)

    if len(sys.argv) < 2:
        print("Usage: python3 translate_with_openai.py <database_path> [--yes]")
        print("Example: python3 translate_with_openai.py data/dictionary.sqlite")
        print("Options:")
        print("  --yes    Skip confirmation prompt")
        sys.exit(1)

    auto_confirm = "--yes" in sys.argv or "-y" in sys.argv

    db_path = sys.argv[1]

    print(f"\n{'='*70}")
    print(f"🚀 AI Translation - OpenAI GPT-4o mini")
    print(f"{'='*70}")
    print(f"Model: {MODEL}")
    print(f"Target: Entries with ID <= {TOP_N_ENTRIES} (includes 行く, 見る, 飲む)")
    print(f"Database: {db_path}")
    print(f"Pricing: $0.150/M input, $0.600/M output (6x cheaper than Claude!)")
    print(f"{'='*70}\n")

    # Connect to database
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Get senses for top N entries by entry ID (JMdict order = frequency order)
    query = f"""
        SELECT DISTINCT s.id, s.entry_id, s.definition_english, s.part_of_speech,
               e.headword, e.id as entry_order
        FROM dictionary_entries e
        JOIN word_senses s ON e.id = s.entry_id
        WHERE (s.definition_chinese_simplified IS NULL OR s.definition_chinese_simplified = '')
          AND e.id <= {TOP_N_ENTRIES}
        ORDER BY e.id ASC, s.id ASC
    """

    cursor.execute(query)
    senses = [dict(row) for row in cursor.fetchall()]

    stats = TranslationStats()
    stats.total = len(senses)

    if stats.total == 0:
        print("✅ All senses already have Chinese translations!")
        return

    print(f"Found {stats.total} senses to translate\n")

    # Estimate cost
    estimated_cost = (stats.total * 50 / 1_000_000) * 0.150 + (stats.total * 15 / 1_000_000) * 0.600
    print(f"Estimated cost: ${estimated_cost:.2f}")
    print(f"Estimated time: {stats.total / 1000:.1f} minutes\n")

    if not auto_confirm:
        response = input("Continue? (yes/no): ")
        if response.lower() not in ['yes', 'y']:
            print("Cancelled.")
            return
    else:
        print("Auto-confirmed with --yes flag")

    print("\n🔄 Starting translation...\n")

    # Initialize OpenAI client
    client = openai.OpenAI(api_key=OPENAI_API_KEY)

    # Process in batches
    for i in range(0, len(senses), BATCH_SIZE):
        batch = senses[i:i+BATCH_SIZE]

        # Translate batch
        translations, input_tok, output_tok = translate_batch(client, [
            {"definition": s["definition_english"], "pos": s["part_of_speech"]}
            for s in batch
        ])

        stats.input_tokens += input_tok
        stats.output_tokens += output_tok

        # Update database
        for sense, translation in zip(batch, translations):
            if translation and len(translation) > 0:
                cursor.execute("""
                    UPDATE word_senses
                    SET definition_chinese_simplified = ?
                    WHERE id = ?
                """, (translation, sense["id"]))
                stats.translated += 1
            else:
                stats.errors += 1

        conn.commit()
        stats.print_progress(i + len(batch))

        # Small delay to avoid rate limiting
        time.sleep(0.05)

    # Final stats
    stats.print_summary()

    # Show some examples
    print("Sample translations:")
    cursor.execute("""
        SELECT e.headword, e.reading_hiragana, s.definition_english, s.definition_chinese_simplified
        FROM dictionary_entries e
        JOIN word_senses s ON e.id = s.entry_id
        WHERE s.definition_chinese_simplified IS NOT NULL
        ORDER BY COALESCE(e.frequency_rank, 999999) ASC
        LIMIT 5
    """)

    for row in cursor.fetchall():
        print(f"  {row['headword']} ({row['reading_hiragana']})")
        print(f"    EN: {row['definition_english']}")
        print(f"    CN: {row['definition_chinese_simplified']}\n")

    conn.close()
    print("✅ Translation complete!")
    print(f"\n💰 You saved ${1.50 - stats.estimate_cost():.2f} by using GPT-4o mini instead of Claude!")

if __name__ == "__main__":
    main()
