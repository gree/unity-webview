# unity-webview

unity-webview is a plugin for Unity 5 that overlays WebView components
on Unity view. It works on Android, iOS, Unity Web Player, and OS X
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

## Platform Specific Notes

### OS X (Editor)

#### Unity 2017.1

The plugin cannot be loaded in Unity 2017.1. Please perform the following to solve the issue:

```bash
$ cd /Applications/Unity/Unity.app/Contents/Frameworks/
$ ln -s Mono/MonoEmbedRuntime .
```

cf. https://github.com/gree/unity-webview/issues/219#issuecomment-315760749

#### App Transport Security

Since Unity 5.3.0, Unity.app is built with ATS (App Transport
Security) enabled and non-secured connection (HTTP) is not
permitted. If you want to open `http://foo/bar.html` with this plugin
on Unity OS X Editor, you need to open
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

#### WebViewSeparated.bundle

WebViewSeparated.bundle is a variation of WebView.bundle. It is based
on https://github.com/gree/unity-webview/pull/161 . As noted in the
pull-request, it shows a separate window and allows a developer to
utilize the Safari debugger. For enabling it, please define
`WEBVIEW_SEPARATED`.

### iOS

The implementation now supports WKWebView but it is disabled by
default. For enabling it, please set enableWKWebView as below:

```csharp
		webViewObject.Init(
            ...
            enableWKWebView: true);
```


### Android

*NOTE: the following steps are now performed by Assets/Plugins/Android/Editor/UnityWebViewPostprocessBuild.cs.*

Once you built an apk, please copy
`sample/Temp/StatingArea/AndroidManifest-main.xml` to
`sample/Assets/Plugins/Android/AndroidManifest.xml`, edit the latter to add
`android:hardwareAccelerated="true"` to `<activity
android:name="com.unity3d.player.UnityPlayerActivity" ...`, and
rebuilt the apk. Although some old/buggy devices may not work well
with `android:hardwareAccelerated="true"`, the WebView runs very
smoothly with this setting.

*NOTE: Unity 5.6.1p4 or newer (including 2017 1.0) seems to fix the issue. cf. https://github.com/gree/unity-webview/pull/212#issuecomment-314952793*

For Unity 5.6.0 and 5.6.1 (except 5.6.1p4), you also need to modify `android:name` from
`com.unity3d.player.UnityPlayerActivity` to
`net.gree.unitywebview.CUnityPlayerActivity`. This custom activity
implementation will adjust Unity's SurfaceView z order. Please refer
`plugins/Android/src/net/gree/unitywebview/CUnityPlayerActivity.java`
and `plugins/Android/src/net/gree/unitywebview/CUnityPlayer.java` if
you already have your own acitivity implementation.

### Web Player

The implementation utilizes IFRAME so please put both
"an\_unityplayer\_page.html" and "a\_page\_loaded\_in\_webview.html"
should be placed on the same domain for avoiding cross-domain
requests.
