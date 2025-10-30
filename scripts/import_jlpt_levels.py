#!/usr/bin/env python3
"""
导入JLPT级别数据到数据库
从 jamsinclair/open-anki-jlpt-decks 获取JLPT词汇数据
"""

import sqlite3
import requests
import csv
from io import StringIO
from typing import Dict, Set

# 数据库路径
DB_PATH = "../NichiDict/Resources/seed.sqlite"

# JLPT词汇CSV URLs
JLPT_URLS = {
    "N5": "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/n5.csv",
    "N4": "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/n4.csv",
    "N3": "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/n3.csv",
    "N2": "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/n2.csv",
    "N1": "https://raw.githubusercontent.com/jamsinclair/open-anki-jlpt-decks/main/src/n1.csv",
}


def download_jlpt_vocab(level: str) -> list:
    """下载指定JLPT级别的词汇CSV"""
    url = JLPT_URLS[level]
    print(f"📥 下载 JLPT {level} 词汇数据...")

    response = requests.get(url)
    response.raise_for_status()

    # 解析CSV
    csv_data = StringIO(response.text)
    reader = csv.DictReader(csv_data)

    vocab_list = []
    for row in reader:
        # CSV格式: expression,reading,meaning,tags,guid
        expression = row['expression'].strip()
        reading = row['reading'].strip()

        # 清理expression，可能包含多个形式（用;分隔）
        expressions = [e.strip() for e in expression.split(';')]

        vocab_list.append({
            'expressions': expressions,
            'reading': reading,
            'level': level
        })

    print(f"   ✅ 下载了 {len(vocab_list)} 个词条")
    return vocab_list


def build_jlpt_map() -> Dict[str, str]:
    """
    构建JLPT词汇映射表
    返回: {headword: jlpt_level}
    如果一个词出现在多个级别，保留最低级别（N5最低，N1最高）
    """
    jlpt_map = {}
    level_priority = {"N5": 5, "N4": 4, "N3": 3, "N2": 2, "N1": 1}

    for level in ["N5", "N4", "N3", "N2", "N1"]:
        vocab_list = download_jlpt_vocab(level)

        for item in vocab_list:
            for expression in item['expressions']:
                # 如果词条未记录，或当前级别更基础，则更新
                if expression not in jlpt_map or level_priority[level] > level_priority[jlpt_map[expression]]:
                    jlpt_map[expression] = level

    print(f"\n📊 总共收集了 {len(jlpt_map)} 个独特词条")
    return jlpt_map


def update_database(jlpt_map: Dict[str, str]):
    """更新数据库中的JLPT级别"""
    print(f"\n💾 连接数据库: {DB_PATH}")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 统计
    total_entries = cursor.execute("SELECT COUNT(*) FROM dictionary_entries").fetchone()[0]
    print(f"📊 数据库中总词条数: {total_entries:,}")

    updated_count = 0
    not_found_count = 0

    print(f"\n🔄 开始更新JLPT级别...")

    # 遍历所有词条
    cursor.execute("SELECT id, headword, reading_hiragana FROM dictionary_entries")
    entries = cursor.fetchall()

    for entry_id, headword, reading in entries:
        jlpt_level = None

        # 首先尝试完全匹配headword
        if headword in jlpt_map:
            jlpt_level = jlpt_map[headword]
        # 其次尝试匹配reading
        elif reading and reading in jlpt_map:
            jlpt_level = jlpt_map[reading]

        if jlpt_level:
            cursor.execute(
                "UPDATE dictionary_entries SET jlpt_level = ? WHERE id = ?",
                (jlpt_level, entry_id)
            )
            updated_count += 1

            if updated_count % 100 == 0:
                print(f"   进度: {updated_count} 个词条已更新...")
        else:
            not_found_count += 1

    conn.commit()
    conn.close()

    print(f"\n✅ 更新完成!")
    print(f"   ✅ 成功更新: {updated_count:,} 个词条")
    print(f"   ⚠️  未找到JLPT级别: {not_found_count:,} 个词条")
    print(f"   📊 覆盖率: {updated_count / total_entries * 100:.2f}%")

    # 显示各级别统计
    print(f"\n📊 各级别词条统计:")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    for level in ["N5", "N4", "N3", "N2", "N1"]:
        count = cursor.execute(
            "SELECT COUNT(*) FROM dictionary_entries WHERE jlpt_level = ?",
            (level,)
        ).fetchone()[0]
        print(f"   {level}: {count:,} 个词条")
    conn.close()


def main():
    print("=" * 60)
    print("📚 JLPT级别数据导入工具")
    print("=" * 60)

    try:
        # 下载并构建JLPT词汇映射
        jlpt_map = build_jlpt_map()

        # 更新数据库
        update_database(jlpt_map)

        print("\n🎉 所有操作完成!")

    except Exception as e:
        print(f"\n❌ 错误: {e}")
        raise


if __name__ == "__main__":
    main()
