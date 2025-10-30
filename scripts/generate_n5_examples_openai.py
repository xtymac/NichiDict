#!/usr/bin/env python3
"""
N5例句生成脚本（OpenAI GPT-4o-mini）
支持断点续传，从上次进度继续
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
PROGRESS_FILE = ".n5_progress.json"

# OpenAI API配置
API_KEY = os.environ.get('OPENAI_API_KEY')
if not API_KEY:
    print("❌ 错误: 请设置 OPENAI_API_KEY 环境变量")
    sys.exit(1)
MODEL_NAME = "gpt-4o-mini"
BATCH_SIZE = 5  # 每批处理5个sense
EXAMPLES_PER_SENSE = 2  # 每个sense生成2条例句

# ==================== 进度管理 ====================

def load_progress() -> Dict:
    """加载进度"""
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {
        "completed_sense_ids": [],
        "total_senses": 0,
        "total_examples_generated": 0,
        "started_at": None
    }

def save_progress(progress: Dict):
    """保存进度"""
    with open(PROGRESS_FILE, 'w', encoding='utf-8') as f:
        json.dump(progress, f, indent=2, ensure_ascii=False)

# ==================== 数据库操作 ====================

def get_n5_senses_without_examples(completed_ids: List[int]) -> List[Tuple]:
    """获取N5级别中没有例句的sense"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    completed_ids_str = ','.join(map(str, completed_ids)) if completed_ids else '0'

    cursor.execute(f"""
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
          AND s.id NOT IN ({completed_ids_str})
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

        # 构建提示词（N5级别）
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

            # 清理JSON（移除markdown代码块标记）
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

        except json.JSONDecodeError as e:
            print(f"    ❌ {headword}: JSON解析失败 - {e}")
        except Exception as e:
            print(f"    ❌ {headword}: 生成失败 - {str(e)[:100]}")

        # 短暂延迟
        time.sleep(0.2)

    return results

# ==================== 主流程 ====================

def main():
    print("=" * 60)
    print("📚 N5例句生成脚本（OpenAI GPT-4o-mini）")
    print("=" * 60)

    if not os.path.exists(DB_PATH):
        print(f"❌ 数据库不存在: {DB_PATH}")
        sys.exit(1)

    # 加载进度
    progress = load_progress()

    if not progress["started_at"]:
        progress["started_at"] = datetime.now().isoformat()

    # 获取待处理的sense
    print("\n🔍 查询N5词条...")
    senses = get_n5_senses_without_examples(progress["completed_sense_ids"])

    if not senses:
        print("\n🎉 所有N5词条都已有例句！")
        return

    total_senses = len(senses)
    progress["total_senses"] = total_senses

    # 显示任务信息
    print(f"\n📊 任务状态：")
    print(f"   - 总sense数：{progress.get('total_senses', total_senses)}")
    print(f"   - 已完成：{len(progress['completed_sense_ids'])}")
    print(f"   - 待处理：{total_senses}")
    print(f"   - 预计生成：{total_senses * EXAMPLES_PER_SENSE} 条例句")

    # 估算成本
    input_tokens = total_senses * 200
    output_tokens = total_senses * 300
    cost = (input_tokens / 1_000_000 * 0.150) + (output_tokens / 1_000_000 * 0.600)
    print(f"   - 预计成本：${cost:.2f} USD")
    print(f"   - 预计时间：{total_senses * (BATCH_SIZE * 0.5 + 0.2) / 60:.1f} 分钟")

    # 确认
    print(f"\n⚠️  准备开始生成")
    print(f"   按 Ctrl+C 取消，或等�� 3 秒自动开始...")
    time.sleep(3)

    # 初始化OpenAI
    print("\n🤖 初始化 OpenAI API...")
    client = init_openai()

    # 批量处理
    print("\n🔄 开始生成例句...\n")

    num_batches = (total_senses + BATCH_SIZE - 1) // BATCH_SIZE

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
                progress["completed_sense_ids"].append(sense_id)
                progress["total_examples_generated"] += inserted
                batch_examples += inserted

        # 保存进度
        save_progress(progress)

        # 显示进度
        completion_pct = len(progress["completed_sense_ids"]) / progress["total_senses"] * 100
        print(f"   💾 已保存 {len(examples_by_sense)} 个词条的例句")
        print(f"   📈 总进度: {completion_pct:.1f}% ({len(progress['completed_sense_ids'])}/{progress['total_senses']})")
        print()

    # 完成
    print("=" * 60)
    print("🎉 N5例句生成完成！")
    print("=" * 60)
    print(f"✅ 总共生成：{progress['total_examples_generated']} 条例句")
    print(f"✅ 覆盖词条：{len(progress['completed_sense_ids'])} 个sense")
    elapsed = (datetime.now() - datetime.fromisoformat(progress["started_at"])).total_seconds() / 3600
    print(f"✅ 总用时：{elapsed:.1f} 小时")
    print("=" * 60)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断，进度已保存")
        sys.exit(0)
    except Exception as e:
        print(f"\n\n❌ 发生错误: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)