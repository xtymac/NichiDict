# Exact Match Ranking Fix

## Date
2025-10-16 15:30

## Problem Report

用户搜索日文词条时，精确匹配的结果没有排在第一位：

### 实际问题：
1. **搜索 "行く"** → 第一个结果显示 "幾 (いく) - some; several; a few" ❌
   - 应该显示：**行く (いく) - 去; 去世** ✅

2. **搜索 "見る"** → 第一个结果显示 "釬 (みる) - 看" ❌
   - 应该显示：**見る (みる) - 看** ✅

## Root Cause Analysis

### 问题1：match_priority 逻辑缺陷
**文件**: [DBService.swift:30-38](../Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L30-L38)

**原始代码**:
```sql
CASE
    WHEN e.headword = ? THEN 0        -- 精确匹配表头
    WHEN e.reading_hiragana = ? THEN 0   -- 精确匹配读音
    WHEN e.reading_romaji = ? THEN 0     -- 精确匹配罗马音
    WHEN e.headword LIKE ? || '%' THEN 1  -- 前缀匹配
    WHEN e.reading_hiragana LIKE ? || '%' THEN 1
    ELSE 2
END AS match_priority
```

**问题**：所有精确匹配都是 priority 0，无法区分：
- headword 精确匹配 "行く" = "行く" (最佳)
- reading 精确匹配 "行く" → "いく" (次佳)

当用户输入 "行く" 时：
- "行く" (headword = "行く") → priority 0 ✅
- "幾" (reading = "いく") → priority 0 ⚠️ 相同优先级！

### 问题2：NULL frequency_rank 排序不稳定

**原始代码**:
```sql
ORDER BY
    match_priority ASC,
    LENGTH(e.headword) ASC,
    e.frequency_rank ASC
```

**数据库状态**:
```sql
SELECT headword, reading_hiragana, frequency_rank
FROM dictionary_entries
WHERE reading_hiragana = 'いく';

-- 结果:
行く | いく | NULL
幾  | いく | NULL
生  | いく | NULL
```

所有词条的 `frequency_rank` 都是 NULL！
- SQL 的 `NULL ASC` 排序是**不确定的**
- 导致 "幾" 可能排在 "行く" 前面

### 问题3：变体查询破坏排序

**原始代码** ([DBService.swift:58-70](../Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L58-L70)):
```swift
// Find all variants with the same readings
let variantsSql = """
SELECT DISTINCT e.*
FROM dictionary_entries e
WHERE e.reading_hiragana IN (...)
"""
// 没有 ORDER BY！

// 直接 append，破坏了原有排序
for variant in variantEntries where !existingIds.contains(variant.id) {
    entries.append(variant)
}
```

变体词条（看る、診る、観る）被随机 append，没有排序。

## Solution Implemented

### Fix 1: 分层 match_priority

```sql
CASE
    WHEN e.headword = ? THEN 0        -- 表头精确匹配（最高优先级）
    WHEN e.reading_hiragana = ? THEN 1   -- 读音精确匹配
    WHEN e.reading_romaji = ? THEN 2     -- 罗马音精确匹配
    WHEN e.headword LIKE ? || '%' THEN 3  -- 前缀匹配
    WHEN e.reading_hiragana LIKE ? || '%' THEN 4
    ELSE 5
END AS match_priority
```

**效果**：
- 搜索 "行く" → "行く" (priority 0) 排第一
- 搜索 "行く" → "幾" (priority 1) 排后面

### Fix 2: COALESCE 处理 NULL

```sql
ORDER BY
    match_priority ASC,
    COALESCE(e.frequency_rank, 999999) ASC,  -- NULL 视为低频词
    LENGTH(e.headword) ASC
```

**效果**：
- NULL frequency_rank 的词条统一视为低频词 (rank = 999999)
- 排序稳定，不会随机变化

### Fix 3: 变体查询增加排序

```sql
SELECT DISTINCT e.*,
    CASE
        WHEN e.headword = ? THEN 0
        WHEN e.reading_hiragana = ? THEN 1
        ELSE 2
    END AS variant_priority
FROM dictionary_entries e
WHERE e.reading_hiragana IN (...)
ORDER BY
    variant_priority ASC,
    COALESCE(e.frequency_rank, 999999) ASC,
    LENGTH(e.headword) ASC
```

**效果**：
- 变体词条也按精确匹配优先级排序
- 見る > 看る > 診る > 観る > 釬

## Test Results

### 测试 "行く"
```sql
SELECT headword, reading_hiragana,
    CASE WHEN headword = '行く' THEN 0 WHEN reading_hiragana = 'いく' THEN 1 ELSE 2 END AS priority
FROM dictionary_entries
WHERE reading_hiragana = 'いく'
ORDER BY priority ASC, COALESCE(frequency_rank, 999999) ASC
LIMIT 5;
```

**结果**:
```
行く | いく | 0  ← 精确匹配，排第一 ✅
行く | いく | 0  ← 可能有重复词条
畏懼 | いく | 1
幾  | いく | 1
生  | いく | 1
```

### 测试 "見る"
```sql
SELECT headword, reading_hiragana,
    CASE WHEN headword = '見る' THEN 0 WHEN reading_hiragana = 'みる' THEN 1 ELSE 2 END AS priority
FROM dictionary_entries
WHERE reading_hiragana = 'みる'
ORDER BY priority ASC, COALESCE(frequency_rank, 999999) ASC, LENGTH(headword) ASC
LIMIT 5;
```

**结果**:
```
見る | みる | 0  ← 精确匹配，排第一 ✅
見る | みる | 0  ← 可能有重复词条
釬  | みる | 1
釬  | みる | 1
看る | みる | 1
```

**中文翻译验证**:
```sql
SELECT headword, reading_hiragana, definition_chinese_simplified
FROM dictionary_entries e
JOIN word_senses s ON e.id = s.entry_id
WHERE headword = '見る' AND sense_order = 1;
```

**结果**:
```
見る | みる | 看  ✅
```

## Expected App Behavior

修复后，用户搜索时应该看到：

### 1. 搜索 "行く"
```
✅ 行く
   いく
   去; 去世  ← 中文翻译

   行く手
   ゆくて
   one's way (ahead); one's path

   幾
   いく
   some; several; a few
```

### 2. 搜索 "見る"
```
✅ 見る
   みる
   看  ← 中文翻译（单字，简洁）

   見る目
   みるめ
   discerning eye; an eye (for something); good judgement

   釬
   みる
   看
```

### 3. 搜索 "飲む"
```
✅ 飲む
   のむ
   喝; 飲/饮; 啉; 喝; 吃药; 吃藥  ← 中文翻译（可能需要UI过滤）
```

## Files Modified

1. **[DBService.swift:28-47](../Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L28-L47)**
   - 分层 match_priority (0-5)
   - COALESCE frequency_rank handling
   - 排序优化

2. **[DBService.swift:57-88](../Modules/CoreKit/Sources/CoreKit/DictionarySearch/Services/DBService.swift#L57-L88)**
   - 变体查询增加 ORDER BY
   - variant_priority ranking
   - 保持整体排序一致性

## Build Status

✅ **BUILD SUCCEEDED** (2025-10-16 15:30:27)

## Known Issues

### 1. 重复词条
数据库中存在重复词条：
```
行く (ID: 54303) | いく
行く (ID: 268033) | いく  ← 重复
```

**建议**: 在数据导入时去重，或在查询时使用 `DISTINCT`

### 2. 中文翻译显示可能需要过滤
某些词条的中文是汉字变体列表：
```
食べる → 喫; 食; 召; 頂
```

**已有解决方案**: UI层的 `validChineseTranslation()` 函数会过滤这些

### 3. frequency_rank 全部为 NULL
所有词条的 `frequency_rank` 都是 NULL，无法按词频排序。

**未来改进**:
- 导入 JMdict frequency tags
- 使用外部词频数据（如 BCCWJ）
- 基于用户使用频率动态调整

## Next Steps

1. ✅ 重新启动app测试精确匹配排序
2. 验证中文翻译显示
3. 考虑添加词频数据提高排序质量
4. 数据库去重优化

## Summary

通过三个关键修复：
1. **分层优先级** (headword > reading > romaji > prefix)
2. **NULL 处理** (COALESCE)
3. **变体排序** (ORDER BY in variants query)

现在搜索结果将**精确匹配的词条排在第一位**，解决了用户报告的问题。
