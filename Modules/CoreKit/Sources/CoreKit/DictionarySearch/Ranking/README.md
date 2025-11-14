# Universal Ranking Framework

## 概述 (Overview)

这是一个全新的、可配置的词典搜索排序框架，旨在解决"修好某些词、换个词又歪"的问题。

### 核心优势

1. **三层架构**：硬规则 → 特征打分 → 稳定排序
2. **完全可配置**：JSON配置文件，支持热更新和A/B测试
3. **类型安全**：基于协议的设计，编译时类型检查
4. **可调试**：内置详细的Score Breakdown工具
5. **向后兼容**：可选的Legacy Scorer回退

## 架构设计

### 第一层：硬规则 (Hard Rules)

硬规则负责将搜索结果分配到不同的Bucket，实现粗粒度的分类：

```
Bucket A (exactMatch)       - 精确匹配、读音匹配
Bucket B (commonPrefixMatch) - 常见前缀、**表达式**（关键修复！）、JLPT N5/N4
Bucket C (generalMatch)      - 一般匹配
Bucket D (specializedTerm)   - 专业领域、古语
```

**关键修复**：Expression词条移至Bucket B，防止"また明日"被"今明日/大明日"压制。

### 第二层：特征打分 (Feature Scoring)

每个特征都有独立的权重和min/max范围，防止单一特征主导排序：

#### 匹配类型特征 (Match Type Features)
- `exactMatch` (0-100): 精确匹配
- `lemmaMatch` (0-35): 读音匹配
- `prefixMatch` (0-30): 前缀匹配
- `containsMatch` (0-10): 包含匹配

#### 权威性特征 (Authority Features)
- `jlpt` (0-15): JLPT等级 (N5=10, N4=7, N3=4, N2=2, N1=0)
- `frequency` (0-15): 词频 **使用S曲线平滑** (sigmoid smoothing)

#### 词性与模式特征 (POS & Pattern Features)
- `posPriority` (0-8): 词性优先级 (动词>形容词>名词>助词)
- `commonWord` (0-5): 常用词奖励
- `entryType` (0-4): 词条类型 (word > compound > expression)
- `surfaceLength` (-5-0): 长度惩罚 (偏好短词)

#### 惩罚特征 (Penalty Features)
- `commonPatternPenalty` (-10-0): 常见模式惩罚 (する、られる等)
- `rareWordPenalty` (-8-0): 罕见词惩罚
- `archaicWordPenalty` (-12-0): 古语惩罚
- `specializedDomainPenalty` (-6-0): 专业领域惩罚
- `vulgarSlangPenalty` (-8-0): 俗语/粗话惩罚

### 第三层：稳定排序 (Tie-Breakers)

当分数相同时，按以下顺序打破平局：

```
1. frequencyRank ↑  (词频排名，升序)
2. jlptBonus ↓      (JLPT等级，降序 N5>N4>N3...)
3. surfaceLength ↑  (表层长度，升序 - 短词优先)
4. createdAt ↑      (创建时间，升序)
5. id ↑             (ID，升序 - 最终保证稳定性)
```

## 文件结构

```
Ranking/
├── Core/
│   ├── ScoringContext.swift          # 评分上下文
│   ├── ScoringFeature.swift          # 特征协议
│   ├── HardRule.swift                # 硬规则协议
│   ├── RankingConfiguration.swift   # 配置结构
│   ├── FeatureRegistry.swift         # 类型安全注册表
│   └── RankingEngine.swift           # 核心引擎
│
├── Features/
│   ├── MatchTypeFeatures.swift      # 匹配类型特征
│   ├── AuthorityFeatures.swift      # 权威性特征
│   ├── POSFeatures.swift            # 词性特征
│   └── PenaltyFeatures.swift        # 惩罚特征
│
├── Rules/
│   └── BucketRules.swift            # Bucket分配规则
│
├── Debug/
│   └── RankingDebugger.swift        # 调试工具
│
├── Resources/
│   └── ranking_config.json          # 默认配置
│
└── RankingConfigLoader.swift        # 配置加载器
```

## 使用方法

### 基本用法

```swift
// 1. 加载配置
let config = try RankingConfigManager.shared.getCurrentConfiguration()

// 2. 创建引擎
let engine = try RankingEngine(configuration: config)

// 3. 准备数据
let entries: [DictionaryEntry] = [...] // 你的词条
let context = ScoringContext(
    query: "明日",
    scriptType: .hiragana,
    matchType: .prefix,
    isExactHeadword: false,
    isLemmaMatch: false,
    useReverseSearch: false
)

let entriesWithContext = entries.map { ($0, context) }

// 4. 排序
let rankedEntries = engine.rank(entries: entriesWithContext)

// 5. 使用结果
for rankedEntry in rankedEntries {
    print("\(rankedEntry.entry.headword): \(rankedEntry.score)")
}
```

### Debug模式

```swift
// 查看单个词条的详细打分
let debugger = RankingDebugger.shared
let breakdown = rankedEntry.breakdown
print(debugger.formatBreakdown(breakdown, headword: rankedEntry.entry.headword))

// 输出：
// 📊 Breakdown for 'また明日':
//    Total: 127.50
//    Bucket: commonPrefixMatch (expressionBucket)
//    Features:
//       exactMatch: 100.00
//       frequency: 18.00
//       jlpt: 8.00
//       ...
```

### A/B测试

```swift
// 切换到实验配置
try RankingConfigManager.shared.switchProfile("exp1")

// 比较两个配置
let report = try debugger.compareRankings(
    query: "明日",
    entries: entries,
    configA: defaultConfig,
    configB: experimentConfig
)

print(debugger.formatComparisonReport(report))
```

## 配置文件

### 位置优先级

1. **Documents目录** (`~/Documents/ranking_config.json`) - Debug覆盖
2. **Bundle资源** (App内置) - 默认配置
3. **硬编码回退** - 最后保障

### 配置格式

```json
{
  "version": "1.0",
  "profile": "default",
  "useLegacyScorer": false,

  "features": [
    {
      "type": "frequency",
      "weight": 1.2,
      "minScore": 0,
      "maxScore": 15,
      "enabled": true,
      "parameters": {
        "smoothing": "sigmoid",
        "midpoint": 5.0
      }
    }
  ],

  "hardRules": [
    {
      "type": "expressionBucket",
      "priority": 3,
      "enabled": true
    }
  ],

  "tieBreakers": [
    { "field": "frequencyRank", "order": "ascending" }
  ]
}
```

### 修改配置

```swift
// 方法1: 直接编辑JSON文件后重新加载
try RankingConfigManager.shared.reloadConfiguration()

// 方法2: 程序化修改并保存
var config = try RankingConfigLoader.shared.loadConfiguration()
// ... 修改config ...
try RankingConfigLoader.shared.saveConfiguration(config, profile: "custom")
```

## 关键技术亮点

### 1. S曲线平滑 (Sigmoid Smoothing)

传统stepwise函数在边界处有跳变 (rank 30→31 突然掉分)。

新的sigmoid函数提供平滑过渡：

```swift
func calculateSigmoid(rank: Int) -> Double {
    let x = log(Double(rank + 1))
    return maxScore / (1.0 + exp(x - midpoint))
}
```

### 2. 类型安全的参数解码

使用`AnyCodable` enum + `FeatureRegistry`实现JSON到强类型的转换：

```swift
enum AnyCodable: Codable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)
    case array([AnyCodable])
    case object([String: AnyCodable])
}
```

### 3. Expression → Bucket B 修复

这是本次最关键的修复：

**问题**：常见表达"また明日"被罕见复合词"今明日/大明日"压制

**原因**：两者都在Bucket C，按频率排序时"今明日"反而靠前

**解决**：Expression词条提升至Bucket B，确保常见表达优先展示

## MVP完成情况

### ✅ 已完成 (Phase 1-5)

- [x] 核心协议和结构 (ScoringFeature, HardRule, RankingConfiguration)
- [x] FeatureRegistry (类型安全参数管理)
- [x] RankingEngine核心逻辑
- [x] 所有特征实现 (15个特征)
- [x] 所有硬规则实现 (7个规则)
- [x] 稳定排序层 (5个tie-breakers)
- [x] 默认配置文件 (ranking_config.json)
- [x] 配置加载与校验
- [x] Debug可视化工具

### ⏳ 待完成 (Phase 6)

- [ ] Legacy Scorer封装 (向后兼容)
- [ ] 集成到SearchService
- [ ] 回归测试用例
- [ ] 性能测试与优化

## 下一步行动

### 建议测试流程

1. **单元测试**：测试各个Feature的calculate方法
2. **集成测试**：对比新旧Scorer的排序结果
3. **A/B测试**：在实际App中切换配置，收集用户反馈

### 集成步骤

```swift
// 在SearchService中添加：

class SearchService {
    private let rankingEngine: RankingEngine
    private let legacyScorer: LegacyScorer // 保留旧实现

    func search(_ query: String) -> [SearchResult] {
        let rawResults = database.search(query)

        // 根据配置选择Scorer
        if RankingConfigManager.shared.isUsingLegacyScorer {
            return legacyScorer.rank(rawResults)
        } else {
            return rankingEngine.rank(rawResults)
        }
    }
}
```

## 故障排除

### 配置加载失败

```swift
// 检查配置是否有效
do {
    let config = try RankingConfigLoader.shared.loadConfiguration()
    try config.validate()
} catch {
    print("配置错误: \(error)")
}
```

### 排序结果异常

```swift
// 使用Debug工具分析
let stats = RankingDebugger.shared.calculateStatistics(rankedEntries)
print(RankingDebugger.shared.formatStatistics(stats))

// 输出Breakdown
print(RankingDebugger.shared.formatBreakdowns(rankedEntries, limit: 20))
```

## 性能考虑

- **特征计算**: O(n) 每个词条
- **排序**: O(n log n) 使用标准库sort
- **预期性能**: 1000个词条 < 10ms (需实测验证)

## 作者与维护

框架设计与实现：Claude Code Assistant
日期：2025-11-10

## License

MIT License (或根据项目许可调整)
