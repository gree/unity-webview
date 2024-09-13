# unity-webview

`unity-webview` is a Unity 5 (and newer) plugin that overlays WebView components on Unity's rendering view. It supports Android, iOS, Unity Web Player, and Mac (Windows is not supported at this time).

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

## General Notes
If you start from the `sample` project, most of the time you just have to comment and uncomment to make the webview fit your needs.

Please also  note that the Init function of the `Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` have a lot of parameter and can be quite long.

If you have a blank screen, it is most likely that you used HTTP (instead of HTTPS) or self signed certificates. In this case, please refer to the `use Cleartext Traffic` section of this README.

You can call JS functions via Unity with the webViewObject.EvaluateJS() function even if your JS is served by a server. However, you cannot launch Unity functions from JS.
To do this, you will either have to use [this repo](https://github.com/zouloux/unity-web-view) or to create a JS->Server->Unity.
If you create a fork that allows a remote Unity to JS communication, feel free to fork this repo, add the functionnality and submit your changes via a clear and well described Pull Request

**Warning** : Carefully look at the ```#if``` and ```#endif``` because they make parts of the code run or not run depending on the platform and the Editor version. 
You sometimes have to look at them to be sure that the code you add or edit will be executed.

## Platform-Specific Notes

### Mac (Editor)

#### macOS Version

The implementation uses [WKWebView’s `takeSnapshotWithConfiguration`](https://developer.apple.com/documentation/webkit/wkwebview/2873260-takesnapshotwithconfiguration) to capture an offscreen WebView image. macOS 10.13 (High Sierra) or later is required.

#### App Transport Security

Since Unity 5.3.0, Unity.app is built with ATS (App Transport Security) enabled, which does not permit non-secured (HTTP) connections. To open HTTP URLs in the Unity Mac Editor, update `/Applications/Unity5.3.4p3/Unity.app/Contents/Info.plist` as follows:

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

##### References

* https://github.com/gree/unity-webview/issues/64
* https://onevcat.zendesk.com/hc/en-us/articles/215527307-I-cannot-open-the-web-page-in-Unity-Editor-

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
[cf.](https://github.com/gree/unity-webview/blob/de9a25c0ab0622b15c15ecbc0c7cd85858aa7745/sample/Assets/Scripts/SampleWebView.cs#L94)

This flag has no effect on platforms without WKWebView (e.g., iOS7 and Android) and should be set to `true` for iOS9 or later.

#### WKWebView Only Implementation for iOS9 or later

Apple now warns against using `UIWebView` APIs :

> ITMS-90809: Deprecated API Usage - Apple will stop accepting submissions of apps that use
> UIWebView APIs . See https://developer.apple.com/documentation/uikit/uiwebview for more
> information.

The plugin includes two variations: `Assets/Plugins/iOS/WebView.mm` and `Assets/Plugins/iOS/WebViewWithUIWebView.mm`. Use `WebView.mm` for iOS9 or later. 
Modify `#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0` in these files if needed.

*NOTE: WKWebView is available since iOS8 but was largely changed in iOS9, so we use `___IPHONE_9_0` instead of `__IPHONE_8_0`*
*NOTE: Several versions of Unity themselves also have the ITMS-90809 issue (cf. https://issuetracker.unity3d.com/issues/ios-apple-throws-deprecated-api-usage-warning-for-using-uiwebview-when-submitting-builds-to-the-app-store-connect ).*/

#### XMLHttpRequest for File URLs

WKWebView doesn't allow to access file URLs with XMLHttpRequest. This limitation can be relaxed by `allowFileAccessFromFileURLs`/`allowUniversalAccessFromFileURLs` settings. Those are however private APIs so currently disabled by default. For enabling them, please define `UNITYWEBVIEW_IOS_ALLOW_FILE_URLS`.

cf. https://github.com/gree/unity-webview/issues/785
cf. https://github.com/gree/unity-webview/issues/224#issuecomment-640642516

### Android

Since `Assets/Plugins/src` is depreciated in recent Unity version, we switched to .aar files (Android Archive Library). 
If you need to edit some AndroidManifest.xml files :
1. Opening the `plugin`folder of this repo in Android Studio
2. Make somes changes (most of the time edit the `plugin/Android/webview/src/main/AndroidManifest.xml`).
3. Build the app
4. You will see your aar file in `build/outputs/aar/`
5. Move this file to `Assets/Plugins/Android/`

#### File Input Field

The Android implementation uses Android Fragment for file input fields since [here](https://github.com/gree/unity-webview/commit/a1a2a89d2d0ced366faed9db308ccf4f689a7278)  and may cause new issues that were not found before. 
If you don't need the file input field, you can install `dist/unity-webview-nofragment.unitypackage` or `dist/unity-webview-nofragment.zip` for selecting the variant without Fragment.

To enable file input fields, set the following permissions:

* `android.permission.READ_EXTERNAL_STORAGE`
* `android.permission.WRITE_EXTERNAL_STORAGE`
* `android.permission.CAMERA`

Set `android.permission.WRITE_EXTERNAL_STORAGE` in `Player Settings/Other Settings/Write Permission` and `android.permission.CAMERA` by defining `UNITYWEBVIEW_ANDROID_ENABLE_CAMERA`. (cf. [Camera/Audio Permission/Feature](#cameraaudio-permissionfeature)).

#### Hardware Acceleration

Ensure the main activity has `android:hardwareAccelerated="true"`:

- **Unity 2018.1 or newer:** Use [UnityWebViewPostprocessBuild.cs](https://forum.unity.com/threads/android-hardwareaccelerated-is-forced-false-in-all-activities.532786/) to set this automatically. (Note that it is already set up in the `sample` project)
- **Unity 2017.x - 2018.0:** Manually edit `AndroidManifest.xml` as Unity forces `android:hardwareAccelerated="false"`.
- **Unity 5.x or older:** Modify `AndroidManifest.xml` after the initial build. *Note: [Unity 5.6.1p4 or newer (including 2017 1.0) seems to fix this issue](https://github.com/gree/unity-webview/pull/212#issuecomment-314952793)*.

#### Uses Cleartext Traffic

To allow cleartext traffic for API level 28 or higher, define `UNITYWEBVIEW_ANDROID_USES_CLEARTEXT_TRAFFIC` so `UnityWebViewPostprocessBuild.cs` adds `android:usesCleartextTraffic="true"`.

#### Camera/Audio Permissions

To enable camera and microphone access:

For allowing camera access (`navigator.mediaDevices.getUserMedia({ video:true })`), please define `UNITYWEBVIEW_ANDROID_ENABLE_CAMERA` so that `Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` adds the followings to `AndroidManifest.xml`,

```xml
  <uses-permission android:name="android.permission.CAMERA" />
  <uses-feature android:name="android.hardware.camera" />
  <queries>
    <intent>
      <action android:name="android.media.action.IMAGE_CAPTURE" />
    </intent>
  </queries>
```

and call the following on runtime.

```c#
        webViewObject.SetCameraAccess(true);
```

For allowing microphone access (`navigator.mediaDevices.getUserMedia({ audio:true })`), please define `UNITYWEBVIEW_ANDROID_ENABLE_MICROPHONE` so that `Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` adds the followings to `AndroidManifest.xml`,

```xml
  <uses-permission android:name="android.permission.MICROPHONE" />
  <uses-feature android:name="android.hardware.microphone" />
  <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
```

and call the following on runtime.

```c#
        webViewObject.SetMicrophoneAccess(true);
```

Details for each Unity version are the same as for hardwareAccelerated. Please also note that it is necessary to request permissions at runtime for Android API 23 or later as below:

```diff
diff --git a/sample/Assets/Scripts/SampleWebView.cs b/sample/Assets/Scripts/SampleWebView.cs
index a62c1ca..a5efe9f 100644
--- a/sample/Assets/Scripts/SampleWebView.cs
+++ b/sample/Assets/Scripts/SampleWebView.cs
@@ -24,6 +24,9 @@ using UnityEngine;
 using UnityEngine.UI;
 using UnityEngine.Networking;
 #endif
+#if !UNITY_EDITOR && UNITY_ANDROID
+using UnityEngine.Android;
+#endif
 
 public class SampleWebView : MonoBehaviour
 {
@@ -31,8 +34,29 @@ public class SampleWebView : MonoBehaviour
     public GUIText status;
     WebViewObject webViewObject;
 
+#if !UNITY_EDITOR && UNITY_ANDROID
+    bool inRequestingCameraPermission;
+
+    void OnApplicationFocus(bool hasFocus)
+    {
+        if (inRequestingCameraPermission && hasFocus) {
+            inRequestingCameraPermission = false;
+        }
+    }
+#endif
+
     IEnumerator Start()
     {
+#if !UNITY_EDITOR && UNITY_ANDROID
+        if (!Permission.HasUserAuthorizedPermission(Permission.Camera))
+        {
+            inRequestingCameraPermission = true;
+            Permission.RequestUserPermission(Permission.Camera);
+        }        
+        while (inRequestingCameraPermission) {
+            yield return new WaitForSeconds(0.5f);
+        }
+#endif
         webViewObject = (new GameObject("WebViewObject")).AddComponent<WebViewObject>();
         webViewObject.Init(
             cb: (msg) =>
```

(cf. https://github.com/gree/unity-webview/issues/473#issuecomment-559412496)
(cf. https://docs.unity3d.com/Manual/android-RequestingPermissions.html)

#### `navigator.onLine`

Enable `navigator.onLine` by defining `UNITYWEBVIEW_ANDROID_ENABLE_NAVIGATOR_ONLINE`. The plugin will check `Application.internetReachability` and update WebView's `setNetworkAvailable()`.

#### Margin Adjustment for Keyboard Popup
This plugin adjusts the bottom margin temporarily when the keyboard pops up to keep the focused input field displayed. This adjustment is however disabled for some cases (non-fullscreen mode or both portrait/landscape are enabled) to avoid odd behaviours (cf. https://github.com/gree/unity-webview/pull/809 ). Please define `UNITYWEBVIEW_ANDROID_FORCE_MARGIN_ADJUSTMENT_FOR_KEYBOARD` to force the margin adjustment even for these cases.

#### How to build WebViewPlugin-*.aar.tmpl

UnityWebViewPostprocessBuild.cs will select one of WebViewPlugin-*.aar.tmpl depending on EditorUserSettings.development. You can build these files as below:

1. Install Unity 2019.4.40f1 with Android Build Support by Unity Hub.
   * Also install Unity 5.6.1f1 from https://unity.com/ja/releases/editor/whats-new/5.6.1 and specify `--zorderpatch` if you need to include CUnityPlayer and CUnityPlayerActivity (cf. [Unity 5.x or older](#unity-5x-or-older)).
2. Open Terminal (mac) or Git Bash (windows), `cd plugins/Android`, and invoke `./install.sh`.

If successful, you should find `build/Packager/Assets/Plugins/Android/WebViewPlugin-*.aar.tmpl`. install.sh has the following options:

```
Usage: ./install.sh [OPTIONS]

Options:

  --nofragment		build a nofragment variant.
  --development		build a development variant.
  --zorderpatch		build with the patch for 5.6.0 and 5.6.1 (except 5.6.1p4)

```

### WebGL

*NOTE: for Unity 2020.1.0f1 or newer, please use `unity-webview-2020` instead of `unity-webview` below.*

After importing `dist/unity-webview.unitypackage` or `dist/unity-webview.zip`, please copy 
`WebGLTemplates/Default/TemplateData` from your Unity installation to `Assets/WebGLTemplates/unity-webview`. If you utilize Unity 2018.4.13f1 for example,

```bash
$ cp -a /Applications/Unity/Hub/Editor/2018.4.13f1/PlaybackEngines/WebGLSupport/BuildTools/WebGLTemplates/Default/TemplateData Assets/WebGLTemplates/unity-webview
```

Then in `Project Settings/Player/Resolution and Presentation`, please select `unity-webview` in `WebGL Template`.
