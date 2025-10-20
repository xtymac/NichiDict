# AI Translation Guide

使用Claude Haiku 4.5批量翻译高频日文词条

## 📋 准备工作

### 1. 获取Anthropic API Key

1. 访问：https://console.anthropic.com/
2. 注册/登录账号
3. 点击左侧 **API Keys**
4. 点击 **Create Key**
5. 复制生成的key（格式：`sk-ant-api03-xxxxx`）

### 2. 设置API Key

**方法A：临时设置（本次terminal会话）**
```bash
export ANTHROPIC_API_KEY='sk-ant-api03-xxxxx'
```

**方法B：永久设置（推荐）**
```bash
# 添加到 ~/.zshrc
echo 'export ANTHROPIC_API_KEY="sk-ant-api03-xxxxx"' >> ~/.zshrc
source ~/.zshrc
```

验证设置：
```bash
echo $ANTHROPIC_API_KEY
# 应该显示你的key
```

## 🚀 运行翻译

### 快速开始

```bash
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict"

# 运行翻译（会提示确认）
./scripts/run_translation.sh
```

### 详细信息

**翻译目标**：
- 前5000个高频词条
- 约15,000个义项定义
- 覆盖80%日常使用

**预估**：
- 成本：~$5 USD
- 时间：~30分钟
- 质量：⭐⭐⭐⭐⭐

**翻译过程**：
1. 脚本会显示翻译数量和预估成本
2. 询问是否继续（输入 `yes` 确认）
3. 实时显示进度和成本
4. 完成后显示统计信息和样例

## 📊 翻译后使用

### 1. 更新App数据库

```bash
# 复制翻译后的数据库到App
cp data/dictionary_full_multilingual.sqlite NichiDict/Resources/seed.sqlite

# 重新构建App
cd NichiDict
xcodebuild -scheme NichiDict -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### 2. 安装到模拟器

```bash
# 卸载旧版
xcrun simctl uninstall booted org.uixai.NichiDict

# 安装新版
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/NichiDict-*/Build/Products/Debug-iphonesimulator/NichiDict.app

# 启动
xcrun simctl launch booted org.uixai.NichiDict
```

## 🎯 验证翻译质量

搜索这些常用词验证翻译效果：

```
行く → 应该显示准确的中文翻译
見る → 应该显示准确的中文翻译
食べる → 应该显示准确的中文翻译
飲む → 应该显示准确的中文翻译
```

## 💡 高级选项

### 只翻译前1000个词（测试）

修改 `scripts/translate_top_words.py` 第12行：
```python
TOP_N_WORDS = 1000  # 改为1000
```

### 查看详细日志

```bash
# 直接运行Python脚本
source venv/bin/activate
python3 scripts/translate_top_words.py data/dictionary_full_multilingual.sqlite
```

## ⚠️ 故障排除

### API Key错误

```
❌ Error: ANTHROPIC_API_KEY not set
```

**解决**：确保已设置API key
```bash
export ANTHROPIC_API_KEY='your-key-here'
```

### 网络错误

```
⚠️  Error: Connection timeout
```

**解决**：检查网络连接，脚本会自动重试

### 数据库锁定

```
Error: database is locked
```

**解决**：关闭其他访问数据库的程序

## 📈 成本优化

### 当前方案（$5）
- 翻译前5000个高频词
- 覆盖80%日常使用

### 扩展方案
如果想要更高覆盖率：

**前10,000词**：$10，覆盖90%
```python
TOP_N_WORDS = 10000
```

**前20,000词**：$20，覆盖95%
```python
TOP_N_WORDS = 20000
```

**全部词条**：$85，100%覆盖
```python
TOP_N_WORDS = 500000  # 实际上会翻译所有词
```

## 🎉 完成！

翻译完成后，你的词典将拥有：
- ✅ 高质量中文翻译
- ✅ 覆盖常用词汇
- ✅ 准确的义项对应
- ✅ 自然的中文表达

享受你的多语言日文词典！🚀
