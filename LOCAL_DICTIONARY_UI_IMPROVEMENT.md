# 本地词库UI改进

## 概述

本次更新优化了本地词库（SQLite数据库）的显示格式，使其更加专业、清晰，与AI词典风格保持一致。

## 改进前后对比

### 改进前

```
食べる
━━━━━━━━━━━━━━━━
たべる
taberu

定義
━━━━━━━━━━━━━━━━
Ichidan verb, transitive verb
1. 喰; 食; 召; 頂
```

**问题**：
- ❌ 标题字体较小
- ❌ 只显示英文定义或简单汉字
- ❌ 品词信息不突出
- ❌ 中文翻译隐藏在下方
- ❌ 信息层级不清晰

### 改进后

```
食べる
━━━━━━━━━━━━━━━━
たべる  [taberu]

アクセント  たべ↘る［1］
頻度  Very Common (Top 100)

━━━━━━━━━━━━━━━━
意味

[一段動詞]

1. to eat
   「吃；食用」

   注：口语常用

   ┌─────────────────────────┐
   │ 朝ごはんを食べる。        │
   │ Eat breakfast.            │
   └─────────────────────────┘

2. to live; to make a living
   「生活；谋生」
```

**优势**：
- ✅ 更大的标题字体（36pt）
- ✅ 英文定义 + 中文翻译分层显示
- ✅ 品词标签更突出（蓝色胶囊）
- ✅ 音调和频率信息清晰展示
- ✅ 用例直接显示在义项下方
- ✅ 使用注意标注为橙色

## 具体改进内容

### 1. 标题区域增强

#### 改进前：
```swift
Text(entry.headword)
    .font(.largeTitle)  // ~34pt
    .fontWeight(.bold)
```

#### 改进后：
```swift
Text(entry.headword)
    .font(.system(size: 36, weight: .bold))  // 36pt，更大更醒目

HStack(spacing: 12) {
    Text(entry.readingHiragana)
        .font(.title2)
    Text("[\(entry.readingRomaji)]")  // 罗马字放在方括号内
        .font(.subheadline)
}
```

### 2. 音调信息优化

#### 改进前：
```swift
Text("detail.pitchAccent")  // 本地化标题
    .font(.headline)
Text(pitchAccent)
    .font(.title2)
```

#### 改进后：
```swift
HStack(spacing: 8) {
    Text("アクセント")  // 日语标签
        .font(.subheadline)
        .fontWeight(.semibold)
    Text(pitchAccent)
        .font(.title3)
        .fontWeight(.medium)
}
```

**显示效果**：`アクセント たべ↘る［1］`

### 3. 频率信息改进

#### 改进前：
```swift
Text("detail.frequency")
Text(frequencyLabel(for: frequencyRank))
Text("Top \(frequencyRank)")
```

#### 改进后：
```swift
HStack(spacing: 8) {
    Text("頻度")  // 日语标签
    Text(frequencyLabel(for: frequencyRank))
        .fontWeight(.medium)
    Text("(Top \(frequencyRank))")
        .font(.caption)
}
```

**显示效果**：`頻度 Very Common (Top 100)`

### 4. 义项显示重构

创建了全新的`LocalSenseView`组件：

```swift
struct LocalSenseView: View {
    let sense: WordSense
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 品词标签
            Text(sense.partOfSpeech)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())

            // 定义（英文 + 中文）
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index).")
                        .fontWeight(.medium)
                    Text(sense.definitionEnglish)
                        .font(.body)
                }

                // 中文翻译
                if let chineseDef = sense.definitionChineseSimplified {
                    Text("「\(chineseDef)」")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24)
                }
            }

            // 使用注意
            if let notes = sense.usageNotes {
                HStack(alignment: .top, spacing: 6) {
                    Text("注")
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    Text(notes)
                        .font(.caption)
                }
                .padding(.leading, 24)
            }

            // 例句（显示前2条）
            if !sense.examples.isEmpty {
                ForEach(sense.examples.prefix(2)) { example in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(example.japaneseText)
                        Text(example.englishTranslation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
                }
                .padding(.leading, 24)
            }
        }
    }
}
```

## 组件化设计

### LocalSenseView

专门用于显示本地词库的义项，特点：

- **品词标签**：蓝色胶囊样式
- **双语显示**：英文定义 + 中文翻译
- **注意标注**：橙色"注"字突出
- **内嵌例句**：每个义项最多显示2条例句
- **层级缩进**：中文翻译、注意、例句都左侧缩进24pt

### 布局层级

```
词条详情页
├── 标题区（36pt 大字）
│   ├── 見出し語
│   ├── よみ [romaji]
│   └── アクセント/頻度
├── 分隔线
├── 意味（义项区）
│   ├── LocalSenseView #1
│   │   ├── [品词标签]
│   │   ├── 1. English definition
│   │   │   └── 「中文翻译」(缩进)
│   │   ├── 注：使用注意 (缩进)
│   │   └── 例句卡片 (缩进)
│   └── LocalSenseView #2
│       └── ...
└── 全部用例区（保留）
```

## 信息优先级

### 主要信息（大字体、醒目）
1. 見出し語（36pt bold）
2. 読み（title2）
3. アクセント（title3）

### 次要信息（中等字体）
4. 品词标签（胶囊标签）
5. 英文定义（body）
6. 中文翻译（subheadline）

### 辅助信息（小字体）
7. ローマ字（subheadline）
8. 頻度（caption）
9. 使用注意（caption）
10. 例句翻译（caption）

## 颜色方案

| 元素 | 颜色 | 说明 |
|------|------|------|
| 見出し語 | Primary | 主标题 |
| よみ | Secondary | 读音 |
| ローマ字 | Tertiary | 罗马字 |
| 品词标签背景 | Blue 10% | 淡蓝色背景 |
| 品词标签文字 | Blue | 蓝色文字 |
| 中文翻译 | Secondary | 次要文字 |
| 注意标签 | Orange | 橙色突出 |
| 例句背景 | Gray 5% | 淡灰色背景 |

## 与AI词典的一致性

### 共同点

| 特性 | 本地词库 | AI词典 |
|------|---------|--------|
| 标题字体 | 36pt bold | 32pt bold |
| 读音显示 | たべる [taberu] | たべる [taberu] |
| 品词标签 | 蓝色胶囊 | 蓝色胶囊 |
| 义项编号 | 1. 2. 3. | 1. 2. 3. |
| 中文翻译 | 「...」缩进 | 「...」缩进 |
| 例句卡片 | 灰色背景 | 灰色背景 |
| 注意标注 | 橙色 | 橙色 |

### 差异点

| 特性 | 本地词库 | AI词典 |
|------|---------|--------|
| 数据来源 | JMdict数据库 | AI生成 |
| 定义语言 | 英文为主 | 日语为主 |
| 语法信息 | 无 | 有（活用、搭配） |
| 关联词 | 无 | 有（类义、反义） |
| 音调 | 有（JMdict数据） | 有（AI推测） |

## 代码文件变更

### 修改的文件

**EntryDetailView.swift**
- [EntryDetailView:125-197](vscode-file://vscode-app/Applications/Visual%20Studio%20Code.app/Contents/Resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) - 主体结构优化
- [LocalSenseView:5-82](vscode-file://vscode-app/Applications/Visual%20Studio%20Code.app/Contents/Resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) - 新增义项组件

## 测试指南

### 测试用例

1. **常用词**：
   - 搜索"食べる"
   - 确认：大标题、音调、频率、双语定义、例句

2. **多义项词**：
   - 搜索"行く"
   - 确认：多个义项清晰分隔，品词标签正确

3. **带注意的词**：
   - 搜索有使用注意的词条
   - 确认：橙色"注"标签显示

4. **无中文的词**：
   - 确认：只显示英文定义，不显示空的中文

5. **有音调的词**：
   - 确认：アクセント正确显示

## 用户反馈点

### 可能的优化方向

1. **字体大小调节**：
   - 允许用户调整字体大小
   - 支持动态类型（Dynamic Type）

2. **深色模式优化**：
   - 调整颜色对比度
   - 优化背景色

3. **更多语法信息**：
   - 显示活用形式
   - 显示常见搭配

4. **关联词**：
   - 添加同义词、反义词链接
   - 点击跳转到相关词条

## 总结

本次本地词库UI改进实现了：

✅ **更大更醒目的标题**：36pt字体
✅ **清晰的信息层级**：主次分明
✅ **双语定义显示**：英文 + 中文
✅ **专业的样式**：品词标签、注意标注
✅ **内嵌例句**：直接显示在义项下
✅ **与AI词典一致**：统一的视觉风格

用户现在查看本地词条时，可以获得更加专业、清晰、易读的词典体验！
