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
using UnityEngine.Events;
#if UNITY_2018_4_OR_NEWER
using UnityEngine.Networking;
#endif
using UnityEngine.UI;

public class CanvasWebView : MonoBehaviour {
  
  public string url = "home.html";
  public Text status;
  public Text console;
  public RectTransform webview;
  public UnityEvent onStart;
  public UnityEvent onLoad;
  public UnityEvent onMessage;
  public UnityEvent onError;
  public UnityEvent onHook;

  protected WebViewObject webViewObject;

  void Start() {
    webViewObject = (new GameObject("WebViewObject")).AddComponent<WebViewObject>();
    webViewObject.Init(
      cb: messaged,
      err: errored,
      started: started,
      hooked: hooked,
      ld: loaded,
      //transparent: false,
      //zoom: true,
      //ua: "custom user agent string",

#if UNITY_EDITOR
    separated: false,
#endif

    //androidForceDarkMode: 0,  // 0: follow system setting, 1: force dark off, 2: force dark on
    enableWKWebView: true,
    wkContentMode: 0);  // 0: recommended, 1: mobile, 2: desktop

#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
    webViewObject.bitmapRefreshCycle = 1;
#endif

    //webview.gameObject.SetActive(false);
    clearConsole();
    resizeView();
    // android only. cf. https://stackoverflow.com/questions/21647641/android-webview-set-font-size-system-default/47017410#47017410
    webViewObject.SetTextZoom(100);
    webViewObject.SetVisibility(true);
    StartCoroutine(render());
  }

  protected void started(string msg) {
    console.text += $"\nStarted: {msg}";
    onStart.Invoke();
  }

  protected void hooked(string msg) {
    console.text += $"\nHooked: {msg}";
    onHook.Invoke();
  }

  protected void errored(string msg) {
    console.text += $"\nError: {msg}";
    onError.Invoke();
  }

  protected void messaged(string msg) {
    console.text += $"\nCallback: {msg}";
    onMessage.Invoke();
  }

  protected void loaded(string msg) {
      console.text += $"\nLoaded: {msg}";
      onLoad.Invoke();
#if UNITY_EDITOR_OSX || (!UNITY_ANDROID && !UNITY_WEBPLAYER && !UNITY_WEBGL)
    // NOTE: depending on the situation, you might prefer
    // the 'iframe' approach.
    // cf. https://github.com/gree/unity-webview/issues/189
#if true
    webViewObject.EvaluateJS(@"
      if (window && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.unityControl) {
        window.Unity = {
          call: function(msg) {
            window.webkit.messageHandlers.unityControl.postMessage(msg);
          }
        }
      } else {
        window.Unity = {
          call: function(msg) {
            window.location = 'unity:' + msg;
          }
        }
      }
    ");
#else
    webViewObject.EvaluateJS(@"
      if (window && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.unityControl) {
        window.Unity = {
          call: function(msg) {
            window.webkit.messageHandlers.unityControl.postMessage(msg);
          }
        }
      } else {
        window.Unity = {
          call: function(msg) {
            var iframe = document.createElement('IFRAME');
            iframe.setAttribute('src', 'unity:' + msg);
            document.documentElement.appendChild(iframe);
            iframe.parentNode.removeChild(iframe);
            iframe = null;
          }
        }
      }
    ");
#endif
#elif UNITY_WEBPLAYER || UNITY_WEBGL
    webViewObject.EvaluateJS(
      "window.Unity = {" +
      "   call:function(msg) {" +
      "       parent.unityWebView.sendMessage('WebViewObject', msg)" +
      "   }" +
      "};");
#endif
    webViewObject.EvaluateJS(@"Unity.call('ua=' + navigator.userAgent)");
  }

  public void back() {
    webViewObject.GoBack();
  }

  public void foward() {
    webViewObject.GoForward();
  }

  public void reload() {
    webViewObject.Reload();
  }

  public void setUrl(string url) {
    this.url = url;
    StartCoroutine(render());
  }

  public void clearConsole() {
    console.text = "";
  }

  public void getCookies() {
    string cookies = webViewObject.GetCookies(url);
    console.text += cookies;
  }

  public void clearCookies() {
    webViewObject.ClearCookies();
    console.text = "";
  }

  private IEnumerator render() {

#if !UNITY_WEBPLAYER && !UNITY_WEBGL
    if (url.StartsWith("http")) {
      webViewObject.LoadURL(url.Replace(" ", "%20"));
      status.text = url;
    }
    else {
      var exts = new string[]{
        ".jpg",
        ".js",
        ".html"  // should be last
      };
      foreach (var ext in exts) {
        var url = this.url.Replace(".html", ext);
        var src = System.IO.Path.Combine(Application.streamingAssetsPath, url);
        var dst = System.IO.Path.Combine(Application.persistentDataPath, url);
        byte[] result = null;
        if (src.Contains("://")) {  // for Android
#if UNITY_2018_4_OR_NEWER
          // NOTE: a more complete code that utilizes UnityWebRequest can be found in https://github.com/gree/unity-webview/commit/2a07e82f760a8495aa3a77a23453f384869caba7#diff-4379160fa4c2a287f414c07eb10ee36d
          var unityWebRequest = UnityWebRequest.Get(src);
          yield return unityWebRequest.SendWebRequest();
          result = unityWebRequest.downloadHandler.data;
#else
                    var www = new WWW(src);
                    yield return www;
                    result = www.bytes;
#endif
        }
        else {
          result = System.IO.File.ReadAllBytes(src);
        }
        System.IO.File.WriteAllBytes(dst, result);
        if (ext == ".html") {
          webViewObject.LoadURL("file://" + dst.Replace(" ", "%20"));
          break;
        }
      }
    }
#else
    if (Url.StartsWith("http")) {
        webViewObject.LoadURL(Url.Replace(" ", "%20"));
    } else {
        webViewObject.LoadURL("StreamingAssets/" + Url.Replace(" ", "%20"));
    }
#endif
    yield break;
  }

  public void resizeView() {

    Bounds bounds = GetRectTransformBounds(webview);
    Rect screenRect = new Rect(bounds.min, bounds.size);
    //Debug.DrawLine(bounds.min, bounds.max, Color.red, 10);

    int left = (int)bounds.min.x;
    int bottom = (int)bounds.min.y;
    int right = (int)(Screen.width - bounds.max.x);
    int top = (int)(Screen.height - bounds.max.y);
    Debug.Log($"Left:{left} top:{top} right:{right} bottom:{bottom}");
    webViewObject.SetMargins(left, top, right, bottom);
  }

  private Bounds GetRectTransformBounds(RectTransform transform) {
    Vector3[] WorldCorners = new Vector3[4];
    transform.GetWorldCorners(WorldCorners);
    Bounds bounds = new Bounds(WorldCorners[0], Vector3.zero);
    for (int i = 1; i < 4; ++i) { bounds.Encapsulate(WorldCorners[i]); }
    return bounds;
  }

}
