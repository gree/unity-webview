---
name: Fix Windows Click Window Shrink
overview: When the app window shrinks (often minimizes) after clicking, the likely cause is the plugin calling SetFocus on the off-screen WebView2 host window while handling mouse/keyboard, which deactivates the foreground (Unity) window; some environments then trigger "minimize on focus loss". This plan removes or corrects SetFocus usage in native code and optionally adds window styles to prevent the host from being activated.
todos: []
isProject: false
---

# Fix: Windows App Window Shrinks After Click

## Problem Description

- **Symptom**: After building and running the Windows app, clicking anywhere on the screen causes the entire app window to "suddenly shrink" (in most cases, it is minimized to the taskbar).
- **When it happens**: It coincides with the click, so it is strongly suspected to be related to window focus/activation when mouse events are forwarded to WebView2.

## Root Cause Analysis

- The plugin uses an **off-screen Win32 window** to host WebView2 (`SetWindowPos(..., -32000, -32000)` + `SW_SHOWNOACTIVATE`). Mouse and keyboard events are sent to that window's STA thread via `PostMessage`.
- In [WebViewPlugin.cpp](WebViewPlugin.cpp):
  - **Mouse**: In `WM_WEBVIEW_SEND_MOUSE` handling, when the **fallback path (non-CompositionController)** is used (around lines 484–491), it calls `**SetFocus(target)**` on the child/host window (around line 487).
  - **Keyboard**: In `WM_WEBVIEW_SEND_KEY` handling (around lines 503–530), it **always** calls `**SetFocus(target)**` on the target (around line 511).
- Windows documentation states that **SetFocus activates the window (or its parent) that receives focus**. Calling `SetFocus` on the off-screen host window moves the "active window" from Unity to the plugin's window; the Unity window loses foreground. If the project or system has behavior such as "minimize on focus loss", the window will shrink after a click.
- Even when the main input path uses CompositionController's `SendMouseInput` (which does not call SetFocus), if the fallback is used or the keyboard path is triggered indirectly after a click, SetFocus can still cause the foreground to switch.

## Fix Direction

1. **Mouse path**: In the **else branch** of `WM_WEBVIEW_SEND_MOUSE` (non-CompositionController), **remove `SetFocus(target)`** so that a mouse click alone does not give focus/activation to the off-screen window.
2. **Keyboard path**: In `WM_WEBVIEW_SEND_KEY`, **avoid making the Unity window lose foreground**:
   - **Option A (recommended first)**: Before calling `SetFocus(target)`, save the current foreground window with `GetForegroundWindow()`. After sending the key, use `SetForegroundWindow(saved_hwnd)` to restore the foreground to Unity. Note: `SetForegroundWindow` has cross-process/thread restrictions; if restoration fails, consider AttachThreadInput or not calling SetFocus.
   - **Option B**: If Option A still cannot reliably restore the foreground on real devices, **do not call SetFocus** and only send keys via `SendMessage(WM_CHAR/KEYDOWN/KEYUP)`; WebView2 may still handle input in some cases (verify that keyboard input still works).
3. **Optional hardening**: When creating the off-screen host window, add **`WS_EX_NOACTIVATE`** so that the window **is not activated** when it receives a click or focus, reducing the chance that any remaining SetFocus or internal logic steals the foreground (verify that this does not affect WebView2 input and IME).

## Implementation Notes (files and locations only)

- **File**: [WebViewPlugin.cpp](WebViewPlugin.cpp)
  - **WM_WEBVIEW_SEND_MOUSE** (around lines 460–501): In the `else` branch, remove `if (data->mouseState == 1) SetFocus(target);` (around line 487).
  - **WM_WEBVIEW_SEND_KEY** (around lines 503–530): Before/after the existing `SetFocus(target)`, add "get current foreground window → send key → restore foreground"; if using Option B, do not call SetFocus and keep only SendMessage for key delivery.
  - **CreateWindowExW** (around line 554): If using the optional hardening, change `WS_EX_TOOLWINDOW` to `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE` (and document that input and IME need to be tested).

## Verification Suggestions

- Build Windows 64-bit Standalone; test multiple times by clicking on the WebView area and on the non-WebView area, and confirm the window no longer shrinks or minimizes.
- Confirm that links, input fields, mouse selection, and keyboard input still work inside the WebView; if `WS_EX_NOACTIVATE` is enabled, additionally test IME and focus-related behavior.

## If "Shrink" Means Window Resize Rather Than Minimize

- If the window actually **resizes** (gets smaller) rather than minimizing, then also check: Unity Player settings, any other code sending `WM_SIZE`/`SW_MINIMIZE`, or fullscreen/resolution logic. The current code does not show any resize/minimize messages sent to the host or Unity; the above changes are based on the main assumption that focus/activation causes minimization.
