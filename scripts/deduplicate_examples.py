#!/usr/bin/env python3
"""
清理N5重复例句脚本
保留每个单词的不重复例句，删除完全相同的重复项
"""

import sqlite3
from collections import defaultdict

DB_PATH = "../NichiDict/Resources/seed.sqlite"

def deduplicate_examples():
    """清理重复例句"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    print("=" * 60)
    print("N5 例句去重脚本")
    print("=" * 60)

    # 1. 统计当前状态
    cursor.execute("""
        SELECT
            COUNT(*) as total,
            COUNT(DISTINCT japanese_text) as unique_count
        FROM example_sentences
        WHERE sense_id IN (
            SELECT s.id FROM word_senses s
            JOIN dictionary_entries d ON s.entry_id = d.id
            WHERE d.jlpt_level = 'N5'
        )
    """)

    total, unique = cursor.fetchone()
    duplicates = total - unique

    print(f"\n当前状态：")
    print(f"  总例句数：{total}")
    print(f"  不重复例句：{unique}")
    print(f"  重复数量：{duplicates} ({duplicates/total*100:.1f}%)")

    # 2. 对每个单词，保留不重复的例句
    cursor.execute("""
        SELECT
            d.id as entry_id,
            d.headword,
            e.id as example_id,
            e.japanese_text,
            e.sense_id
        FROM dictionary_entries d
        JOIN word_senses s ON d.id = s.entry_id
        JOIN example_sentences e ON s.id = e.sense_id
        WHERE d.jlpt_level = 'N5'
        ORDER BY d.id, e.id
    """)

    rows = cursor.fetchall()

    # 按单词分组
    by_word = defaultdict(list)
    for entry_id, headword, example_id, japanese_text, sense_id in rows:
        by_word[entry_id].append({
            'headword': headword,
            'example_id': example_id,
            'japanese_text': japanese_text,
            'sense_id': sense_id
        })

    # 3. 找出需要删除的重复例句
    to_delete = []
    stats = {'processed_words': 0, 'deleted_examples': 0}

    for entry_id, examples in by_word.items():
        seen_texts = {}  # japanese_text -> first example_id

        for ex in examples:
            text = ex['japanese_text']

            if text in seen_texts:
                # 这是重复的，标记删除
                to_delete.append(ex['example_id'])
            else:
                # 第一次见到这个例句，保留
                seen_texts[text] = ex['example_id']

        if len(to_delete) > stats['deleted_examples']:
            stats['processed_words'] += 1

    stats['deleted_examples'] = len(to_delete)

    print(f"\n分析结果：")
    print(f"  涉及单词数：{stats['processed_words']}")
    print(f"  将删除例句：{stats['deleted_examples']} 条")

    # 4. 确认并执行删除
    if stats['deleted_examples'] == 0:
        print("\n✅ 没有发现需要删除的重复例句！")
        return

    print(f"\n⚠️  准备删除 {stats['deleted_examples']} 条重复例句")
    print("   这将使同一单词的相同例句只保留一份")
    print(f"   按 Ctrl+C 取消，或等待 3 秒自动开始...")

    import time
    time.sleep(3)

    # 执行删除
    try:
        cursor.execute(f"""
            DELETE FROM example_sentences
            WHERE id IN ({','.join(map(str, to_delete))})
        """)

        conn.commit()

        print(f"\n✅ 删除完成！")

        # 5. 显示最终状态
        cursor.execute("""
            SELECT
                COUNT(*) as total,
                COUNT(DISTINCT japanese_text) as unique_count
            FROM example_sentences
            WHERE sense_id IN (
                SELECT s.id FROM word_senses s
                JOIN dictionary_entries d ON s.entry_id = d.id
                WHERE d.jlpt_level = 'N5'
            )
        """)

        final_total, final_unique = cursor.fetchone()

        print(f"\n最终状态：")
        print(f"  总例句数：{final_total}")
        print(f"  不重复例句：{final_unique}")
        print(f"  多样性：{final_unique/final_total*100:.1f}%")

    except Exception as e:
        conn.rollback()
        print(f"\n❌ 删除失败：{e}")
    finally:
        conn.close()

    print("\n" + "=" * 60)
    print("去重完成！")
    print("=" * 60)

if __name__ == "__main__":
    try:
        deduplicate_examples()
    except KeyboardInterrupt:
        print("\n\n⚠️  用户取消")
    except Exception as e:
        print(f"\n\n❌ 发生错误: {e}")
        import traceback
        traceback.print_exc()