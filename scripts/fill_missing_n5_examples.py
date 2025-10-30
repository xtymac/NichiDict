#!/usr/bin/env python3
"""
为缺失例句的N5 sense补充生成例句
使用OpenAI GPT-4o-mini，确保每个sense至少有1条例句
"""

import sqlite3
import json
import os
import sys
import time
from datetime import datetime
from typing import Dict, List, Tuple
from openai import OpenAI

# ==================== 配置 ====================

DB_PATH = "../NichiDict/Resources/seed.sqlite"

# OpenAI API配置
API_KEY = os.environ.get('OPENAI_API_KEY')
if not API_KEY:
    print("❌ 错误: 请设置 OPENAI_API_KEY 环境变量")
    sys.exit(1)
MODEL_NAME = "gpt-4o-mini"
BATCH_SIZE = 5
EXAMPLES_PER_SENSE = 2

# ==================== 数据库操作 ====================

def get_n5_senses_without_examples() -> List[Tuple]:
    """获取N5级别中没有例句的sense"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            s.id as sense_id,
            d.headword,
            d.reading_hiragana,
            d.reading_romaji,
            s.definition_english,
            COALESCE(s.definition_chinese_simplified, '') as definition_chinese
        FROM word_senses s
        JOIN dictionary_entries d ON s.entry_id = d.id
        WHERE d.jlpt_level = 'N5'
          AND s.id NOT IN (SELECT DISTINCT sense_id FROM example_sentences WHERE sense_id IS NOT NULL)
        ORDER BY d.frequency_rank DESC NULLS LAST, d.id
    """)

    senses = cursor.fetchall()
    conn.close()
    return senses

def insert_examples(sense_id: int, examples: List[Dict]) -> int:
    """插入例句到数据库"""
    if not examples:
        return 0

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    inserted = 0

    try:
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
            inserted += 1

        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f"    ❌ 数据库插入失败: {e}")
    finally:
        conn.close()

    return inserted

# ==================== OpenAI 生成 ====================

def init_openai():
    """初始化OpenAI客户端"""
    return OpenAI(api_key=API_KEY)

def generate_examples_for_batch(client, batch: List[Tuple]) -> Dict[int, List[Dict]]:
    """为一批sense生成例句"""
    results = {}

    for sense in batch:
        sense_id, headword, reading, romaji, def_en, def_cn = sense

        prompt = f"""为日语初学者（JLPT N5级别）生成{EXAMPLES_PER_SENSE}个简单的例句。

词汇信息：
- 单词：{headword}
- 读音：{reading} ({romaji})
- 英文：{def_en}
{f'- 中文：{def_cn}' if def_cn else ''}

要求：
1. 生成{EXAMPLES_PER_SENSE}个非常简单的日语句子（15-25个字符）
2. 必须使用N5级别的语法（现在时、过去时、です/ます体）
3. 避免复杂的语法结构（不要用ている、ように、ために等）
4. 使用日常生活场景
5. 必须包含这个词汇：{headword}

返回JSON格式：
{{"examples":[
  {{"japanese":"简单句子1", "chinese":"中文翻译1", "english":"英文翻译1"}},
  {{"japanese":"简单句子2", "chinese":"中文翻译2", "english":"英文翻译2"}}
]}}

只返回JSON，不要其他内容。"""

        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=[
                    {"role": "system", "content": "You are a Japanese language expert specializing in beginner-level (N5) content."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.7,
                max_tokens=400
            )

            response_text = response.choices[0].message.content.strip()

            # 清理JSON
            if response_text.startswith('```'):
                lines = response_text.split('\n')
                response_text = '\n'.join(lines[1:-1]) if len(lines) > 2 else response_text

            data = json.loads(response_text)
            examples = data.get("examples", [])

            if len(examples) == EXAMPLES_PER_SENSE:
                results[sense_id] = examples
                print(f"    ✅ {headword} ({reading}): {len(examples)} 例句")
            else:
                print(f"    ⚠️  {headword}: 返回{len(examples)}个例句（预期{EXAMPLES_PER_SENSE}）")
                if examples:  # 即使数量不对，也保存
                    results[sense_id] = examples

        except json.JSONDecodeError as e:
            print(f"    ❌ {headword}: JSON解析失败 - {e}")
        except Exception as e:
            print(f"    ❌ {headword}: 生成失败 - {str(e)[:100]}")

        time.sleep(0.2)

    return results

# ==================== 主流程 ====================

def main():
    print("=" * 60)
    print("N5 缺失例句补充脚本（OpenAI GPT-4o-mini）")
    print("=" * 60)

    if not os.path.exists(DB_PATH):
        print(f"❌ 数据库不存在: {DB_PATH}")
        sys.exit(1)

    # 获取缺失例句的sense
    print("\n🔍 查询缺失例句的N5 sense...")
    senses = get_n5_senses_without_examples()

    if not senses:
        print("\n🎉 所有N5 sense都已有例句！")
        return

    total_senses = len(senses)

    # 显示任务信息
    print(f"\n📊 任务状态：")
    print(f"   - 缺失例句的sense：{total_senses}")
    print(f"   - 需要生成例句：{total_senses * EXAMPLES_PER_SENSE} 条")

    # 估算成本
    input_tokens = total_senses * 200
    output_tokens = total_senses * 300
    cost = (input_tokens / 1_000_000 * 0.150) + (output_tokens / 1_000_000 * 0.600)
    print(f"   - 预计成本：${cost:.2f} USD")
    print(f"   - 预计时间：{total_senses * 0.3 / 60:.1f} 分钟")

    # 确认
    print(f"\n⚠️  准备开始生成")
    print(f"   按 Ctrl+C 取消，或等待 3 秒自动开始...")
    time.sleep(3)

    # 初始化OpenAI
    print("\n🤖 初始化 OpenAI API...")
    client = init_openai()

    # 批量处理
    print("\n🔄 开始生成例句...\n")

    num_batches = (total_senses + BATCH_SIZE - 1) // BATCH_SIZE
    total_generated = 0

    for i in range(0, total_senses, BATCH_SIZE):
        batch = senses[i:i + BATCH_SIZE]
        batch_num = i // BATCH_SIZE + 1

        print(f"📦 批次 {batch_num}/{num_batches} (sense {i+1}-{min(i+BATCH_SIZE, total_senses)}/{total_senses})")

        # 生成例句
        examples_by_sense = generate_examples_for_batch(client, batch)

        # 保存到数据库
        batch_examples = 0
        for sense_id, examples in examples_by_sense.items():
            inserted = insert_examples(sense_id, examples)
            if inserted > 0:
                batch_examples += inserted

        total_generated += batch_examples

        # 显示进度
        completion_pct = (i + len(batch)) / total_senses * 100
        print(f"   💾 已保存 {len(examples_by_sense)} 个sense的例句")
        print(f"   📈 总进度: {completion_pct:.1f}% ({i + len(batch)}/{total_senses})")
        print()

    # 完成
    print("=" * 60)
    print("🎉 缺失例句补充完成！")
    print("=" * 60)
    print(f"✅ 总共生成：{total_generated} 条例句")
    print(f"✅ 覆盖sense：{total_senses} 个")
    print("=" * 60)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断")
        sys.exit(0)
    except Exception as e:
        print(f"\n\n❌ 发生错误: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)