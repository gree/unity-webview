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
import android.graphics.Bitmap;
import android.graphics.Point;
import android.net.Uri;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup.LayoutParams;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
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
    private CWebViewPluginInterface mWebViewPlugin;
    private boolean canGoBack;
    private boolean canGoForward;

    public CWebViewPlugin() {
    }

    public boolean IsInitialized() {
        return mWebView != null;
    }

    public void Init(final String gameObject, final boolean transparent) {
        final CWebViewPlugin self = this;
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView != null) {
                return;
            }
            final WebView webView = new WebView(a);
            webView.setVisibility(View.GONE);
            webView.setFocusable(true);
            webView.setFocusableInTouchMode(true);

            // webView.setWebChromeClient(new WebChromeClient() {
            //     public boolean onConsoleMessage(android.webkit.ConsoleMessage cm) {
            //         Log.d("Webview", cm.message());
            //         return true;
            //     }
            // });
            webView.setWebChromeClient(new WebChromeClient());

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
                public void onPageStarted(WebView view, String url, Bitmap favicon) {
                    canGoBack = webView.canGoBack();
                    canGoForward = webView.canGoForward();
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
                    view.getContext().startActivity(intent);
                    return true;
                }
            });
            webView.addJavascriptInterface(mWebViewPlugin , "Unity");

            WebSettings webSettings = webView.getSettings();
            webSettings.setSupportZoom(false);
            webSettings.setJavaScriptEnabled(true);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                // Log.i("CWebViewPlugin", "Build.VERSION.SDK_INT = " + Build.VERSION.SDK_INT);
                webSettings.setAllowUniversalAccessFromFileURLs(true);
            }
            webSettings.setDatabaseEnabled(true);
            webSettings.setDomStorageEnabled(true);
            String databasePath = webView.getContext().getDir("databases", Context.MODE_PRIVATE).getPath();
            webSettings.setDatabasePath(databasePath);

            if (transparent) {
                webView.setBackgroundColor(0x00000000);
            }

            if (layout == null) {
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
        activityRootView.getViewTreeObserver().addOnGlobalLayoutListener(new android.view.ViewTreeObserver.OnGlobalLayoutListener() {
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
        });
    }

    public void Destroy() {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
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
            mWebView.loadUrl(url);
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
            mWebView.loadUrl("javascript:" + js);
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
}
