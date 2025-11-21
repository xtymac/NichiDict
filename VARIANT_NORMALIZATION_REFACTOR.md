# Variant Normalization Refactor

## Branch
`feature/jmdict-variant-normalization`

## Objective
Implement JMDict-based variant normalization and remove all hardcoded variant logic.

## Goals
- Replace hardcoded variant handling with JMDict-based normalization
- Remove all hardcoded variant logic from the codebase
- Improve maintainability by relying on JMDict data structure
- Ensure consistent variant handling across the application

## Current Status
- Branch created: `feature/jmdict-variant-normalization`
- Branch pushed to remote: ✅
- Checkpoint tag created: `checkpoint-before-variant-refactor` ✅
- Previous work stashed: Conjunction priority adjustments from `feature/n4-vocabulary-testing`

## Rollback Instructions (如果失败需要退回)

### 方法 1: 使用检查点标签回退
```bash
# 切换到基础分支
git checkout feature/n4-vocabulary-testing

# 回退到检查点
git reset --hard checkpoint-before-variant-refactor

# 如果需要强制推送（谨慎使用）
git push origin feature/n4-vocabulary-testing --force
```

### 方法 2: 删除当前分支，重新从检查点创建
```bash
# 删除本地分支
git branch -D feature/jmdict-variant-normalization

# 从检查点创建新分支
git checkout -b feature/jmdict-variant-normalization checkpoint-before-variant-refactor

# 删除远程分支（如果需要）
git push origin --delete feature/jmdict-variant-normalization
```

### 方法 3: 恢复到基础分支的最新状态
```bash
# 切换到基础分支
git checkout feature/n4-vocabulary-testing

# 拉取最新代码
git pull origin feature/n4-vocabulary-testing

# 恢复暂存的更改（如果需要）
git stash pop
```

## Testing Plan
- [ ] Test variant normalization with various kanji forms
- [ ] Verify search results consistency
- [ ] Test reverse search functionality
- [ ] Validate against existing test cases
- [ ] Performance testing

## Notes
- This is a major refactor of the database sorting algorithm
- Will return to testing after implementation
- Previous branch `feature/n4-vocabulary-testing` is preserved with stashed changes

