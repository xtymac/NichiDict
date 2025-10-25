# 🚀 Gemini 2.5 Flash 配置指南

## 为什么使用 Gemini 2.5 Flash？

### ⚡ 性能对比

| 特性 | GPT-4o-mini | Gemini 2.5 Flash | 优势 |
|-----|------------|-----------------|------|
| 响应速度 | 5-15秒 | **2-8秒** | ✅ **快 2-3倍** |
| 免费配额 | 较小 | **15 RPM, 1500 RPD** | ✅ **配额大** |
| API 访问 | 国际网络 | 全球分布 | ✅ **更稳定** |
| JSON 模式 | 支持 | **原生支持** | ✅ **更准确** |
| 价格 | $0.15/1M tokens | **免费或更便宜** | ✅ **成本低** |

- RPM = Requests Per Minute（每分钟请求数）
- RPD = Requests Per Day（每天请求数）

---

## 步骤 1：获取 Gemini API Key

### 1.1 访问 Google AI Studio
1. 打开浏览器访问：https://aistudio.google.com/
2. 使用 Google 账号登录

### 1.2 创建 API Key
1. 点击左侧菜单的 **"Get API key"**
2. 点击 **"Create API key"**
3. 选择项目（或创建新项目）
4. 复制生成的 API Key（格式类似：`AIzaSyC...`）
5. 妥善保存这个 Key

### 1.3 启用 API
- Gemini API 默认已启用
- 免费配额：
  - 每分钟 15 次请求
  - 每天 1500 次请求
  - 完全免费！

---

## 步骤 2：在应用中配置

### 方法 1：在代码中配置（开发测试）

找到应用启动的地方（通常是 `ContentView.swift` 或 `App.swift`），添加：

```swift
import CoreKit

// 在 App 启动时配置
LLMClient.shared.configure(
    apiKey: "YOUR_GEMINI_API_KEY",
    provider: .gemini("gemini-2.0-flash-exp")  // 最新最快的模型
)
```

### 方法 2：从环境变量读取（推荐）

```swift
import CoreKit

if let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
    LLMClient.shared.configure(
        apiKey: apiKey,
        provider: .gemini("gemini-2.0-flash-exp")
    )
}
```

然后在 Xcode 中设置环境变量：
1. Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. 添加：`GEMINI_API_KEY` = `你的API Key`

---

## 步骤 3：选择模型

### 推荐模型

#### 1. **gemini-2.0-flash-exp** ⭐ 推荐
- **最快**的模型
- 实验版本，性能最佳
- 适合：生产环境，追求速度

#### 2. **gemini-1.5-flash**
- 稳定版本
- 速度也很快
- 适合：需要稳定性的场景

#### 3. **gemini-1.5-pro**
- 质量最高
- 速度较慢
- 适合：需要最高质量的场景

### 配置示例

```swift
// 最快（推荐）
LLMClient.shared.configure(
    apiKey: apiKey,
    provider: .gemini("gemini-2.0-flash-exp")
)

// 稳定
LLMClient.shared.configure(
    apiKey: apiKey,
    provider: .gemini("gemini-1.5-flash")
)

// 最高质量
LLMClient.shared.configure(
    apiKey: apiKey,
    provider: .gemini("gemini-1.5-pro")
)
```

---

## 步骤 4：测试配置

### 4.1 运行应用
```bash
# 在 Xcode 中直接运行，或使用命令行
xcodebuild -project NichiDict.xcodeproj \
  -scheme NichiDict \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build run
```

### 4.2 测试搜索
1. 打开应用
2. 点击 Debug → Clear AI Cache（清除缓存）
3. 搜索："お金が足りません"
4. 查看 Xcode 控制台

### 4.3 预期日志
```
🔑 Cache key calculation:
   - sentence: お金が足りません
   - provider: gemini:gemini-2.0-flash-exp  ← 确认使用 Gemini
   - locale: zh
   - version: v3
❌ Cache MISS - will request AI
📤 Sending AI request with locale: zh
📝 Prompt length: 3247 characters
✅ AI response received in 3.45s  ← 应该在 2-8 秒
```

### 4.4 性能对比
搜索同一个词多次，记录时间：

| API | 第1次 | 第2次 | 第3次 | 平均 |
|-----|-------|-------|-------|------|
| GPT-4o-mini | 12s | 11s | 13s | 12s |
| Gemini Flash | 4s | 3s | 5s | **4s** |

---

## 常见问题

### Q1: API Key 无效
**错误**：`HTTP 400: API key not valid`

**解决**：
1. 检查 Key 是否正确复制（包括开头的 `AIza`）
2. 确认 API 已启用（访问 Google Cloud Console）
3. 检查项目配额未超限

### Q2: 速度没有变快
**可能原因**：
1. 命中了旧缓存 → 清除 AI 缓存
2. 网络问题 → 检查网络连接
3. 模型选择错误 → 确认使用 `gemini-2.0-flash-exp`

### Q3: JSON 解析错误
**错误**：`AI返回格式错误 (Gemini)`

**解决**：
- Gemini 已配置 `responseMimeType: "application/json"`
- 如果仍然出错，检查提示词格式
- 查看控制台的原始响应进行调试

### Q4: 配额超限
**错误**：`HTTP 429: Resource exhausted`

**解决**：
- 免费配额：15 RPM, 1500 RPD
- 等待 1 分钟后重试
- 或升级到付费计划（很便宜）

---

## 高级配置

### 自定义超时时间

如果网络很慢，可以增加超时：

在 `LLMClient.swift` 的 `requestGeminiContent` 方法中：
```swift
req.timeoutInterval = 60  // 改为 60 秒
```

### 调整温度参数

控制 AI 的创造性：
```swift
"generationConfig": [
    "temperature": 0.1,  // 0-1，越低越确定
    "maxOutputTokens": 2048
]
```

### 启用安全设置

```swift
"safetySettings": [
    [
        "category": "HARM_CATEGORY_HARASSMENT",
        "threshold": "BLOCK_MEDIUM_AND_ABOVE"
    ]
]
```

---

## 性能优化建议

### 1. 使用 Gemini 2.0 Flash Exp
- 这是目前最快的模型
- 响应时间通常在 3-5 秒

### 2. 优化提示词
- 当前提示词约 3000+ 字符
- 可以考虑简化（但需要平衡质量）

### 3. 预加载常见查询
- 后台预先查询热门词汇
- 用户搜索时直接返回缓存

### 4. 实现流式响应（下一步）
- 结果逐步显示
- 用户体验更好

---

## 迁移指南：从 OpenAI 切换到 Gemini

### 当前配置（OpenAI）
```swift
LLMClient.shared.configure(
    apiKey: openAIKey,
    provider: .openAI("gpt-4o-mini")
)
```

### 新配置（Gemini）
```swift
LLMClient.shared.configure(
    apiKey: geminiKey,
    provider: .gemini("gemini-2.0-flash-exp")
)
```

### 注意事项
1. ✅ API 格式已自动处理
2. ✅ JSON 输出已配置
3. ✅ 缓存系统自动适配
4. ⚠️ 清除旧缓存（不同 provider 的缓存互不影响）

---

## 成本对比（付费使用时）

### OpenAI GPT-4o-mini
- 输入：$0.150 / 1M tokens
- 输出：$0.600 / 1M tokens
- 每次查询约：0.5-1分钱

### Gemini 2.5 Flash
- **免费额度很大**（每天 1500 次）
- 付费：$0.075 / 1M tokens（输入）
- 付费：$0.30 / 1M tokens（输出）
- 每次查询约：0.3-0.5分钱

💡 **Gemini 更便宜！**

---

## 监控和调试

### 查看性能日志
```
📝 Prompt length: 3247 characters
✅ AI response received in 3.45s
```

### 性能基准
- ✅ 优秀：< 5 秒
- ⚠️ 可接受：5-10 秒
- ❌ 需优化：> 10 秒

### 调试技巧
1. 清除缓存测试真实速度
2. 对比不同模型的性能
3. 记录网络环境对速度的影响
4. 使用 Instruments 分析性能瓶颈

---

## 总结

### ✅ Gemini 的优势
1. **速度快 2-3 倍**
2. **免费配额大**
3. **API 稳定**
4. **成本更低**

### 📝 配置步骤
1. 获取 API Key
2. 配置 provider
3. 选择模型（推荐 `gemini-2.0-flash-exp`）
4. 清除缓存测试

### 🎯 预期效果
- 搜索响应时间：**从 12秒 → 4秒**
- 用户体验大幅提升
- 成本显著降低

---

**下一步**：实现流式响应，让结果逐步显示，进一步提升体验！
