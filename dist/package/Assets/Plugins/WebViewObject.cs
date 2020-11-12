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
using UnityEngine.Rendering;
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
    bool visibility;
    bool alertDialogEnabled;
    bool scrollBounceEnabled;
    int mMarginLeft;
    int mMarginTop;
    int mMarginRight;
    int mMarginBottom;
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
    IntPtr webView;
    Rect rect;
    Texture2D texture;
    byte[] textureDataBuffer;
    string inputString = "";
    // string keyChars0 = "";
    // ushort keyCode0 = 0;
    bool hasFocus;
#elif UNITY_IPHONE
    IntPtr webView;
#elif UNITY_ANDROID
    AndroidJavaObject webView;
    
    bool mVisibility;
    bool mIsKeyboardVisible0;
    bool mIsKeyboardVisible;
    float mResumedTimestamp;
    
    void OnApplicationPause(bool paused)
    {
        if (webView == null)
            return;
        if (!paused)
        {
            webView.Call("SetVisibility", false);
            mResumedTimestamp = Time.realtimeSinceStartup;
        }
        webView.Call("OnApplicationPause", paused);
    }

    void Awake()
    {
        alertDialogEnabled = true;
        scrollBounceEnabled = true;
    }

    void Update()
    {
        if (webView == null)
            return;
        if (mResumedTimestamp != 0.0f && Time.realtimeSinceStartup - mResumedTimestamp > 0.5f)
        {
            mResumedTimestamp = 0.0f;
            webView.Call("SetVisibility", mVisibility);
        }
    }

    /// Called from Java native plugin to set when the keyboard is opened
    public void SetKeyboardVisible(string pIsVisible)
    {
        mIsKeyboardVisible = (pIsVisible == "true");
        if (mIsKeyboardVisible != mIsKeyboardVisible0)
        {
            mIsKeyboardVisible0 = mIsKeyboardVisible;
            SetMargins(mMarginLeft, mMarginTop, mMarginRight, mMarginBottom);
        } else if (mIsKeyboardVisible) {
            SetMargins(mMarginLeft, mMarginTop, mMarginRight, mMarginBottom);
        }
    }
    
    public int AdjustBottomMargin(int bottom)
    {
        if (!mIsKeyboardVisible)
        {
            return bottom;
        }
        else
        {
            int keyboardHeight = 0;
            using(AndroidJavaClass UnityClass = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
            {
                AndroidJavaObject View = UnityClass.GetStatic<AndroidJavaObject>("currentActivity").Get<AndroidJavaObject>("mUnityPlayer").Call<AndroidJavaObject>("getView");
                using(AndroidJavaObject Rct = new AndroidJavaObject("android.graphics.Rect"))
                {
                    View.Call("getWindowVisibleDisplayFrame", Rct);
                    keyboardHeight = View.Call<int>("getHeight") - Rct.Call<int>("height");
                }
            }
            return (bottom > keyboardHeight) ? bottom : keyboardHeight;
        }
    }
#else
    IntPtr webView;
#endif

    public bool IsKeyboardVisible
    {
        get
        {
#if !UNITY_EDITOR && UNITY_ANDROID
            return mIsKeyboardVisible;
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
        string gameObject, bool transparent, int width, int height, string ua, bool separated);
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
    private static extern void _CWebViewPlugin_Update(IntPtr instance, bool refreshBitmap);
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
    private static extern string _CWebViewPlugin_GetMessage(IntPtr instance);
#elif UNITY_IPHONE
    [DllImport("__Internal")]
    private static extern IntPtr _CWebViewPlugin_Init(string gameObject, bool transparent, string ua, bool enableWKWebView, int wkContentMode);
    [DllImport("__Internal")]
    private static extern int _CWebViewPlugin_Destroy(IntPtr instance);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetMargins(
        IntPtr instance, float left, float top, float right, float bottom, bool relative);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetVisibility(
        IntPtr instance, bool visibility);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetAlertDialogEnabled(
        IntPtr instance, bool enabled);
    [DllImport("__Internal")]
    private static extern void _CWebViewPlugin_SetScrollBounceEnabled(
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
    private static extern void   _CWebViewPlugin_AddCustomHeader(IntPtr instance, string headerKey, string headerValue);
    [DllImport("__Internal")]
    private static extern string _CWebViewPlugin_GetCustomHeaderValue(IntPtr instance, string headerKey);
    [DllImport("__Internal")]
    private static extern void   _CWebViewPlugin_RemoveCustomHeader(IntPtr instance, string headerKey);
    [DllImport("__Internal")]
    private static extern void   _CWebViewPlugin_ClearCustomHeader(IntPtr instance);
    [DllImport("__Internal")]
    private static extern void   _CWebViewPlugin_ClearCookies();
    [DllImport("__Internal")]
    private static extern void   _CWebViewPlugin_SaveCookies();
    [DllImport("__Internal")]
    private static extern string _CWebViewPlugin_GetCookies(string url);
    [DllImport("__Internal")]
    private static extern void   _CWebViewPlugin_SetBasicAuthInfo(IntPtr instance, string userName, string password);
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
        return (new AndroidJavaObject("net.gree.unitywebview.CWebViewPlugin")).CallStatic<bool>("IsWebViewAvailable");
#else
        return true;
#endif
    }

    public void Init(
        Callback cb = null,
        bool transparent = false,
        string ua = "",
        Callback err = null,
        Callback httpErr = null,
        Callback ld = null,
        bool enableWKWebView = false,
        int  wkContentMode = 0,  // 0: recommended, 1: mobile, 2: desktop
        Callback started = null,
        Callback hooked = null
#if UNITY_EDITOR
        , bool separated = false
#endif
        )
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
            Screen.width,
            Screen.height,
            ua
#if UNITY_EDITOR
            , separated
#else
            , false
#endif
            );
        // define pseudo requestAnimationFrame.
        EvaluateJS(@"(function() {
            var vsync = 1000 / 60;
            var t0 = window.performance.now();
            window.requestAnimationFrame = function(callback, element) {
                var t1 = window.performance.now();
                var duration = t1 - t0;
                var d = vsync - ((duration > vsync) ? duration % vsync : duration);
                var id = window.setTimeout(function() {t0 = window.performance.now(); callback(t1 + d);}, d);
                return id;
            };
        })()");
        rect = new Rect(0, 0, Screen.width, Screen.height);
        OnApplicationFocus(true);
#elif UNITY_IPHONE
        webView = _CWebViewPlugin_Init(name, transparent, ua, enableWKWebView, wkContentMode);
#elif UNITY_ANDROID
        webView = new AndroidJavaObject("net.gree.unitywebview.CWebViewPlugin");
        webView.Call("Init", name, transparent, ua);
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
        webView = null;
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
#if UNITY_WEBPLAYER || UNITY_WEBGL
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
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
        if (mMarginLeft == left
            && mMarginTop == top
            && mMarginRight == right
            && mMarginBottom == bottom)
        {
            return;
        }
        mMarginLeft = left;
        mMarginTop = top;
        mMarginRight = right;
        mMarginBottom = bottom;
#if UNITY_WEBGL
#if !UNITY_EDITOR
        _gree_unity_webview_setMargins(name, left, top, right, bottom);
#endif
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.setMargins", name, left, top, right, bottom);
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
#elif UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
        int width = Screen.width - (left + right);
        int height = Screen.height - (bottom + top);
        _CWebViewPlugin_SetRect(webView, width, height);
        rect = new Rect(left, bottom, width, height);
#elif UNITY_IPHONE
        if (relative) {
            float w = (float)Screen.width;
            float h = (float)Screen.height;
            _CWebViewPlugin_SetMargins(webView, left / w, top / h, right / w, bottom / h, true);
        } else {
            _CWebViewPlugin_SetMargins(webView, (float)left, (float)top, (float)right, (float)bottom, false);
        }
#elif UNITY_ANDROID
        if (relative) {
            float w = (float)Screen.width;
            float h = (float)Screen.height;
            int iw = Screen.currentResolution.width;
            int ih = Screen.currentResolution.height;
            webView.Call("SetMargins", (int)(left / w * iw), (int)(top / h * ih), (int)(right / w * iw), AdjustBottomMargin((int)(bottom / h * ih)));
        } else {
            webView.Call("SetMargins", left, top, right, AdjustBottomMargin(bottom));
        }
#endif
    }

    public void SetVisibility(bool v)
    {
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
#elif UNITY_IPHONE && !UNITY_EDITOR
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
#elif UNITY_IPHONE && !UNITY_EDITOR
        if (webView == IntPtr.Zero)
            return;
        _CWebViewPlugin_SaveCookies();
#elif UNITY_ANDROID && !UNITY_EDITOR
        if (webView == null)
            return;
        webView.Call("SaveCookies");
#endif
    }


    public string GetCookies(string url)
    {
#if UNITY_WEBPLAYER || UNITY_WEBGL
        //TODO: UNSUPPORTED
        return "";
#elif UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN || UNITY_EDITOR_LINUX
        //TODO: UNSUPPORTED
        return "";
#elif UNITY_IPHONE && !UNITY_EDITOR
        if (webView == IntPtr.Zero)
            return "";
        return _CWebViewPlugin_GetCookies(url);
#elif UNITY_ANDROID && !UNITY_EDITOR
        if (webView == null)
            return "";
        return webView.Call<string>("GetCookies", url);
#else
        //TODO: UNSUPPORTED
        return "";
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


#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
    void OnApplicationFocus(bool focus)
    {
        hasFocus = focus;
    }

    void Update()
    {
        if (hasFocus) {
            inputString += Input.inputString;
        }
        for (;;) {
            if (webView == IntPtr.Zero)
                break;
            string s = _CWebViewPlugin_GetMessage(webView);
            if (s == null)
                break;
            switch (s[0]) {
            case 'E':
                CallOnError(s.Substring(1));
                break;
            case 'S':
                CallOnStarted(s.Substring(1));
                break;
            case 'L':
                CallOnLoaded(s.Substring(1));
                break;
            case 'J':
                CallFromJS(s.Substring(1));
                break;
            case 'H':
                CallOnHooked(s.Substring(1));
                break;
            }
        }
        if (webView == IntPtr.Zero || !visibility)
            return;
        bool refreshBitmap = (Time.frameCount % bitmapRefreshCycle == 0);
        _CWebViewPlugin_Update(webView, refreshBitmap);
        if (refreshBitmap) {
            {
                var w = _CWebViewPlugin_BitmapWidth(webView);
                var h = _CWebViewPlugin_BitmapHeight(webView);
                if (texture == null || texture.width != w || texture.height != h) {
                    texture = new Texture2D(w, h, TextureFormat.RGBA32, false, true);
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

    public int bitmapRefreshCycle = 1;

    void OnGUI()
    {
        if (webView == IntPtr.Zero || !visibility)
            return;

        switch (Event.current.type) {
        case EventType.MouseDown:
        case EventType.MouseUp:
        case EventType.MouseMove:
        case EventType.MouseDrag:
        case EventType.ScrollWheel:
            {
                Vector3 p;
                p.x = Input.mousePosition.x - rect.x;
                p.y = Input.mousePosition.y - rect.y;
                {
                    int mouseState = 0;
                    if (Input.GetButtonDown("Fire1")) {
                        mouseState = 1;
                    } else if (Input.GetButtonUp("Fire1")) {
                        mouseState = 3;
                    } else if (Input.GetButton("Fire1")) {
                        mouseState = 2;
                    }
                    _CWebViewPlugin_SendMouseEvent(webView, (int)p.x, (int)p.y, Input.GetAxis("Mouse ScrollWheel"), mouseState);
                }
            }
            break;
        case EventType.KeyDown:
        case EventType.KeyUp:
            {
                string keyChars = "";
                ushort keyCode = 0;
                if (!string.IsNullOrEmpty(inputString)) {
                    keyChars = inputString.Substring(0, 1);
                    keyCode = (ushort)inputString[0];
                        inputString = inputString.Substring(1);
                }
                if (!string.IsNullOrEmpty(keyChars) || keyCode != 0) {
                    Vector3 p;
                    p.x = Input.mousePosition.x - rect.x;
                    p.y = Input.mousePosition.y - rect.y;
                    _CWebViewPlugin_SendKeyEvent(webView, (int)p.x, (int)p.y, keyChars, keyCode, 1);
                }
                // if (keyChars != keyChars0) {
                //     if (!string.IsNullOrEmpty(keyChars0)) {
                //         Debug.Log("XX1 " + (short)keyChars0[0]);
                //         _CWebViewPlugin_SendKeyEvent(webView, (int)p.x, (int)p.y, keyChars0, keyCode0, 3);
                //     }
                //     if (!string.IsNullOrEmpty(keyChars)) {
                //         Debug.Log("XX2 " + (short)keyChars[0]);
                //         _CWebViewPlugin_SendKeyEvent(webView, (int)p.x, (int)p.y, keyChars, keyCode, 1);
                //     }
                // } else {
                //     if (!string.IsNullOrEmpty(keyChars)) {
                //         Debug.Log("XX3");
                //         _CWebViewPlugin_SendKeyEvent(webView, (int)p.x, (int)p.y, keyChars, keyCode, 2);
                //     }
                // }
                // keyChars0 = keyChars;
                // keyCode0 = keyCode;
            }
            break;
        case EventType.Repaint:
            if (texture != null) {
                Matrix4x4 m = GUI.matrix;
                GUI.matrix
                    = Matrix4x4.TRS(
                        new Vector3(0, Screen.height, 0),
                        Quaternion.identity,
                        new Vector3(1, -1, 1));
                GUI.DrawTexture(rect, texture);
                GUI.matrix = m;
            }
            break;
        }
    }
#endif
}
