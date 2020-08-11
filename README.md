# unity-webview

unity-webview is a plugin for Unity 5 that overlays WebView components
on Unity view. It works on Android, iOS, Unity Web Player, and Mac
(Windows is not supported for now).

unity-webview is derived from keijiro-san's
https://github.com/keijiro/unity-webview-integration .

## Sample Project

It is placed under `sample/`. You can open it and import the plugin as
below:

1. Open `sample/Assets/Sample.unity`.
2. Open `dist/unity-webview.unitypackage` and import all files. It
   might be easier to extract `dist/unity-webview.zip` instead if
   you've imported unity-webview before.

*NOTE: The current implementation for Android utilizes Android Fragment for enabling the file input field after https://github.com/gree/unity-webview/commit/a1a2a89d2d0ced366faed9db308ccf4f689a7278 and may cause new issues that were not found before. If you don't need the file input field, you can install `dist/unity-webview-nofragment.unitypackage` or `dist/unity-webview-nofragment.zip` for selecting the variant without Fragment.*

## Package Manager

If you use Unity 2019.1 or later, the plugin can also be imported with Package Manager, by adding
the following entry in your `Packages/manifest.json`:

```json
{
  "dependencies": {
    ...
    "net.gree.unity-webview": "https://github.com/gree/unity-webview.git?path=/dist/package",
    ...
  }
}
```

## Common Notes

### UnityWebViewPostprocessBuild.cs

`Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` contains code for Android/iOS build, which
may cause errors if you haven't installed components for these platforms. As discussed in
https://github.com/gree/unity-webview/pull/397#issuecomment-464631894, I intentionally don't utilize
`UNITY_IOS` and/or `UNITY_ANDROID`. If you haven't installed Android/iOS components, please comment
out adequate parts in the script.

## Platform Specific Notes

### Mac (Editor)

#### macOS Version

The current implementation utilizes https://developer.apple.com/documentation/webkit/wkwebview/2873260-takesnapshotwithconfiguration to capture an offscreen webview image so that macOS 10.13 (High Sierra) or later is required.

#### App Transport Security

Since Unity 5.3.0, Unity.app is built with ATS (App Transport
Security) enabled and non-secured connection (HTTP) is not
permitted. If you want to open `http://foo/bar.html` with this plugin
on Unity Mac Editor, you need to open
`/Applications/Unity5.3.4p3/Unity.app/Contents/Info.plist` with a text
editor and add the following,

```diff
--- Info.plist~	2016-04-11 18:29:25.000000000 +0900
+++ Info.plist	2016-04-15 16:17:28.000000000 +0900
@@ -57,5 +57,10 @@
 	<string>EditorApplicationPrincipalClass</string>
 	<key>UnityBuildNumber</key>
 	<string>b902ad490cea</string>
+	<key>NSAppTransportSecurity</key>
+	<dict>
+		<key>NSAllowsArbitraryLoads</key>
+		<true/>
+	</dict>
 </dict>
 </plist>
```

or invoke the following from your terminal,

```bash
/usr/libexec/PlistBuddy -c "Add NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" /Applications/Unity/Unity.app/Contents/Info.plist
```

##### References

* https://github.com/gree/unity-webview/issues/64
* https://onevcat.zendesk.com/hc/en-us/articles/215527307-I-cannot-open-the-web-page-in-Unity-Editor-

#### Separeted Mode

A separate window will be shown if `separated: true` is specified:

```csharp
        webViewObject = (new GameObject("WebViewObject")).AddComponent<WebViewObject>();
        webViewObject.Init(
            ...
#if UNITY_EDITOR
            separated: true
#endif
            ...);
```

This is based on https://github.com/gree/unity-webview/pull/161 and allows a developer to utilize
the Safari debugger.

### iOS

#### enableWKWebView

The implementation now supports WKWebView but it is disabled by
default. For enabling it, please set enableWKWebView as below:

```csharp
        webViewObject = (new GameObject("WebViewObject")).AddComponent<WebViewObject>();
        webViewObject.Init(
            ...
            enableWKWebView: true);
```
(cf. https://github.com/gree/unity-webview/blob/de9a25c0ab0622b15c15ecbc0c7cd85858aa7745/sample/Assets/Scripts/SampleWebView.cs#L94)

This flag have no effect on platforms without WKWebView (such as iOS7 and Android) and should always
be set true for iOS9 or later (see the next section).

#### WKWebView only implementation for iOS9 or later

Apple recently sends the following warning for an app submission,

> ITMS-90809: Deprecated API Usage - Apple will stop accepting submissions of apps that use
> UIWebView APIs . See https://developer.apple.com/documentation/uikit/uiwebview for more
> information.

so the current implementation for iOS has two variations (Assets/Plugins/iOS/WebView.mm and Assets/Plugins/iOS/WebViewWithUIWebView.mm), in
which new one (Assets/Plugins/iOS/WebView.mm) utilizes only WKWebView if iOS deployment target is iOS9 or later. Please modify
`#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0` in those files if you need to change this behavior.

*NOTE: WKWebView is available since iOS8 but was largely changed in iOS9, so we use `___IPHONE_9_0` instead of `__IPHONE_8_0`*
*NOTE: Several versions of Unity themselves also have the ITMS-90809 issue (cf. https://issuetracker.unity3d.com/issues/ios-apple-throws-deprecated-api-usage-warning-for-using-uiwebview-when-submitting-builds-to-the-app-store-connect ).*/

### Android

*NOTE: The current implementation for Android utilizes Android Fragment for enabling the file input field after https://github.com/gree/unity-webview/commit/a1a2a89d2d0ced366faed9db308ccf4f689a7278 and may cause new issues that were not found before. If you don't need the file input field, you can install `dist/unity-webview-nofragment.unitypackage` or `dist/unity-webview-nofragment.zip` for selecting the variant without Fragment.*

#### hardwareAccelerated

The main activity should have `android:hardwareAccelerated="true"`, otherwise a webview won't run
smoothly. Depending on unity versions, we need to set it as below (basically this will be done by
post-process build scripts).

##### Unity 2018.1 or newer

Based on the technique discussed in
https://forum.unity.com/threads/android-hardwareaccelerated-is-forced-false-in-all-activities.532786/ and https://github.com/Over17/UnityAndroidManifestCallback, `Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` edit the manifest to set `android:hardwareAccelerated="true"`. Please note this works with the `gradle` (not `internal`) build setting.

##### Unity 2017.x - 2018.0

Unity forcibly set `android:hardwareAccelerated="false"` regardless of its setting in `Plugins/Android/AndroidManifest.xml`, as discussed in https://github.com/gree/unity-webview/issues/382 (see also https://github.com/gree/unity-webview/issues/342 and https://forum.unity.com/threads/android-hardwareaccelerated-is-forced-false-in-all-activities.532786/ ), and there is no solution for automatically correcting this setting. Please export the project and manually correct `AndroidManifest.xml`.

##### Unity 5.x or older

After the initial build, `Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` will copy
`Temp/StatingArea/AndroidManifest-main.xml` to
`Assets/Plugins/Android/AndroidManifest.xml`, edit the latter to add
`android:hardwareAccelerated="true"` to `<activity
android:name="com.unity3d.player.UnityPlayerActivity" ...`. Then you need to build the app again to
reflect this change.

*NOTE: Unity 5.6.1p4 or newer (including 2017 1.0) seems to fix the following issue (cf. https://github.com/gree/unity-webview/pull/212#issuecomment-314952793)*

For Unity 5.6.0 and 5.6.1 (except 5.6.1p4), you also need to modify `android:name` from
`com.unity3d.player.UnityPlayerActivity` to
`net.gree.unitywebview.CUnityPlayerActivity`. This custom activity
implementation will adjust Unity's SurfaceView z order. Please refer
`plugins/Android/src/net/gree/unitywebview/CUnityPlayerActivity.java`
and `plugins/Android/src/net/gree/unitywebview/CUnityPlayer.java` if
you already have your own activity implementation.

#### usesCleartextTraffic

For allowing http cleartext traffic for Android API level 28 or higher, please define `UNITYWEBVIEW_ANDROID_USES_CLEARTEXT_TRAFFIC` so that `Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` adds `android:usesCleartextTraffic="true"` to the applicaiton.

#### Camera/Audio Permission/Feature

For allowing camera access (`navigator.mediaDevices.getUserMedia({ video:true })`), please define `UNITYWEBVIEW_ANDROID_ENABLE_CAMERA` so that `Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` adds the followings to `AndroidManifest.xml`.

```xml
  <uses-permission android:name="android.permission.CAMERA" />
  <uses-feature android:name="android.hardware.camera" />
```

For allowing microphone access (`navigator.mediaDevices.getUserMedia({ audio:true })`), please define `UNITYWEBVIEW_ANDROID_ENABLE_MICROPHONE` so that `Assets/Plugins/Editor/UnityWebViewPostprocessBuild.cs` adds the followings to `AndroidManifest.xml`.

```xml
  <uses-permission android:name="android.permission.MICROPHONE" />
  <uses-feature android:name="android.hardware.microphone" />
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

#### How to build WebViewPlugin.jar

The following steps are for Mac but you can follow similar ones for Windows.

1. Place Unity 5.6.1f1 as `/Applications/Unity5.6.1f1` on osx or `\Program Files\Unity5.6.1f1\` on windows.
2. Install [Android Studio](https://developer.android.com/studio/install).
3. Open Android Studio and select "Configure/SDK Manager", select the followings with "Show Package Details",
   and click OK.
  * SDK Platforms
    * Android 6.0 (Marshmallow)
      * Android SDK Platform 23
  * SDK Tools
    * Android SDK Build Tools
      * 28.0.2
4. Open Terminal.app and perform the followings. You should find
   `unity-webview/build/Packager/Assets/Plugins/Android/WebViewPlugin.jar` if successful.

```bash
$ export ANDROID_HOME=~/Library/Android/sdk
$ export PATH=$PATH:~/Library/Android/sdk/platform-tools/bin:~/Library/Android/sdk/tools:~/Library/Android/sdk/tools/bin
$ cd unity-webview/plugins/Android
$ ./install.sh
```

### WebGL

After importing `dist/unity-webview.unitypackage` or `dist/unity-webview.zip`, please copy `WebGLTemplates/Default/TemplateData` from your Unity installation to `Assets/WebGLTemplates/unity-webivew`. If you utilize Unity 2019.4.13f1 for example,

```bash
$ cp -a /Applications/Unity/Hub/Editor/2018.4.13f1/PlaybackEngines/WebGLSupport/BuildTools/WebGLTemplates/Default/TemplateData Assets/WebGLTemplates/unity-webview
```

Then in `Project Settings/Player/Resolution and Presentation`, please select `unity-webview` in `WebGL Template`.

### Web Player

*NOTE: Web Player is obsolete so that the support for it will be removed.*

The implementation utilizes IFRAME so please put both
"an\_unityplayer\_page.html" and "a\_page\_loaded\_in\_webview.html"
should be placed on the same domain for avoiding cross-domain
requests.
