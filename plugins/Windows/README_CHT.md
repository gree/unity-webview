# Windows WebView Plugin (WebView2)

This folder contains the native Windows plugin for unity-webview, using **Microsoft WebView2** (Edge Chromium).

## Requirements

- Windows 10 or later
- Visual Studio 2019 or 2022 with "Desktop development with C++"
- [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (usually preinstalled on Windows 11 / recent Windows 10)

## Building the DLL

### 1. Get the WebView2 SDK（必做，否則會找不到 WebView2.h）

專案需要 WebView2 SDK 的標頭檔與 lib，**請先執行下列其中一種方式**，再開 Visual Studio 建置。

**方式 A – 用腳本還原（建議）**

在 `plugins/Windows` 資料夾內，用 **PowerShell** 執行：

```powershell
.\restore_webview2_sdk.ps1
```

腳本會自動下載 nuget.exe（若尚未安裝）並還原 `Microsoft.Web.WebView2`，產生 `packages\Microsoft.Web.WebView2.1.0.3800.47\`，裡面會有 `build\native\include\WebView2.h` 等檔案。

**方式 B – 手動用 NuGet 還原**

若已安裝 [NuGet CLI](https://www.nuget.org/downloads)，在 **命令提示字元** 或 **Developer PowerShell** 中切到 `plugins/Windows`，執行：

```cmd
cd 專案根目錄\plugins\Windows
nuget install Microsoft.Web.WebView2 -Version 1.0.3800.47 -OutputDirectory packages
```

完成後應會出現 `packages\Microsoft.Web.WebView2.1.0.3800.47\build\native\include\WebView2.h`。

**方式 C – 手動下載 SDK**

1. 到 [NuGet: Microsoft.Web.WebView2](https://www.nuget.org/packages/Microsoft.Web.WebView2/) 下載 1.0.3800.47 的 .nupkg，副檔名改為 .zip 後解壓。
2. 將解壓後的 `build\native\include` 與 `build\native\x64`（32 位元則用 `build\native\x86`）放到對應的位置，或在 `WebViewPlugin.vcxproj` 中把 Include/Lib 路徑改為指向你存放的地方。

### 2. 用 Visual Studio 建置

1. **確認已執行過上面的「1. Get the WebView2 SDK」**，使 `packages\Microsoft.Web.WebView2.1.0.3800.47\build\native\include\WebView2.h` 等檔案存在。
2. 雙擊開啟 `WebViewPlugin.sln`（或用 Visual Studio 開啟此方案檔）。
3. **建置 64 位元 (x64)**：
   - 上方平台下拉選單選 **x64**，組態選 **Release**。
   - 點擊「建置 → 建置方案」。
   - 產出的 DLL 位於：`plugins\Windows\bin\x64\Release\WebView.dll`
4. **建置 32 位元 (Win32 / x86)**：
   - 上方平台下拉選單選 **Win32**，組態選 **Release**。
   - 點擊「建置 → 建置方案」。
   - 產出的 DLL 位於：`plugins\Windows\bin\Win32\Release\WebView.dll`

命令列建置（可選）：

```cmd
cd 專案根目錄\plugins\Windows
msbuild WebViewPlugin.sln /p:Configuration=Release /p:Platform=x64
msbuild WebViewPlugin.sln /p:Configuration=Release /p:Platform=Win32
```

### 3. Use in Unity

將建置出的 `WebView.dll` 複製到你的 Unity 專案內對應的資料夾：

- 64-bit (x64): 複製到 `Assets/Plugins/x64/WebView.dll`
- 32-bit (Win32): 複製到 `Assets/Plugins/x86/WebView.dll`

Unity will load it on Windows Editor and Windows Standalone builds. The WebView2 **Runtime** must be installed on the machine where the built game runs (see main README for distribution notes).

## Debug 日誌（排查滑鼠／鍵盤無法操作）

外掛內建 `OutputDebugString` 日誌，可用來確認滑鼠／鍵盤是否有進到 DLL、以及目標視窗為何。

1. **編譯時**：預設已開啟（`WebViewPlugin.cpp` 頂端 `WEBVIEW_DEBUG` 為 1）。若要關閉，改為 `#define WEBVIEW_DEBUG 0` 後重新建置。
2. **查看日誌**：
   - **DebugView**（建議）：下載 [Sysinternals DebugView](https://learn.microsoft.com/en-us/sysinternals/downloads/debugview)，以**系統管理員**執行，選單 **Capture → Capture Global Win32** 打勾，再執行 Unity 與範例場景，點擊 WebView 時應會看到 `[WebView2]` 開頭的行（例如 `SendMouseEvent called`、`MOUSE recv`、`targetClass=...`）。
   - **Visual Studio**：用「啟動偵錯」執行 Unity 專案（或附加到 Unity 程序），在 **輸出** 視窗選擇「偵錯」即可看到相同內容。

日誌會印出：C# 是否呼叫了 `SendMouseEvent`/`SendKeyEvent`、STA 執行緒是否收到、`hwnd`/`child`/`target` 視窗代碼、目標視窗的 **類別名稱**（例如 `Chrome_WidgetWin_1` 或 `UnityWebView2Window`）、以及轉換後的座標。若 `child` 為 null 或目標類別不對，可據此判斷是否需改用其他方式轉發輸入（例如 CompositionController 的 SendMouseInput）。
