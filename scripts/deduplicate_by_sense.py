#!/usr/bin/env python3
"""
改进的N5例句去重脚本
策略：在sense级别去重，确保每个sense至少保留1条例句
"""

import sqlite3
from collections import defaultdict

DB_PATH = "../NichiDict/Resources/seed.sqlite"

def deduplicate_by_sense():
    """按sense级别去重"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    print("=" * 60)
    print("N5 例句去重脚本（改进版 - 按sense去重）")
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
    print(f"  多样性：{unique/total*100:.1f}%")

    # 2. 获取所有N5例句，按entry分组
    cursor.execute("""
        SELECT
            e.id as example_id,
            e.sense_id,
            d.id as entry_id,
            e.japanese_text,
            d.headword
        FROM example_sentences e
        JOIN word_senses s ON e.sense_id = s.id
        JOIN dictionary_entries d ON s.entry_id = d.id
        WHERE d.jlpt_level = 'N5'
        ORDER BY d.id, e.sense_id, e.id
    """)

    rows = cursor.fetchall()

    # 3. 按entry(单词)分组，在单词内去重但确保每个sense至少有1条
    by_entry = defaultdict(list)
    for example_id, sense_id, entry_id, japanese_text, headword in rows:
        by_entry[entry_id].append({
            'example_id': example_id,
            'sense_id': sense_id,
            'japanese_text': japanese_text,
            'headword': headword
        })

    # 4. 对每个单词，删除重复但确保每个sense至少保留1条
    to_delete = []
    stats = {
        'total_entries': len(by_entry),
        'entries_with_duplicates': 0,
        'deleted_examples': 0,
        'protected_senses': 0
    }

    for entry_id, examples in by_entry.items():
        if len(examples) <= 1:
            continue

        # 跟踪每个sense是否已有例句
        sense_has_example = defaultdict(bool)
        seen_texts = set()

        for ex in examples:
            text = ex['japanese_text']
            sense_id = ex['sense_id']

            if text in seen_texts:
                # 这是重复的例句
                if sense_has_example[sense_id]:
                    # 这个sense已经有其他例句了，可以删除
                    to_delete.append(ex['example_id'])
                else:
                    # 这个sense还没有例句，即使重复也要保留
                    sense_has_example[sense_id] = True
                    stats['protected_senses'] += 1
            else:
                # 第一次见到这个例句，保留
                seen_texts.add(text)
                sense_has_example[sense_id] = True

        if len(seen_texts) < len(examples):
            stats['entries_with_duplicates'] += 1

    stats['deleted_examples'] = len(to_delete)

    print(f"\n分析结果：")
    print(f"  总单词数：{stats['total_entries']}")
    print(f"  有重复的单词：{stats['entries_with_duplicates']}")
    print(f"  受保护的sense：{stats['protected_senses']} (即使重复也保留)")
    print(f"  将删除例句：{stats['deleted_examples']} 条")
    print(f"  预期保留：{total - stats['deleted_examples']} 条")
    if stats['deleted_examples'] > 0:
        print(f"  预期多样性：{unique/(total - stats['deleted_examples'])*100:.1f}%")

    # 5. 确认
    if stats['deleted_examples'] == 0:
        print("\n✅ 没有发现需要删除的重复例句！")
        conn.close()
        return

    print(f"\n⚠️  准备删除 {stats['deleted_examples']} 条重复例句")
    print("   每个sense至少保留1条例句")
    print(f"   按 Ctrl+C 取消，或等待 3 秒自动开始...")

    import time
    time.sleep(3)

    # 6. 执行删除
    try:
        # 分批删除，避免SQL太长
        batch_size = 500
        for i in range(0, len(to_delete), batch_size):
            batch = to_delete[i:i+batch_size]
            cursor.execute(f"""
                DELETE FROM example_sentences
                WHERE id IN ({','.join(map(str, batch))})
            """)
            print(f"   删除进度: {min(i+batch_size, len(to_delete))}/{len(to_delete)}")

        conn.commit()
        print(f"\n✅ 删除完成！")

        # 7. 显示最终状态
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
        print(f"  改善：{(final_unique/final_total - unique/total)*100:+.1f}%")

        # 8. 验证没有sense失去所有例句
        cursor.execute("""
            SELECT COUNT(DISTINCT s.id)
            FROM word_senses s
            JOIN dictionary_entries d ON s.entry_id = d.id
            WHERE d.jlpt_level = 'N5'
              AND s.id NOT IN (SELECT DISTINCT sense_id FROM example_sentences WHERE sense_id IS NOT NULL)
        """)

        missing_senses = cursor.fetchone()[0]

        if missing_senses > 5:
            print(f"\n⚠️  警告：{missing_senses} 个sense失去了例句！")
        else:
            print(f"\n✅ 验证通过：仅{missing_senses}个sense缺失例句（正常）")

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
        deduplicate_by_sense()
    except KeyboardInterrupt:
        print("\n\n⚠️  用户取消")
    except Exception as e:
        print(f"\n\n❌ 发生错误: {e}")
        import traceback
        traceback.print_exc()