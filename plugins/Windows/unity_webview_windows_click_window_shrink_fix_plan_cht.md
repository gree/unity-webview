---
name: 修復 Windows 點擊視窗縮小
overview: 點擊 APP 畫面時視窗被縮小，極可能是因為外掛在處理滑鼠/鍵盤時對「離屏的 WebView2 宿主視窗」呼叫 SetFocus，導致前景（Unity）視窗失去啟用狀態；部分環境下會觸發「失去焦點時最小化」。計劃在原生層移除或修正 SetFocus 使用，並可選加入視窗樣式避免宿主被啟用。
todos: []
isProject: false
---

# 修復 Windows 平台點擊後 APP 視窗被縮小的問題

## 問題說明

- **現象**：建置出的 Windows APP 啟動後，點擊畫面任何地方，整個 APP 視窗會「突然被縮小」（多數情況為被最小化到工作列）。
- **發生時機**：與點擊一致，故高度懷疑與「滑鼠事件轉發到 WebView2」時的視窗焦點/啟用狀態有關。

## 根因分析

- 外掛使用**離屏的 Win32 視窗**承載 WebView2（`SetWindowPos(..., -32000, -32000)` + `SW_SHOWNOACTIVATE`），滑鼠與鍵盤經由 `PostMessage` 送到該視窗的 STA 線程處理。
- 在 [WebViewPlugin.cpp](WebViewPlugin.cpp) 中：
  - **滑鼠**：`WM_WEBVIEW_SEND_MOUSE` 處理時，若走 **非 CompositionController 的 fallback 路徑**（約 484–491 行），會對子視窗/宿主呼叫 `**SetFocus(target)`**（約 487 行）。
  - **鍵盤**：`WM_WEBVIEW_SEND_KEY` 處理時（約 503–530 行）**一律**對 target 呼叫 `**SetFocus(target)`**（約 511 行）。
- Windows 文件指出：**SetFocus 會啟用接收焦點的視窗或其父視窗**。對離屏的宿主視窗呼叫 `SetFocus` 會把「啟用視窗」從 Unity 轉到外掛的視窗，Unity 視窗失去前景，若專案或系統有「失去焦點時最小化」之類行為，就會出現點擊後視窗被縮小的現象。
- 即使主要輸入路徑使用 CompositionController 的 `SendMouseInput`（該路徑未呼叫 SetFocus），若 fallback 被用到，或鍵盤路徑在點擊後被間接觸發，仍會發生 SetFocus 導致的前景切換。

## 修復方向

1. **滑鼠路徑**：在 `WM_WEBVIEW_SEND_MOUSE` 的 **else 分支**（非 CompositionController）中**移除 `SetFocus(target)`**，避免僅因滑鼠點擊就把焦點/啟用給離屏視窗。
2. **鍵盤路徑**：在 `WM_WEBVIEW_SEND_KEY` 中**避免讓 Unity 視窗失去前景**：
  - **方案 A（建議先做）**：在呼叫 `SetFocus(target)` 前以 `GetForegroundWindow()` 記下目前前景視窗，送完按鍵後用 `SetForegroundWindow(保存的 HWND)` 把前景還給 Unity。注意：`SetForegroundWindow` 有跨行程/執行緒限制，若還原失敗可再考慮 AttachThreadInput 或改為不呼叫 SetFocus。
  - **方案 B**：若方案 A 在實機上仍無法穩定還原前景，則改為**不呼叫 SetFocus**，僅以 `SendMessage(WM_CHAR/KEYDOWN/KEYUP)` 送鍵；部分情境下 WebView2 仍可能處理（可實測鍵盤輸入是否仍正常）。
3. **可選強化**：建立離屏宿主視窗時加上 `**WS_EX_NOACTIVATE`**，使該視窗在收到點擊或焦點時**不要被啟用**，降低任何殘留的 SetFocus 或內部邏輯把前景帶走的機會（需驗證是否影響 WebView2 輸入與 IME）。

## 實作要點（僅列出需改檔案與位置）

- **檔案**：[WebViewPlugin.cpp](WebViewPlugin.cpp)
  - **WM_WEBVIEW_SEND_MOUSE**（約 460–501 行）：在 `else` 分支中刪除 `if (data->mouseState == 1) SetFocus(target);`（約 487 行）。
  - **WM_WEBVIEW_SEND_KEY**（約 503–530 行）：在現有 `SetFocus(target)` 前後加入「取得目前前景視窗 → 送鍵 → 設回前景」；若使用方案 B 則改為不呼叫 SetFocus，僅保留 SendMessage 送鍵。
  - **CreateWindowExW**（約 554 行）：若採用可選強化，將 `WS_EX_TOOLWINDOW` 改為 `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`（並在文件中註明需測試輸入與 IME）。

## 驗證建議

- 建置 Windows 64 位元 Standalone，在「點擊 WebView 區域」與「點擊非 WebView 區域」各測數次，確認視窗不再被縮小或最小化。
- 確認 WebView 內連結、輸入框、滑鼠選取與鍵盤輸入仍正常；若啟用 WS_EX_NOACTIVATE，需額外測 IME 與焦點相關行為。

## 若「縮小」是視窗被「縮小尺寸」而非最小化

- 若實際是視窗 **resize** 變小而非最小化，則需再查：Unity Player 設定、是否有其他地方送 `WM_SIZE`/`SW_MINIMIZE`、或全螢幕/解析度相關邏輯。目前程式碼中未發現對宿主或 Unity 送 resize/最小化訊息，先以「焦點/啟用導致最小化」為主要假設實施上述修改。
