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

using Callback = System.Action<string>;

#if UNITY_EDITOR || UNITY_STANDALONE_OSX
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
    Callback callback;
#if UNITY_EDITOR || UNITY_STANDALONE_OSX
    IntPtr webView;
    bool visibility;
    Rect rect;
    Texture2D texture;
    string inputString;
#elif UNITY_IPHONE
    IntPtr webView;
#elif UNITY_ANDROID
    AndroidJavaObject webView;
    
    bool mIsKeyboardVisible = false;
    
    /// Called from Java native plugin to set when the keyboard is opened
    public void SetKeyboardVisible(string pIsVisible)
    {
        mIsKeyboardVisible = (pIsVisible == "true");
    }
#elif UNITY_WEBPLAYER
#endif
    
    public bool IsKeyboardVisible {
        get {
#if UNITY_ANDROID && !UNITY_EDITOR
            return mIsKeyboardVisible;
#else
            return TouchScreenKeyboard.visible;
#endif
        }
    }

#if UNITY_EDITOR || UNITY_STANDALONE_OSX
    [DllImport("WebView")]
    private static extern IntPtr _WebViewPlugin_Init(
        string gameObject, int width, int height, bool ineditor);
    [DllImport("WebView")]
    private static extern int _WebViewPlugin_Destroy(IntPtr instance);
    [DllImport("WebView")]
    private static extern void _WebViewPlugin_SetRect(
        IntPtr instance, int width, int height);
    [DllImport("WebView")]
    private static extern void _WebViewPlugin_SetVisibility(
        IntPtr instance, bool visibility);
    [DllImport("WebView")]
    private static extern void _WebViewPlugin_LoadURL(
        IntPtr instance, string url);
    [DllImport("WebView")]
    private static extern void _WebViewPlugin_EvaluateJS(
        IntPtr instance, string url);
    [DllImport("WebView")]
    private static extern void _WebViewPlugin_Update(IntPtr instance,
        int x, int y, float deltaY, bool down, bool press, bool release,
        bool keyPress, short keyCode, string keyChars);
    [DllImport("WebView")]
    private static extern int _WebViewPlugin_BitmapWidth(IntPtr instance);
    [DllImport("WebView")]
    private static extern int _WebViewPlugin_BitmapHeight(IntPtr instance);
    [DllImport("WebView")]
    private static extern void _WebViewPlugin_SetTextureId(IntPtr instance, int textureId);
    [DllImport("WebView")]
    private static extern void _WebViewPlugin_SetCurrentInstance(IntPtr instance);
    [DllImport("WebView")]
    private static extern IntPtr GetRenderEventFunc();
#elif UNITY_IPHONE
    [DllImport("__Internal")]
    private static extern IntPtr _WebViewPlugin_Init(string gameObject);
    [DllImport("__Internal")]
    private static extern int _WebViewPlugin_Destroy(IntPtr instance);
    [DllImport("__Internal")]
    private static extern void _WebViewPlugin_SetMargins(
        IntPtr instance, int left, int top, int right, int bottom);
    [DllImport("__Internal")]
    private static extern void _WebViewPlugin_SetVisibility(
        IntPtr instance, bool visibility);
    [DllImport("__Internal")]
    private static extern void _WebViewPlugin_LoadURL(
        IntPtr instance, string url);
    [DllImport("__Internal")]
    private static extern void _WebViewPlugin_EvaluateJS(
        IntPtr instance, string url);
    [DllImport("__Internal")]
    private static extern void _WebViewPlugin_SetFrame(
        IntPtr instance, int x , int y , int width , int height);
#endif

    public void Init(Callback cb = null)
    {
        callback = cb;
#if UNITY_EDITOR || UNITY_STANDALONE_OSX
        webView = _WebViewPlugin_Init(name, Screen.width, Screen.height,
            Application.platform == RuntimePlatform.OSXEditor);
        rect = new Rect(0, 0, Screen.width, Screen.height);
#elif UNITY_IPHONE
        webView = _WebViewPlugin_Init(name);
#elif UNITY_ANDROID
        webView = new AndroidJavaObject("net.gree.unitywebview.WebViewPlugin");
        webView.Call("Init", name);
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.init", name);
#endif
    }

    void OnDestroy()
    {
#if UNITY_EDITOR || UNITY_STANDALONE_OSX
        if (webView == IntPtr.Zero)
            return;
        _WebViewPlugin_Destroy(webView);
        webView = IntPtr.Zero;
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _WebViewPlugin_Destroy(webView);
        webView = IntPtr.Zero;
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("Destroy");
        webView = null;
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.destroy", name);
        webView = null;
#endif
    }

    /** Use this function instead of SetMargins to easily set up a centered window */
    public void SetCenterPositionWithScale(Vector2 center , Vector2 scale)
    {
#if UNITY_EDITOR || UNITY_STANDALONE_OSX
        rect.x = center.x + (Screen.width - scale.x)/2;
        rect.y = center.y + (Screen.height - scale.y)/2;
        rect.width = scale.x;
        rect.height = scale.y;
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero) return;
        _WebViewPlugin_SetFrame(webView,(int)center.x,(int)center.y,(int)scale.x,(int)scale.y);
#endif
    }

    public void SetMargins(int left, int top, int right, int bottom)
    {
#if UNITY_EDITOR || UNITY_STANDALONE_OSX
        if (webView == IntPtr.Zero)
            return;
        int width = Screen.width - (left + right);
        int height = Screen.height - (bottom + top);
        _WebViewPlugin_SetRect(webView, width, height);
        rect = new Rect(left, bottom, width, height);
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _WebViewPlugin_SetMargins(webView, left, top, right, bottom);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("SetMargins", left, top, right, bottom);
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.setMargins", name, left, top, right, bottom);
#endif
    }

    public void SetVisibility(bool v)
    {
#if UNITY_EDITOR || UNITY_STANDALONE_OSX
        if (webView == IntPtr.Zero)
            return;
        visibility = v;
        _WebViewPlugin_SetVisibility(webView, v);
#elif UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _WebViewPlugin_SetVisibility(webView, v);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("SetVisibility", v);
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.setVisibility", name, v);
#endif
    }

    public void LoadURL(string url)
    {
#if UNITY_EDITOR || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _WebViewPlugin_LoadURL(webView, url);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("LoadURL", url);
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.loadURL", name, url);
#endif
    }

    public void EvaluateJS(string js)
    {
#if UNITY_EDITOR || UNITY_STANDALONE_OSX || UNITY_IPHONE
        if (webView == IntPtr.Zero)
            return;
        _WebViewPlugin_EvaluateJS(webView, js);
#elif UNITY_ANDROID
        if (webView == null)
            return;
        webView.Call("LoadURL", "javascript:" + js);
#elif UNITY_WEBPLAYER
        Application.ExternalCall("unityWebView.evaluateJS", name, js);
#endif
    }

    public void CallFromJS(string message)
    {
        if (callback != null) {
#if !UNITY_ANDROID
            message = WWW.UnEscapeURL(message);
#endif
            callback(message);
        }
    }

#if UNITY_EDITOR || UNITY_STANDALONE_OSX
    void Update()
    {
        inputString += Input.inputString;
    }

    void OnGUI()
    {
        if (webView == IntPtr.Zero || !visibility)
            return;

        Vector3 pos = Input.mousePosition;
        bool down = Input.GetButton("Fire1");
        bool press = Input.GetButtonDown("Fire1");
        bool release = Input.GetButtonUp("Fire1");
        float deltaY = Input.GetAxis("Mouse ScrollWheel");
        bool keyPress = false;
        string keyChars = "";
        short keyCode = 0;
        if (inputString != null && inputString.Length > 0) {
            keyPress = true;
            keyChars = inputString.Substring(0, 1);
            keyCode = (short)inputString[0];
            inputString = inputString.Substring(1);
        }
        _WebViewPlugin_Update(webView,
            (int)(pos.x - rect.x), (int)(pos.y - rect.y), deltaY,
            down, press, release, keyPress, keyCode, keyChars);
        {
            var w = _WebViewPlugin_BitmapWidth(webView);
            var h = _WebViewPlugin_BitmapHeight(webView);
            if (texture == null || texture.width != w || texture.height != h) {
                texture = new Texture2D(w, h, TextureFormat.RGBA32, false, true);
                texture.filterMode = FilterMode.Bilinear;
                texture.wrapMode = TextureWrapMode.Clamp;
            }
        }
        _WebViewPlugin_SetTextureId(webView, (int)texture.GetNativeTexturePtr());
        _WebViewPlugin_SetCurrentInstance(webView);
#if UNITY_4_6 || UNITY_5_0 || UNITY_5_1
        GL.IssuePluginEvent(-1);
#else
        GL.IssuePluginEvent(GetRenderEventFunc(), -1);
#endif
        Matrix4x4 m = GUI.matrix;
        GUI.matrix = Matrix4x4.TRS(new Vector3(0, Screen.height, 0),
            Quaternion.identity, new Vector3(1, -1, 1));
        GUI.DrawTexture(rect, texture);
        GUI.matrix = m;
    }
#endif
}
