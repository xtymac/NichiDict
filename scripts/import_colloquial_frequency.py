#!/usr/bin/env python3
"""
Import colloquial phrase frequency data to database.

This script adds frequency data for common Japanese colloquial expressions
that are missing from Wikipedia and JMdict frequency data.

Usage:
    python3 scripts/import_colloquial_frequency.py
"""

import sqlite3
import json
import sys
from pathlib import Path

def import_colloquial_frequencies(db_path: Path, freq_file: Path):
    """
    Import colloquial phrase frequencies to database.

    Args:
        db_path: Path to database
        freq_file: Path to colloquial frequencies JSON file
    """
    print("=" * 60)
    print("口语短语词频导入")
    print("=" * 60)

    # Load frequency data
    print(f"\n📖 读取口语词频数据: {freq_file}")
    with open(freq_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    phrases = data['phrases']
    metadata = data['metadata']

    print(f"   数据来源: {metadata['source']}")
    print(f"   描述: {metadata['description']}")
    print(f"   短语数量: {len(phrases)}")

    # Connect to database
    print(f"\n💾 连接数据库: {db_path}")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Statistics
    cursor.execute('SELECT COUNT(*) FROM dictionary_entries')
    total_entries = cursor.fetchone()[0]

    cursor.execute('SELECT COUNT(*) FROM dictionary_entries WHERE frequency_rank IS NOT NULL')
    existing_freq = cursor.fetchone()[0]

    print(f"\n📊 数据库统计:")
    print(f"   总词条: {total_entries:,}")
    print(f"   已有词频: {existing_freq:,} ({existing_freq*100/total_entries:.1f}%)")

    # Import frequencies
    print(f"\n🔄 开始导入...")
    updated = 0
    new_freq = 0
    not_found = []

    for phrase in phrases:
        headword = phrase['headword']
        reading = phrase['reading']
        rank = phrase['rank']
        category = phrase['category']
        note = phrase.get('note', '')

        # Find matching entry
        cursor.execute('''
            SELECT id, frequency_rank
            FROM dictionary_entries
            WHERE headword = ? AND reading_hiragana = ?
            LIMIT 1
        ''', (headword, reading))

        result = cursor.fetchone()

        if not result:
            not_found.append(f"{headword} ({reading})")
            print(f"   ⚠️  未找到: {headword} ({reading})")
            continue

        entry_id, current_rank = result

        # Use minimum rank (higher priority)
        if current_rank is None:
            new_rank = rank
            new_freq += 1
            status = "新增"
        else:
            new_rank = min(current_rank, rank)
            status = "更新" if new_rank != current_rank else "保持"

        # Update frequency
        cursor.execute('''
            UPDATE dictionary_entries
            SET frequency_rank = ?
            WHERE id = ?
        ''', (new_rank, entry_id))

        print(f"   ✅ {status}: {headword} ({reading}) → rank {new_rank} ({category})")
        print(f"      {note}")
        updated += 1

    conn.commit()

    # Get final statistics
    cursor.execute('SELECT COUNT(*) FROM dictionary_entries WHERE frequency_rank IS NOT NULL')
    final_freq = cursor.fetchone()[0]

    conn.close()

    # Summary
    print(f"\n" + "=" * 60)
    print("✅ 导入完成！")
    print("=" * 60)
    print(f"   处理短语: {len(phrases)}")
    print(f"   成功更新: {updated}")
    print(f"   新增词频: {new_freq}")
    print(f"   未找到: {len(not_found)}")

    if not_found:
        print(f"\n⚠️  以下短语在词典中未找到:")
        for phrase in not_found:
            print(f"   - {phrase}")

    print(f"\n📊 最终统计:")
    print(f"   有词频的词条: {final_freq:,} ({final_freq*100/total_entries:.1f}%)")
    print(f"   改进: +{final_freq - existing_freq:,} (+{(final_freq - existing_freq)*100/total_entries:.2f}%)")

    print(f"\n🎯 下一步:")
    print("   1. 重新构建应用: xcodebuild build")
    print("   2. 在模拟器中测试搜索效果")
    print("   3. 验证常用短语是否正确分组")

def main():
    # Paths
    script_dir = Path(__file__).parent
    db_path = script_dir.parent / "NichiDict" / "Resources" / "seed.sqlite"
    freq_file = script_dir / "colloquial_phrases_frequency.json"

    # Validate paths
    if not db_path.exists():
        print(f"❌ 数据库未找到: {db_path}")
        sys.exit(1)

    if not freq_file.exists():
        print(f"❌ 词频文件未找到: {freq_file}")
        sys.exit(1)

    # Create backup
    backup_path = db_path.with_suffix('.sqlite.colloquial_backup')
    print(f"\n💾 创建备份: {backup_path.name}")
    import shutil
    shutil.copy2(db_path, backup_path)
    print("   备份完成")

    # Import frequencies
    import_colloquial_frequencies(db_path, freq_file)

if __name__ == '__main__':
    main()
