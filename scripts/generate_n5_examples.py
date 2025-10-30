#!/usr/bin/env python3
"""
N5例句生成脚本（Gemini 2.5 Flash-Lite 免费版）
使用断点续传 + 自动提醒功能
"""

import sqlite3
import json
import os
import sys
import time
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
import subprocess

try:
    import google.generativeai as genai
except ImportError:
    print("❌ 请先安装 Google Generative AI SDK:")
    print("")
    print("如果你在虚拟环境中：")
    print("   python -m pip install google-generativeai")
    print("")
    print("或者使用虚拟环境的Python运行脚本：")
    print("   python generate_n5_examples.py  (不要用python3)")
    print("")
    print("当前Python路径:", sys.executable)
    sys.exit(1)

# ==================== 配置 ====================

DB_PATH = "../NichiDict/Resources/seed.sqlite"
PROGRESS_FILE = ".n5_progress.json"
REMINDER_FILE = os.path.expanduser("~/Desktop/⚠️ 明天继续生成N5例句.txt")

# Gemini API配置
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', '')
if not GEMINI_API_KEY:
    print("⚠️  警告: 未设置GEMINI_API_KEY环境变量")
    print("   请运行: export GEMINI_API_KEY='your-api-key'")
    print("   或者在脚本中直接设置")
    # GEMINI_API_KEY = "your-api-key-here"  # 取消注释并填写

MODEL_NAME = "gemini-2.0-flash-exp"  # 使用稳定版本，配额更高
BATCH_SIZE = 5  # 每批处理5个sense（降低以确保免费额度）
MAX_DAILY_REQUESTS = 500  # 免费额度限制
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
        "requests_today": 0,
        "last_run_date": None,
        "started_at": None
    }


def save_progress(progress: Dict):
    """保存进度"""
    with open(PROGRESS_FILE, 'w', encoding='utf-8') as f:
        json.dump(progress, f, indent=2, ensure_ascii=False)


def reset_daily_requests(progress: Dict) -> Dict:
    """重置每日请求计数（如果是新的一天）"""
    today = datetime.now().strftime("%Y-%m-%d")
    if progress["last_run_date"] != today:
        print(f"🌅 新的一天开始！重置请求计数")
        progress["requests_today"] = 0
        progress["last_run_date"] = today
    return progress


# ==================== 数据库操作 ====================

def get_n5_senses_without_examples(completed_ids: List[int]) -> List[Tuple]:
    """获取N5级别中没有例句的sense"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 构建已完成ID的SQL片段
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
          AND s.id NOT IN (SELECT DISTINCT sense_id FROM example_sentences)
          AND s.id NOT IN ({completed_ids_str})
        ORDER BY d.id
    """)

    results = cursor.fetchall()
    conn.close()
    return results


def insert_examples(sense_id: int, examples: List[Dict]):
    """插入例句到数据库"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

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

    conn.commit()
    conn.close()


# ==================== Gemini API ====================

def init_gemini():
    """初始化Gemini API"""
    genai.configure(api_key=GEMINI_API_KEY)
    return genai.GenerativeModel(MODEL_NAME)


def generate_n5_examples(model, batch: List[Tuple]) -> Dict[int, List[Dict]]:
    """
    为一批sense生成N5级别的例句
    返回: {sense_id: [example1, example2]}
    """
    results = {}

    for sense in batch:
        sense_id, headword, reading, romaji, def_en, def_cn = sense

        # 构建提示词（强调N5级别和简单性）
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
            response = model.generate_content(prompt)
            response_text = response.text.strip()

            # 清理JSON（移除markdown代码块标记）
            if response_text.startswith('```'):
                lines = response_text.split('\n')
                response_text = '\n'.join(lines[1:-1])

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
            print(f"    ❌ {headword}: 生成失败 - {e}")

        # 短暂延迟，避免触发速率限制
        time.sleep(8.0)

    return results


# ==================== 提醒功能 ====================

def create_reminder_file(progress: Dict):
    """创建桌面提醒文件"""
    remaining = progress["total_senses"] - len(progress["completed_sense_ids"])
    completion_pct = len(progress["completed_sense_ids"]) / progress["total_senses"] * 100

    content = f"""
{'='*60}
⚠️  N5例句生成任务 - 需要继续！
{'='*60}

📊 当前进度：
   - 已完成：{len(progress["completed_sense_ids"])} / {progress["total_senses"]} ({completion_pct:.1f}%)
   - 剩余：{remaining} 个sense
   - 已生成例句：{progress["total_examples_generated"]} 条

📅 下次运行：
   明天（或稍后）在终端运行：

   cd /Users/mac/Maku\\ Box\\ Dropbox/Maku\\ Box/Project/NichiDict/scripts
   python3 generate_n5_examples.py

⏱️  预计剩余时间：
   约 {remaining // (BATCH_SIZE * MAX_DAILY_REQUESTS) + 1} 天

💡 提示：
   - 脚本会自动从上次进度继续
   - 免费额度每天自动刷新
   - 无需担心数据丢失

{'='*60}
创建时间：{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
{'='*60}
"""

    with open(REMINDER_FILE, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f"\n📝 已创建桌面提醒文件：{REMINDER_FILE}")


def send_macos_notification(title: str, message: str):
    """发送macOS系统通知"""
    try:
        script = f'''
        display notification "{message}" with title "{title}" sound name "default"
        '''
        subprocess.run(['osascript', '-e', script], check=False)
    except Exception as e:
        print(f"⚠️  无法发送系统通知: {e}")


def print_completion_banner(progress: Dict):
    """打印完成横幅"""
    if len(progress["completed_sense_ids"]) >= progress["total_senses"]:
        # 全部完成
        print("\n" + "="*60)
        print("🎉 恭喜！N5例句生成任务完成！")
        print("="*60)
        print(f"✅ 总共生成：{progress['total_examples_generated']} 条例句")
        print(f"✅ 覆盖词条：{progress['total_senses']} 个sense")
        print(f"✅ 总用时：{(datetime.now() - datetime.fromisoformat(progress['started_at'])).total_seconds() / 3600:.1f} 小时")
        print("="*60)

        # 清理进度文件
        if os.path.exists(PROGRESS_FILE):
            os.remove(PROGRESS_FILE)
        if os.path.exists(REMINDER_FILE):
            os.remove(REMINDER_FILE)

        send_macos_notification("N5例句生成完成", f"成功生成{progress['total_examples_generated']}条例句！")

    else:
        # 今日额度用完
        remaining = progress["total_senses"] - len(progress["completed_sense_ids"])
        completion_pct = len(progress["completed_sense_ids"]) / progress["total_senses"] * 100

        print("\n" + "="*60)
        print(f"✅ 今日任务完成！已生成 {len(progress['completed_sense_ids'])}/{progress['total_senses']} ({completion_pct:.1f}%)")
        print("="*60)
        print(f"📊 进度详情：")
        print(f"   - 剩余sense：{remaining}")
        print(f"   - 已生成例句：{progress['total_examples_generated']} 条")
        print(f"   - 今日请求数：{progress['requests_today']}/{MAX_DAILY_REQUESTS}")
        print(f"\n📅 明天继续：")
        print(f"   python3 generate_n5_examples.py")
        print(f"\n💡 脚本会自动从进度继续，无需担心！")
        print("="*60)

        create_reminder_file(progress)
        send_macos_notification(
            "N5例句生成进度",
            f"今日完成 {completion_pct:.1f}%，剩余{remaining}个词条"
        )


# ==================== 主函数 ====================

def main():
    print("="*60)
    print("📚 N5例句生成脚本（Gemini 2.5 Flash-Lite 免费版）")
    print("="*60)

    # 检查API密钥
    if not GEMINI_API_KEY:
        print("❌ 错误：未设置GEMINI_API_KEY")
        print("请运行: export GEMINI_API_KEY='your-api-key'")
        sys.exit(1)

    # 加载进度
    progress = load_progress()
    progress = reset_daily_requests(progress)

    # 获取待处理的sense
    senses = get_n5_senses_without_examples(progress["completed_sense_ids"])

    if progress["total_senses"] == 0:
        progress["total_senses"] = len(senses) + len(progress["completed_sense_ids"])
        progress["started_at"] = datetime.now().isoformat()

    if not senses:
        print("\n🎉 所有N5词条都已有例句！")
        if os.path.exists(PROGRESS_FILE):
            os.remove(PROGRESS_FILE)
        if os.path.exists(REMINDER_FILE):
            os.remove(REMINDER_FILE)
        return

    print(f"\n📊 任务状态：")
    print(f"   - 总sense数：{progress['total_senses']}")
    print(f"   - 已完成：{len(progress['completed_sense_ids'])}")
    print(f"   - 待处理：{len(senses)}")
    print(f"   - 今日已用额度：{progress['requests_today']}/{MAX_DAILY_REQUESTS}")

    # 检查今日额度
    remaining_requests = MAX_DAILY_REQUESTS - progress["requests_today"]
    if remaining_requests <= 0:
        print(f"\n⚠️  今日免费额度已用完（{progress['requests_today']}/{MAX_DAILY_REQUESTS}）")
        print(f"   请明天继续运行相同命令")
        create_reminder_file(progress)
        return

    # 计算今天能处理多少
    max_senses_today = remaining_requests * BATCH_SIZE
    senses_to_process = min(len(senses), max_senses_today)

    print(f"   - 今日可处理：{senses_to_process} 个sense")
    print(f"   - 预计时间：{senses_to_process / BATCH_SIZE * 0.5 / 60:.1f} 分钟")

    print(f"\n⚠️  准备开始生成，将使用 {senses_to_process // BATCH_SIZE} 次API请求")
    print("   按 Ctrl+C 取消，或等待 3 秒自动开始...")

    try:
        time.sleep(3)
    except KeyboardInterrupt:
        print("\n\n❌ 用户取消")
        return

    # 初始化Gemini
    print(f"\n🤖 初始化 Gemini 2.5 Flash-Lite...")
    model = init_gemini()

    # 批量处理
    total_batches = (senses_to_process + BATCH_SIZE - 1) // BATCH_SIZE
    processed = 0

    print(f"\n🔄 开始生成例句...\n")

    for i in range(0, senses_to_process, BATCH_SIZE):
        batch_num = i // BATCH_SIZE + 1
        batch = senses[i:i+BATCH_SIZE]

        print(f"📦 批次 {batch_num}/{total_batches} (sense {i+1}-{min(i+BATCH_SIZE, senses_to_process)}/{senses_to_process})")

        # 生成例句
        results = generate_n5_examples(model, batch)

        # 插入数据库
        for sense_id, examples in results.items():
            insert_examples(sense_id, examples)
            progress["completed_sense_ids"].append(sense_id)
            progress["total_examples_generated"] += len(examples)

        progress["requests_today"] += 1
        processed += len(batch)

        # 保存进度
        save_progress(progress)

        # 显示进度
        completion_pct = len(progress["completed_sense_ids"]) / progress["total_senses"] * 100
        print(f"   💾 已保存 {len(results)} 个词条的例句")
        print(f"   📈 总进度: {completion_pct:.1f}% ({len(progress['completed_sense_ids'])}/{progress['total_senses']})")
        print()

        # 检查是否达到今日限制
        if progress["requests_today"] >= MAX_DAILY_REQUESTS:
            print(f"⚠️  已达到今日免费额度上限（{MAX_DAILY_REQUESTS}次请求）")
            break

    # 显示完成信息
    print_completion_banner(progress)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  任务被中断，进度已保存")
        print("   下次运行相同命令将从当前进度继续")
    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()
        print("\n进度已保存，可以重新运行脚本继续")