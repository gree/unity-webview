---
name: WebView freeze and destroy crash fix
overview: Based on crash reports, when loading specific pages (such as interserv.com.tw) in the Windows Editor and then pressing Stop, Unity crashes during the Destroy flow inside WebView2 (EmbeddedBrowserWebView.dll). The root cause is related to destroying the WebView while it is still loading/busy and race conditions between the main thread and the STA thread. We can mitigate this by stopping navigation before Destroy, avoiding C# calls to GetMessage during Destroy, and optionally handling timeouts more safely.
todos: []
isProject: false
---

## WebView freeze and crash after pressing Stop – fix plan

### Problem summary

- **Symptom**: In the Windows Editor, when loading `https://www.interserv.com.tw/#service`, the WebView tends to freeze, and Unity crashes after the user presses Stop.
- **Crash location**: `EmbeddedBrowserWebView.dll` in `GetHandleVerifier` (exception_code 0x80000003). The call stack includes `CWebViewPlugin_Destroy` and `CWebViewPlugin_GetMessage`.
- **Suspected causes**:
  1. The page is heavy (lots of scripts/resources and hash navigation). WebView2 is destroyed while still "loading" or busy, leading to unstable internal COM state and a crash during release.
  2. During Destroy, the main thread may still call `GetMessage`/Update in the same frame, causing a race with Destroy.
  3. If the STA thread is stuck in WebView2 (e.g. navigation or scripts not finished), `WM_WEBVIEW_DESTROY` cannot be processed in time. After the 10s timeout, the main thread may still remove the instance from `s_instances`, which can lead to use-after-free or bad COM release order when the STA thread eventually processes the message.

### 1. In `WM_WEBVIEW_DESTROY`, stop navigation before releasing COM (core)

**File**: `plugins/Windows/WebViewPlugin.cpp`

Before setting `controller` / `compositionController` / `webview` to `nullptr`:

- If `inst->webview` is valid, call `inst->webview->Stop()` first so WebView2 cancels ongoing navigation and attempts to leave the busy state.
- Optional: call `Navigate(L"about:blank")` afterwards to clear the content. (Stopping and then synchronously waiting may complicate things; we can start by only calling `Stop`.)

This reduces the chance that destroying WebView2 "while loading" triggers an internal check failure (such as in `GetHandleVerifier`).

**Code location**: Around lines 353–368, inside `case WM_WEBVIEW_DESTROY`. Add the `inst->webview->Stop()` call before `inst->controller = nullptr`, and ensure `inst` is checked for null.

### 2. C# `OnDestroy`: clear `webView` before calling Destroy (avoid race)

**File**: for example `plugins/WebViewObject.cs` (or the corresponding file under `dist/package`)

In the `UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN` branch:

- If `webView != IntPtr.Zero`, first copy the pointer into a local variable, then **immediately** set `webView` to `IntPtr.Zero`, and finally call `_CWebViewPlugin_Destroy(savedPtr)`.
- With this pattern, even if `Update` still runs in the same frame, it will see `webView == IntPtr.Zero` and stop calling `GetMessage`/Update/Render. This prevents managed code from entering the native layer or WebView2 paths while Destroy is in progress, reducing races with `EmbeddedBrowserWebView`.

**Code location**: Around lines 836–845. Change it to:

```csharp
if (webView == IntPtr.Zero) return;
var ptr = webView;
webView = IntPtr.Zero;
_CWebViewPlugin_Destroy(ptr);
```

(The rest of Destroy logic for textures, background, etc. stays unchanged.)

### 3. On timeout, avoid removing from `s_instances` (optional, reduce UAF risk)

**File**: `plugins/Windows/WebViewPlugin.cpp`

Currently, `_CWebViewPlugin_Destroy` removes the instance from `s_instances` and releases it even when `WaitForSingleObject(destroyDoneEvent, 10000)` times out. If the STA thread later processes `WM_WEBVIEW_DESTROY`, it may access a deleted instance or hit a bad COM release order.

- **Option A**: On timeout, do **not** remove the instance from `s_instances` (just log/ignore). This avoids the main thread freeing an instance that the STA thread may still use later. The downside is that the instance may leak until process exit.
- **Option B**: Keep the current behavior but add comments documenting the risk, and rely on items 1 and 2 to make timeouts much less likely.

Recommendation: implement 1 and 2 first. If crashes still occur, then consider Option A.

### 4. Relationship between the URL and the "freeze"

- `#service` is a front-end hash navigation target that may trigger heavy JS or dynamic loading, making WebView2 stay busy for longer.
- The "freeze" may come from long-running scripts, multiple navigations/iframes, or slow `CapturePreview` on complex pages. All of these delay the STA thread from returning to the message loop. If the user presses Stop at this moment, Destroy is more likely to run while WebView2 is busy, so **stopping before releasing** becomes especially important.

---

### Recommended implementation order

1. **Must-do**: In `WM_WEBVIEW_DESTROY`, call `inst->webview->Stop()` before releasing COM objects.
2. **Must-do**: In C# `OnDestroy` (Windows), set `webView = IntPtr.Zero` before calling `_CWebViewPlugin_Destroy(ptr)`.
3. **Optional**: If crashes still occur, consider not removing the instance from `s_instances` on Destroy timeout, or add a `destroying` flag so `GetMessage` returns `nullptr` early (requires changes in both the plugin and C# side).

After implementing 1 and 2, test in the Editor by loading `https://www.interserv.com.tw/#service`, waiting until it freezes or is still loading, then pressing Stop. Verify whether the crash still happens and decide if step 3 is necessary.

