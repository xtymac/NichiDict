#!/usr/bin/env python3
"""
AI Batch Translation Script - High Frequency Words Only
Translates English definitions to Chinese using Claude Haiku 4.5
Only processes top 5000 most common words for cost efficiency
"""

import sqlite3
import anthropic
import os
import sys
import time
from typing import List, Dict, Optional

# Configuration
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY")
MODEL = "claude-haiku-4-5-20250916"  # Claude Haiku 4.5
BATCH_SIZE = 50  # Process 50 definitions at once
TOP_N_WORDS = 5000  # Only translate top 5000 words

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
              f"Cost: ${self.estimate_cost():.2f}", end="", flush=True)

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
        # Claude Haiku 4.5 pricing
        input_cost = (self.input_tokens / 1_000_000) * 0.80
        output_cost = (self.output_tokens / 1_000_000) * 4.00
        return input_cost + output_cost

def translate_batch(client: anthropic.Anthropic, senses: List[Dict]) -> tuple:
    """
    Translate a batch of senses using Claude API
    Returns (translations, input_tokens, output_tokens)
    """

    # Build prompt with all senses
    sense_list = []
    for i, sense in enumerate(senses):
        # Keep it concise for the prompt
        pos_short = sense['pos'].split(',')[0]  # Take first part of speech only
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
        response = client.messages.create(
            model=MODEL,
            max_tokens=800,
            temperature=0.3,
            messages=[{"role": "user", "content": prompt}]
        )

        # Parse response
        chinese_text = response.content[0].text.strip()
        translations = [line.strip() for line in chinese_text.split('\n') if line.strip()]

        # Pad with None if needed
        while len(translations) < len(senses):
            translations.append(None)

        return translations[:len(senses)], response.usage.input_tokens, response.usage.output_tokens

    except Exception as e:
        print(f"\n⚠️  Error: {e}")
        return [None] * len(senses), 0, 0

def main():
    if not ANTHROPIC_API_KEY:
        print("❌ Error: ANTHROPIC_API_KEY not set")
        print("\nPlease set it:")
        print('  export ANTHROPIC_API_KEY="sk-ant-api03-..."')
        print("\nOr add to ~/.zshrc:")
        print('  echo \'export ANTHROPIC_API_KEY="your-key"\' >> ~/.zshrc')
        sys.exit(1)

    if len(sys.argv) < 2:
        print("Usage: python3 translate_top_words.py <database_path>")
        print("Example: python3 translate_top_words.py data/dictionary.sqlite")
        sys.exit(1)

    db_path = sys.argv[1]

    print(f"\n{'='*70}")
    print(f"🚀 AI Translation - High Frequency Words")
    print(f"{'='*70}")
    print(f"Model: Claude Haiku 4.5")
    print(f"Target: Top {TOP_N_WORDS} words")
    print(f"Database: {db_path}")
    print(f"{'='*70}\n")

    # Connect to database
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Get top N entries by frequency rank (or first N if no rank)
    # Join with senses that need translation
    query = f"""
        SELECT DISTINCT s.id, s.entry_id, s.definition_english, s.part_of_speech,
               e.headword, e.frequency_rank
        FROM dictionary_entries e
        JOIN word_senses s ON e.id = s.entry_id
        WHERE (s.definition_chinese_simplified IS NULL OR s.definition_chinese_simplified = '')
        ORDER BY COALESCE(e.frequency_rank, 999999) ASC, e.id ASC
        LIMIT {TOP_N_WORDS * 3}
    """

    cursor.execute(query)
    senses = [dict(row) for row in cursor.fetchall()]

    stats = TranslationStats()
    stats.total = len(senses)

    if stats.total == 0:
        print("✅ All senses already have Chinese translations!")
        return

    print(f"Found {stats.total} senses to translate\n")

    # Ask for confirmation
    estimated_cost = (stats.total * 50 / 1_000_000) * 0.80 + (stats.total * 15 / 1_000_000) * 4.00
    print(f"Estimated cost: ${estimated_cost:.2f}")
    print(f"Estimated time: {stats.total / 500:.1f} minutes\n")

    response = input("Continue? (yes/no): ")
    if response.lower() not in ['yes', 'y']:
        print("Cancelled.")
        return

    print("\n🔄 Starting translation...\n")

    # Initialize Claude client
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

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
        time.sleep(0.1)

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

if __name__ == "__main__":
    main()
