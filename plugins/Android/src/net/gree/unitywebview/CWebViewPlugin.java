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

package net.gree.unitywebview;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Point;
import android.net.Uri;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup.LayoutParams;
import android.view.ViewTreeObserver.OnGlobalLayoutListener;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.CookieManager;
import android.webkit.CookieSyncManager;
import android.widget.FrameLayout;

import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.HashMap;
import java.util.Hashtable;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.FutureTask;

import com.unity3d.player.UnityPlayer;

class CWebViewPluginInterface {
    private CWebViewPlugin mPlugin;
    private String mGameObject;

    public CWebViewPluginInterface(CWebViewPlugin plugin, String gameObject) {
        mPlugin = plugin;
        mGameObject = gameObject;
    }

    @JavascriptInterface
    public void call(final String message) {
        call("CallFromJS", message);
    }

    public void call(final String method, final String message) {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mPlugin.IsInitialized()) {
                UnityPlayer.UnitySendMessage(mGameObject, method, message);
            }
        }});
    }
}

public class CWebViewPlugin {
    private static FrameLayout layout = null;
    private WebView mWebView;
    private OnGlobalLayoutListener mGlobalLayoutListener;
    private CWebViewPluginInterface mWebViewPlugin;
    private int progress;
    private boolean canGoBack;
    private boolean canGoForward;
    private Hashtable<String, String> mCustomHeaders;
    private String mWebViewUA;

    public CWebViewPlugin() {
    }

    public static boolean IsWebViewAvailable() {
        final Activity a = UnityPlayer.currentActivity;
        FutureTask<Boolean> t = new FutureTask<Boolean>(new Callable<Boolean>() {
            public Boolean call() throws Exception {
                boolean isAvailable = false;
                try {
                    WebView webView = new WebView(a);
                    if (webView != null) {
                        webView = null;
                        isAvailable = true;
                    }
                } catch (Exception e) {
                }
                return isAvailable;
            }
        });
        a.runOnUiThread(t);
        try {
            return t.get();
        } catch (Exception e) {
            return false;
        }
    }

    public boolean IsInitialized() {
        return mWebView != null;
    }

    public void Init(final String gameObject, final boolean transparent, final String ua) {
        final CWebViewPlugin self = this;
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView != null) {
                return;
            }
            mCustomHeaders = new Hashtable<String, String>();
            
            final WebView webView = new WebView(a);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                try {
                    ApplicationInfo ai = a.getPackageManager().getApplicationInfo(a.getPackageName(), 0);
                    if ((ai.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
                        webView.setWebContentsDebuggingEnabled(true);
                    }
                } catch (Exception ex) {
                }
            }
            webView.setVisibility(View.GONE);
            webView.setFocusable(true);
            webView.setFocusableInTouchMode(true);

            // webView.setWebChromeClient(new WebChromeClient() {
            //     public boolean onConsoleMessage(android.webkit.ConsoleMessage cm) {
            //         Log.d("Webview", cm.message());
            //         return true;
            //     }
            // });
            webView.setWebChromeClient(new WebChromeClient() {
                View videoView;

                @Override
                public void onProgressChanged(WebView view, int newProgress) {
                    progress = newProgress;
                }

                @Override
                public void onShowCustomView(View view, CustomViewCallback callback) {
                    super.onShowCustomView(view, callback);
                    if (layout != null) {
                        videoView = view;
                        layout.setBackgroundColor(0xff000000);
                        layout.addView(videoView);
                    }
                }

                @Override
                public void onHideCustomView() {
                    super.onHideCustomView();
                    if (layout != null) {
                        layout.removeView(videoView);
                        layout.setBackgroundColor(0x00000000);
                        videoView = null;
                    }
                }
            });

            mWebViewPlugin = new CWebViewPluginInterface(self, gameObject);
            webView.setWebViewClient(new WebViewClient() {
                @Override
                public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
                    webView.loadUrl("about:blank");
                    canGoBack = webView.canGoBack();
                    canGoForward = webView.canGoForward();
                    mWebViewPlugin.call("CallOnError", errorCode + "\t" + description + "\t" + failingUrl);
                }
                
                @Override
                public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
                	canGoBack = webView.canGoBack();
                    canGoForward = webView.canGoForward();
                    mWebViewPlugin.call("CallOnHttpError", Integer.toString(errorResponse.getStatusCode()));
                }

                @Override
                public void onPageStarted(WebView view, String url, Bitmap favicon) {
                    canGoBack = webView.canGoBack();
                    canGoForward = webView.canGoForward();
                    mWebViewPlugin.call("CallOnStarted", url);
                }

                @Override
                public void onPageFinished(WebView view, String url) {
                    canGoBack = webView.canGoBack();
                    canGoForward = webView.canGoForward();
                    mWebViewPlugin.call("CallOnLoaded", url);
                }

                @Override
                public void onLoadResource(WebView view, String url) {
                    canGoBack = webView.canGoBack();
                    canGoForward = webView.canGoForward();
                }

                @Override
                public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
                    if (mCustomHeaders == null || mCustomHeaders.isEmpty()) {
                        return super.shouldInterceptRequest(view, url);
                    }

                    try {
                        HttpURLConnection urlCon = (HttpURLConnection) (new URL(url)).openConnection();
                        // The following should make HttpURLConnection have a same user-agent of webView)
                        // cf. http://d.hatena.ne.jp/faw/20070903/1188796959 (in Japanese)
                        urlCon.setRequestProperty("User-Agent", mWebViewUA);

                        for (HashMap.Entry<String, String> entry: mCustomHeaders.entrySet()) {
                            urlCon.setRequestProperty(entry.getKey(), entry.getValue());
                        }

                        urlCon.connect();

                        return new WebResourceResponse(
                            urlCon.getContentType().split(";", 2)[0],
                            urlCon.getContentEncoding(),
                            urlCon.getInputStream()
                        );

                    } catch (Exception e) {
                        return super.shouldInterceptRequest(view, url);
                    }
                }

                @Override
                public boolean shouldOverrideUrlLoading(WebView view, String url) {
                    canGoBack = webView.canGoBack();
                    canGoForward = webView.canGoForward();
                    if (url.startsWith("http://") || url.startsWith("https://")
                        || url.startsWith("file://") || url.startsWith("javascript:")) {
                        // Let webview handle the URL
                        return false;
                    } else if (url.startsWith("unity:")) {
                        String message = url.substring(6);
                        mWebViewPlugin.call("CallFromJS", message);
                        return true;
                    }
                    Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    PackageManager pm = a.getPackageManager();
                    List<ResolveInfo> apps = pm.queryIntentActivities(intent, 0);
                    if (apps.size() > 0) {
                        view.getContext().startActivity(intent);
                    }
                    return true;
                }
            });
            webView.addJavascriptInterface(mWebViewPlugin , "Unity");

            WebSettings webSettings = webView.getSettings();
            if (ua != null && ua.length() > 0) {
                webSettings.setUserAgentString(ua);
            }
            mWebViewUA = webSettings.getUserAgentString();
            webSettings.setSupportZoom(true);
            webSettings.setBuiltInZoomControls(true);
            webSettings.setDisplayZoomControls(false);
            webSettings.setLoadWithOverviewMode(true);
            webSettings.setUseWideViewPort(true);
            webSettings.setJavaScriptEnabled(true);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                // Log.i("CWebViewPlugin", "Build.VERSION.SDK_INT = " + Build.VERSION.SDK_INT);
                webSettings.setAllowUniversalAccessFromFileURLs(true);
            }
            if (android.os.Build.VERSION.SDK_INT >= 17) {
                webSettings.setMediaPlaybackRequiresUserGesture(false);
            }
            webSettings.setDatabaseEnabled(true);
            webSettings.setDomStorageEnabled(true);
            String databasePath = webView.getContext().getDir("databases", Context.MODE_PRIVATE).getPath();
            webSettings.setDatabasePath(databasePath);

            if (transparent) {
                webView.setBackgroundColor(0x00000000);
            }

            if (layout == null || layout.getParent() != a.findViewById(android.R.id.content)) {
                layout = new FrameLayout(a);
                a.addContentView(
                    layout,
                    new LayoutParams(
                        LayoutParams.MATCH_PARENT,
                        LayoutParams.MATCH_PARENT));
                layout.setFocusable(true);
                layout.setFocusableInTouchMode(true);
            }
            layout.addView(
                webView,
                new FrameLayout.LayoutParams(
                    LayoutParams.MATCH_PARENT,
                    LayoutParams.MATCH_PARENT,
                    Gravity.NO_GRAVITY));
            mWebView = webView;
        }});

        final View activityRootView = a.getWindow().getDecorView().getRootView();
        mGlobalLayoutListener = new OnGlobalLayoutListener() {
            @Override
            public void onGlobalLayout() {
                android.graphics.Rect r = new android.graphics.Rect();
                //r will be populated with the coordinates of your view that area still visible.
                activityRootView.getWindowVisibleDisplayFrame(r);
                android.view.Display display = a.getWindowManager().getDefaultDisplay();
                // cf. http://stackoverflow.com/questions/9654016/getsize-giving-me-errors/10564149#10564149
                int h = 0;
                try {
                    Point size = new Point();
                    display.getSize(size);
                    h = size.y;
                } catch (java.lang.NoSuchMethodError err) {
                    h = display.getHeight();
                }
                int heightDiff = activityRootView.getRootView().getHeight() - (r.bottom - r.top);
                //System.out.print(String.format("[NativeWebview] %d, %d\n", h, heightDiff));
                if (heightDiff > h / 3) { // assume that this means that the keyboard is on
                    UnityPlayer.UnitySendMessage(gameObject, "SetKeyboardVisible", "true");
                } else {
                    UnityPlayer.UnitySendMessage(gameObject, "SetKeyboardVisible", "false");
                }
            }
        };
        activityRootView.getViewTreeObserver().addOnGlobalLayoutListener(mGlobalLayoutListener);
    }

    public void Destroy() {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            if (mGlobalLayoutListener != null) {
                View activityRootView = a.getWindow().getDecorView().getRootView();
                activityRootView.getViewTreeObserver().removeOnGlobalLayoutListener(mGlobalLayoutListener);
                mGlobalLayoutListener = null;
            }
            mWebView.stopLoading();
            layout.removeView(mWebView);
            mWebView.destroy();
            mWebView = null;
        }});
    }

    public void LoadURL(final String url) {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            if (mCustomHeaders != null && !mCustomHeaders.isEmpty()) {
                mWebView.loadUrl(url, mCustomHeaders);
            } else {
                mWebView.loadUrl(url);;
            }
        }});
    }

    public void LoadHTML(final String html, final String baseURL)
    {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.loadDataWithBaseURL(baseURL, html, "text/html", "UTF8", null);
        }});
    }

    public void EvaluateJS(final String js) {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                mWebView.evaluateJavascript(js, null);
            } else {
                mWebView.loadUrl("javascript:" + URLEncoder.encode(js));
            }
        }});
    }

    public void GoBack() {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.goBack();
        }});
    }

    public void GoForward() {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.goForward();
        }});
    }

    public void SetMargins(int left, int top, int right, int bottom) {
        final FrameLayout.LayoutParams params
            = new FrameLayout.LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT,
                Gravity.NO_GRAVITY);
        params.setMargins(left, top, right, bottom);
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.setLayoutParams(params);
        }});
    }

    public void SetVisibility(final boolean visibility) {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            if (visibility) {
                mWebView.setVisibility(View.VISIBLE);
                layout.requestFocus();
                mWebView.requestFocus();
            } else {
                mWebView.setVisibility(View.GONE);
            }
        }});
    }

    // cf. https://stackoverflow.com/questions/31788748/webview-youtube-videos-playing-in-background-on-rotation-and-minimise/31789193#31789193
    public void OnApplicationPause(final boolean paused) {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            if (paused) {
                mWebView.onPause();
                mWebView.pauseTimers();
            } else {
                mWebView.onResume();
                mWebView.resumeTimers();
            }
        }});
    }

    public void AddCustomHeader(final String headerKey, final String headerValue)
    {
        if (mCustomHeaders == null) {
            return;
        }
        mCustomHeaders.put(headerKey, headerValue);
    }

    public String GetCustomHeaderValue(final String headerKey)
    {
        if (mCustomHeaders == null) {
            return null;
        }

        if (!mCustomHeaders.containsKey(headerKey)) {
            return null;
        }
        return this.mCustomHeaders.get(headerKey);
    }

    public void RemoveCustomHeader(final String headerKey)
    {
        if (mCustomHeaders == null) {
            return;
        }

        if (this.mCustomHeaders.containsKey(headerKey)) {
            this.mCustomHeaders.remove(headerKey);
        }
    }

    public void ClearCustomHeader()
    {
        if (mCustomHeaders == null) {
            return;
        }

        this.mCustomHeaders.clear();
    }

    public void ClearCookies()
    {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) 
        {
           CookieManager.getInstance().removeAllCookies(null);
           CookieManager.getInstance().flush();
        } else {
           final Activity a = UnityPlayer.currentActivity;
           CookieSyncManager cookieSyncManager = CookieSyncManager.createInstance(a);
           cookieSyncManager.startSync();
           CookieManager cookieManager = CookieManager.getInstance();
           cookieManager.removeAllCookie();
           cookieManager.removeSessionCookie();
           cookieSyncManager.stopSync();
           cookieSyncManager.sync();
        }
    }

    public String GetCookies(String url)
    {
        CookieManager cookieManager = CookieManager.getInstance();
        return cookieManager.getCookie(url);
    }
}
