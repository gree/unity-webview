/*
 * Copyright (C) 2011 Keijiro Takahashi
 * Copyright (C) 2012 GREE, Inc.
 * 
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 * 
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 * 
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

using UnityEngine;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
#if UNITY_2018_4_OR_NEWER
using UnityEngine.Networking;
#endif
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
using System.IO;
using System.Text.RegularExpressions;
using UnityEngine.EventSystems;
using UnityEngine.Rendering;
using UnityEngine.UI;
#endif
#if UNITY_ANDROID
using UnityEngine.Android;
#endif

using Callback = System.Action<string>;

#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
public class UnitySendMessageDispatcher
{
    public static void Dispatch(string name, string method, string message)
    {
        GameObject obj = GameObject.Find(name);
        if (obj != null)
            obj.SendMessage(method, message);
    }
}
#endif

public class WebViewObject : MonoBehaviour
{
    Callback onJS;
    Callback onError;
    Callback onHttpError;
    Callback onStarted;
    Callback onLoaded;
    Callback onHooked;
    Callback onCookies;
    bool paused;
    bool visibility;
    bool alertDialogEnabled;
    bool scrollBounceEnabled;
    int mMarginLeft;
    int mMarginTop;
    int mMarginRight;
    int mMarginBottom;
    bool mMarginRelative;
    float mMarginLeftComputed;
    float mMarginTopComputed;
    float mMarginRightComputed;
    float mMarginBottomComputed;
    bool mMarginRelativeComputed;
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
    public GameObject canvas;
    Image bg;
    IntPtr webView;
    Rect rect;
    Texture2D texture;
    byte[] textureDataBuffer;
    string inputString = "";
    bool hasFocus;
#elif UNITY_IPHONE
    IntPtr webView;
#elif UNITY_ANDROID
    AndroidJavaObject webView;
    
    bool mVisibility;
    int mKeyboardVisibleHeight;
    float mResumedTimestamp;
    int mLastScreenHeight;
#if UNITYWEBVIEW_ANDROID_ENABLE_NAVIGATOR_ONLINE
    float androidNetworkReachabilityCheckT0 = -1.0f;
    NetworkReachability? androidNetworkReachability0 = null;
#endif
    
    void OnApplicationPause(bool paused)
    {
        this.paused = paused;
        if (webView == null)
            return;
        // if (!paused && mKeyboardVisibleHeight > 0)
        // {
        //     webView.Call("SetVisibility", false);
        //     mResumedTimestamp = Time.realtimeSinceStartup;
        // }
        webView.Call("OnApplicationPause", paused);
    }

    void Update()
    {
        // NOTE:
        //
        // When OnApplicationPause(true) is called and the app is in closing, webView.Call(...)
        // after that could cause crashes because underlying java instances were closed.
        //
        // This has not been cleary confirmed yet. However, as Update() is called once after
        // OnApplicationPause(true), it is likely correct.
        //
        // Base on this assumption, we do nothing here if the app is paused.
        //
        // cf. https://github.com/gree/unity-webview/issues/991#issuecomment-1776628648
        // cf. https://docs.unity3d.com/2020.3/Documentation/Manual/ExecutionOrder.html
        //
        // In between frames
        //
        // * OnApplicationPause: This is called at the end of the frame where the pause is detected,
        //   effectively between the normal frame updates. One extra frame will be issued after
        //   OnApplicationPause is called to allow the game to show graphics that indicate the
        //   paused state.
        //
        if (paused)
            return;
        if (webView == null)
            return;
#if UNITYWEBVIEW_ANDROID_ENABLE_NAVIGATOR_ONLINE
        var t = Time.time;
        if (t - 1.0f >= androidNetworkReachabilityCheckT0)
        {
            androidNetworkReachabilityCheckT0 = t;
            var androidNetworkReachability = Application.internetReachability;
            if (androidNetworkReachability0 != androidNetworkReachability)
            {
                androidNetworkReachability0 = androidNetworkReachability;
                webView.Call("SetNetworkAvailable", androidNetworkReachability != NetworkReachability.NotReachable);
            }
        }
#endif
        if (mResumedTimestamp != 0.0f && Time.realtimeSinceStartup - mResumedTimestamp > 0.5f)
        {
            mResumedTimestamp = 0.0f;
            webView.Call("SetVisibility", mVisibility);
        }
        if (Screen.height != mLastScreenHeight)
        {
            mLastScreenHeight = Screen.height;
            webView.Call("EvaluateJS", "(function() {var e = document.activeElement; if (e != null && e.tagName.toLowerCase() != 'body') {e.blur(); e.focus();}})()");
        }
        for (;;) {
            if (webView == null)
                break;
            var s = webView.Call<String>("GetMessage");
            if (s == null)
                break;
            var i = s.IndexOf(':', 0);
            if (i == -1)
                continue;
            switch (s.Substring(0, i)) {
            case "CallFromJS":
                CallFromJS(s.Substring(i + 1));
                break;
            case "CallOnError":
                CallOnError(s.Substring(i + 1));
                break;
            case "CallOnHttpError":
                CallOnHttpError(s.Substring(i + 1));
                break;
            case "CallOnLoaded":
                CallOnLoaded(s.Substring(i + 1));
                break;
            case "CallOnStarted":
                CallOnStarted(s.Substring(i + 1));
                break;
            case "CallOnHooked":
                CallOnHooked(s.Substring(i + 1));
                break;
            case "CallOnCookies":
                CallOnCookies(s.Substring(i + 1));
                break;
            case "SetKeyboardVisible":
                SetKeyboardVisible(s.Substring(i + 1));
                break;
            case "RequestFileChooserPermissions":
                RequestFileChooserPermissions();
                break;
            }
        }
    }

    /// Called from Java native plugin to set when the keyboard is opened
    public void SetKeyboardVisible(string keyboardVisibleHeight)
    {
        if (BottomAdjustmentDisabled())
        {
            return;
        }
        var keyboardVisibleHeight0 = mKeyboardVisibleHeight;
        var keyboardVisibleHeight1 = Int32.Parse(keyboardVisibleHeight);
        if (keyboardVisibleHeight0 != keyboardVisibleHeight1)
        {
            mKeyboardVisibleHeight = keyboardVisibleHeight1;
            SetMargins(mMarginLeft, mMarginTop, mMarginRight, mMarginBottom, mMarginRelative);
        }
    }
    
    /// Called from Java native plugin to request permissions for the file chooser.
    public void RequestFileChooserPermissions()
    {
        var permissions = new List<string>();
        using (var version = new AndroidJavaClass("android.os.Build$VERSION"))
        {
            if (version.GetStatic<int>("SDK_INT") >= 33)
            {
                if (!Permission.HasUserAuthorizedPermission("android.permission.READ_MEDIA_IMAGES"))
                {
                    permissions.Add("android.permission.READ_MEDIA_IMAGES");
                }
                if (!Permission.HasUserAuthorizedPermission("android.permission.READ_MEDIA_VIDEO"))
                {
                    permissions.Add("android.permission.READ_MEDIA_VIDEO");
                }
                if (!Permission.HasUserAuthorizedPermission("android.permission.READ_MEDIA_AUDIO"))
                {
                    permissions.Add("android.permission.READ_MEDIA_AUDIO");
                }
            }
            else
            {
                if (!Permission.HasUserAuthorizedPermission(Permission.ExternalStorageRead))
                {
                    permissions.Add(Permission.ExternalStorageRead);
                }
                if (!Permission.HasUserAuthorizedPermission(Permission.ExternalStorageWrite))
                {
                    permissions.Add(Permission.ExternalStorageWrite);
                }
            }
        }
        if (!Permission.HasUserAuthorizedPermission(Permission.Camera))
        {
            permissions.Add(Permission.Camera);
        }
        if (permissions.Count > 0)
        {
#if UNITY_2020_2_OR_NEWER
            var grantedCount = 0;
            var deniedCount = 0;
            var callbacks = new PermissionCallbacks();
            callbacks.PermissionGranted += (permission) =>
            {
                grantedCount++;
                if (grantedCount + deniedCount == permissions.Count)
                {
                    StartCoroutine(CallOnRequestFileChooserPermissionsResult(grantedCount == permissions.Count));
                }
            };
            callbacks.PermissionDenied += (permission) =>
            {
                deniedCount++;
                if (grantedCount + deniedCount == permissions.Count)
                {
                    StartCoroutine(CallOnRequestFileChooserPermissionsResult(grantedCount == permissions.Count));
                }
            };
            callbacks.PermissionDeniedAndDontAskAgain += (permission) =>
            {
                deniedCount++;
                if (grantedCount + deniedCount == permissions.Count)
                {
                    StartCoroutine(CallOnRequestFileChooserPermissionsResult(grantedCount == permissions.Count));
                }
            };
            Permission.RequestUserPermissions(permissions.ToArray(), callbacks);
#else
            StartCoroutine(RequestFileChooserPermissionsCoroutine(permissions.ToArray()));
#endif
        }
        else
        {
            StartCoroutine(CallOnRequestFileChooserPermissionsResult(true));
        }
    }

#if UNITY_2020_2_OR_NEWER
#else
    int mRequestPermissionPhase;

    IEnumerator RequestFileChooserPermissionsCoroutine(string[] permissions)
    {
        foreach (var permission in permissions)
        {
            mRequestPermissionPhase = 0;
            Permission.RequestUserPermission(permission);
            // waiting permission dialog that may not be opened.
            for (var i = 0; i < 8 && mRequestPermissionPhase == 0; i++)
            {
                yield return new WaitForSeconds(0.25f);
            }
            if (mRequestPermissionPhase == 0)
            {
                // permission dialog was not opened.
                continue;
            }
            while (mRequestPermissionPhase == 1)
            {
                yield return new WaitForSeconds(0.3f);
            }
        }
        yield return new WaitForSeconds(0.3f);
        var granted = 0;
        foreach (var permission in permissions)
        {
            if (Permission.HasUserAuthorizedPermission(permission))
            {
                granted++;
            }
        }
        StartCoroutine(CallOnRequestFileChooserPermissionsResult(granted == permissions.Length));
    }

    void OnApplicationFocus(bool hasFocus)
    {
        if (hasFocus)
        {
            if (mRequestPermissionPhase == 1)
            {
                mRequestPermissionPhase = 2;
            }
        }
        else
        {
            if (mRequestPermissionPhase == 0)
            {
                mRequestPermissionPhase = 1;
            }
        }
    }
#endif

    private IEnumerator CallOnRequestFileChooserPermissionsResult(bool granted)
    {
        for (var i = 0; i < 3; i++)
        {
            yield return null;
        }
        webView.Call("OnRequestFileChooserPermissionsResult", granted);
    }

    public int AdjustBottomMargin(int bottom)
    {
        if (BottomAdjustmentDisabled())
        {
            return bottom;
        }
        else if (mKeyboardVisibleHeight <= 0)
        {
            return bottom;
        }
        else
        {
            int keyboardHeight = 0;
            using (var unityClass = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
            using (var activity = unityClass.GetStatic<AndroidJavaObject>("currentActivity"))
            using (var player = activity.Get<AndroidJavaObject>("mUnityPlayer"))
            using (var view = player.Call<AndroidJavaObject>("getView"))
            using (var rect = new AndroidJavaObject("android.graphics.Rect"))
            {
                if (view.Call<bool>("getGlobalVisibleRect", rect))
                {
                    int h0 = rect.Get<int>("bottom");
                    view.Call("getWindowVisibleDisplayFrame", rect);
                    int h1 = rect.Get<int>("bottom");
                    keyboardHeight = h0 - h1;
                }
            }
            return (bottom > keyboardHeight) ? bottom : keyboardHeight;
        }
    }

    private bool BottomAdjustmentDisabled()
    {
#if UNITYWEBVIEW_ANDROID_FORCE_MARGIN_ADJUSTMENT_FOR_KEYBOARD
        return false;
#else
        return
            !Screen.fullScreen
            || ((Screen.autorotateToLandscapeLeft || Screen.autorotateToLandscapeRight)
                && (Screen.autorotateToPortrait || Screen.autorotateToPortraitUpsideDown));
#endif
    }
#else
    IntPtr webView;
#endif

    void Awake()
    {
        alertDialogEnabled = true;
        scrollBounceEnabled = true;
        mMarginLeftComputed = -9999;
        mMarginTopComputed = -9999;
        mMarginRightComputed = -9999;
        mMarginBottomComputed = -9999;
    }

    public bool IsKeyboardVisible
    {
        get
        {
#if !UNITY_EDITOR && UNITY_ANDROID
            return mKeyboardVisibleHeight > 0;
#elif !UNITY_EDITOR && UNITY_IPHONE
            return TouchScreenKeyboard.visible;
#else
            return false;
#endif
        }
    }

#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
    [DllImport("WebView")]
    private static extern string _CWebViewPlugin_GetAppPath();
    [DllImport("WebView")]
    private static extern IntPtr _CWebViewPlugin_InitStatic(
        bool inEditor, bool useMetal);
    [DllImport("WebView")]
    private static extern IntPtr _CWebViewPlugin_Init(
        string gameObject, bool transparent, bool zoom, int width, int height, string ua, bool separated);
    [DllImport("WebView")]
    private static extern int _CWebViewPlugin_Destroy(IntPtr instance);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_SetRect(
        IntPtr instance, int width, int height);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_SetVisibility(
        IntPtr instance, bool visibility);
    [DllImport("WebView")]
    private static extern bool _CWebViewPlugin_SetURLPattern(
        IntPtr instance, string allowPattern, string denyPattern, string hookPattern);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_LoadURL(
        IntPtr instance, string url);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_LoadHTML(
        IntPtr instance, string html, string baseUrl);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_EvaluateJS(
        IntPtr instance, string url);
    [DllImport("WebView")]
    private static extern int _CWebViewPlugin_Progress(
        IntPtr instance);
    [DllImport("WebView")]
    private static extern bool _CWebViewPlugin_CanGoBack(
        IntPtr instance);
    [DllImport("WebView")]
    private static extern bool _CWebViewPlugin_CanGoForward(
        IntPtr instance);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_GoBack(
        IntPtr instance);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_GoForward(
        IntPtr instance);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_Reload(
        IntPtr instance);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_SendMouseEvent(IntPtr instance, int x, int y, float deltaY, int mouseState);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_SendKeyEvent(IntPtr instance, int x, int y, string keyChars, ushort keyCode, int keyState);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_Update(IntPtr instance, bool refreshBitmap, int devicePixelRatio);
    [DllImport("WebView")]
    private static extern int _CWebViewPlugin_BitmapWidth(IntPtr instance);
    [DllImport("WebView")]
    private static extern int _CWebViewPlugin_BitmapHeight(IntPtr instance);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_Render(IntPtr instance, IntPtr textureBuffer);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_AddCustomHeader(IntPtr instance, string headerKey, string headerValue);
    [DllImport("WebView")]
    private static extern string _CWebViewPlugin_GetCustomHeaderValue(IntPtr instance, string headerKey);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_RemoveCustomHeader(IntPtr instance, string headerKey);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_ClearCustomHeader(IntPtr instance);
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_ClearCookies();
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_SaveCookies();
    [DllImport("WebView")]
    private static extern void _CWebViewPlugin_GetCookies(IntPtr instance, string url);
    [DllImport("WebView")]
    private static extern string _CWebViewPlugin_GetMessage(IntPtr instance);
#elif UNITY_IPHONE
    [DllImport("__Internal")]
    private static extern IntPtr _CWebViewPlugin_Init(string gameObject, bool transparent, bool zoom, string ua, bool enableWKWebView, int wkContentMode, bool wkAllowsLinkPreview, bool wkAllowsBackForwardNavigationGestures, int radius);
    [DllImport("__Internal")]
    private static extern int _CWebViewPlugin_Destroy(IntPtr instance);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetMargins(
        IntPtr instance, float left, float top, float right, float bottom, bool relative);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetVisibility(
        IntPtr instance, bool visibility);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetScrollbarsVisibility(
        IntPtr instance, bool visibility);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetAlertDialogEnabled(
        IntPtr instance, bool enabled);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetScrollBounceEnabled(
        IntPtr instance, bool enabled);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetInteractionEnabled(
        IntPtr instance, bool enabled);
    [DllImport("__Internal")]
    private static extern bool _CWebViewPlugin_SetURLPattern(
        IntPtr instance, string allowPattern, string denyPattern, string hookPattern);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_LoadURL(
        IntPtr instance, string url);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_LoadHTML(
        IntPtr instance, string html, string baseUrl);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_EvaluateJS(
        IntPtr instance, string url);
    [DllImport("__Internal")]
    private static extern int _CWebViewPlugin_Progress(
        IntPtr instance);
    [DllImport("__Internal")]
    private static extern bool _CWebViewPlugin_CanGoBack(
        IntPtr instance);
    [DllImport("__Internal")]
    private static extern bool _CWebViewPlugin_CanGoForward(
        IntPtr instance);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_GoBack(
        IntPtr instance);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_GoForward(
        IntPtr instance);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_Reload(
        IntPtr instance);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_AddCustomHeader(IntPtr instance, string headerKey, string headerValue);
    [DllImport("__Internal")]
    private static extern string _CWebViewPlugin_GetCustomHeaderValue(IntPtr instance, string headerKey);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_RemoveCustomHeader(IntPtr instance, string headerKey);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_ClearCustomHeader(IntPtr instance);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_ClearCookies();
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SaveCookies();
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_GetCookies(IntPtr instance, string url);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetBasicAuthInfo(IntPtr instance, string userName, string password);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_ClearCache(IntPtr instance, bool includeDiskFiles);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetSuspended(IntPtr instance, bool suspended);
#elif UNITY_WEBGL
    [DllImport("__Internal")]
    private static extern void _gree_unity_webview_init(string name);
    [DllImport("__Internal")]
    private static extern void _gree_unity_webview_setMargins(string name, int left, int top, int right, int bottom);
    [DllImport("__Internal")]
    private static extern void _gree_unity_webview_setVisibility(string name, bool visible);
    [DllImport("__Internal")]
    private static extern void _gree_unity_webview_loadURL(string name, string url);
    [DllImport("__Internal")]
    private static extern void _gree_unity_webview_evaluateJS(string name, string js);
    [DllImport("__Internal")]
    private static extern void _gree_unity_webview_destroy(string name);
#endif

    public static bool IsWebViewAvailable()
    {
#if !UNITY_EDITOR && UNITY_ANDROID
        using (var plugin = new AndroidJavaObject("net.gree.unitywebview.CWebViewPlugin"))
        {
            return plugin.CallStatic<bool>("IsWebViewAvailable");
        }
#else
        return true;
#endif
    }

    public void Init(
        Callback cb = null,
        Callback err = null,
        Callback httpErr = null,
        Callback ld = null,
        Callback started = null,
        Callback hooked = null,
        Callback cookies = null,
        bool transparent = false,
        bool zoom = true,
        string ua = "",
        int radius = 0,
        // android
        int androidForceDarkMode = 0,  // 0: follow system setting, 1: force dark off, 2: force dark on
        // ios
        bool enableWKWebView = true,
        int  wkContentMode = 0,  // 0: recommended, 1: mobile, 2: desktop
        bool wkAllowsLinkPreview = true,
        bool wkAllowsBackForwardNavigationGestures = true,
        // editor
        bool separated = false)
    {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        _CWebViewPlugin_InitStatic(
            Application.platform == RuntimePlatform.OSXEditor,
            SystemInfo.graphicsDeviceType == GraphicsDeviceType.Metal);
#endif
        onJS = cb;
        onError = err;
        onHttpError = httpErr;
        onStarted = started;
        onLoaded = ld;
        onHooked = hooked;
        onCookies = cookies;
#if UNITY_WEBGL
#if !UNITY_EDITOR
        _gree_unity_webview_init(name);
#endif
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.init", name);
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
        Debug.LogError("Webview is not supported on this platform.");
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        {
            var uri = new Uri(_CWebViewPlugin_GetAppPath());
            var info = File.ReadAllText(uri.LocalPath + "Contents/Info.plist");
            if (Regex.IsMatch(info, @"<key>CFBundleGetInfoString</key>\s*<string>Unity version [5-9]\.[3-9]")
                && !Regex.IsMatch(info, @"<key>NSAppTransportSecurity</key>\s*<dict>\s*<key>NSAllowsArbitraryLoads</key>\s*<true/>\s*</dict>")) {
                Debug.LogWarning("<color=yellow>WebViewObject: NSAppTransportSecurity isn't configured to allow HTTP. If you need to allow any HTTP access, please shutdown Unity and invoke:</color>\n/usr/libexec/PlistBuddy -c \"Add NSAppTransportSecurity:NSAllowsArbitraryLoads bool true\" /Applications/Unity/Unity.app/Contents/Info.plist");
            }
        }
#if UNITY_EDITOR_OSX
        // if (string.IsNullOrEmpty(ua)) {
        //     ua = @"Mozilla/5.0 (iPhone; CPU iPhone OS 7_1_2 like Mac OS X) AppleWebKit/537.51.2 (KHTML, like Gecko) Version/7.0 Mobile/11D257 Safari/9537.53";
        // }
#endif
        webView = _CWebViewPlugin_Init(
            name,
            transparent,
            zoom,
            Screen.width,
            Screen.height,
            ua
#if UNITY_EDITOR
            , separated
#else
            , false
#endif
            );
        rect = new Rect(0, 0, Screen.width, Screen.height);
#elif UNITY_IPHONE
        webView = _CWebViewPlugin_Init(name, transparent, zoom, ua, enableWKWebView, wkContentMode, wkAllowsLinkPreview, wkAllowsBackForwardNavigationGestures, radius);
#elif UNITY_ANDROID
        webView = new AndroidJavaObject("net.gree.unitywebview.CWebViewPlugin");
#if UNITY_2021_1_OR_NEWER
        webView.SetStatic<bool>("forceBringToFront", true);
#endif
        webView.Call("Init", name, transparent, zoom, androidForceDarkMode, ua, radius);
#else
        Debug.LogError("Webview is not supported on this platform.");
#endif
    }

    protected virtual void OnDestroy()
    {
#if UNITY_WEBGL
#if !UNITY_EDITOR
        _gree_unity_webview_destroy(name);
#endif
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.destroy", name);
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        if (bg != null) {
            Destroy(bg.gameObject);
        }
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_Destroy(webView);
        webView = IntPtr.Zero;
        Destroy(texture);
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_Destroy(webView);
        webView = IntPtr.Zero;
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("Destroy");
        webView.Dispose();
        webView = null;
#endif
    }

    public void Pause()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        //TODO: UNSUPPORTED
#elif UNITY_IPHONE
        // NOTE: this suspends media playback only.
        if (webView == null)
            return;
        _CWebViewPlugin_SetSuspended(webView, true);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("Pause");
#endif
    }

    public void Resume()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        //TODO: UNSUPPORTED
#elif UNITY_IPHONE
        // NOTE: this resumes media playback only.
        _CWebViewPlugin_SetSuspended(webView, false);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("Resume");
#endif
    }

    // Use this function instead of SetMargins to easily set up a centered window
    // NOTE: for historical reasons, `center` means the lower left corner and positive y values extend up.
    public void SetCenterPositionWithScale(Vector2 center, Vector2 scale)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#else
        float left = (Screen.width - scale.x) / 2.0f + center.x;
        float right = Screen.width - (left + scale.x);
        float bottom = (Screen.height - scale.y) / 2.0f + center.y;
        float top = Screen.height - (bottom + scale.y);
        SetMargins((int)left, (int)top, (int)right, (int)bottom);
#endif
    }

    public void SetMargins(int left, int top, int right, int bottom, bool relative = false)
    {
#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
        return;
#elif UNITY_WEBPLAYER || UNITY_WEBGL
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        if (webView == IntPtr.Zero)
            return;
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
#elif UNITY_ANDROID
        if (webView == null)
            return;
#endif

        mMarginLeft = left;
        mMarginTop = top;
        mMarginRight = right;
        mMarginBottom = bottom;
        mMarginRelative = relative;
        float ml, mt, mr, mb;
#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_WEBPLAYER || UNITY_WEBGL
        ml = left;
        mt = top;
        mr = right;
        mb = bottom;
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        ml = left;
        mt = top;
        mr = right;
        mb = bottom;
#elif UNITY_IPHONE
        if (relative)
        {
            float w = (float)Screen.width;
            float h = (float)Screen.height;
            ml = left / w;
            mt = top / h;
            mr = right / w;
            mb = bottom / h;
        }
        else
        {
            ml = left;
            mt = top;
            mr = right;
            mb = bottom;
        }
#elif UNITY_ANDROID
        if (relative)
        {
            float w = (float)Screen.width;
            float h = (float)Screen.height;
            int iw = Display.main.systemWidth;
            int ih = Display.main.systemHeight;
            if (!Screen.fullScreen)
            {
                using (var unityClass = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
                using (var activity = unityClass.GetStatic<AndroidJavaObject>("currentActivity"))
                using (var player = activity.Get<AndroidJavaObject>("mUnityPlayer"))
                using (var view = player.Call<AndroidJavaObject>("getView"))
                using (var rect = new AndroidJavaObject("android.graphics.Rect"))
                {
                    view.Call("getDrawingRect", rect);
                    iw = rect.Call<int>("width");
                    ih = rect.Call<int>("height");
                }
            }
            ml = left / w * iw;
            mt = top / h * ih;
            mr = right / w * iw;
            mb = AdjustBottomMargin((int)(bottom / h * ih));
        }
        else
        {
            ml = left;
            mt = top;
            mr = right;
            mb = AdjustBottomMargin(bottom);
        }
#endif
        bool r = relative;

        if (ml == mMarginLeftComputed
            && mt == mMarginTopComputed
            && mr == mMarginRightComputed
            && mb == mMarginBottomComputed
            && r == mMarginRelativeComputed)
        {
            return;
        }
        mMarginLeftComputed = ml;
        mMarginTopComputed = mt;
        mMarginRightComputed = mr;
        mMarginBottomComputed = mb;
        mMarginRelativeComputed = r;

#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.setMargins", name, (int)ml, (int)mt, (int)mr, (int)mb);
#elif UNITY_WEBGL && !UNITY_EDITOR
        _gree_unity_webview_setMargins(name, (int)ml, (int)mt, (int)mr, (int)mb);
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        int width = (int)(Screen.width - (ml + mr));
        int height = (int)(Screen.height - (mb + mt));
        _CWebViewPlugin_SetRect(webView, width, height);
        rect = new Rect(left, bottom, width, height);
        UpdateBGTransform();
#elif UNITY_IPHONE
        _CWebViewPlugin_SetMargins(webView, ml, mt, mr, mb, r);
#elif UNITY_ANDROID
        webView.Call("SetMargins", (int)ml, (int)mt, (int)mr, (int)mb);
#endif
    }

    public void SetVisibility(bool v)
    {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        if (bg != null)
        {
            bg.gameObject.active = v;
        }
#endif
        if (GetVisibility() && !v)
        {
            EvaluateJS("if (document && document.activeElement) document.activeElement.blur();");
        }
#if UNITY_WEBGL
#if !UNITY_EDITOR
        _gree_unity_webview_setVisibility(name, v);
#endif
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.setVisibility", name, v);
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SetVisibility(webView, v);
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SetVisibility(webView, v);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        mVisibility = v;
        webView.Call("SetVisibility", v);
#endif
        visibility = v;
    }

    public bool GetVisibility()
    {
        return visibility;
    }

    public void SetScrollbarsVisibility(bool v)
    {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        // TODO: UNSUPPORTED
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SetScrollbarsVisibility(webView, v);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("SetScrollbarsVisibility", v);
#else
        // TODO: UNSUPPORTED
#endif
    }

    public void SetInteractionEnabled(bool enabled)
    {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        // TODO: UNSUPPORTED
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SetInteractionEnabled(webView, enabled);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("SetInteractionEnabled", enabled);
#else
        // TODO: UNSUPPORTED
#endif
    }

    public void SetAlertDialogEnabled(bool e)
    {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        // TODO: UNSUPPORTED
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SetAlertDialogEnabled(webView, e);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("SetAlertDialogEnabled", e);
#else
        // TODO: UNSUPPORTED
#endif
        alertDialogEnabled = e;
    }

    public bool GetAlertDialogEnabled()
    {
        return alertDialogEnabled;
    }

    public void SetScrollBounceEnabled(bool e)
    {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        // TODO: UNSUPPORTED
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SetScrollBounceEnabled(webView, e);
#elif UNITY_ANDROID
        // TODO: UNSUPPORTED
#else
        // TODO: UNSUPPORTED
#endif
        scrollBounceEnabled = e;
    }

    public bool GetScrollBounceEnabled()
    {
        return scrollBounceEnabled;
    }

    public void SetCameraAccess(bool allowed)
    {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        // TODO: UNSUPPORTED
#elif UNITY_IPHONE
        // TODO: UNSUPPORTED
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("SetCameraAccess", allowed);
#else
        // TODO: UNSUPPORTED
#endif
    }

    public void SetMicrophoneAccess(bool allowed)
    {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        // TODO: UNSUPPORTED
#elif UNITY_IPHONE
        // TODO: UNSUPPORTED
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("SetMicrophoneAccess", allowed);
#else
        // TODO: UNSUPPORTED
#endif
    }

    public bool SetURLPattern(string allowPattern, string denyPattern, string hookPattern)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
        return false;
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
        return false;
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return false;
        return _CWebViewPlugin_SetURLPattern(webView, allowPattern, denyPattern, hookPattern);
#elif UNITY_ANDROID
        if (webView == null)
            return false;
        return webView.Call<bool>("SetURLPattern", allowPattern, denyPattern, hookPattern);
#endif
    }

    public void LoadURL(string url)
    {
        if (string.IsNullOrEmpty(url))
            return;
#if UNITY_WEBGL
#if !UNITY_EDITOR
        _gree_unity_webview_loadURL(name, url);
#endif
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.loadURL", name, url);
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_LoadURL(webView, url);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("LoadURL", url);
#endif
    }

    public void LoadHTML(string html, string baseUrl)
    {
        if (string.IsNullOrEmpty(html))
            return;
        if (string.IsNullOrEmpty(baseUrl))
            baseUrl = "";
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_LoadHTML(webView, html, baseUrl);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("LoadHTML", html, baseUrl);
#endif
    }

    public void EvaluateJS(string js)
    {
#if UNITY_WEBGL
#if !UNITY_EDITOR
        _gree_unity_webview_evaluateJS(name, js);
#endif
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.evaluateJS", name, js);
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_EvaluateJS(webView, js);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("EvaluateJS", js);
#endif
    }

    public int Progress()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
        return 0;
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
        return 0;
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return 0;
        return _CWebViewPlugin_Progress(webView);
#elif UNITY_ANDROID
        if (webView == null)
            return 0;
        return webView.Get<int>("progress");
#endif
    }

    public bool CanGoBack()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
        return false;
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
        return false;
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return false;
        return _CWebViewPlugin_CanGoBack(webView);
#elif UNITY_ANDROID
        if (webView == null)
            return false;
        return webView.Get<bool>("canGoBack");
#endif
    }

    public bool CanGoForward()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
        return false;
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
        return false;
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return false;
        return _CWebViewPlugin_CanGoForward(webView);
#elif UNITY_ANDROID
        if (webView == null)
            return false;
        return webView.Get<bool>("canGoForward");
#endif
    }

    public void GoBack()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_GoBack(webView);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("GoBack");
#endif
    }

    public void GoForward()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_GoForward(webView);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("GoForward");
#endif
    }

    public void Reload()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_Reload(webView);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("Reload");
#endif
    }

    public void CallOnError(string error)
    {
        if (onError != null)
        {
            onError(error);
        }
    }

    public void CallOnHttpError(string error)
    {
        if (onHttpError != null)
        {
            onHttpError(error);
        }
    }

    public void CallOnStarted(string url)
    {
        if (onStarted != null)
        {
            onStarted(url);
        }
    }

    public void CallOnLoaded(string url)
    {
        if (onLoaded != null)
        {
            onLoaded(url);
        }
    }

    public void CallFromJS(string message)
    {
        if (onJS != null)
        {
#if !UNITY_ANDROID
#if UNITY_2018_4_OR_NEWER
            message = UnityWebRequest.UnEscapeURL(message);
#else // UNITY_2018_4_OR_NEWER
            message = WWW.UnEscapeURL(message);
#endif // UNITY_2018_4_OR_NEWER
#endif // !UNITY_ANDROID
            onJS(message);
        }
    }

    public void CallOnHooked(string message)
    {
        if (onHooked != null)
        {
#if !UNITY_ANDROID
#if UNITY_2018_4_OR_NEWER
            message = UnityWebRequest.UnEscapeURL(message);
#else // UNITY_2018_4_OR_NEWER
            message = WWW.UnEscapeURL(message);
#endif // UNITY_2018_4_OR_NEWER
#endif // !UNITY_ANDROID
            onHooked(message);
        }
    }

    public void CallOnCookies(string cookies)
    {
        if (onCookies != null)
        {
            onCookies(cookies);
        }
    }

    public void AddCustomHeader(string headerKey, string headerValue)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_AddCustomHeader(webView, headerKey, headerValue);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("AddCustomHeader", headerKey, headerValue);
#endif
    }

    public string GetCustomHeaderValue(string headerKey)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
        return null;
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
        return null;
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return null;
        return _CWebViewPlugin_GetCustomHeaderValue(webView, headerKey);  
#elif UNITY_ANDROID
        if (webView == null)
            return null;
        return webView.Call<string>("GetCustomHeaderValue", headerKey);
#endif
    }

    public void RemoveCustomHeader(string headerKey)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_RemoveCustomHeader(webView, headerKey);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("RemoveCustomHeader", headerKey);
#endif
    }

    public void ClearCustomHeader()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_ClearCustomHeader(webView);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("ClearCustomHeader");
#endif
    }

    public void ClearCookies()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_ClearCookies();
#elif UNITY_ANDROID && !UNITY_EDITOR
        if (webView == null)
            return;
        webView.Call("ClearCookies");
#endif
    }


    public void SaveCookies()
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SaveCookies();
#elif UNITY_ANDROID && !UNITY_EDITOR
        if (webView == null)
            return;
        webView.Call("SaveCookies");
#endif
    }


    public void GetCookies(string url)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_GetCookies(webView, url);
#elif UNITY_ANDROID && !UNITY_EDITOR
        if (webView == null)
            return;
        webView.Call("GetCookies", url);
#else
        //TODO: UNSUPPORTED
#endif
    }

    public void SetBasicAuthInfo(string userName, string password)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        //TODO: UNSUPPORTED
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SetBasicAuthInfo(webView, userName, password);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("SetBasicAuthInfo", userName, password);
#endif
    }

    public void ClearCache(bool includeDiskFiles)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_IPHONE && !UNITY_EDITOR
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_ClearCache(webView, includeDiskFiles);
#elif UNITY_ANDROID && !UNITY_EDITOR
        if (webView == null)
            return;
        webView.Call("ClearCache", includeDiskFiles);
#endif
    }


    public void SetTextZoom(int textZoom)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_IPHONE && !UNITY_EDITOR
        //TODO: UNSUPPORTED
#elif UNITY_ANDROID && !UNITY_EDITOR
        if (webView == null)
            return;
        webView.Call("SetTextZoom", textZoom);
#endif
    }

#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
    void OnApplicationFocus(bool focus)
    {
        if (!focus)
        {
            hasFocus = false;
        }
    }

    void Start()
    {
        if (canvas != null)
        {
            var g = new GameObject(gameObject.name + "BG");
            g.transform.parent = canvas.transform;
            bg = g.AddComponent<Image>();
            UpdateBGTransform();
        }
    }

    void Update()
    {
        if (bg != null) {
            bg.transform.SetAsLastSibling();
        }
        if (hasFocus) {
            inputString += Input.inputString;
        }
        for (;;) {
            if (webView == IntPtr.Zero)
                break;
            string s = _CWebViewPlugin_GetMessage(webView);
            if (s == null)
                break;
            var i = s.IndexOf(':', 0);
            if (i == -1)
                continue;
            switch (s.Substring(0, i)) {
            case "CallFromJS":
                CallFromJS(s.Substring(i + 1));
                break;
            case "CallOnError":
                CallOnError(s.Substring(i + 1));
                break;
            case "CallOnHttpError":
                CallOnHttpError(s.Substring(i + 1));
                break;
            case "CallOnLoaded":
                CallOnLoaded(s.Substring(i + 1));
                break;
            case "CallOnStarted":
                CallOnStarted(s.Substring(i + 1));
                break;
            case "CallOnHooked":
                CallOnHooked(s.Substring(i + 1));
                break;
            case "CallOnCookies":
                CallOnCookies(s.Substring(i + 1));
                break;
            }
        }
        if (webView == IntPtr.Zero || !visibility)
            return;
        bool refreshBitmap = (Time.frameCount % bitmapRefreshCycle == 0);
        _CWebViewPlugin_Update(webView, refreshBitmap, devicePixelRatio);
        if (refreshBitmap) {
            {
                var w = _CWebViewPlugin_BitmapWidth(webView);
                var h = _CWebViewPlugin_BitmapHeight(webView);
                if (texture == null || texture.width != w || texture.height != h) {
                    bool isLinearSpace = QualitySettings.activeColorSpace == ColorSpace.Linear;
                    texture = new Texture2D(w, h, TextureFormat.RGBA32, false, !isLinearSpace);
                    texture.filterMode = FilterMode.Bilinear;
                    texture.wrapMode = TextureWrapMode.Clamp;
                    textureDataBuffer = new byte[w * h * 4];
                }
            }
            if (textureDataBuffer.Length > 0) {
                var gch = GCHandle.Alloc(textureDataBuffer, GCHandleType.Pinned);
                _CWebViewPlugin_Render(webView, gch.AddrOfPinnedObject());
                gch.Free();
                texture.LoadRawTextureData(textureDataBuffer);
                texture.Apply();
            }
        }
    }

    void UpdateBGTransform()
    {
        if (bg != null) {
            bg.rectTransform.anchorMin = Vector2.zero;
            bg.rectTransform.anchorMax = Vector2.zero;
            bg.rectTransform.pivot = Vector2.zero;
            bg.rectTransform.position = rect.min;
            bg.rectTransform.SetSizeWithCurrentAnchors(RectTransform.Axis.Horizontal, rect.size.x);
            bg.rectTransform.SetSizeWithCurrentAnchors(RectTransform.Axis.Vertical, rect.size.y);
        }
    }

    public int bitmapRefreshCycle = 1;
    public int devicePixelRatio = 1;

    void OnGUI()
    {
        if (webView == IntPtr.Zero || !visibility)
            return;
        switch (Event.current.type) {
        case EventType.MouseDown:
        case EventType.MouseUp:
            hasFocus = rect.Contains(Input.mousePosition);
            break;
        }
        switch (Event.current.type) {
        case EventType.MouseMove:
        case EventType.MouseDown:
        case EventType.MouseDrag:
        case EventType.MouseUp:
        case EventType.ScrollWheel:
            if (hasFocus) {
                Vector3 p;
                p.x = Input.mousePosition.x - rect.x;
                p.y = Input.mousePosition.y - rect.y;
                {
                    int mouseState = 0;
                    if (Input.GetButtonDown("Fire1")) {
                        mouseState = 1;
                    } else if (Input.GetButton("Fire1")) {
                        mouseState = 2;
                    } else if (Input.GetButtonUp("Fire1")) {
                        mouseState = 3;
                    }
                    //_CWebViewPlugin_SendMouseEvent(webView, (int)p.x, (int)p.y, Input.GetAxis("Mouse ScrollWheel"), mouseState);
                    _CWebViewPlugin_SendMouseEvent(webView, (int)p.x, (int)p.y, Input.mouseScrollDelta.y, mouseState);
                }
            }
            break;
        case EventType.Repaint:
            while (!string.IsNullOrEmpty(inputString)) {
                var keyChars = inputString.Substring(0, 1);
                var keyCode = (ushort)inputString[0];
                inputString = inputString.Substring(1);
                if (!string.IsNullOrEmpty(keyChars) || keyCode != 0) {
                    Vector3 p;
                    p.x = Input.mousePosition.x - rect.x;
                    p.y = Input.mousePosition.y - rect.y;
                    _CWebViewPlugin_SendKeyEvent(webView, (int)p.x, (int)p.y, keyChars, keyCode, 1);
                }
            }
            if (texture != null) {
                Matrix4x4 m = GUI.matrix;
                GUI.matrix
                    = Matrix4x4.TRS(
                        new Vector3(0, Screen.height, 0),
                        Quaternion.identity,
                        new Vector3(1, -1, 1));
                Graphics.DrawTexture(rect, texture);
                GUI.matrix = m;
            }
            break;
        }
    }
#endif
}
