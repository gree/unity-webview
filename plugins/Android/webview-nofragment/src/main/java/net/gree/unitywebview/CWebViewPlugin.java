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
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
//#if UNITYWEBVIEW_DEVELOPMENT
import android.content.pm.ApplicationInfo;
//#endif
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Point;
import android.net.Uri;
import android.os.Build;
import android.util.Base64;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewGroup.LayoutParams;
import android.view.ViewTreeObserver.OnGlobalLayoutListener;
import android.webkit.GeolocationPermissions.Callback;
import android.webkit.HttpAuthHandler;
import android.webkit.JavascriptInterface;
import android.webkit.JsResult;
import android.webkit.JsPromptResult;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.CookieManager;
import android.webkit.CookieSyncManager;
import android.widget.FrameLayout;
import android.webkit.PermissionRequest;

import java.net.HttpURLConnection;
import java.net.URISyntaxException;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Hashtable;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.concurrent.Callable;
import java.util.concurrent.FutureTask;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mPlugin.IsInitialized()) {
                mPlugin.MyUnitySendMessage(mGameObject, method, message);
            }
        }});
    }
}

public class CWebViewPlugin {
    private static boolean forceBringToFront;
    private static FrameLayout layout = null;
    private Queue<String> mMessages = new ArrayDeque<String>();
    private WebView mWebView;
    private View mVideoView;
    private OnGlobalLayoutListener mGlobalLayoutListener;
    private CWebViewPluginInterface mWebViewPlugin;
    private int progress;
    private boolean canGoBack;
    private boolean canGoForward;
    private boolean mInteractionEnabled = true;
    private boolean mGoogleAppRedirectionEnabled;
    private boolean mAlertDialogEnabled;
    private boolean mAllowVideoCapture;
    private boolean mAllowAudioCapture;
    private Hashtable<String, String> mCustomHeaders;
    private String mWebViewUA;
    private Pattern mAllowRegex;
    private Pattern mDenyRegex;
    private Pattern mHookRegex;

    private String mBasicAuthUserName;
    private String mBasicAuthPassword;

    // cf. https://chromium.googlesource.com/chromium/src/+/3e5a94daf32200d65dea6072dd4d1b9a2025508b/components/external_intents/android/java/src/org/chromium/components/external_intents/ExternalNavigationHandler.java#121
    private static final int ALLOWED_INTENT_FLAGS
        = Intent.FLAG_EXCLUDE_STOPPED_PACKAGES
        | Intent.FLAG_ACTIVITY_CLEAR_TOP
        | Intent.FLAG_ACTIVITY_SINGLE_TOP
        | Intent.FLAG_ACTIVITY_MATCH_EXTERNAL
        | Intent.FLAG_ACTIVITY_NEW_TASK
        | Intent.FLAG_ACTIVITY_MULTIPLE_TASK
        | Intent.FLAG_ACTIVITY_NEW_DOCUMENT
        | Intent.FLAG_ACTIVITY_RETAIN_IN_RECENTS
        | Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT;

    // cf. https://chromium.googlesource.com/chromium/src/+/3e5a94daf32200d65dea6072dd4d1b9a2025508b/components/external_intents/android/java/src/org/chromium/components/external_intents/ExternalNavigationHandler.java#1808
    private static void sanitizeQueryIntentActivitiesIntent(Intent intent) {
        intent.setFlags(intent.getFlags() & ALLOWED_INTENT_FLAGS);
        intent.addCategory(Intent.CATEGORY_BROWSABLE);
        intent.setComponent(null);

        // Intent Selectors allow intents to bypass the intent filter and potentially send apps URIs
        // they were not expecting to handle. https://crbug.com/1254422
        intent.setSelector(null);
    }

    // cf. https://github.com/gree/unity-webview/issues/753
    // cf. https://github.com/mixpanel/mixpanel-android/issues/400
    // cf. https://github.com/mixpanel/mixpanel-android/commit/98bb530f9263f3bac0737971acc00dfef7ea4c35
    public static boolean isDestroyed(final Activity a) {
        if (a == null) {
            return true;
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            return a.isDestroyed();
        } else {
            return false;
        }
    }

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
        if (CWebViewPlugin.isDestroyed(a)) {
            return false;
        }
        a.runOnUiThread(t);
        try {
            return t.get();
        } catch (Exception e) {
            return false;
        }
    }

    public String GetMessage() {
        synchronized(mMessages) {
            return (mMessages.size() > 0) ? mMessages.poll() : null;
        }
    }

    public void MyUnitySendMessage(String gameObject, String method, String message) {
        synchronized(mMessages) {
            mMessages.add(method + ":" + message);
        }
    }

    public boolean IsInitialized() {
        return mWebView != null;
    }

    public void Init(final String gameObject, final boolean transparent, final boolean zoom, final int androidForceDarkMode, final String ua, final int radius) {
        final CWebViewPlugin self = this;
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView != null) {
                return;
            }
            mAlertDialogEnabled = true;
            mAllowVideoCapture = false;
            mAllowAudioCapture = false;
            mCustomHeaders = new Hashtable<String, String>();

            final WebView webView = (radius > 0) ? new RoundedWebView(a, radius) : new WebView(a);
//#if UNITYWEBVIEW_DEVELOPMENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                try {
                    ApplicationInfo ai = a.getPackageManager().getApplicationInfo(a.getPackageName(), 0);
                    if ((ai.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
                        webView.setWebContentsDebuggingEnabled(true);
                    }
                } catch (Exception ex) {
                }
            }
//#endif
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
                // cf. https://stackoverflow.com/questions/40659198/how-to-access-the-camera-from-within-a-webview/47525818#47525818
                // cf. https://github.com/googlesamples/android-PermissionRequest/blob/eff1d21f0b9c91d67c7f2a2303b591447e61e942/Application/src/main/java/com/example/android/permissionrequest/PermissionRequestFragment.java#L148-L161
                @Override
                public void onPermissionRequest(final PermissionRequest request) {
                    final String[] requestedResources = request.getResources();
                    for (String r : requestedResources) {
                        if ((r.equals(PermissionRequest.RESOURCE_VIDEO_CAPTURE) && mAllowVideoCapture)
                            || (r.equals(PermissionRequest.RESOURCE_AUDIO_CAPTURE) && mAllowAudioCapture)
                            || r.equals(PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID)) {
                            request.grant(requestedResources);
                            // if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            //     a.runOnUiThread(new Runnable() {public void run() {
                            //         final String[] permissions = {
                            //             "android.permission.CAMERA",
                            //             "android.permission.RECORD_AUDIO",
                            //         };
                            //         ActivityCompat.requestPermissions(a, permissions, 0);
                            //     }});
                            // }
                            break;
                        }
                    }
                }

                @Override
                public void onProgressChanged(WebView view, int newProgress) {
                    progress = newProgress;
                }

                @Override
                public void onShowCustomView(View view, CustomViewCallback callback) {
                    super.onShowCustomView(view, callback);
                    if (layout != null) {
                        mVideoView = view;
                        layout.setBackgroundColor(0xff000000);
                        layout.addView(mVideoView);
                    }
                }

                @Override
                public void onHideCustomView() {
                    super.onHideCustomView();
                    if (layout != null) {
                        layout.removeView(mVideoView);
                        layout.setBackgroundColor(0x00000000);
                        mVideoView = null;
                    }
                }

                @Override
                public boolean onJsAlert(WebView view, String url, String message, JsResult result) {
                    if (!mAlertDialogEnabled) {
                        result.cancel();
                        return true;
                    }
                    return super.onJsAlert(view, url, message, result);
                }

                @Override
                public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
                    if (!mAlertDialogEnabled) {
                        result.cancel();
                        return true;
                    }
                    return super.onJsConfirm(view, url, message, result);
                }

                @Override
                public boolean onJsPrompt(WebView view, String url, String message, String defaultValue, JsPromptResult result) {
                    if (!mAlertDialogEnabled) {
                        result.cancel();
                        return true;
                    }
                   return super.onJsPrompt(view, url, message, defaultValue, result);
                }

                @Override
                public void onGeolocationPermissionsShowPrompt(String origin, Callback callback) {
                    callback.invoke(origin, true, false);
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
                public void onReceivedHttpAuthRequest(WebView view, HttpAuthHandler handler, String host, String realm) {
                    if (mBasicAuthUserName != null && mBasicAuthPassword != null) {
                        handler.proceed(mBasicAuthUserName, mBasicAuthPassword);
                    } else {
                        handler.cancel();
                    }
                }

                @Override
                public WebResourceResponse shouldInterceptRequest(WebView view, final String url) {
                    if (mCustomHeaders == null || mCustomHeaders.isEmpty()) {
                        return super.shouldInterceptRequest(view, url);
                    }
                    return shouldInterceptRequest(view, url, null);
                }

                @Override
                public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                    if (mCustomHeaders == null || mCustomHeaders.isEmpty()) {
                        return super.shouldInterceptRequest(view, request);
                    }
                    return shouldInterceptRequest(view, request.getUrl().toString(), request.getRequestHeaders());
                }

                public WebResourceResponse shouldInterceptRequest(WebView view, final String url, Map<String, String> headers) {
                    try {
                        HttpURLConnection urlCon = (HttpURLConnection) (new URL(url)).openConnection();
                        urlCon.setInstanceFollowRedirects(false);
                        // The following should make HttpURLConnection have a same user-agent of webView)
                        // cf. http://d.hatena.ne.jp/faw/20070903/1188796959 (in Japanese)
                        urlCon.setRequestProperty("User-Agent", mWebViewUA);

                        if (mBasicAuthUserName != null && mBasicAuthPassword != null) {
                            String authorization = mBasicAuthUserName + ":" + mBasicAuthPassword;
                            urlCon.setRequestProperty("Authorization", "Basic " + Base64.encodeToString(authorization.getBytes(), Base64.NO_WRAP));
                        }

                        if (Build.VERSION.SDK_INT != Build.VERSION_CODES.KITKAT && Build.VERSION.SDK_INT != Build.VERSION_CODES.KITKAT_WATCH) {
                            // cf. https://issuetracker.google.com/issues/36989494
                            String cookies = CookieManager.getInstance().getCookie(url);
                            if (cookies != null && !cookies.isEmpty()) {
                                urlCon.addRequestProperty("Cookie", cookies);
                            }
                        }

                        if (headers != null) {
                            for (Map.Entry<String, String> entry: headers.entrySet()) {
                                urlCon.setRequestProperty(entry.getKey(), entry.getValue());
                            }
                        }
                        for (HashMap.Entry<String, String> entry: mCustomHeaders.entrySet()) {
                            urlCon.setRequestProperty(entry.getKey(), entry.getValue());
                        }

                        urlCon.connect();

                        int responseCode = urlCon.getResponseCode();
                        if (responseCode >= 300 && responseCode < 400) {
                            // To avoid a problem due to a mismatch between requested URL and returned content,
                            // make WebView request again in the case that redirection response was returned.
                            return null;
                        }

                        final List<String> setCookieHeaders = urlCon.getHeaderFields().get("Set-Cookie");
                        if (setCookieHeaders != null) {
                            if (Build.VERSION.SDK_INT == Build.VERSION_CODES.KITKAT || Build.VERSION.SDK_INT == Build.VERSION_CODES.KITKAT_WATCH) {
                                // In addition to getCookie, setCookie cause deadlock on Android 4.4.4 cf. https://issuetracker.google.com/issues/36989494
                                final Activity a = UnityPlayer.currentActivity;
                                if (!CWebViewPlugin.isDestroyed(a)) {
                                    a.runOnUiThread(new Runnable() {
                                        public void run() {
                                            SetCookies(url, setCookieHeaders);
                                        }
                                    });
                                }
                            } else {
                                SetCookies(url, setCookieHeaders);
                            }
                        }

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
                    boolean pass = true;
                    if (mAllowRegex != null && mAllowRegex.matcher(url).find()) {
                        pass = true;
                    } else if (mDenyRegex != null && mDenyRegex.matcher(url).find()) {
                        pass = false;
                    }
                    if (!pass) {
                        return true;
                    }
                    if (url.startsWith("unity:")) {
                        String message = url.substring(6);
                        mWebViewPlugin.call("CallFromJS", message);
                        return true;
                    } else if (mHookRegex != null && mHookRegex.matcher(url).find()) {
                        mWebViewPlugin.call("CallOnHooked", url);
                        return true;
                    } else if (!mGoogleAppRedirectionEnabled && url.startsWith("https://www.google.com/")) {
                        mWebView.loadUrl(url);
                        return true;
                    } else if (!mGoogleAppRedirectionEnabled && url.startsWith("intent://www.google.com/")) {
                        return true;
                    } else if (!url.toLowerCase().endsWith(".pdf")
                               && !url.startsWith("https://maps.app.goo.gl")
                               && (url.startsWith("http://")
                                   || url.startsWith("https://")
                                   || url.startsWith("file://")
                                   || url.startsWith("javascript:"))) {
                        mWebViewPlugin.call("CallOnStarted", url);
                        // Let webview handle the URL
                        return false;
                    } else if (url.startsWith("intent://") || url.startsWith("android-app://")) {
                        Intent intent = null;
                        try {
                            intent = Intent.parseUri(url, Intent.URI_INTENT_SCHEME);
                            // cf. https://www.m3tech.blog/entry/android-webview-intent-scheme
                            sanitizeQueryIntentActivitiesIntent(intent);
                            view.getContext().startActivity(intent);
                        } catch (URISyntaxException ex) {
                        } catch (ActivityNotFoundException ex) {
                            launchMarket(view.getContext(), intent);
                        }
                        return true;
                    }
                    Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    // PackageManager pm = a.getPackageManager();
                    // List<ResolveInfo> apps = pm.queryIntentActivities(intent, 0);
                    // if (apps.size() > 0) {
                    //     view.getContext().startActivity(intent);
                    // }
                    try {
                        view.getContext().startActivity(intent);
                    } catch (ActivityNotFoundException ex) {
                    }
                    return true;
                }

                private void launchMarket(Context context, Intent intent) {
                    if (intent == null) {
                        return;
                    }
                    String packageName = intent.getPackage();
                    if (packageName == null) {
                        return;
                    }
                    // cf. https://stackoverflow.com/questions/11753000/how-to-open-the-google-play-store-directly-from-my-android-application/11753070#11753070
                    try {
                        intent = new Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=" + packageName));
                        context.startActivity(intent);
                    } catch (android.content.ActivityNotFoundException ex) {
                        try {
                            intent = new Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=" + packageName));
                            context.startActivity(intent);
                        } catch (android.content.ActivityNotFoundException ex2) {
                        }
                    }
                }
            });
            webView.addJavascriptInterface(mWebViewPlugin , "Unity");

            WebSettings webSettings = webView.getSettings();
            if (ua != null && ua.length() > 0) {
                webSettings.setUserAgentString(ua);
            }
            mWebViewUA = webSettings.getUserAgentString();
            if (zoom) {
                webSettings.setSupportZoom(true);
                webSettings.setBuiltInZoomControls(true);
            } else {
                webSettings.setSupportZoom(false);
                webSettings.setBuiltInZoomControls(false);
            }
            webSettings.setDisplayZoomControls(false);
            webSettings.setLoadWithOverviewMode(true);
            webSettings.setUseWideViewPort(true);
            webSettings.setJavaScriptEnabled(true);
            webSettings.setGeolocationEnabled(true);

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
            webSettings.setAllowFileAccess(true);  // cf. https://github.com/gree/unity-webview/issues/625

            // cf. https://forum.unity.com/threads/unity-ios-dark-mode.805344/#post-6476051
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                switch (androidForceDarkMode) {
                case 0:
                    {
                        Configuration configuration = UnityPlayer.currentActivity.getResources().getConfiguration();
                        switch (configuration.uiMode & Configuration.UI_MODE_NIGHT_MASK) {
                        case Configuration.UI_MODE_NIGHT_NO:
                            webSettings.setForceDark(WebSettings.FORCE_DARK_OFF);
                            break;
                        case Configuration.UI_MODE_NIGHT_YES:
                            webSettings.setForceDark(WebSettings.FORCE_DARK_ON);
                            break;
                        }
                    }
                    break;
                case 1:
                    webSettings.setForceDark(WebSettings.FORCE_DARK_OFF);
                    break;
                case 2:
                    webSettings.setForceDark(WebSettings.FORCE_DARK_ON);
                    break;
                }
            }

            if (transparent) {
                webView.setBackgroundColor(0x00000000);
            }

            // cf. https://stackoverflow.com/questions/3853794/disable-webview-touch-events-in-android/3856199#3856199
            webView.setOnTouchListener(
                new View.OnTouchListener() {
                    @Override
                    public boolean onTouch(View view, MotionEvent event) {
                        return !mInteractionEnabled;
                    }
                });

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

                // View rootView = activityRootView.getRootView();
                // int bottomPadding = 0;
                // if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                //     Point realSize = new Point();
                //     display.getRealSize(realSize); // this method was added at JELLY_BEAN_MR1
                //     int[] location = new int[2];
                //     rootView.getLocationOnScreen(location);
                //     bottomPadding = realSize.y - (location[1] + rootView.getHeight());
                // }
                // int heightDiff = rootView.getHeight() - (r.bottom - r.top);
                // String param = "" ;
                // if (heightDiff > 0 && (heightDiff + bottomPadding) > (h + bottomPadding) / 3) { // assume that this means that the keyboard is on
                //     param = "true";
                // } else {
                //     param = "false";
                // }

                int heightDiff = activityRootView.getRootView().getHeight() - (r.bottom - r.top);
                if (IsInitialized()) {
                    MyUnitySendMessage(gameObject, "SetKeyboardVisible", Integer.toString(heightDiff));
                }
            }
        };
        activityRootView.getViewTreeObserver().addOnGlobalLayoutListener(mGlobalLayoutListener);
    }

    public void Destroy() {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            final WebView webView = mWebView;
            mWebView = null;
            if (webView == null) {
                return;
            }
            if (mGlobalLayoutListener != null) {
                View activityRootView = a.getWindow().getDecorView().getRootView();
                activityRootView.getViewTreeObserver().removeOnGlobalLayoutListener(mGlobalLayoutListener);
                mGlobalLayoutListener = null;
            }
            webView.stopLoading();
            if (mVideoView != null) {
                layout.removeView(mVideoView);
                layout.setBackgroundColor(0x00000000);
                mVideoView = null;
            }
            layout.removeView(webView);
            webView.destroy();
        }});
    }

    public boolean SetURLPattern(final String allowPattern, final String denyPattern, final String hookPattern)
    {
        try {
            final Pattern allow = (allowPattern == null || allowPattern.length() == 0) ? null : Pattern.compile(allowPattern);
            final Pattern deny = (denyPattern == null || denyPattern.length() == 0) ? null : Pattern.compile(denyPattern);
            final Pattern hook = (hookPattern == null || hookPattern.length() == 0) ? null : Pattern.compile(hookPattern);
            final Activity a = UnityPlayer.currentActivity;
            if (CWebViewPlugin.isDestroyed(a)) {
                return false;
            }
            a.runOnUiThread(new Runnable() {public void run() {
                mAllowRegex = allow;
                mDenyRegex = deny;
                mHookRegex = hook;
            }});
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public void LoadURL(final String url) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
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
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.loadDataWithBaseURL(baseURL, html, "text/html", "UTF8", null);
        }});
    }

    public void EvaluateJS(final String js) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
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
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.goBack();
        }});
    }

    public void GoForward() {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.goForward();
        }});
    }

    public void Reload() {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.reload();
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
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.setLayoutParams(params);
        }});
    }

    public void SetVisibility(final boolean visibility) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            if (visibility) {
                mWebView.setVisibility(View.VISIBLE);
                layout.requestFocus();
                mWebView.requestFocus();
                if (layout != null && layout.getParent() != null && layout.getParent().getParent() != null) {
                    ((ViewGroup)layout.getParent().getParent()).requestLayout();
                }
                if (forceBringToFront && layout != null) {
                    layout.bringToFront();
                }
            } else {
                mWebView.setVisibility(View.GONE);
            }
        }});
    }

    public void SetInteractionEnabled(final boolean enabled) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            mInteractionEnabled = enabled;
        }});
    }

    public void SetGoogleAppRedirectionEnabled(final boolean enabled) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            mGoogleAppRedirectionEnabled = enabled;
        }});
    }

    public void SetScrollbarsVisibility(final boolean visibility) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.setHorizontalScrollBarEnabled(visibility);
            mWebView.setVerticalScrollBarEnabled(visibility);
        }});
    }

    public void SetAlertDialogEnabled(final boolean enabled) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            mAlertDialogEnabled = enabled;
        }});
    }

    public void SetCameraAccess(final boolean allowed) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            mAllowVideoCapture = allowed;
        }});
    }

    public void SetMicrophoneAccess(final boolean allowed) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            mAllowAudioCapture = allowed;
        }});
    }

    public void SetNetworkAvailable(final boolean networkUp) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.setNetworkAvailable(networkUp);
        }});
    }

    // as the following explicitly pause/resume, pauseTimers()/resumeTimers() are always
    // called. this differs from OnApplicationPause().
    public void Pause() {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.onPause();
            mWebView.pauseTimers();
        }});
    }

    public void Resume() {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.onResume();
            mWebView.resumeTimers();
        }});
    }

    // cf. https://stackoverflow.com/questions/31788748/webview-youtube-videos-playing-in-background-on-rotation-and-minimise/31789193#31789193
    public void OnApplicationPause(final boolean paused) {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            if (paused) {
                mWebView.onPause();
                if (mWebView.getVisibility() == View.VISIBLE) {
                    // cf. https://qiita.com/nbhd/items/d31711faa8852143f3a4
                    mWebView.pauseTimers();
                }
            } else {
                mWebView.onResume();
                mWebView.resumeTimers();
                if (forceBringToFront && layout != null) {
                    layout.bringToFront();
                }
            }
        }});
    }

    public void AddCustomHeader(final String headerKey, final String headerValue)
    {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mCustomHeaders == null) {
                return;
            }
            mCustomHeaders.put(headerKey, headerValue);
        }});
    }

    public String GetCustomHeaderValue(final String headerKey)
    {
        if (mCustomHeaders == null) {
            return null;
        }
        if (!mCustomHeaders.containsKey(headerKey)) {
            return null;
        }
        return mCustomHeaders.get(headerKey);
    }

    public void RemoveCustomHeader(final String headerKey)
    {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mCustomHeaders == null) {
                return;
            }
            if (mCustomHeaders.containsKey(headerKey)) {
                mCustomHeaders.remove(headerKey);
            }
        }});
    }

    public void ClearCustomHeader()
    {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mCustomHeaders == null) {
                return;
            }
            mCustomHeaders.clear();
        }});
    }

    public void ClearCookie(String url, String name)
    {
        try {
            URL u = new URL(url);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                CookieManager cookieManager = CookieManager.getInstance();
                String cookieString = name + "=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=" + u.getPath();
                cookieManager.setCookie(url, cookieString);
                cookieManager.flush();
            } else {
                final Activity a = UnityPlayer.currentActivity;
                if (CWebViewPlugin.isDestroyed(a)) {
                    return;
                }
                CookieSyncManager cookieSyncManager = CookieSyncManager.createInstance(a);
                cookieSyncManager.startSync();
                CookieManager cookieManager = CookieManager.getInstance();
                String cookieString = name + "=; expires=Thu, 01 Jan 1970 00:00:00 UTC; domain=" + u.getHost() + "; path=" + u.getPath();
                cookieManager.setCookie(url, cookieString);
            }
        } catch (Exception e) {
        }
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

    public void SaveCookies()
    {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
        {
           CookieManager.getInstance().flush();
        } else {
           final Activity a = UnityPlayer.currentActivity;
           CookieSyncManager cookieSyncManager = CookieSyncManager.createInstance(a);
           cookieSyncManager.startSync();
           cookieSyncManager.stopSync();
           cookieSyncManager.sync();
        }
    }

    public void GetCookies(String url)
    {
        CookieManager cookieManager = CookieManager.getInstance();
        mWebViewPlugin.call("CallOnCookies", cookieManager.getCookie(url));
    }

    public void SetCookies(String url, List<String> setCookieHeaders)
    {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
        {
           CookieManager cookieManager = CookieManager.getInstance();
           for (String header : setCookieHeaders)
           {
              cookieManager.setCookie(url, header);
           }
           cookieManager.flush();
        } else {
           final Activity a = UnityPlayer.currentActivity;
           CookieSyncManager cookieSyncManager = CookieSyncManager.createInstance(a);
           cookieSyncManager.startSync();
           CookieManager cookieManager = CookieManager.getInstance();
           for (String header : setCookieHeaders)
           {
              cookieManager.setCookie(url, header);
           }
           cookieSyncManager.stopSync();
           cookieSyncManager.sync();
        }
    }

    public void SetBasicAuthInfo(final String userName, final String password)
    {
        mBasicAuthUserName = userName;
        mBasicAuthPassword = password;
    }

    public void ClearCache(final boolean includeDiskFiles)
    {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.clearCache(includeDiskFiles);
        }});
    }

    public void SetTextZoom(final int textZoom)
    {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            mWebView.getSettings().setTextZoom(textZoom);
        }});
    }

    public void SetMixedContentMode(final int mode)
    {
        final Activity a = UnityPlayer.currentActivity;
        if (CWebViewPlugin.isDestroyed(a)) {
            return;
        }
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView == null) {
                return;
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mWebView.getSettings().setMixedContentMode(mode);
            }
        }});
    }
}
