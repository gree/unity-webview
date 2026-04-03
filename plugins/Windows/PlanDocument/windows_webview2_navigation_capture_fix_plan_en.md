---
name: Windows WebView2 navigation and capture pipeline fixes
overview: When switching URLs quickly or loading heavy pages, Unity could show stale textures, miss navigations, or get stuck with CallOnStarted without CallOnLoaded. The Windows plugin now stops in-flight navigation before starting a new one, defers Navigate to the next message pump, clears the CapturePreview gate when loading or when navigation completes, and aligns Destroy-time behavior with safer teardown.
todos: []
isProject: false
---

## Windows WebView2: navigation and offscreen capture fixes

### Problem summary

- **Stale texture after URL change**: On Windows, the visible page is a bitmap from `CapturePreview`. `_CWebViewPlugin_Update` only posts `WM_WEBVIEW_CAPTURE` when `captureInProgress` is false. If a previous `CapturePreview` completion is delayed or never runs, `captureInProgress` can stay true, so Unity keeps rendering the old frame even though `CallOnLoaded` already fired for the new document.
- **Rapid URL switching**: Calling `Navigate` immediately after `Stop()` in the same message handler can race WebView2: `Stop()` is not always synchronous, so the next `Navigate` may be ignored or the view may appear stuck until the user retries.
- **Repeated `LoadURL` to the same URL**: If navigation started (`CallOnStarted`) but never completed successfully (`CallOnLoaded`), resending the same URL from managed code may not recover; application-level workarounds (e.g. `about:blank` then target URL) may still be needed in C#.
- **Destroy while loading**: Stopping navigation before releasing COM (already documented in related plans) reduces crashes on heavy pages; this change keeps `Stop()` before `Navigate` consistent with that idea for normal loads.

**File**: `plugins/Windows/WebViewPlugin.cpp`

---

### 1. `NavigationCompleted`: clear `captureInProgress`

**Location**: `add_NavigationCompleted` handler (early in the callback).

**Reason**: Unity’s managed `WebViewObject.Update` uses `captureInProgress.exchange(true)` before posting a capture. If the flag never clears, no new `CapturePreview` is scheduled and the texture never updates for the new page.

**Change**: At the beginning of the `NavigationCompleted` callback, set `inst->captureInProgress = false` so the next Unity `Update` can enqueue a fresh capture after each navigation finishes (success or failure path still advances the pipeline).

**Note**: There is a theoretical race if two `CapturePreview` operations overlap; in practice this unblocks the common “stuck bitmap” case. If needed later, a generation counter could ignore stale completion callbacks.

---

### 2. `WM_WEBVIEW_LOAD_URL`: `Stop()`, clear capture flag, defer `Navigate`

**Location**: `case WM_WEBVIEW_LOAD_URL` in `WndProc`.

**Reason**:

- Cancel the previous navigation before starting another, matching the pattern used in `WM_WEBVIEW_DESTROY`.
- Clearing `captureInProgress` when explicitly loading a new URL avoids a stuck capture lock when switching away from a heavy or hung page.
- Posting `Navigate` on the **next** message pump (`PostMessage` with `wParam == 1`) gives `Stop()` time to take effect; immediate `Navigate` in the same handler could be dropped on busy pages.

**Change**:

- `wParam == 0` (used by `_CWebViewPlugin_LoadURL`): `Stop()`, set `captureInProgress = false`, then `PostMessage(hwnd, WM_WEBVIEW_LOAD_URL, 1, (LPARAM)url)` without deleting `url` yet.
- `wParam == 1`: `Navigate(url)`, then `delete[] url`.
- If `inst` or `webview` is invalid, `delete[] url` and return (avoid leaks).

`_CWebViewPlugin_LoadURL` continues to post with `wParam == 0` only.

---

### 3. `WM_WEBVIEW_LOAD_HTML`: `Stop()` and clear `captureInProgress` before `NavigateToString`

**Location**: `case WM_WEBVIEW_LOAD_HTML`.

**Reason**: Same as HTTP loads: cancel in-flight navigation and unlock the capture pipeline before replacing document content.

**Change**: Before `NavigateToString`, call `Stop()` and set `captureInProgress = false`.

---

### 4. Relationship to Unity / C# side (out of scope for this C++ file)

- Keep the default `bitmapRefreshCycle = 10` on Windows: unlike iOS-style paths that are closer to native rendering, Windows relies on `CapturePreview` offscreen bitmaps, and more frequent updates cost more CPU/GPU. If the texture still feels laggy, you may **lower** this value (e.g. to `3`) for smoother redraws at the expense of performance, and tune it together with these native fixes.
- Managed code can add navigation watchdogs (timeouts, `about:blank` sandwich, cache-busting query strings) when `CallOnStarted` repeats without `CallOnLoaded`.

---

### Recommended verification

1. Editor or standalone Windows: switch quickly among several HTTPS sites (including heavy homepages).
2. Confirm `CallOnLoaded` and on-screen texture both match the last requested URL.
3. From a slow-loading page, switch to another URL before load finishes; confirm the new page eventually appears without requiring multiple manual retries.
4. Regression: destroy the WebView while a page is still loading; confirm no new crashes (together with existing Destroy / C# `OnDestroy` fixes if applied).
