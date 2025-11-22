#!/usr/bin/env python3
"""
从备份数据库恢复例句，根据词条内容匹配而不是ID
"""

import sqlite3
import sys

CURRENT_DB = "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite"
BACKUP_DB = "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict/Resources/seed.sqlite.backup_20251115_175418"

def restore_examples():
    """根据词条内容匹配来恢复例句"""

    # 连接两个数据库
    current_conn = sqlite3.connect(CURRENT_DB)
    backup_conn = sqlite3.connect(BACKUP_DB)

    current_cursor = current_conn.cursor()
    backup_cursor = backup_conn.cursor()

    print("📊 开始恢复例句...")

    # 从备份获取所有例句及其对应的词条信息
    backup_cursor.execute("""
        SELECT
            de.headword,
            de.reading_hiragana,
            ws.sense_order,
            ws.definition_english,
            es.japanese_text,
            es.english_translation,
            es.example_order
        FROM example_sentences es
        JOIN word_senses ws ON es.sense_id = ws.id
        JOIN dictionary_entries de ON ws.entry_id = de.id
        ORDER BY de.headword, ws.sense_order, es.example_order
    """)

    backup_examples = backup_cursor.fetchall()
    print(f"✅ 从备份中找到 {len(backup_examples)} 条例句")

    # 统计
    matched = 0
    unmatched = 0
    inserted = 0

    # 为每个例句在当前数据库中找到匹配的sense_id
    for idx, (headword, reading, sense_order, definition, jp_text, en_text, ex_order) in enumerate(backup_examples):
        if (idx + 1) % 1000 == 0:
            print(f"   处理中... {idx + 1}/{len(backup_examples)}")

        # 在当前数据库中查找匹配的sense
        current_cursor.execute("""
            SELECT ws.id
            FROM word_senses ws
            JOIN dictionary_entries de ON ws.entry_id = de.id
            WHERE de.headword = ?
                AND de.reading_hiragana = ?
                AND ws.sense_order = ?
                AND ws.definition_english = ?
            LIMIT 1
        """, (headword, reading, sense_order, definition))

        result = current_cursor.fetchone()

        if result:
            sense_id = result[0]
            matched += 1

            # 检查是否已存在相同的例句
            current_cursor.execute("""
                SELECT COUNT(*) FROM example_sentences
                WHERE sense_id = ? AND japanese_text = ? AND example_order = ?
            """, (sense_id, jp_text, ex_order))

            if current_cursor.fetchone()[0] == 0:
                # 插入例句
                current_cursor.execute("""
                    INSERT INTO example_sentences
                    (sense_id, japanese_text, english_translation, example_order)
                    VALUES (?, ?, ?, ?)
                """, (sense_id, jp_text, en_text, ex_order))
                inserted += 1
        else:
            unmatched += 1
            if unmatched <= 10:  # 只显示前10个未匹配的
                print(f"   ⚠️  未匹配: {headword} ({reading}) - {definition[:50]}...")

    # 提交更改
    current_conn.commit()

    print(f"\n" + "="*60)
    print(f"✅ 恢复完成！")
    print(f"="*60)
    print(f"   总例句数: {len(backup_examples)}")
    print(f"   匹配成功: {matched} ({matched*100/len(backup_examples):.1f}%)")
    print(f"   插入例句: {inserted}")
    print(f"   未匹配: {unmatched} ({unmatched*100/len(backup_examples):.1f}%)")
    print(f"="*60)

    # 验证结果
    current_cursor.execute("SELECT COUNT(*) FROM example_sentences")
    total = current_cursor.fetchone()[0]
    print(f"\n📊 当前数据库例句总数: {total}")

    # 关闭连接
    current_conn.close()
    backup_conn.close()

if __name__ == "__main__":
    try:
        restore_examples()
    except Exception as e:
        print(f"❌ 错误: {e}")
        sys.exit(1)
