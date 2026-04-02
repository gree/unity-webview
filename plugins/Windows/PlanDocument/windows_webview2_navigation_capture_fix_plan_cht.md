---
name: Windows WebView2 導覽與擷取管線修正
overview: 快速切換網址或載入繁重頁面時, Unity 可能仍顯示舊貼圖、導覽未生效, 或僅有 CallOnStarted 而無 CallOnLoaded. Windows 外掛改為在新導覽前先停止進行中的導覽、將 Navigate 延後到下一輪訊息迴圈、在載入或導覽完成時解除 CapturePreview 鎖定, 並與 Destroy 時先 Stop 的行為一致.
todos: []
isProject: false
---

## Windows WebView2: 導覽與離屏擷取修正

### 問題摘要

- **換網址後畫面仍是舊頁**: Windows 上畫面來自 `CapturePreview` 的點陣圖. `_CWebViewPlugin_Update` 僅在 `captureInProgress` 為 false 時才 Post `WM_WEBVIEW_CAPTURE`. 若上一張 `CapturePreview` 的回呼延遲或未執行, 旗標可能一直為 true, Unity 仍畫舊幀, 即使新文件已觸發 `CallOnLoaded`.
- **快速連續換網址**: 在同一個訊息處理裡對 `Stop()` 後立刻 `Navigate` 可能與 WebView2 競態: `Stop()` 未必同步完成, 下一個 `Navigate` 可能被忽略或看起來卡住.
- **對同一 URL 重複 LoadURL**: 若已 `CallOnStarted` 卻始終沒有成功的 `CallOnLoaded`, 僅重送相同 URL 可能無法恢復; C# 端可能仍需 `about:blank` 再導向等作法.
- **載入中 Destroy**: 釋放 COM 前先停止導覽 (其他計畫已述) 可降低繁重頁面崩潰; 一般載入路徑也採用先 `Stop` 再導向, 與該策略一致.

**檔案**: `plugins/Windows/WebViewPlugin.cpp`

---

### 1. `NavigationCompleted`: 清除 `captureInProgress`

**位置**: `add_NavigationCompleted` 回呼開頭.

**原因**: Unity 端 `WebViewObject.Update` 以 `captureInProgress.exchange(true)` 決定是否 Post 擷取. 若旗標未清除, 不會再排 `CapturePreview`, 貼圖不會更新.

**作法**: 在 `NavigationCompleted` 回呼一開始設 `inst->captureInProgress = false`, 讓每次導覽結束後下一幀的 `Update` 能再排新的擷取.

**備註**: 理論上可能與尚未完成的舊 `CapturePreview` 重疊; 實務上可解決常見的貼圖卡死. 若需更嚴謹可再加世代序號忽略過期回呼.

---

### 2. `WM_WEBVIEW_LOAD_URL`: `Stop()`、清除擷取旗標、延遲 `Navigate`

**位置**: `WndProc` 的 `case WM_WEBVIEW_LOAD_URL`.

**原因**:

- 新導覽前先取消上一段, 與 `WM_WEBVIEW_DESTROY` 的作法一致.
- 明確換網址時清除 `captureInProgress`, 避免從繁重或異常頁面切走時擷取鎖卡住.
- 以 **下一輪訊息迴圈** 執行 `Navigate` (`PostMessage` 且 `wParam == 1`), 讓 `Stop()` 有機會生效; 同一則訊息內立刻 `Navigate` 在忙碌頁面上可能被丟棄.

**作法**:

- `wParam == 0` (由 `_CWebViewPlugin_LoadURL` 送出): `Stop()`, `captureInProgress = false`, 再 `PostMessage(hwnd, WM_WEBVIEW_LOAD_URL, 1, (LPARAM)url)`, 此時不可 `delete[] url`.
- `wParam == 1`: `Navigate(url)` 後 `delete[] url`.
- 若 `inst` 或 `webview` 無效則 `delete[] url` 並 return, 避免洩漏.

---

### 3. `WM_WEBVIEW_LOAD_HTML`: `NavigateToString` 前先 `Stop()` 並清除 `captureInProgress`

**位置**: `case WM_WEBVIEW_LOAD_HTML`.

**原因**: 與 HTTP 載入相同, 先結束進行中導覽並解鎖擷取管線, 再換文件內容.

**作法**: 在 `NavigateToString` 前呼叫 `Stop()` 並設 `captureInProgress = false`.

---

### 4. 與 Unity / C# 的關係 (本 C++ 檔案外)

- Windows 上 `WebViewObject` 預設 `bitmapRefreshCycle = 10` 建議維持: iOS 等路徑較接近原生顯示, Windows 依賴 `CapturePreview` 離屏貼圖, 更新越頻繁越吃效能. 若仍覺畫面不夠順, 可視裝置與場景**自行調低**此值 (例如 `3`) 以換取較常重繪, 與上述原生修正可一併評估.
- C# 可另做導覽監看 (逾時、`about:blank`、cache-busting) 處理僅有 `CallOnStarted` 而無 `CallOnLoaded` 的情況.

---

### 建議驗證

1. Windows Editor 或 Standalone: 於多個 HTTPS 站之間快速切換 (含首頁較重的站).
2. 確認最後一次要求的網址與 `CallOnLoaded`、畫面內容一致.
3. 在慢載頁面完成前切到另一站, 確認不需多次手動重試即可看到新頁.
4. 迴歸: 載入中 Destroy WebView, 確認無新崩潰 (若已套用其他 Destroy / C# `OnDestroy` 修正則一併驗證).
