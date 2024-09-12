# unity-webview

`unity-webview` is a Unity 5 plugin that overlays WebView components on Unity's rendering view. It supports Android, iOS, Unity Web Player, and Mac (Windows is not supported at this time).

This plugin is derived from [keijiro-san's Unity WebView Integration](https://github.com/keijiro/unity-webview-integration).

**Note:** This plugin overlays native WebView/WKWebView views over Unity's rendering view and does not support these views in 3D. For alternative solutions, refer to [this issue comment](https://github.com/gree/unity-webview/issues/612#issuecomment-724541385).

## Sample Project

The sample project can be found under the `sample/` directory. To import the plugin:

1. Open `sample/Assets/Sample.unity`.
2. Import `dist/unity-webview.unitypackage` by opening it in Unity. If you've imported `unity-webview` before, it might be easier to extract `dist/unity-webview.zip`.

**Note:** For Android, the current implementation uses Android Fragment to enable the file input field. This might cause new issues. If you don't need the file input field, you can use `dist/unity-webview-nofragment.unitypackage` or `dist/unity-webview-nofragment.zip`.

## Package Manager

For Unity 2019.4 or later, import the plugin using the Package Manager by adding the following entry to your `Packages/manifest.json`:

```json
{
  "dependencies": {
    "net.gree.unity-webview": "https://github.com/gree/unity-webview.git?path=/dist/package"
  }
}
```

For the variant without Fragment:

```json
{
  "dependencies": {
    "net.gree.unity-webview": "https://github.com/gree/unity-webview.git?path=/dist/package-nofragment"
  }
}
```

**Note:** Importing with the Package Manager does not work well for WebGL. Refer to the instructions for `dist/unity-webview.unitypackage`.

## Platform-Specific Notes

### Mac (Editor)

#### macOS Version

The implementation uses [WKWebView’s `takeSnapshotWithConfiguration`](https://developer.apple.com/documentation/webkit/wkwebview/2873260-takesnapshotwithconfiguration) to capture an offscreen WebView image. macOS 10.13 (High Sierra) or later is required.

#### App Transport Security

Since Unity 5.3.0, Unity.app is built with ATS (App Transport Security) enabled, which does not permit non-secured (HTTP) connections. To open HTTP URLs in the Unity Mac Editor, update `Info.plist` as follows:

```diff
--- Info.plist~  2016-04-11 18:29:25.000000000 +0900
+++ Info.plist   2016-04-15 16:17:28.000000000 +0900
@@ -57,5 +57,10 @@
  <string>EditorApplicationPrincipalClass</string>
  <key>UnityBuildNumber</key>
  <string>b902ad490cea</string>
+ <key>NSAppTransportSecurity</key>
+ <dict>
+   <key>NSAllowsArbitraryLoads</key>
+   <true/>
+ </dict>
 </dict>
 </plist>
```

Alternatively, execute the following terminal command:

```bash
/usr/libexec/PlistBuddy -c "Add NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" /Applications/Unity/Unity.app/Contents/Info.plist
```

#### Separate Mode

Specify `separated: true` to open WebView in a separate window:

```csharp
webViewObject = (new GameObject("WebViewObject")).AddComponent<WebViewObject>();
webViewObject.Init(
#if UNITY_EDITOR
    separated: true
#endif
    ...);
```

This allows the use of the Safari debugger, based on [pull request #161](https://github.com/gree/unity-webview/pull/161).

### iOS

#### Enable WKWebView

WKWebView is supported but disabled by default. Enable it with:

```csharp
webViewObject = (new GameObject("WebViewObject")).AddComponent<WebViewObject>();
webViewObject.Init(
    ...
    enableWKWebView: true);
```

This flag has no effect on platforms without WKWebView (e.g., iOS7 and Android) and should be set to `true` for iOS9 or later.

#### WKWebView Only Implementation

Apple now warns against using `UIWebView` APIs. The plugin includes two variations: `WebView.mm` and `WebViewWithUIWebView.mm`. Use `WebView.mm` for iOS9 or later. Modify `#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0` in these files if needed.

**Note:** WKWebView is available since iOS8 but was significantly changed in iOS9.

#### XMLHttpRequest for File URLs

WKWebView does not allow XMLHttpRequest access to file URLs by default. Enable this by defining `UNITYWEBVIEW_IOS_ALLOW_FILE_URLS`.

### Android

#### File Input Field

The Android implementation uses Android Fragment for file input fields. If you don’t need this feature, use `dist/unity-webview-nofragment.unitypackage` or `dist/unity-webview-nofragment.zip`.

To enable file input fields, set the following permissions:

* `android.permission.READ_EXTERNAL_STORAGE`
* `android.permission.WRITE_EXTERNAL_STORAGE`
* `android.permission.CAMERA`

Configure `android.permission.WRITE_EXTERNAL_STORAGE` in `Player Settings/Other Settings/Write Permission` and `android.permission.CAMERA` by defining `UNITYWEBVIEW_ANDROID_ENABLE_CAMERA`.

#### Hardware Acceleration

Ensure the main activity has `android:hardwareAccelerated="true"`:

- **Unity 2018.1 or newer:** Use [UnityWebViewPostprocessBuild.cs](https://forum.unity.com/threads/android-hardwareaccelerated-is-forced-false-in-all-activities.532786/) to set this automatically.
- **Unity 2017.x - 2018.0:** Manually edit `AndroidManifest.xml` as Unity forces `android:hardwareAccelerated="false"`.
- **Unity 5.x or older:** Modify `AndroidManifest.xml` after the initial build.

**Note:** Unity 5.6.1p4 or newer resolves related issues.

#### Uses Cleartext Traffic

To allow cleartext traffic for API level 28 or higher, define `UNITYWEBVIEW_ANDROID_USES_CLEARTEXT_TRAFFIC` so `UnityWebViewPostprocessBuild.cs` adds `android:usesCleartextTraffic="true"`.

#### Camera/Audio Permissions

To enable camera and microphone access:

- Define `UNITYWEBVIEW_ANDROID_ENABLE_CAMERA` and `UNITYWEBVIEW_ANDROID_ENABLE_MICROPHONE`.
- Update `AndroidManifest.xml` with the required permissions and features.

**Note:** Request permissions at runtime for Android API 23 or later.

#### `navigator.onLine`

Enable `navigator.onLine` by defining `UNITYWEBVIEW_ANDROID_ENABLE_NAVIGATOR_ONLINE`. The plugin will check `Application.internetReachability` and update WebView's `setNetworkAvailable()`.

#### Margin Adjustment for Keyboard Popup

To force margin adjustment for keyboard popups, define `UNITYWEBVIEW_ANDROID_FORCE_MARGIN_ADJUSTMENT_FOR_KEYBOARD`.

#### Building WebViewPlugin-*.aar.tmpl

To build `WebViewPlugin-*.aar.tmpl` files:

1. Install Unity 2019.4.40f1 with Android Build Support and Unity 5.6.1f1.
2. Run `./install.sh` from `plugins/Android`.

Options:

```
Usage: ./install.sh [OPTIONS]

Options:

  --nofragment       Build a nofragment variant.
  --development      Build a development variant.
  --zorderpatch      Build with the patch for Unity 5.6.0 and 5.6.1.
```

### WebGL

**Note:** For Unity 2020.1.0f1 or newer, use `unity-webview-2020` instead.

After importing `dist/unity-webview.unitypackage` or `dist/unity-webview.zip`, copy `WebGLTemplates/Default/TemplateData` from your Unity installation to `Assets/WebGLTemplates/unity-webview`.

Example for Unity 2018.4.13f1:

```bash
$ cp -a /Applications/Unity/Hub/Editor/2018.4.13f1/PlaybackEngines/WebGLSupport/BuildTools/WebGLTemplates/Default/TemplateData Assets/WebGLTemplates/unity-webview
```

In `Project Settings/Player/Resolution and Presentation`, select `unity-webview` in `WebGL Template`.

### Web Player

**Note:** Support for Web Player will be removed as it is obsolete.

The implementation uses IFRAME. Ensure both "an_unityplayer_page.html" and "a_page_loaded_in_webview.html" are on the same domain to avoid cross-domain requests.