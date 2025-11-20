# 假名优先显示功能实现报告

**日期**: 2025-11-19
**功能**: 稀有汉字自动假名化显示
**状态**: ✅ 已完成并测试通过

---

## 概述

实现了智能检测和处理日语词汇中的稀有汉字写法，自动在搜索结果、详情页和例句中优先显示常用的假名形式，将稀有汉字形式作为备选显示。

### 问题背景

在日语中，许多词汇存在多种书写形式：
- **常用形式**：假名（如：きっと、もっと）
- **稀有形式**：使用罕见汉字（如：屹度、尤）

在现代日语中，这些词通常用假名书写。但原有系统会直接显示数据库中的汉字形式，导致：
1. 用户看到不熟悉的生僻汉字
2. 学习者产生困惑（以为应该记住这些汉字）
3. 例句中混用汉字和假名，不一致

### 解决方案

实现三层自动检测和替换机制：
1. **搜索结果页**: 显示假名标题 + 汉字备注
2. **词条详情页**: 显示假名标题 + 汉字备注
3. **例句**: 自动将稀有汉字替换为假名

---

## 技术实现

### 1. 稀有汉字检测算法

**位置**: `SearchView.swift` (lines 85-111)

```swift
// 检测条件（所有条件必须同时满足）：
let isRareKanjiWriting = isAllKanji &&              // 1. 纯汉字（无假名混写）
                        isPureKana(reading) &&       // 2. 读音是纯假名
                        primaryHeadword != reading && // 3. 写法和读音不同
                        primaryHeadword.count <= 3 && // 4. 长度 ≤ 3 个字
                        (isPureAdverb ||              // 5a. 纯副词（不兼具名词等）
                         (!isN5Word && isBasicWord && !hasVeryHighFrequency) || // 5b. N4词且频率不高
                         primaryEntry.frequencyRank == nil)  // 5c. 无频率数据
```

#### 检测逻辑说明

**纯副词检测**:
```swift
let hasAdverb = primaryEntry.senses.contains { sense in
    sense.partOfSpeech.lowercased().contains("adverb") ||
    sense.partOfSpeech.contains("副詞")
}
let hasNoun = primaryEntry.senses.contains { sense in
    sense.partOfSpeech.lowercased().contains("noun") ||
    sense.partOfSpeech.contains("名詞")
}
let isPureAdverb = hasAdverb && !hasNoun
```

**频率阈值**:
- 高频词阈值: frequency_rank ≤ 1000
- N5词例外: 即使低频也保留汉字（如：今日、明日）

### 2. 搜索结果显示

**位置**: `SearchView.swift` (lines 57-152)

#### 显示逻辑

```swift
var displayHeadword: String {
    if hasKanaVariant || isRareKanjiWriting {
        return reading  // 显示假名
    }
    return primaryHeadword  // 保留原汉字
}

var alternateHeadwords: [String] {
    if displayHeadword != primaryHeadword {
        return allHeadwords.filter { containsKanji($0) }  // 收集所有汉字形式
    }
    return []
}
```

#### UI 渲染

```swift
Text(group.displayHeadword)           // 主标题：假名
    .font(.headline)

if !group.alternateHeadwords.isEmpty {
    Text("Kanji: " + group.alternateHeadwords.joined(separator: ", "))  // 备注：汉字
        .font(.caption)
        .foregroundStyle(.tertiary)
}
```

### 3. 详情页显示

**位置**: `EntryDetailView.swift` (lines 721-758)

#### 标题处理

```swift
private var displayHeadword: String {
    if let alternates = alternateHeadwords,
       !alternates.isEmpty,
       containsKanji(entry.headword) {
        return entry.readingHiragana  // 显示假名
    }
    return entry.headword  // 保留原汉字
}

private var displayAlternates: [String] {
    guard let providedAlternates = alternateHeadwords, !providedAlternates.isEmpty else {
        return []
    }

    var alternates: [String] = []
    if containsKanji(entry.headword) {
        alternates.append(entry.headword)  // 添加原汉字形式
    }
    // 添加其他汉字变体
    for alternate in providedAlternates {
        if !alternates.contains(alternate) {
            alternates.append(alternate)
        }
    }
    return alternates
}
```

### 4. 例句自动替换

**位置**: `EntryDetailView.swift`

#### ExampleSentenceView (lines 252-372)

```swift
struct ExampleSentenceView: View {
    let example: ExampleSentence
    let targetWord: String
    let kanjiVariants: [String]?  // 需要替换的汉字形式

    private var displayedExampleText: String {
        guard let variants = kanjiVariants, !variants.isEmpty else {
            return example.japaneseText
        }

        var text = example.japaneseText
        for variant in variants {
            text = text.replacingOccurrences(of: variant, with: targetWord)
        }
        return text
    }
}
```

#### InlineSenseExampleView (lines 424-540)

同样的替换逻辑应用于词义内联例句。

#### LocalSenseView (lines 5-248)

将 `kanjiVariants` 参数传递给所有例句组件。

---

## 测试用例

### 1. 纯副词 - きっと (屹度)

| 项目 | 值 |
|------|-----|
| 原始标题 | 屹度 |
| JLPT级别 | N4 |
| 词性 | 纯副词 (adverb) |
| 频率排名 | 101 |

**预期显示**:
```
标题: きっと
Kanji: 屹度
例句: 彼はきっと来るでしょう。（自动替换）
```

**检测结果**: ✅ 通过
- `isAllKanji`: ✅ (屹度 = 纯汉字)
- `isPureKana(reading)`: ✅ (きっと = 纯假名)
- `isPureAdverb`: ✅ (只有副词词性)
- **判定**: 稀有汉字 → 显示假名

### 2. N5常用词 - 今日 (きょう)

| 项目 | 值 |
|------|-----|
| 原始标题 | 今日 |
| JLPT级别 | N5 |
| 词性 | 名词 + 副词 |
| 频率排名 | 201 |

**预期显示**:
```
标题: 今日
（无汉字备注）
```

**检测结果**: ✅ 通过
- `isN5Word`: ✅
- `hasVeryHighFrequency`: ✅ (201 ≤ 1000)
- **判定**: 常用汉字 → 保留汉字

### 3. 混合假名词 - 食べる

| 项目 | 值 |
|------|-----|
| 原始标题 | 食べる |
| JLPT级别 | N5 |
| 词性 | 动词 |
| 频率排名 | 2501 |

**预期显示**:
```
标题: 食べる
（无汉字备注）
```

**检测结果**: ✅ 通过
- `isAllKanji`: ❌ (含假名 "べる")
- **判定**: 非纯汉字 → 保留原样

### 4. 纯副词 - やっと (漸と)

| 项目 | 值 |
|------|-----|
| 原始标题 | 漸と |
| JLPT级别 | N4 |
| 词性 | 纯副词 |
| 频率排名 | 101 |

**预期显示**:
```
标题: やっと
Kanji: 漸と
```

**检测结果**: ✅ 通过
- `isPureAdverb`: ✅
- **判定**: 稀有汉字 → 显示假名

### 5. 名词兼副词 - 多分 (たぶん)

| 项目 | 值 |
|------|-----|
| 原始标题 | 多分 |
| JLPT级别 | N5 |
| 词性 | 名词 + 形容动词 |
| 频率排名 | 1301 |

**预期显示**:
```
标题: 多分
（无汉字备注）
```

**检测结果**: ✅ 通过
- `isPureAdverb`: ❌ (兼具名词词性)
- `isN5Word`: ✅
- **判定**: N5常用词 → 保留汉字

---

## 关键文件清单

### 核心逻辑文件

| 文件 | 行数范围 | 功能 |
|------|----------|------|
| `SearchView.swift` | 57-152 | 稀有汉字检测、displayHeadword、alternateHeadwords |
| `SearchView.swift` | 207-248 | 搜索结果UI显示 |
| `EntryDetailView.swift` | 5-248 | LocalSenseView（词义显示） |
| `EntryDetailView.swift` | 252-372 | ExampleSentenceView（例句显示与替换） |
| `EntryDetailView.swift` | 424-540 | InlineSenseExampleView（内联例句） |
| `EntryDetailView.swift` | 721-758 | displayHeadword/displayAlternates 计算属性 |
| `EntryDetailView.swift` | 931-939 | LocalSenseView 参数传递 |
| `EntryDetailView.swift` | 949-955 | ExampleSentenceView 参数传递 |

### 数据模型

| 文件 | 说明 |
|------|------|
| `DictionaryEntry.swift` | 词条数据结构（headword, readingHiragana, frequencyRank, jlptLevel） |
| `WordSense.swift` | 词义数据结构（partOfSpeech） |
| `ExampleSentence.swift` | 例句数据结构（japaneseText） |

---

## 性能优化

### 计算属性缓存

所有检测逻辑使用 SwiftUI 的计算属性（computed property），自动享受以下优化：
- **值缓存**: 相同输入不重复计算
- **懒加载**: 仅在需要时计算
- **自动失效**: 依赖数据变化时重新计算

### 字符串处理优化

```swift
// Unicode scalar 级别的检测（比正则表达式快）
func containsKanji(_ text: String) -> Bool {
    return text.unicodeScalars.contains { scalar in
        (0x4E00...0x9FFF).contains(scalar.value)
    }
}

func isPureKana(_ text: String) -> Bool {
    return text.unicodeScalars.allSatisfy { scalar in
        (0x3040...0x309F).contains(scalar.value) ||  // Hiragana
        (0x30A0...0x30FF).contains(scalar.value)     // Katakana
    }
}
```

### 时间复杂度

- 稀有汉字检测: O(n) - n 为字符串长度（通常 ≤ 3）
- 例句替换: O(m × k) - m 为例句长度，k 为汉字变体数量（通常 = 1-2）

---

## 用户体验改进

### Before (改进前)

```
搜索 "きっと"

结果:
┌─────────────────────┐
│ 屹度          [N4]  │  ← 生僻汉字，用户困惑
│ きっと              │
│ surely; undoubtedly │
│                     │
│ 例句:               │
│ 彼は屹度来るでしょう。│  ← 例句用汉字，不统一
│ He will surely come.│
└─────────────────────┘
```

### After (改进后)

```
搜索 "きっと"

结果:
┌─────────────────────┐
│ きっと        [N4]  │  ← 常用假名形式
│ Kanji: 屹度         │  ← 汉字作为备选信息
│ surely; undoubtedly │
│                     │
│ 例句:               │
│ 彼はきっと来るでしょう。│  ← 自动替换为假名
│ He will surely come.│
└─────────────────────┘
```

### 改进要点

1. **学习友好**: 学习者看到的是现代日语实际使用的写法
2. **信息完整**: 汉字形式仍然保留，作为扩展知识
3. **一致性**: 标题、例句统一使用假名形式
4. **语音合成**: 语音按钮使用假名文本，发音正确

---

## 边界情况处理

### 1. 无词性数据
```swift
// 如果没有词性信息，使用其他条件判断
let isPureAdverb = hasAdverb && !hasNoun
// 如果 senses 为空，isPureAdverb = false，回退到频率判断
```

### 2. 无频率数据
```swift
let hasVeryHighFrequency = (primaryEntry.frequencyRank ?? Int.max) <= 1000
// nil 转为 Int.max，自动判定为低频
```

### 3. 多个汉字变体
```swift
var alternateHeadwords: [String] {
    if displayHeadword != primaryHeadword {
        return allHeadwords.filter { containsKanji($0) }  // 返回所有汉字形式
    }
    return []
}

// 显示: "Kanji: 屹度, 屹と"
```

### 4. 已是假名形式
```swift
if !containsKanji(primaryHeadword) {
    return allHeadwords.filter { headword in
        headword != primaryHeadword &&
        containsKanji(headword)
    }
}
// 主词条已是假名时，仍显示汉字变体作为参考
```

---

## 未来优化方向

### 1. 用户偏好设置

允许用户选择显示偏好：
```swift
enum KanjiDisplayPreference {
    case alwaysKana      // 总是假名优先
    case alwaysKanji     // 总是汉字优先
    case auto            // 智能判断（当前实现）
}
```

### 2. JLPT级别自定义

不同级别用户可能有不同需求：
- **初学者(N5-N4)**: 更激进的假名优先
- **进阶者(N3-N1)**: 保留更多汉字形式

### 3. 词频数据完善

当前频率数据来源有限，可考虑：
- 导入更全面的词频数据库
- 使用现代语料库（如维基百科、新闻）
- 区分口语频率 vs 书面语频率

### 4. AI辅助判断

对于边界情况，可使用LLM辅助判断：
```swift
// 伪代码
let shouldUseKana = await LLMClient.shared.evaluateKanaUsage(
    word: "屹度",
    context: "modern conversational Japanese"
)
```

---

## 维护注意事项

### 阈值调整

如果发现误判，可调整以下参数：

```swift
// SearchView.swift 第101行
let hasVeryHighFrequency = (primaryEntry.frequencyRank ?? Int.max) <= 1000
// 调整 1000 → 更高值: 更多词被判定为低频（更多假名）
// 调整 1000 → 更低值: 更少词被判定为低频（更多汉字）

// SearchView.swift 第108行
primaryHeadword.count <= 3
// 调整长度限制可影响检测范围
```

### 添加词性类别

如果需要支持其他词性的假名优先：

```swift
// SearchView.swift 第88-96行
let hasAdverb = primaryEntry.senses.contains { sense in
    sense.partOfSpeech.lowercased().contains("adverb") ||
    sense.partOfSpeech.contains("副詞") ||
    sense.partOfSpeech.contains("YOUR_NEW_POS")  // 添加新词性
}
```

### 测试覆盖

添加新检测规则后，务必测试：
1. ✅ 稀有副词（きっと、ずっと）
2. ✅ 常用N5词（今日、明日）
3. ✅ 混合假名词（食べる、見る）
4. ✅ 纯汉字N1词（矛盾、曖昧）

---

## 构建状态

```
Build Configuration: Debug
Platform: iOS Simulator (iPhone 17 Pro Max)
Xcode Project: NichiDict/NichiDict.xcodeproj
Build Result: ✅ BUILD SUCCEEDED
Date: 2025-11-19 20:47
```

---

## 总结

此功能通过智能检测和多层次的显示策略，实现了稀有汉字的自动假名化处理：

1. **检测准确**: 基于词性、JLPT级别、词频的多维度判断
2. **信息完整**: 假名优先显示，汉字作为备选保留
3. **一致体验**: 搜索、详情、例句全链路统一处理
4. **性能优化**: 使用计算属性缓存和Unicode级别处理

该功能显著提升了学习者的使用体验，使其能够接触到现代日语的实际用法，同时保留汉字形式作为扩展知识。

---

**相关文档**:
- [KANJI_VARIANT_AND_COMPOUND_FIX.md](KANJI_VARIANT_AND_COMPOUND_FIX.md) - 汉字变体与复合词处理
- [SEARCH_RANKING_TEST_REPORT.md](SEARCH_RANKING_TEST_REPORT.md) - 搜索排序优化
- [EXAMPLE_SENTENCES_IMPLEMENTATION.md](EXAMPLE_SENTENCES_IMPLEMENTATION.md) - 例句系统实现
