# AI提示词优化 - 专业词典格式

## 概述

本次更新对AI词典系统进行了全面优化，实现了更加专业、规范和详细的词典格式输出。

## 核心改进

### 1. 智能模式判断

AI现在会自动判断查询类型：

```
判断逻辑：
- 若输入包含句点/疑问/感叹或空格较多、长度>12且含多个词形
  → 句子解析模式
- 否则
  → 词条模式
- 无法识别
  → 未収録模式
```

### 2. 增强的词条信息

#### 之前的结构：
```json
{
  "headword": "食べる",
  "reading": "たべる",
  "romaji": "taberu",
  "partOfSpeech": "動詞",
  "senses": ["吃", "耗费"],  // 简单字符串数组
  "examples": [...]
}
```

#### 现在的结构：
```json
{
  "headword": "食べる",
  "reading": "たべる",
  "romaji": "taberu",
  "partOfSpeech": "一段動詞・他動",
  "accent": "たべ↘る［1］",  // ✨ 新增：音调标注
  "senses": [  // ✨ 改进：结构化释义
    {
      "definition": "口に入れて噛み、飲み込む",  // 日语释义
      "chinese": "吃；进食",                   // 中文译文
      "english": "to eat"                      // 英文译文
    }
  ],
  "grammar": {  // ✨ 新增：语法信息
    "conjugation": ["食べます", "食べない", "食べた", "食べて"],
    "collocation": ["を食べる", "外で食べる"],
    "honorific": "召し上がる（尊敬）、いただく（謙譲）"
  },
  "examples": [  // ✨ 改进：双语例句
    {
      "japanese": "朝ごはんを食べる。",
      "chinese": "我吃早饭。",
      "english": "I eat breakfast."
    }
  ],
  "related": {  // ✨ 新增：关联词
    "synonym": "喫する（書）／いただく（謙）",
    "antonym": "断食する",
    "derived": null
  }
}
```

### 3. 句子解析增强

#### 之前：
```json
{
  "wordBreakdown": [...],
  "grammar": ["语法点1", "语法点2"],  // 简单字符串
  "translation": "今天要下雨"
}
```

#### 现在：
```json
{
  "original": "今日は雨が降りそうです。",  // ✨ 新增：原句
  "translation": {  // ✨ 改进：双语翻译
    "chinese": "今天好像要下雨。",
    "english": "It looks like it will rain today."
  },
  "wordBreakdown": [...],
  "grammarPoints": [  // ✨ 改进：详细语法解释
    {
      "pattern": "そうです",
      "reading": "そうです",
      "meaning": "样态推测",
      "explanation": "表示根据外观或样子进行推测"
    }
  ]
}
```

## 新的数据模型

### LLMSense（义项）
```swift
public struct LLMSense: Codable, Hashable {
    public let definition: String    // 日语释义
    public let chinese: String       // 中文译文
    public let english: String       // 英文译文
}
```

### LLMGrammar（语法）
```swift
public struct LLMGrammar: Codable, Hashable {
    public let conjugation: [String]?  // 活用形式
    public let collocation: [String]?  // 常见搭配
    public let honorific: String?      // 敬语形式
}
```

### LLMRelated（关联词）
```swift
public struct LLMRelated: Codable, Hashable {
    public let synonym: String?    // 类义词
    public let antonym: String?    // 反义词
    public let derived: String?    // 派生词
}
```

### LLMGrammarPoint（语法点）
```swift
public struct LLMGrammarPoint: Codable, Hashable {
    public let pattern: String         // 文法模式
    public let reading: String         // 读音
    public let meaning: String         // 含义
    public let explanation: String     // 详细说明
}
```

## 提示词优化要点

### 1. 通用约束

```markdown
## 2) 通用约束
- 语言：界面语言保持日语为主；释义提供简体中文与英语的简短译文
- 不要废话、不要自我解释、不要重复相同释义
- 去重规则：同义/同词性/同释义内容合并为一条；空释义或仅有同形汉字的条目删除
- 每个词条最多 3 个义项，例句 2-3 条
- 不确定时标注「(推定)」
- 若输入是中文/英文概念词（如"中午""eat"），映射到对应日语词条
```

### 2. 质量要求

```markdown
## 质量要求
- 禁止：重复 sense、空释义、只列汉字变体、冗长解释
- 必须：每条意义都有日语释义 + 中文 + 英文的短译；例句自然、常用
- 输出只包含 JSON，不加前后缀说明
- 多候选时按现代通用度排序（常用 > 文語 > 方言），最多返回 3 个词条
```

### 3. 完整的词条模板

```json
{
  "queryType": "word",
  "entries": [
    {
      "headword": "食べる",
      "reading": "たべる",
      "romaji": "taberu",
      "partOfSpeech": "一段動詞・他動",
      "accent": "たべ↘る［1］",
      "senses": [
        {
          "definition": "口に入れて噛み、飲み込む",
          "chinese": "吃；进食",
          "english": "to eat"
        },
        {
          "definition": "資源や時間を大量に消費する",
          "chinese": "耗费",
          "english": "to consume"
        }
      ],
      "grammar": {
        "conjugation": ["食べます", "食べない", "食べた", "食べて"],
        "collocation": ["を食べる", "外で食べる", "偏食をする"],
        "honorific": "召し上がる（尊敬）、いただく（謙譲）"
      },
      "examples": [
        {
          "japanese": "朝ごはんを食べる。",
          "chinese": "我吃早饭。",
          "english": "I eat breakfast."
        }
      ],
      "related": {
        "synonym": "喫する（書）／いただく（謙）",
        "antonym": "断食する",
        "derived": null
      }
    }
  ]
}
```

## UI层改进

### 词条展示增强

创建了独立的`WordEntryView`组件以避免SwiftUI编译器类型检查超时：

```swift
struct WordEntryView: View {
    let entry: LLMDictEntry
    let showDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView      // 見出し語 + 読み + ローマ字
            partOfSpeechView // 品詞标签
            sensesView       // 義項（日+中+英）
            examplesView     // 用例（日+中）
            relatedView      // 関連語
        }
    }
}
```

### 显示效果对比

#### 义项显示

**之前**：
```
1. 吃
2. 耗费
```

**现在**：
```
1. 口に入れて噛み、飲み込む
   「吃；进食」

2. 資源や時間を大量に消費する
   「耗费」
```

#### 例句显示

**之前**：
```
朝ごはんを食べる。
我吃早饭。
```

**现在**：
```
┌─────────────────────────┐
│ 朝ごはんを食べる。        │
│ 中：我吃早饭。            │
└─────────────────────────┘
```

#### 新增：关联词显示

```
関連
類義：喫する（書）／いただく（謙）
```

## 测试场景

### 1. 单词查询（中文输入）

**输入**：`中午`

**期望输出**：
```json
{
  "queryType": "word",
  "entries": [
    {
      "headword": "正午",
      "reading": "しょうご",
      "romaji": "shōgo",
      "partOfSpeech": "名詞",
      "accent": "しょ↘うご［1］",
      "senses": [
        {
          "definition": "昼の12時",
          "chinese": "正午；中午十二点",
          "english": "noon; midday"
        }
      ],
      ...
    },
    {
      "headword": "昼",
      "reading": "ひる",
      ...
    }
  ]
}
```

### 2. 单词查询（英文输入）

**输入**：`eat`

**期望输出**：
```json
{
  "queryType": "word",
  "entries": [
    {
      "headword": "食べる",
      "reading": "たべる",
      ...
    },
    {
      "headword": "食う",
      "reading": "くう",
      ...
    }
  ]
}
```

### 3. 句子解析

**输入**：`今日は雨が降りそうです。`

**期望输出**：
```json
{
  "queryType": "sentence",
  "sentenceAnalysis": {
    "original": "今日は雨が降りそうです。",
    "translation": {
      "chinese": "今天好像要下雨。",
      "english": "It looks like it will rain today."
    },
    "wordBreakdown": [
      {
        "word": "今日",
        "reading": "きょう",
        "meaning": "今天",
        "grammaticalRole": "時間名詞"
      },
      ...
    ],
    "grammarPoints": [
      {
        "pattern": "そうです",
        "reading": "そうです",
        "meaning": "样态推测",
        "explanation": "表示根据外观或样子进行推测"
      }
    ]
  }
}
```

## 性能考虑

### 编译器优化

原始的`wordView`太复杂，导致SwiftUI编译器类型检查超时：

```swift
// ❌ 编译器超时
private var wordView: some View {
    ForEach(...) { entry in
        VStack { // 100+ 行嵌套视图
            ...
        }
    }
}

// ✅ 拆分为独立组件
private var wordView: some View {
    ForEach(...) { entry in
        WordEntryView(entry: entry, showDivider: ...)
    }
}
```

### 扩展组织

使用extension将`sentenceView`和`notFoundView`与主体分离：

```swift
struct AIExplainFullView: View {
    // 主体
}

extension AIExplainFullView {
    var sentenceView: some View { ... }
    var notFoundView: some View { ... }
}
```

## 向后兼容

为了保持代码整洁，旧的`AIExplainCard`组件已被移除。所有AI结果现在统一使用`AIExplainFullView`全屏展示。

## 总结

本次优化实现了：

✅ **更专业的词典格式**：音调、活用、搭配、敬语、关联词
✅ **结构化释义**：日语定义 + 中文 + 英文三语对照
✅ **双语例句**：中英文翻译完整
✅ **详细语法解释**：模式、读音、含义、用法说明
✅ **智能模式判断**：自动识别单词/句子/未收录
✅ **质量控制**：去重、精简、无废话
✅ **UI组件优化**：避免编译器超时，提升性能

用户现在可以获得接近专业日语词典的查询体验，所有释义、例句、语法说明都遵循规范的词典格式。
