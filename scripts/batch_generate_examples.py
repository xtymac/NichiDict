#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量生成例句脚本 - Batch Example Generator

用途：为高频词条批量生成AI例句，提升用户体验
策略：
  1. 优先处理 frequency_rank <= 5000 的常用词
  2. 跳过已有例句的词条
  3. 使用便宜的AI模型（gpt-4o-mini）
  4. 支持断点续传和错误重试
  5. 限制每日API调用次数

使用方法：
  python3 batch_generate_examples.py --db path/to/dict.sqlite --api-key YOUR_KEY

  可选参数：
    --max-rank 5000              最大频率排名（默认5000）
    --batch-size 10              每批处理数量（默认10）
    --max-examples 3             每个词生成的例句数（默认3）
    --daily-limit 100            每日API调用限制（默认100）
    --model gpt-4o-mini          OpenAI模型（默认gpt-4o-mini）
    --dry-run                    测试模式，不实际写入数据库
"""

import sqlite3
import json
import time
import argparse
import sys
import os
from datetime import datetime, date
from typing import List, Dict, Optional, Tuple
import hashlib

# API 客户端
try:
    from openai import OpenAI
    HAS_OPENAI = True
except ImportError:
    HAS_OPENAI = False
    print("⚠️  警告: 未安装 openai 包。运行: pip install openai")

# 进度跟踪文件
PROGRESS_FILE = ".batch_generate_progress.json"
STATE_FILE = ".batch_generate_state.json"


class BatchExampleGenerator:
    """批量例句生成器"""

    def __init__(self,
                 db_path: str,
                 api_key: str,
                 model: str = "gpt-4o-mini",
                 max_rank: int = 5000,
                 batch_size: int = 10,
                 max_examples: int = 3,
                 daily_limit: int = 100,
                 dry_run: bool = False):

        self.db_path = db_path
        self.api_key = api_key
        self.model = model
        self.max_rank = max_rank
        self.batch_size = batch_size
        self.max_examples = max_examples
        self.daily_limit = daily_limit
        self.dry_run = dry_run

        # 统计信息
        self.stats = {
            'total_entries': 0,
            'processed': 0,
            'skipped': 0,
            'failed': 0,
            'examples_generated': 0,
            'api_calls': 0,
            'start_time': datetime.now().isoformat()
        }

        # 加载状态
        self.state = self._load_state()

        # 配置 OpenAI
        self.client = None
        if HAS_OPENAI and not dry_run:
            self.client = OpenAI(api_key=api_key)

    def _load_state(self) -> Dict:
        """加载上次运行状态"""
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {
            'date': str(date.today()),
            'api_calls_today': 0,
            'last_processed_id': 0
        }

    def _save_state(self):
        """保存当前状态"""
        with open(STATE_FILE, 'w', encoding='utf-8') as f:
            json.dump(self.state, f, indent=2, ensure_ascii=False)

    def _check_daily_quota(self) -> bool:
        """检查今日配额"""
        today = str(date.today())
        if self.state['date'] != today:
            # 新的一天，重置计数
            self.state['date'] = today
            self.state['api_calls_today'] = 0
            self._save_state()

        if self.state['api_calls_today'] >= self.daily_limit:
            print(f"❌ 今日API调用已达上限 ({self.daily_limit})")
            return False

        remaining = self.daily_limit - self.state['api_calls_today']
        print(f"✅ 今日剩余配额: {remaining}/{self.daily_limit}")
        return True

    def _get_entries_without_examples(self) -> List[Dict]:
        """获取需要生成例句的词条"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        # 首先检查是否有frequency_rank数据
        cursor.execute("SELECT COUNT(*) as cnt FROM dictionary_entries WHERE frequency_rank IS NOT NULL")
        has_rank_data = cursor.fetchone()['cnt'] > 0

        if has_rank_data:
            # 查询：frequency_rank <= max_rank 且没有例句的词条
            query = """
            SELECT
                e.id,
                e.headword,
                e.reading_hiragana,
                e.reading_romaji,
                e.frequency_rank
            FROM dictionary_entries e
            WHERE e.frequency_rank <= ?
              AND e.id > ?
              AND NOT EXISTS (
                  SELECT 1
                  FROM word_senses ws
                  JOIN example_sentences ex ON ws.id = ex.sense_id
                  WHERE ws.entry_id = e.id
              )
            ORDER BY e.frequency_rank ASC, e.id ASC
            LIMIT ?
            """
            cursor.execute(query, (self.max_rank, self.state['last_processed_id'], self.batch_size))
        else:
            # 无frequency_rank数据，按ID排序取前N个
            print(f"⚠️  数据库无frequency_rank数据，使用ID顺序（前{self.max_rank}个词条）")
            query = """
            SELECT
                e.id,
                e.headword,
                e.reading_hiragana,
                e.reading_romaji,
                e.frequency_rank
            FROM dictionary_entries e
            WHERE e.id > ?
              AND e.id <= ?
              AND NOT EXISTS (
                  SELECT 1
                  FROM word_senses ws
                  JOIN example_sentences ex ON ws.id = ex.sense_id
                  WHERE ws.entry_id = e.id
              )
            ORDER BY e.id ASC
            LIMIT ?
            """
            cursor.execute(query, (self.state['last_processed_id'], self.max_rank, self.batch_size))

        entries = [dict(row) for row in cursor.fetchall()]

        conn.close()
        return entries

    def _get_senses_for_entry(self, entry_id: int) -> List[Dict]:
        """获取词条的所有义项"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        query = """
        SELECT
            id,
            definition_english,
            definition_chinese_simplified,
            definition_chinese_traditional,
            part_of_speech
        FROM word_senses
        WHERE entry_id = ?
        ORDER BY sense_order ASC
        """

        cursor.execute(query, (entry_id,))
        senses = [dict(row) for row in cursor.fetchall()]

        conn.close()
        return senses

    def _build_prompt(self, entry: Dict, senses: List[Dict]) -> str:
        """构建生成例句的Prompt"""
        definitions = []
        for idx, sense in enumerate(senses[:5], 1):  # 最多取5个义项
            chinese = sense['definition_chinese_simplified'] or sense['definition_chinese_traditional'] or ""
            definitions.append(f"{idx}. {sense['definition_english']} | JP: {sense['part_of_speech']} | CN: {chinese}")

        definitions_text = "\n".join(definitions)

        return f"""You are an expert Japanese language tutor. Generate natural example sentences for a dictionary entry.

Entry:
- Headword: {entry['headword']}
- Reading: {entry['reading_hiragana']}
- Romaji: {entry['reading_romaji']}
- Core meanings:
{definitions_text}

Requirements:
1. Produce up to {self.max_examples} concise Japanese sentences (<= 25 characters) that demonstrate the typical usage of the word. Each sentence MUST include the headword or its conjugated/inflected form once.
2. Provide context that matches the meanings listed above. Avoid uncommon idioms or archaic grammar.
3. Return JSON ONLY with schema:
   {{"examples":[{{"japanese":"...", "chinese":"...", "english":"..."}}]}}
4. Use Simplified Chinese for the chinese field. Keep english field in natural English.
5. Avoid romaji, avoid placeholders, avoid line breaks inside fields.

Respond with JSON only."""

    def _call_openai_api(self, prompt: str) -> Optional[List[Dict]]:
        """调用OpenAI API生成例句"""
        if not HAS_OPENAI or not self.client:
            print("❌ OpenAI 客户端未初始化")
            return None

        try:
            response = self.client.chat.completions.create(
                model=self.model,
                temperature=0.2,
                response_format={"type": "json_object"},
                messages=[
                    {"role": "system", "content": "Return JSON only. No prose."},
                    {"role": "user", "content": prompt}
                ]
            )

            content = response.choices[0].message.content
            data = json.loads(content)

            # 更新API调用计数
            self.state['api_calls_today'] += 1
            self.stats['api_calls'] += 1
            self._save_state()

            return data.get('examples', [])

        except Exception as e:
            print(f"❌ API调用失败: {e}")
            return None

    def _insert_examples(self, entry_id: int, senses: List[Dict], examples: List[Dict]):
        """将生成的例句插入数据库"""
        if self.dry_run:
            print(f"  [DRY-RUN] 将插入 {len(examples)} 个例句")
            return

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        try:
            # 为每个义项分配例句
            # 策略：如果只有1个义项，所有例句归它；否则平均分配
            if len(senses) == 1:
                sense_ids = [senses[0]['id']] * len(examples)
            else:
                # 循环分配
                sense_ids = [senses[i % len(senses)]['id'] for i in range(len(examples))]

            for order, (example, sense_id) in enumerate(zip(examples, sense_ids)):
                cursor.execute("""
                    INSERT INTO example_sentences
                    (sense_id, japanese_text, english_translation, example_order)
                    VALUES (?, ?, ?, ?)
                """, (
                    sense_id,
                    example['japanese'],
                    example['english'],
                    order
                ))

            conn.commit()
            self.stats['examples_generated'] += len(examples)
            print(f"  ✅ 成功插入 {len(examples)} 个例句")

        except Exception as e:
            conn.rollback()
            print(f"  ❌ 数据库插入失败: {e}")
            raise
        finally:
            conn.close()

    def process_entry(self, entry: Dict) -> bool:
        """处理单个词条"""
        entry_id = entry['id']
        headword = entry['headword']
        rank = entry['frequency_rank'] or 'N/A'

        print(f"\n📖 处理中: {headword} (ID={entry_id}, Rank={rank})")

        # 获取义项
        senses = self._get_senses_for_entry(entry_id)
        if not senses:
            print(f"  ⚠️  跳过: 无义项")
            self.stats['skipped'] += 1
            return False

        print(f"  📝 义项数: {len(senses)}")

        # 构建Prompt
        prompt = self._build_prompt(entry, senses)

        # 调用API生成例句
        examples = self._call_openai_api(prompt)

        if not examples:
            print(f"  ❌ 生成失败")
            self.stats['failed'] += 1
            return False

        print(f"  🎯 生成了 {len(examples)} 个例句:")
        for ex in examples:
            print(f"     • {ex['japanese']}")

        # 插入数据库
        try:
            self._insert_examples(entry_id, senses, examples)
            self.stats['processed'] += 1

            # 更新状态
            self.state['last_processed_id'] = entry_id
            self._save_state()

            return True

        except Exception as e:
            print(f"  ❌ 插入失败: {e}")
            self.stats['failed'] += 1
            return False

    def run(self):
        """运行批量生成"""
        print("=" * 60)
        print("🚀 批量例句生成器启动")
        print("=" * 60)
        print(f"数据库: {self.db_path}")
        print(f"模型: {self.model}")
        print(f"最大频率排名: {self.max_rank}")
        print(f"批次大小: {self.batch_size}")
        print(f"每词例句数: {self.max_examples}")
        print(f"每日限额: {self.daily_limit}")
        print(f"测试模式: {'是' if self.dry_run else '否'}")
        print("=" * 60)

        # 检查配额
        if not self._check_daily_quota():
            print("\n⏸️  已达今日限额，明天再来！")
            return

        # 获取待处理词条
        print("\n🔍 查询需要生成例句的词条...")
        entries = self._get_entries_without_examples()

        if not entries:
            print("✅ 所有词条都已有例句！")
            return

        self.stats['total_entries'] = len(entries)
        print(f"📊 找到 {len(entries)} 个词条需要生成例句\n")

        # 处理每个词条
        for idx, entry in enumerate(entries, 1):
            # 检查配额
            if self.state['api_calls_today'] >= self.daily_limit:
                print(f"\n⏸️  已达今日限额 ({self.daily_limit})，停止处理")
                break

            print(f"\n[{idx}/{len(entries)}]", end=" ")
            self.process_entry(entry)

            # API速率限制：避免触发限流
            if not self.dry_run and idx < len(entries):
                time.sleep(1)  # 每个请求间隔1秒

        # 打印统计
        self._print_stats()

    def _print_stats(self):
        """打印统计信息"""
        print("\n" + "=" * 60)
        print("📊 批量生成统计")
        print("=" * 60)
        print(f"总词条数: {self.stats['total_entries']}")
        print(f"成功处理: {self.stats['processed']} ✅")
        print(f"跳过: {self.stats['skipped']} ⚠️")
        print(f"失败: {self.stats['failed']} ❌")
        print(f"生成例句数: {self.stats['examples_generated']}")
        print(f"API调用次数: {self.stats['api_calls']}")
        print(f"今日已用配额: {self.state['api_calls_today']}/{self.daily_limit}")
        print(f"上次处理ID: {self.state['last_processed_id']}")
        print("=" * 60)

        # 保存统计到文件
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = f"batch_generate_log_{timestamp}.json"
        with open(log_file, 'w', encoding='utf-8') as f:
            json.dump({
                'stats': self.stats,
                'state': self.state,
                'config': {
                    'db_path': self.db_path,
                    'model': self.model,
                    'max_rank': self.max_rank,
                    'batch_size': self.batch_size,
                    'max_examples': self.max_examples
                }
            }, f, indent=2, ensure_ascii=False)

        print(f"\n📄 详细日志已保存: {log_file}")


def main():
    parser = argparse.ArgumentParser(
        description='批量生成词典例句',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 基础用法（使用环境变量中的API key）
  python3 batch_generate_examples.py --db dict.sqlite

  # 指定API key和参数
  python3 batch_generate_examples.py --db dict.sqlite --api-key sk-xxx \\
    --max-rank 3000 --batch-size 20 --daily-limit 200

  # 测试模式（不实际调用API和写入数据库）
  python3 batch_generate_examples.py --db dict.sqlite --dry-run
"""
    )

    parser.add_argument('--db', required=True, help='SQLite数据库路径')
    parser.add_argument('--api-key', help='OpenAI API Key（可选，默认从环境变量OPENAI_API_KEY读取）')
    parser.add_argument('--model', default='gpt-4o-mini', help='OpenAI模型（默认: gpt-4o-mini）')
    parser.add_argument('--max-rank', type=int, default=5000, help='最大频率排名（默认: 5000）')
    parser.add_argument('--batch-size', type=int, default=10, help='每批处理数量（默认: 10）')
    parser.add_argument('--max-examples', type=int, default=3, help='每词生成例句数（默认: 3）')
    parser.add_argument('--daily-limit', type=int, default=100, help='每日API调用限制（默认: 100）')
    parser.add_argument('--dry-run', action='store_true', help='测试模式，不实际执行')

    args = parser.parse_args()

    # 获取API Key
    api_key = args.api_key or os.getenv('OPENAI_API_KEY')
    if not api_key and not args.dry_run:
        print("❌ 错误: 需要提供 OpenAI API Key")
        print("   方法1: --api-key YOUR_KEY")
        print("   方法2: 设置环境变量 OPENAI_API_KEY")
        sys.exit(1)

    # 检查数据库文件
    if not os.path.exists(args.db):
        print(f"❌ 错误: 数据库文件不存在: {args.db}")
        sys.exit(1)

    # 创建生成器并运行
    generator = BatchExampleGenerator(
        db_path=args.db,
        api_key=api_key or "",
        model=args.model,
        max_rank=args.max_rank,
        batch_size=args.batch_size,
        max_examples=args.max_examples,
        daily_limit=args.daily_limit,
        dry_run=args.dry_run
    )

    try:
        generator.run()
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断，保存进度...")
        generator._print_stats()
    except Exception as e:
        print(f"\n❌ 发生错误: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
