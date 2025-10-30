#!/usr/bin/env python3
"""
批量翻译例句脚本
将数据库中的所有日文例句翻译成中文
使用 Gemini 2.5 Flash API
"""

import sqlite3
import os
import sys
import time
import json
from typing import List, Tuple
import google.generativeai as genai

# Gemini API 配置
API_KEY = "AIzaSyAn-0ipZvmCOl19nPEp8JqR620peM87mBY"
MODEL_NAME = "gemini-2.5-flash"

# 数据库路径
DB_PATHS = [
    "../NichiDict/Resources/seed.sqlite",
    "../data/dictionary_full_multilingual.sqlite"
]

# 批量处理参数
BATCH_SIZE = 50  # 每批翻译的例句数量
DELAY_BETWEEN_BATCHES = 2  # 批次间延迟（秒）

def init_gemini():
    """初始化 Gemini API"""
    genai.configure(api_key=API_KEY)
    model = genai.GenerativeModel(MODEL_NAME)
    return model

def get_examples_to_translate(db_path: str) -> List[Tuple[int, str, str]]:
    """
    获取需要翻译的例句
    返回: [(id, japanese_text, english_translation), ...]
    """
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 只获取还没有中文翻译的例句
    cursor.execute("""
        SELECT id, japanese_text, english_translation
        FROM example_sentences
        WHERE chinese_translation IS NULL OR chinese_translation = ''
        ORDER BY id
    """)

    examples = cursor.fetchall()
    conn.close()

    return examples

def translate_batch(model, examples: List[Tuple[int, str, str]]) -> List[Tuple[int, str]]:
    """
    批量翻译一组例句
    返回: [(id, chinese_translation), ...]
    """
    if not examples:
        return []

    # 构建批量翻译提示
    prompt = """请将以下日文例句翻译成简体中文。要求：
1. 翻译要准确、自然、符合中文表达习惯
2. 保持原句的语气和含义
3. 每行一个翻译，与输入顺序对应
4. 只输出中文翻译，不要编号或额外说明

日文例句：
"""

    for idx, (_, japanese, _) in enumerate(examples, 1):
        prompt += f"{idx}. {japanese}\n"

    try:
        # 调用 Gemini API
        response = model.generate_content(prompt)
        translations = response.text.strip().split('\n')

        # 清理翻译结果（移除可能的编号）
        cleaned_translations = []
        for trans in translations:
            # 移除开头的数字编号
            trans = trans.strip()
            if trans and trans[0].isdigit():
                # 找到第一个非数字、非点、非空格的字符
                for i, c in enumerate(trans):
                    if not (c.isdigit() or c in '. 、。'):
                        trans = trans[i:]
                        break
            cleaned_translations.append(trans.strip())

        # 匹配翻译结果与原句
        results = []
        for i, (ex_id, japanese, english) in enumerate(examples):
            if i < len(cleaned_translations):
                chinese = cleaned_translations[i]
                results.append((ex_id, chinese))
            else:
                # 如果翻译结果不够，使用英文作为后备
                print(f"⚠️  警告: 例句 {ex_id} 没有翻译结果，跳过")

        return results

    except Exception as e:
        print(f"❌ 翻译批次失败: {e}")
        return []

def update_translations(db_path: str, translations: List[Tuple[int, str]]):
    """
    更新数据库中的中文翻译
    """
    if not translations:
        return

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        for ex_id, chinese in translations:
            cursor.execute("""
                UPDATE example_sentences
                SET chinese_translation = ?
                WHERE id = ?
            """, (chinese, ex_id))

        conn.commit()
        print(f"✅ 成功更新 {len(translations)} 条翻译")

    except Exception as e:
        conn.rollback()
        print(f"❌ 更新数据库失败: {e}")
    finally:
        conn.close()

def translate_database(db_path: str):
    """
    翻译一个数据库中的所有例句
    """
    if not os.path.exists(db_path):
        print(f"⚠️  数据库不存在: {db_path}")
        return

    print(f"\n{'='*60}")
    print(f"开始处理数据库: {db_path}")
    print(f"{'='*60}")

    # 获取需要翻译的例句
    examples = get_examples_to_translate(db_path)
    total = len(examples)

    if total == 0:
        print("✅ 所有例句都已有中文翻译")
        return

    print(f"📊 需要翻译的例句数量: {total}")

    # 初始化 Gemini
    model = init_gemini()

    # 批量处理
    translated_count = 0
    batch_num = 0

    for i in range(0, total, BATCH_SIZE):
        batch = examples[i:i + BATCH_SIZE]
        batch_num += 1

        print(f"\n🔄 处理批次 {batch_num}/{(total + BATCH_SIZE - 1) // BATCH_SIZE} "
              f"(例句 {i+1}-{min(i+BATCH_SIZE, total)}/{total})")

        # 翻译批次
        translations = translate_batch(model, batch)

        # 更新数据库
        if translations:
            update_translations(db_path, translations)
            translated_count += len(translations)

        # 显示进度
        progress = (i + len(batch)) / total * 100
        print(f"📈 进度: {progress:.1f}% ({translated_count}/{total})")

        # 批次间延迟，避免 API 限流
        if i + BATCH_SIZE < total:
            print(f"⏳ 等待 {DELAY_BETWEEN_BATCHES} 秒...")
            time.sleep(DELAY_BETWEEN_BATCHES)

    print(f"\n✅ 数据库处理完成！共翻译 {translated_count} 条例句")

def main():
    """主函数"""
    print("=" * 60)
    print("📚 例句中文翻译批处理脚本")
    print("=" * 60)
    print(f"使用模型: {MODEL_NAME}")
    print(f"批次大小: {BATCH_SIZE}")
    print()

    # 切换到脚本目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    # 处理所有数据库
    for db_path in DB_PATHS:
        translate_database(db_path)

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
