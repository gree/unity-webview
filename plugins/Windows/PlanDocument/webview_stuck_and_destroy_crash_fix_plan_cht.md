---
name: WebView 卡住與 Destroy 當機修復
overview: 根據 Crash 報告，當在 Windows 編輯器載入特定網頁（如 interserv.com.tw）後按停止時，Unity 會在 Destroy 流程中於 WebView2（EmbeddedBrowserWebView.dll）內崩潰。原因與「載入中/忙碌時銷毀」以及主線與 STA 線程的競態有關，可透過 Destroy 前先停止導覽、C# 端避免 Destroy 期間再呼叫 GetMessage、以及可選的逾時後安全處理來緩解。
todos: []
isProject: false
---

# WebView 卡住與按下停止後 Unity 當機修復計畫

## 問題摘要

- **現象**：Windows 編輯器中載入 `https://www.interserv.com.tw/#service` 時 WebView 易卡住，按下停止後 Unity 當機。
- **Crash 位置**：`EmbeddedBrowserWebView.dll` 的 `GetHandleVerifier`（exception_code 0x80000003），呼叫鏈包含 `CWebViewPlugin_Destroy` 與 `CWebViewPlugin_GetMessage`。
- **推測原因**：
  1. 該頁面較重（腳本/資源多、hash 導覽），WebView2 在「載入中」或忙碌時被銷毀，COM 釋放時內部狀態不穩定導致崩潰。
  2. Destroy 時主線程可能仍在同一幀呼叫 `GetMessage`/Update，與 Destroy 競態。
  3. 若 STA 線程被 WebView2 卡住（例如導覽或腳本未結束），`WM_WEBVIEW_DESTROY` 無法及時處理，逾時後主線程仍從 `s_instances` 移除 instance，可能造成後續 use-after-free 或 COM 釋放順序問題。

## 修復方向

### 1. 在 WM_WEBVIEW_DESTROY 中先停止導覽再釋放 COM（核心）

**檔案**：[plugins/Windows/WebViewPlugin.cpp](c:_Work\Unity_Practice\unity-webview_Syaoran\plugins\Windows\WebViewPlugin.cpp)

在將 `controller` / `compositionController` / `webview` 設為 `nullptr` 之前：

- 若 `inst->webview` 有效，先呼叫 `inst->webview->Stop()`，讓 WebView2 取消進行中的導覽並盡量離開忙碌狀態。
- 可選：再 `Navigate(L"about:blank")` 清空內容（若 Stop 後同步等待可能增加複雜度，可先只做 Stop）。

這樣可降低「在載入中銷毀」導致 WebView2 內部檢查（如 GetHandleVerifier）失敗的機率。

**程式位置**：約 353–368 行，`case WM_WEBVIEW_DESTROY` 內，在 `inst->controller = nullptr` 之前加入對 `inst->webview->Stop()` 的呼叫，並注意 `inst` 可能為 null 的檢查。

### 2. C# OnDestroy：先清空 webView 再呼叫 Destroy（避免競態）

**檔案**：例如 [plugins/WebViewObject.cs](c:_Work\Unity_Practice\unity-webview_Syaoran\plugins\WebViewObject.cs)（或 dist/package 內對應檔）

在 `UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN` 分支中：

- 若 `webView != IntPtr.Zero`，先將指標存到區域變數，然後**立即**將 `webView` 設為 `IntPtr.Zero`，再呼叫 `_CWebViewPlugin_Destroy(保存的指標)`。
- 這樣同一幀內若 Update 仍執行，會因 `webView == IntPtr.Zero` 而不再呼叫 `GetMessage`/Update/Render，避免在 Destroy 過程中再進入原生層或 WebView2 相關路徑，減少與 EmbeddedBrowserWebView 的競態。

**程式位置**：約 836–845 行，改為：

```csharp
if (webView == IntPtr.Zero) return;
var ptr = webView;
webView = IntPtr.Zero;
_CWebViewPlugin_Destroy(ptr);
```

（其餘 Destroy texture、bg 等維持不變。）

### 3. 逾時後不從 s_instances 移除（可選，降低 use-after-free 風險）

**檔案**：[plugins/Windows/WebViewPlugin.cpp](c:_Work\Unity_Practice\unity-webview_Syaoran\plugins\Windows\WebViewPlugin.cpp)

目前 `_CWebViewPlugin_Destroy` 在 `WaitForSingleObject(destroyDoneEvent, 10000)` 逾時後仍會從 `s_instances` 移除並釋放 instance。若 STA 線程之後才處理 `WM_WEBVIEW_DESTROY`，可能觸及已刪除的 instance 或 COM 釋放順序異常。

- **選項 A**：逾時時不從 `s_instances` 移除該 instance（僅記錄或略過），避免主線程釋放後 STA 仍使用該指標；缺點是 instance 會殘留直到程序結束。
- **選項 B**：維持現狀但加上註解說明風險，並依賴 1、2 降低逾時發生機率。

建議先實作 1 與 2，若仍發生當機再考慮選項 A。

### 4. 網址本身與「卡住」的關係

- `#service` 為前端 hash 導覽，可能觸發大量 JS 或動態載入，使 WebView2 長時間忙碌。
- 「卡住」可能來自：長時間腳本、多個導覽/iframe、或 CapturePreview 在複雜頁面上較慢。這些都會讓 STA 線程較晚回到訊息迴圈，若此時使用者按停止，Destroy 更容易在「忙碌狀態」下執行，因此**先 Stop 再釋放**特別重要。

---

## 實作順序建議

1. **必做**：在 `WM_WEBVIEW_DESTROY` 中對 `inst->webview` 呼叫 `Stop()` 再釋放 COM。
2. **必做**：C# OnDestroy（Windows）改為先 `webView = IntPtr.Zero` 再 `_CWebViewPlugin_Destroy(ptr)`。
3. **可選**：若仍有崩潰，再考慮 Destroy 逾時時不從 `s_instances` 移除，或加入「destroying」旗標讓 GetMessage 提早回傳 nullptr（需在 plugin 與 C# 端一致）。

完成 1、2 後建議在編輯器下重現：載入 `https://www.interserv.com.tw/#service`，等待卡住或載入中時按停止，確認是否還會當機並視情況再套用 3。
