/*
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

using System.Collections;
using UnityEngine;
#if UNITY_2018_4_OR_NEWER
using UnityEngine.Networking;
#endif
using UnityEngine.UI;
using UnityEngine.Android;

public class SampleWebView : MonoBehaviour
{
    WebViewObject webView;
    WebViewObject webViewObject;

    void Start()
    {
        Debug.Log(Application.internetReachability);
    }

    public void OpenMicTesting()
    {
        if (webView == null)
        {
            //canvas.SetActive(false);
            webView = (new GameObject("WebViewObject")).AddComponent<WebViewObject>();
            webView.SetCameraAccess(true);
            webView.SetMicrophoneAccess(true);
            webView.SetInteractionEnabled(true);
            webView.Init(transparent: false, enableWKWebView: true, cb: (msg) => Debug.Log("WV MSG: " + msg));
            webView.SetMargins(0, 100, 0, 0);
            webView.SetVisibility(true);
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
        }
        string url = "https://webrtc.github.io/samples/src/content/devices/input-output/";
        webView.LoadURL(url);
        webView.SetVisibility(true);
    }

    public void OpenCameraTesting()
    {
        if (webView == null)
        {
            //canvas.SetActive(false);
            webView = (new GameObject("WebViewObject")).AddComponent<WebViewObject>();
            webView.SetCameraAccess(true);
            webView.SetMicrophoneAccess(true);
            webView.SetInteractionEnabled(true);
            webView.Init(transparent: false, enableWKWebView: true, cb: (msg) => Debug.Log("WV MSG: " + msg));
            webView.SetMargins(0, 100, 0, 0);
            webView.SetVisibility(true);
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
        }
        string url = "https://webrtc.github.io/samples/src/content/getusermedia/gum/";
        webView.LoadURL(url);
        webView.SetVisibility(true);
    }

    void Awake()
    {
        if (!Permission.HasUserAuthorizedPermission(Permission.Camera))
            Permission.RequestUserPermission(Permission.Camera);
        if (!Permission.HasUserAuthorizedPermission(Permission.Microphone))
            Permission.RequestUserPermission(Permission.Microphone);
    }

    void OnGUI()
    {
        var x = 10;

        if (GUI.Button(new Rect(x, 10, 80, 80), "Mic")) {
            var g = GameObject.Find("WebViewObject");
            if (g != null) {
                Destroy(g);
            } else {
                OpenMicTesting();
            }
        }
        x += 90;

        if (GUI.Button(new Rect(x, 10, 80, 80), "Camera")) {
            var g = GameObject.Find("WebViewObject");
            if (g != null) {
                Destroy(g);
            } else {
                OpenCameraTesting();
            }
        }
        x += 90;
    }
}
