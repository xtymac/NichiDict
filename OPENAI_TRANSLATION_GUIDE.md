# OpenAI Translation Guide (GPT-4o mini)

使用OpenAI GPT-4o mini批量翻译 - **超便宜方案！**

## 💰 成本对比

| 方案 | 成本 | 质量 |
|------|------|------|
| **OpenAI GPT-4o mini** | **$0.25** | ⭐⭐⭐⭐ |
| Claude Haiku 4.5 | $1.50 | ⭐⭐⭐⭐⭐ |
| OpenAI GPT-4o | $4.13 | ⭐⭐⭐⭐⭐ |

**推荐理由**：
- ✅ 便宜6倍（$0.25 vs $1.50）
- ✅ 质量完全够用
- ✅ 翻译速度更快

---

## 🔑 获取OpenAI API Key

### 如果你已经有OpenAI账号

1. 访问：https://platform.openai.com/api-keys
2. 点击 **Create new secret key**
3. 给key起个名字（如 "NichiDict Translation"）
4. 复制key（格式：`sk-proj-xxxxx` 或 `sk-xxxxx`）
5. **重要**：复制后立即保存，关闭后无法再查看

### 如果你没有OpenAI账号

1. 访问：https://platform.openai.com/signup
2. 注册账号（可以用Google账号快速注册）
3. 进入 **Billing** 页面添加付款方式
4. 充值至少 $5（推荐充值$10）
5. 然后按上面步骤创建API key

---

## ⚙️ 设置API Key

### 方法A：临时设置（本次terminal会话）
```bash
export OPENAI_API_KEY='sk-proj-xxxxx'
```

### 方法B：永久设置（推荐）
```bash
# 添加到 ~/.zshrc
echo 'export OPENAI_API_KEY="sk-proj-xxxxx"' >> ~/.zshrc
source ~/.zshrc
```

### 验证设置
```bash
echo $OPENAI_API_KEY
# 应该显示你的key
```

---

## 🚀 运行翻译

### 快速开始

```bash
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict"

# 运行翻译（会提示确认）
./scripts/run_openai_translation.sh
```

### 翻译详情

**翻译目标**：
- 前5000个高频词条
- 约15,000个义项定义
- 覆盖80%日常使用

**预估**：
- 💰 成本：**~$0.25** (超便宜！)
- ⏱️ 时间：~15分钟（比Claude快）
- 📈 质量：⭐⭐⭐⭐ (非常好)

**运行过程**：
```
🚀 AI Translation - OpenAI GPT-4o mini
Model: gpt-4o-mini
Target: Top 5000 words
Pricing: $0.150/M input, $0.600/M output

Found 14,532 senses to translate

Estimated cost: $0.24
Estimated time: 14.5 minutes

Continue? (yes/no): yes

🔄 Starting translation...

Progress: 14532/14532 (100%) | Rate: 16.7/s | Cost: $0.24

✅ Translation complete!
💰 You saved $1.25 by using GPT-4o mini instead of Claude!
```

---

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

---

## 🎯 验证翻译

搜索这些词验证效果：

```
行く → 应该显示中文翻译
見る → 应该显示中文翻译
食べる → 应该显示中文翻译
飲む → 应该显示中文翻译
幾 → 应该显示正确的中文（几个；多少）而不是"去; 去世"
```

---

## 💡 扩展选项

### 翻译更多词（如果$0.25太便宜）

由于GPT-4o mini超便宜，你可以翻译更多词：

#### 翻译前10,000词（$0.50）
```python
# 编辑 scripts/translate_with_openai.py 第12行
TOP_N_WORDS = 10000  # 覆盖90%日常使用
```

#### 翻译前20,000词（$1.00）
```python
TOP_N_WORDS = 20000  # 覆盖95%日常使用
```

#### 翻译所有词条（$8-10）
```python
TOP_N_WORDS = 500000  # 100%覆盖，所有42万词条
```

---

## ⚠️ 故障排除

### API Key错误
```
❌ Error: OPENAI_API_KEY not set
```
**解决**：设置API key
```bash
export OPENAI_API_KEY='your-key-here'
```

### 余额不足
```
Error: Insufficient quota
```
**解决**：在 https://platform.openai.com/account/billing 充值

### 速率限制
```
Error: Rate limit exceeded
```
**解决**：脚本会自动重试，稍等片刻

---

## 🎁 额外福利

由于GPT-4o mini超便宜，你可以：

1. **翻译所有词条**：只要$8-10，获得100%覆盖
2. **实时翻译**：在app中集成实时AI翻译功能
3. **批量更新**：定期重新翻译以改进质量

---

## 🆚 OpenAI vs Claude 对比

| 特性 | OpenAI GPT-4o mini | Claude Haiku 4.5 |
|------|-------------------|------------------|
| 成本 (5000词) | **$0.25** ⭐ | $1.50 |
| 成本 (全部) | $8-10 | $85 |
| 质量 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 速度 | 更快 ⚡ | 快 |
| 中文能力 | 很好 | 优秀 |
| Batch size | 100 | 50 |

**结论**：对于词典翻译，**OpenAI GPT-4o mini 性价比更高**！

---

## ✅ 完成！

翻译完成后，你的词典将拥有：
- ✅ 高质量中文翻译
- ✅ 只花了$0.25！
- ✅ 覆盖常用词汇
- ✅ 准确的义项对应

**节省的钱可以用来**：
- 翻译更多词条
- 喝杯咖啡 ☕
- 或者什么都不做，因为省钱就是赚钱！💰

享受你的多语言日文词典！🚀
