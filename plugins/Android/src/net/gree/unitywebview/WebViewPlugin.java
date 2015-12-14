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

import com.unity3d.player.UnityPlayer;
import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup.LayoutParams;
import android.content.Context;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.webkit.JavascriptInterface;
import android.content.Intent;
import android.net.Uri;

class WebViewPluginInterface
{
    private String mGameObject;

    public WebViewPluginInterface(final String gameObject)
    {
        mGameObject = gameObject;
    }

    @JavascriptInterface
    public void call(String message)
    {
        UnityPlayer.UnitySendMessage(mGameObject, "CallFromJS", message);
    }
}

public class WebViewPlugin
{
    private static FrameLayout layout = null;
    private WebView mWebView;
    private WebViewPluginInterface mWebViewPlugin;
    private long mDownTime;

    public WebViewPlugin()
    {
    }

    public void Init(final String gameObject)
    {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {

            mWebView = new WebView(a);
            mWebView.setVisibility(View.GONE);
            mWebView.setFocusable(true);
            mWebView.setFocusableInTouchMode(true);

            if (layout == null) {
                layout = new FrameLayout(a);
                a.addContentView(layout, new LayoutParams(
                    LayoutParams.FILL_PARENT, LayoutParams.FILL_PARENT));
                layout.setFocusable(true);
                layout.setFocusableInTouchMode(true);
            }

            layout.addView(mWebView, new FrameLayout.LayoutParams(
                LayoutParams.FILL_PARENT, LayoutParams.FILL_PARENT,
                Gravity.NO_GRAVITY));

            mWebView.setWebChromeClient(new WebChromeClient() {
                public boolean onConsoleMessage(android.webkit.ConsoleMessage cm) {
                    Log.d("Webview", cm.message());
                    return true;
                }
            });
            mWebView.setWebViewClient(new WebViewClient() {
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, String url) {
                    if (url.startsWith("http://") || url.startsWith("https://") || 
                            url.startsWith("file://") || url.startsWith("javascript:")) {
                        // Let webview handle the URL
                        return false;
                    }
                    else if (url.startsWith("unity:")) {
                        String message = url.substring(6);
                        mWebViewPlugin.call(message);
                        return true;
                    }
                    Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    view.getContext().startActivity(intent);
                    return true;
                }
            });
            
            mWebViewPlugin = new WebViewPluginInterface(gameObject);
            
            mWebView.addJavascriptInterface(
                mWebViewPlugin , "Unity");

            WebSettings webSettings = mWebView.getSettings();
            webSettings.setSupportZoom(false);
            webSettings.setJavaScriptEnabled(true);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                Log.i("WebViewPlugin", "Build.VERSION.SDK_INT = " + Build.VERSION.SDK_INT);
                webSettings.setAllowUniversalAccessFromFileURLs(true);
            }
            webSettings.setRenderPriority(WebSettings.RenderPriority.HIGH);
            webSettings.setCacheMode(WebSettings.LOAD_NO_CACHE);

            String databasePath = mWebView.getContext().getDir("databases", Context.MODE_PRIVATE).getPath(); 
            webSettings.setDatabaseEnabled(true);
            webSettings.setDomStorageEnabled(true);
            webSettings.setDatabasePath(databasePath); 

        }});

        final View activityRootView = a.getWindow().getDecorView().getRootView();
        activityRootView.getViewTreeObserver().addOnGlobalLayoutListener(new android.view.ViewTreeObserver.OnGlobalLayoutListener() {
        @Override
        public void onGlobalLayout() {
                android.graphics.Rect r = new android.graphics.Rect();
                //r will be populated with the coordinates of your view that area still visible.
                activityRootView.getWindowVisibleDisplayFrame(r);
                android.view.Display display = a.getWindowManager().getDefaultDisplay();
                int screenHeight = display.getHeight();
                int heightDiff = activityRootView.getRootView().getHeight() - (r.bottom - r.top);
                //System.out.print(String.format("[NativeWebview] %d, %d\n", screenHeight, heightDiff));
                if (heightDiff > screenHeight/3) { // assume that this means that the keyboard is on
                    UnityPlayer.UnitySendMessage(gameObject, "SetKeyboardVisible", "true");
                } else {
                    UnityPlayer.UnitySendMessage(gameObject, "SetKeyboardVisible", "false");
                }
            }
        }); 
    }

    public void Destroy()
    {
        Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {

            if (mWebView != null) {
                layout.removeView(mWebView);
                mWebView = null;
            }

        }});
    }

    public void LoadURL(final String url)
    {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {

            mWebView.loadUrl(url);

        }});
    }

    public void EvaluateJS(final String js)
    {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {

            mWebView.loadUrl("javascript:" + js);

        }});
    }

    public void SetMargins(int left, int top, int right, int bottom)
    {
        final FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
            LayoutParams.FILL_PARENT, LayoutParams.FILL_PARENT,
                Gravity.NO_GRAVITY);
        params.setMargins(left, top, right, bottom);

        Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {

            mWebView.setLayoutParams(params);

        }});
    }

    public void SetVisibility(final boolean visibility)
    {
        Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {

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
