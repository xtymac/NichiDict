# NichiDict 測試指南

**版本**: 1.0 - 完整詞庫版
**日期**: 2025-10-13

## 快速開始

### 1. 在 Xcode 中運行 (最簡單)

```bash
# 1. 打開項目
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict"
open NichiDict.xcodeproj

# 2. 在 Xcode 中：
#    - 選擇 iPhone 17 Pro 模擬器（或其他設備）
#    - 點擊 ▶️ 運行按鈕（或按 Cmd+R）
#    - 等待編譯和啟動（首次啟動可能需要 10-20 秒，因為要載入 60MB 數據庫）
```

### 2. 使用命令行運行

```bash
cd "/Users/mac/Maku Box Dropbox/Maku Box/Project/NichiDict/NichiDict"

# 構建並運行
xcodebuild -scheme NichiDict \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# 啟動模擬器
open -a Simulator

# 在模擬器中安裝並運行 app
xcrun simctl install booted \
  "$HOME/Library/Developer/Xcode/DerivedData/NichiDict-alttqmwmehovdldfmqiqlgmqtvjf/Build/Products/Debug-iphonesimulator/NichiDict.app"

xcrun simctl launch booted org.uixai.NichiDict
```

## 🧪 測試場景

### 場景 1: 基本搜索功能

#### 測試用例 1.1: 搜索漢字詞
```
輸入: 食べる
預期結果:
  - 顯示多個結果（食べる, たべる, 等變體）
  - 首個結果顯示 "食べる"
  - 副標題顯示 "たべる"
  - 定義: "to eat"
```

#### 測試用例 1.2: 搜索假名
```
輸入: たべる
預期結果:
  - 顯示相同結果（與 1.1 相同）
  - 結果包含所有相關變體
```

#### 測試用例 1.3: 搜索羅馬字
```
輸入: taberu
預期結果:
  - 顯示 "食べる" 和相關詞條
  - 自動轉換為假名搜索
```

#### 測試用例 1.4: 實時搜索
```
操作: 慢慢輸入 "ta-be-ru"
預期結果:
  - 每個字符後顯示加載指示器
  - 結果實時更新
  - 沒有明顯延遲（< 300ms）
```

#### 測試用例 1.5: 常用詞搜索
```
測試以下詞彙是否能找到：
✓ 日本 (nihon) - Japan
✓ 学校 (gakkou) - school
✓ 先生 (sensei) - teacher
✓ 勉強 (benkyou) - study
✓ 友達 (tomodachi) - friend
✓ 本 (hon) - book
✓ 水 (mizu) - water
✓ 時間 (jikan) - time
```

### 場景 2: 詳情頁功能

#### 測試用例 2.1: 查看詞條詳情
```
操作:
  1. 搜索 "食べる"
  2. 點擊第一個結果

預期結果:
  - 顯示詳情頁
  - 標題: "食べる"
  - 讀音: "たべる"
  - 羅馬字: "taberu"
  - 定義: 包含英文翻譯
  - 詞性: "ichidan verb, transitive"
```

#### 測試用例 2.2: 音調顯示（如果有）
```
操作: 查看有音調數據的詞條
預期結果:
  - 音調部分顯示正確（如 "た↓べる"）
  - 如無音調數據，該部分不顯示
```

#### 測試用例 2.3: 頻率顯示（如果有）
```
操作: 查看常用詞
預期結果:
  - 頻率部分顯示排名（如 "Top 500"）
  - 如無頻率數據，顯示 "Uncommon" 或不顯示
```

### 場景 3: 邊界情況測試

#### 測試用例 3.1: 空搜索
```
操作: 清空搜索框
預期結果:
  - 不顯示任何結果
  - 不顯示錯誤消息
  - 顯示初始提示（如有）
```

#### 測試用例 3.2: 無結果搜索
```
輸入: xyzabc123
預期結果:
  - 顯示 "未找到本地詞條"
  - 可選：顯示 "用 AI 解說/翻譯" 按鈕
```

#### 測試用例 3.3: 超長查詢
```
輸入: 101 個字符的字符串
預期結果:
  - 顯示錯誤消息："Search query too long"
  - 不崩潰
```

#### 測試用例 3.4: 特殊字符
```
輸入: !@#$%^&*()
預期結果:
  - 顯示 "Search contains invalid characters" 或無結果
  - 不崩潰
```

#### 測試用例 3.5: SQL 注入嘗試
```
輸入: '; DROP TABLE dictionary_entries; --
預期結果:
  - 安全處理，不執行任何 SQL
  - 顯示無結果或過濾後的搜索
  - 數據庫完好無損
```

### 場景 4: 性能測試

#### 測試用例 4.1: 冷啟動時間
```
操作:
  1. 完全關閉 app
  2. 重新啟動
  3. 測量到搜索框可用的時間

預期結果:
  - < 2 秒到達可搜索狀態
  - 數據庫完整性檢查通過
```

#### 測試用例 4.2: 搜索響應時間
```
操作: 搜索 "a"（會返回大量結果）
預期結果:
  - < 200ms 返回結果
  - 結果限制在 100 個
```

#### 測試用例 4.3: 滾動性能
```
操作:
  1. 搜索返回多個結果
  2. 快速滾動列表

預期結果:
  - 流暢滾動（60 fps）
  - 無卡頓或延遲
```

#### 測試用例 4.4: 內存使用
```
操作:
  1. 在 Xcode 中打開 Memory Debugger
  2. 執行多次搜索
  3. 查看多個詳情頁

預期結果:
  - 無明顯內存洩漏
  - 內存使用穩定
```

### 場景 5: 多語言測試

#### 測試用例 5.1: 英文界面
```
操作:
  1. 設定 → 一般 → 語言與地區
  2. 設置為 English
  3. 重啟 app

預期結果:
  - 搜索占位符: "Enter Japanese word (e.g., 勉強)"
  - 詳情頁標籤: "Pitch Accent", "Frequency", "Definitions"
```

#### 測試用例 5.2: 日文界面
```
操作: 切換系統語言到日本語
預期結果:
  - 所有 UI 文本顯示日文
  - 搜索提示: "日本語を入力..."
```

#### 測試用例 5.3: 簡體中文界面
```
操作: 切換系統語言到簡體中文
預期結果:
  - 搜索提示: "輸入日文詞彙（例如：勉強）"
  - 詳情頁: "音調", "頻率", "定義"
```

#### 測試用例 5.4: 繁體中文界面
```
操作: 切換系統語言到繁體中文
預期結果:
  - 搜索提示: "輸入日文詞彙（例如：勉強）"
  - 詳情頁: "音調", "頻率", "定義"
```

## 🐛 已知問題

### 當前限制
1. ❌ **無頻率排名** - JMdict 不包含頻率數據
2. ❌ **無音調數據** - JMdict 不包含音調標記
3. ❌ **無例句** - 需要從 Tatoeba 或其他來源導入
4. ⚠️ **首次啟動較慢** - 需要載入 60MB 數據庫並驗證完整性（~10-20 秒）
5. ⚠️ **App 體積較大** - 60MB 數據庫使 app bundle 增加

### 預期行為
- 詳情頁的 "Pitch Accent" 部分可能不顯示（因為無數據）
- 詳情頁的 "Frequency" 部分可能顯示 "Uncommon"（因為無數據）
- 詳情頁的 "All Examples" 部分不顯示（因為無例句數據）

## 📊 測試檢查清單

### 基本功能 ✅
- [ ] App 成功啟動
- [ ] 搜索框可以輸入
- [ ] 搜索返回結果
- [ ] 點擊結果進入詳情頁
- [ ] 返回按鈕工作正常

### 搜索功能 ✅
- [ ] 漢字搜索正常
- [ ] 假名搜索正常
- [ ] 羅馬字搜索正常
- [ ] 實時搜索工作
- [ ] 無結果時顯示提示
- [ ] 結果按相關性排序

### 詳情頁 ✅
- [ ] 標題顯示正確
- [ ] 讀音顯示正確
- [ ] 定義顯示正確
- [ ] 詞性顯示正確
- [ ] 導航工作正常

### 邊界情況 ✅
- [ ] 空搜索不崩潰
- [ ] 超長查詢被正確處理
- [ ] 特殊字符被過濾
- [ ] SQL 注入被防止

### 性能 ✅
- [ ] 啟動時間 < 2 秒
- [ ] 搜索響應 < 200ms
- [ ] 滾動流暢
- [ ] 無內存洩漏

### 多語言 ✅
- [ ] 英文界面正確
- [ ] 日文界面正確
- [ ] 簡體中文界面正確
- [ ] 繁體中文界面正確

## 🔍 調試技巧

### 查看控制台日誌
在 Xcode 中運行時，查看控制台輸出：
- 數據庫打開日誌
- 搜索查詢日誌
- 錯誤消息

### 使用數據庫查詢工具
```bash
# 連接到 app 的數據庫
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/NichiDict-*/Build/Products/Debug-iphonesimulator/NichiDict.app"
sqlite3 "$APP_PATH/seed.sqlite"

# 查詢示例
SELECT COUNT(*) FROM dictionary_entries;
SELECT * FROM dictionary_entries WHERE headword = '食べる';
```

### 檢查數據庫完整性
```bash
sqlite3 "$APP_PATH/seed.sqlite" "PRAGMA integrity_check;"
```

## 📱 在真機上測試

### 準備工作
1. 連接 iPhone/iPad
2. 在 Xcode 中選擇真實設備
3. 設置開發者證書（如需要）
4. 點擊運行

### 真機特定測試
- [ ] 啟動時間（真機通常更快）
- [ ] 滾動性能（真機通常更好）
- [ ] 內存限制（真機可能更嚴格）
- [ ] 電池消耗（執行長時間搜索）

## 🎯 下一步測試

### 推薦的增強功能測試
1. **添加 JLPT 數據後**
   - 測試按級別過濾
   - 驗證級別標籤顯示

2. **添加頻率數據後**
   - 測試頻率排序
   - 驗證 "Top 100" 等標籤

3. **添加音調數據後**
   - 測試音調符號顯示
   - 驗證 ↓ 箭頭位置正確

4. **添加例句後**
   - 測試例句顯示
   - 驗證詞彙高亮
   - 測試例句滾動

## 🔍 Debug：Script Detection Snapshot（僅限 DEBUG）

- 在 Debug build 中開啟搜尋頁面，可透過右上角 `Debug` 選單叫出統計工具：
  - `Dump Script Stats`：輸出目前累積的腳本偵測次數與 romaji 反查的可疑案例。
  - `Dump Script Stats (JSON)`：以 JSON 形式輸出，方便貼進 Slack / QA 報告。
  - `Reset Script Stats`：清除計數，便於重複測試。
  - `Set Outlier Threshold`：調整多少次以上才視為可疑（預設 3 次）。
- 亦可在 LLDB / Console 呼叫：

```swift
Task { await DebugTools.dumpScriptStats(minCount: 2, asJSON: true) }
```

## ✅ CI Smoke Test：Japanese Language Ranking

- GitHub Actions Workflow: `.github/workflows/ci-smoke.yml`
- 每個 Pull Request 皆會執行 `testJapaneseLanguageRanking`，確保英語反查 `Japanese` 時 `日本語` 排名第一。
- 關鍵指令（可本地手動驗證）：

```bash
cd Modules/CoreKit
set -o pipefail
xcodebuild \
  -scheme CoreKit \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:CoreKitTests/EnglishReverseSearchTests/testJapaneseLanguageRanking \
  test | xcpretty
```

如測試失敗，CI 會阻擋合併，請檢查資料庫排序或 Script Detection 行為。

## ❓ 常見問題

### Q: App 啟動很慢？
A: 首次啟動需要驗證 60MB 數據庫完整性（~10-20 秒）。後續啟動會更快。

### Q: 搜索返回太多結果？
A: 結果已限制在前 100 個。可以輸入更具體的查詢。

### Q: 為什麼沒有音調和例句？
A: JMdict 不包含這些數據。需要從其他來源導入。

### Q: 如何更新詞典數據？
A: 重新運行 `scripts/import_jmdict.py` 使用新的 JMdict XML 文件。

### Q: 數據庫太大怎麼辦？
A: 可以考慮：
   - 只導入常用詞（按 JLPT 級別過濾）
   - 壓縮數據庫
   - 使用按需下載

## 📝 報告 Bug

如果發現問題，請記錄：
1. **重現步驟** - 如何觸發問題
2. **預期行為** - 應該發生什麼
3. **實際行為** - 實際發生了什麼
4. **環境信息** - iOS 版本、設備型號
5. **錯誤日誌** - Xcode 控制台輸出

---

**祝測試順利！** 🎉

如有任何問題，請查看：
- [CODE_QUALITY_REPORT.md](CODE_QUALITY_REPORT.md)
- [DICTIONARY_IMPORT_REPORT.md](DICTIONARY_IMPORT_REPORT.md)
- [specs/001-offline-dictionary-search/](specs/001-offline-dictionary-search/)
