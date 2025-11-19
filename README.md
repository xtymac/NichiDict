# NichiDict

一个智能的离线日语词典应用，专为中文母语学习者设计。

## 核心功能

### 📚 离线词典
- 基于 JMDict 的完整日语词汇数据库
- 支持日语→中文和中文→日语双向搜索
- 多语言定义（中文简体、中文繁体、英文）
- JLPT 级别标注（N5-N1）
- 词频排名数据

### 🎯 智能显示
- **假名优先显示**（2025-11-19新增）
  - 自动识别稀有汉字写法（如：屹度 → きっと）
  - 基于词性、JLPT级别、词频的智能判断
  - 例句自动替换为假名形式，保持一致性
  - 汉字形式作为备选信息显示
  - 详见：[KANA_PRIORITY_DISPLAY_FEATURE.md](KANA_PRIORITY_DISPLAY_FEATURE.md)

### 🔍 精准搜索
- 智能搜索排序（优先显示完全匹配）
- 支持平假名、片假名、汉字、罗马字输入
- 动词词干匹配（如：食べる ← 食べ）
- 变体分组显示（合并书写变体，分离同音异义词）

### 📖 例句系统
- 来自 Tatoeba 的真实例句
- 支持中文翻译
- 一键句子分析（基于 LLM）
- 语音朗读功能

### 🤖 AI 辅助
- GPT-4o / Gemini 2.0 Flash 驱动的例句生成
- 智能句子翻译和语法分析
- 自动生成针对性例句（特别针对 JLPT N5-N4 词汇）

## 技术栈

- **语言**: Swift 6.0（启用严格并发检查）
- **框架**: SwiftUI
- **数据库**: GRDB.swift（SQLite）
- **AI**: OpenAI GPT-4o、Google Gemini 2.0 Flash
- **词典数据**: JMDict (日英词典)、CC-CEDICT (汉英词典)
- **例句数据**: Tatoeba、自动生成

## 项目结构

```
NichiDict/
├── NichiDict/                  # 主应用
│   ├── Views/                  # SwiftUI 视图
│   │   ├── SearchView.swift    # 搜索界面（假名优先显示逻辑）
│   │   ├── EntryDetailView.swift # 词条详情（例句替换逻辑）
│   │   └── ...
│   └── Resources/              # 资源文件
│       └── seed.sqlite         # 词典数据库
├── Modules/
│   └── CoreKit/                # 核心功能模块
│       ├── DictionarySearch/   # 词典搜索服务
│       │   ├── Services/       # DBService、SearchService
│       │   ├── Models/         # DictionaryEntry、WordSense
│       │   └── Database/       # DatabaseManager
│       └── LLMClient.swift     # AI 客户端
└── scripts/                    # 数据导入脚本
    ├── import_frequency_data.py
    ├── import_tatoeba_examples.py
    └── generate_n5_examples.py
```

## 最近更新

### 2025-11-19: 假名优先显示功能
- ✅ 实现稀有汉字自动检测算法
- ✅ 搜索结果显示假名标题 + 汉字备注
- ✅ 详情页同步显示逻辑
- ✅ 例句自动替换汉字为假名
- ✅ 基于词性（纯副词）、JLPT级别、词频的多维度判断
- 详见：[KANA_PRIORITY_DISPLAY_FEATURE.md](KANA_PRIORITY_DISPLAY_FEATURE.md)

### 2025-11 之前更新
- ✅ 完成 N5 词汇例句覆盖（98%+）
- ✅ 优化搜索排序（JLPT优先、完全匹配优先）
- ✅ 修复复合词搜索问题
- ✅ 添加维基百科词频数据

## 文档

- [假名优先显示功能](KANA_PRIORITY_DISPLAY_FEATURE.md) - 稀有汉字自动假名化
- [搜索排序优化](SEARCH_RANKING_TEST_REPORT.md)
- [例句系统实现](EXAMPLE_SENTENCES_IMPLEMENTATION.md)
- [N5例句生成报告](N5_COMPLETION_REPORT.md)
- [测试指南](TESTING_GUIDE.md)

## 开发指南

### 构建要求

- Xcode 15+
- iOS 17.0+
- Swift 6.0

### 构建步骤

```bash
# 1. 打开项目
cd NichiDict
open NichiDict.xcodeproj

# 2. 在 Xcode 中选择目标设备（模拟器或真机）

# 3. 构建并运行 (⌘R)
```

### 数据库准备

词典数据库 `seed.sqlite` 应放置在：
```
NichiDict/Resources/seed.sqlite
```

数据库包含：
- `dictionary_entries`: 词条表
- `word_senses`: 词义表
- `example_sentences`: 例句表
- `dictionary_fts`: 全文搜索索引

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

[待定]