# Windows WebView Plugin (WebView2)

This folder contains the native Windows plugin for unity-webview, using **Microsoft WebView2** (Edge Chromium).

## Requirements

- Windows 10 or later
- Visual Studio 2019 or 2022 (or newer) with "Desktop development with C++"
- [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (usually preinstalled on Windows 11 / recent Windows 10)

## Building the DLL

### 1. Get the WebView2 SDK (Required)

The project requires the WebView2 SDK headers and libraries. **Please perform one of the following methods** before opening Visual Studio to build.

**Method A – Restore via Script (Recommended)**

Open **PowerShell** and navigate to the `plugins/Windows` folder, then run:

```powershell
.\restore_webview2_sdk.ps1
```

The script will automatically download `nuget.exe` (if not installed) and restore `Microsoft.Web.WebView2`, generating the `packages\Microsoft.Web.WebView2.1.0.3800.47\` folder which contains `build\native\include\WebView2.h` and other necessary files.

**Method B – Manual NuGet Restore**

If you have the [NuGet CLI](https://www.nuget.org/downloads) installed, open **Command Prompt** or **Developer PowerShell**, navigate to `plugins/Windows`, and run:

```cmd
nuget install Microsoft.Web.WebView2 -Version 1.0.3800.47 -OutputDirectory packages
```

**Method C – Manual SDK Download**

1. Go to [NuGet: Microsoft.Web.WebView2](https://www.nuget.org/packages/Microsoft.Web.WebView2/), download the 1.0.3800.47 `.nupkg` file, rename its extension to `.zip`, and extract it.
2. Place the extracted `build\native\include` and `build\native\x64` (use `build\native\x86` for 32-bit) in the appropriate paths, or modify the Include/Library directories in `WebViewPlugin.vcxproj` to point to your custom location.

### 2. Build with Visual Studio

1. **Ensure you have completed "1. Get the WebView2 SDK"** above, so that files like `packages\Microsoft.Web.WebView2.1.0.3800.47\build\native\include\WebView2.h` exist.
2. Double-click to open **`WebViewPlugin.sln`** (or open this solution file via Visual Studio).
3. **Build 64-bit (x64)**:
   - Select **x64** from the platform dropdown at the top, and set the configuration to **Release**.
   - Click "Build → Build Solution".
   - The output DLL will be located at: `plugins\Windows\bin\x64\Release\WebView.dll`
4. **Build 32-bit (Win32 / x86)**:
   - Select **Win32** from the platform dropdown at the top, and set the configuration to **Release**.
   - Click "Build → Build Solution".
   - The output DLL will be located at: `plugins\Windows\bin\Win32\Release\WebView.dll`

Command-line build (Optional):

```cmd
cd <ProjectRoot>\plugins\Windows
msbuild WebViewPlugin.sln /p:Configuration=Release /p:Platform=x64
msbuild WebViewPlugin.sln /p:Configuration=Release /p:Platform=Win32
```

### 3. Use in Unity

Copy the built `WebView.dll` into the corresponding directory in your Unity project:

- 64-bit (x64): Copy to `Assets/Plugins/x64/WebView.dll`
- 32-bit (Win32): Copy to `Assets/Plugins/x86/WebView.dll`

Unity will load it on Windows Editor and Windows Standalone builds. The WebView2 **Runtime** must be installed on the machine where the built game runs (see the main README for distribution notes).

## Debug Logging (Troubleshooting Mouse/Keyboard Input)

The plugin has built-in `OutputDebugString` logging to verify if mouse/keyboard events reach the DLL and what the target window is.

1. **Compile Time**: Logging is controlled by `WEBVIEW_DEBUG` at the top of `WebViewPlugin.cpp` (default is **0**, which means disabled). Change it to `#define WEBVIEW_DEBUG 1` and rebuild to enable it.
2. **View Logs**:
   - **DebugView** (Recommended): Download [Sysinternals DebugView](https://learn.microsoft.com/en-us/sysinternals/downloads/debugview). Run it as **Administrator**, check **Capture → Capture Global Win32** in the menu, then run Unity and the sample scene. When you click on the WebView, you should see lines starting with `[WebView2]` (e.g., `SendMouseEvent called`, `MOUSE recv`, `targetClass=...`).
   - **Visual Studio**: Run the Unity project using "Start Debugging" (or attach to the Unity process), and select "Debug" in the **Output** window to see the same logs.

The logs will print: whether C# called `SendMouseEvent`/`SendKeyEvent`, if the STA thread received it, the handles for `hwnd`/`child`/`target`, the **class name** of the target window (e.g., `Chrome_WidgetWin_1` or `UnityWebView2Window`), and the converted coordinates. This information is crucial for determining if input forwarding is working correctly.