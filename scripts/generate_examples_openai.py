#!/usr/bin/env python3
"""
批量生成例句脚本（OpenAI GPT-4o-mini）
为没有例句的词条生成例句并存入数据库
"""

import sqlite3
import os
import sys
import time
import json
from typing import List, Tuple, Dict
from openai import OpenAI

# OpenAI API 配置
API_KEY = os.environ.get('OPENAI_API_KEY')
if not API_KEY:
    print("❌ 错误: 请设置 OPENAI_API_KEY 环境变量")
    sys.exit(1)
MODEL_NAME = "gpt-4o-mini"

# 数据库路径
DB_PATHS = [
    "../NichiDict/Resources/seed.sqlite"
]

# 批量处理参数
BATCH_SIZE = 50  # 每批处理的词条数
EXAMPLES_PER_WORD = 3  # 每个词生成3个例句
DELAY_BETWEEN_BATCHES = 0.5  # 批次间延迟（秒）
TOP_N_WORDS = 5000  # 处理前5000个词

def init_openai():
    """初始化 OpenAI API"""
    client = OpenAI(api_key=API_KEY)
    return client

def get_words_without_examples(db_path: str, top_n: int) -> List[Tuple]:
    """
    获取没有例句的词条（前N个）
    返回: [(entry_id, headword, reading_hiragana, reading_romaji, sense_id, definition_english, definition_chinese), ...]
    """
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 获取前N个词条中没有例句的
    cursor.execute(f"""
        SELECT DISTINCT
            d.id as entry_id,
            d.headword,
            d.reading_hiragana,
            d.reading_romaji,
            s.id as sense_id,
            s.definition_english,
            COALESCE(s.definition_chinese_simplified, s.definition_chinese_traditional, '') as definition_chinese
        FROM dictionary_entries d
        JOIN word_senses s ON d.id = s.entry_id
        WHERE d.id <= {top_n}
          AND s.id NOT IN (SELECT DISTINCT sense_id FROM example_sentences)
        ORDER BY d.id
    """)

    words = cursor.fetchall()
    conn.close()

    return words

def generate_examples_for_word(client, word: Tuple) -> Tuple[int, List[Dict]]:
    """
    为一个词生成例句
    返回: (sense_id, [example1, example2, example3])
    """
    entry_id, headword, reading_hiragana, reading_romaji, sense_id, def_en, def_cn = word

    prompt = f"""Generate {EXAMPLES_PER_WORD} natural Japanese example sentences for this word.

Word: {headword}
Reading: {reading_hiragana} ({reading_romaji})
Meaning: {def_en}
{f'中文: {def_cn}' if def_cn else ''}

Requirements:
1. Generate {EXAMPLES_PER_WORD} natural Japanese sentences (20-30 characters each)
2. Each sentence must demonstrate typical usage in daily life
3. Keep sentences simple and practical
4. Include the word '{headword}' or its conjugated form

Return ONLY a JSON object with this schema:
{{"examples":[
  {{"japanese":"...", "chinese":"...", "english":"..."}},
  {{"japanese":"...", "chinese":"...", "english":"..."}},
  {{"japanese":"...", "chinese":"...", "english":"..."}}
]}}

Respond with JSON only."""

    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": "You are a Japanese language expert. Generate natural example sentences."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.7,
            max_tokens=500
        )

        response_text = response.choices[0].message.content.strip()

        # 清理 markdown 代码块标记
        if response_text.startswith("```json"):
            response_text = response_text[7:]
        if response_text.startswith("```"):
            response_text = response_text[3:]
        if response_text.endswith("```"):
            response_text = response_text[:-3]
        response_text = response_text.strip()

        # 解析 JSON
        data = json.loads(response_text)
        examples = data.get("examples", [])

        return (sense_id, examples)

    except Exception as e:
        print(f"    ❌ {headword} 生成失败: {str(e)[:100]}")
        return (sense_id, [])

def generate_examples_for_batch(client, words: List[Tuple]) -> Dict[int, List[Dict]]:
    """
    为一批词生成例句
    返回: {sense_id: [example1, example2, example3], ...}
    """
    if not words:
        return {}

    results = {}

    for word in words:
        _, headword, reading_hiragana, _, sense_id, _, _ = word

        sense_id, examples = generate_examples_for_word(client, word)

        if examples:
            results[sense_id] = examples
            print(f"    ✅ {headword} ({reading_hiragana}): {len(examples)} 例句")
        else:
            print(f"    ⚠️  {headword}: 生成失败")

    return results

def insert_examples(db_path: str, examples_by_sense: Dict[int, List[Dict]]):
    """
    将生成的例句插入数据库
    """
    if not examples_by_sense:
        return 0

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    total_inserted = 0

    try:
        for sense_id, examples in examples_by_sense.items():
            for idx, example in enumerate(examples, 1):
                japanese = example.get("japanese", "")
                chinese = example.get("chinese", "")
                english = example.get("english", "")

                if not japanese or not english:
                    continue

                cursor.execute("""
                    INSERT INTO example_sentences
                    (sense_id, japanese_text, english_translation, chinese_translation, example_order)
                    VALUES (?, ?, ?, ?, ?)
                """, (sense_id, japanese, english, chinese if chinese else None, idx))
                total_inserted += 1

        conn.commit()

    except Exception as e:
        conn.rollback()
        print(f"    ❌ 数据库插入失败: {e}")
    finally:
        conn.close()

    return total_inserted

def process_database(db_path: str):
    """
    处理一个数据库
    """
    if not os.path.exists(db_path):
        print(f"⚠️  数据库不存在: {db_path}")
        return

    print(f"\n{'='*60}")
    print(f"开始处理数据库: {db_path}")
    print(f"{'='*60}")

    # 获取需要生成例句的词
    words = get_words_without_examples(db_path, TOP_N_WORDS)
    total = len(words)

    if total == 0:
        print("✅ 所有词条都已有例句")
        return

    print(f"📊 需要生成例句的词条: {total} 个")
    print(f"📊 预计生成例句: {total * EXAMPLES_PER_WORD} 条")
    print(f"📊 预计批次: {(total + BATCH_SIZE - 1) // BATCH_SIZE} 批")

    # 估算成本
    input_tokens = total * 200
    output_tokens = total * 400
    cost = (input_tokens / 1_000_000 * 0.150) + (output_tokens / 1_000_000 * 0.600)
    print(f"💰 预计成本: ${cost:.2f} USD")
    print(f"⏱️  预计时间: {total / 60:.1f} 分钟")

    # 确认
    print(f"\n⚠️  准备开始生成，将消耗 API 配额")
    print(f"按 Ctrl+C 取消，或等待 5 秒自动开始...")
    time.sleep(5)

    # 初始化 OpenAI
    client = init_openai()

    # 批量处理
    processed_count = 0
    total_examples_inserted = 0
    batch_num = 0

    for i in range(0, total, BATCH_SIZE):
        batch = words[i:i + BATCH_SIZE]
        batch_num += 1

        print(f"\n🔄 处理批次 {batch_num}/{(total + BATCH_SIZE - 1) // BATCH_SIZE} "
              f"(词条 {i+1}-{min(i+BATCH_SIZE, total)}/{total})")

        # 生成例句
        examples_by_sense = generate_examples_for_batch(client, batch)

        # 插入数据库
        if examples_by_sense:
            inserted = insert_examples(db_path, examples_by_sense)
            total_examples_inserted += inserted
            processed_count += len(examples_by_sense)
            print(f"    💾 插入 {inserted} 条例句")

        # 显示进度
        progress = (i + len(batch)) / total * 100
        print(f"📈 进度: {progress:.1f}% ({processed_count}/{total} 词，{total_examples_inserted} 例句)")

        # 批次间延迟
        if i + BATCH_SIZE < total:
            time.sleep(DELAY_BETWEEN_BATCHES)

    print(f"\n✅ 数据库处理完成！")
    print(f"   处理词数: {processed_count}")
    print(f"   生成例句: {total_examples_inserted} 条")

def main():
    """主函数"""
    print("=" * 60)
    print(f"📚 例句批量生成脚本 (OpenAI {MODEL_NAME})")
    print("=" * 60)
    print(f"目标范围: 前 {TOP_N_WORDS} 个词条（无例句）")
    print(f"每词例句: {EXAMPLES_PER_WORD} 条")
    print(f"批次大小: {BATCH_SIZE}")
    print()

    # 切换到脚本目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    # 处理所有数据库
    for db_path in DB_PATHS:
        process_database(db_path)

    print("\n" + "=" * 60)
    print("🎉 所有数据库处理完成！")
    print("=" * 60)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n❌ 发生错误: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
