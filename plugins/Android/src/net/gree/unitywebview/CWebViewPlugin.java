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
import android.app.Fragment;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Point;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;
import android.util.Pair;
import android.view.Gravity;
import android.view.View;
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
import android.webkit.ValueCallback;
// import android.support.v4.app.ActivityCompat;

import java.io.File;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.Hashtable;
import java.util.List;
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
        a.runOnUiThread(new Runnable() {public void run() {
            if (mPlugin.IsInitialized()) {
                UnityPlayer.UnitySendMessage(mGameObject, method, message);
            }
        }});
    }
}

public class CWebViewPlugin extends Fragment {
    private static FrameLayout layout = null;
    private WebView mWebView;
    private OnGlobalLayoutListener mGlobalLayoutListener;
    private CWebViewPluginInterface mWebViewPlugin;
    private int progress;
    private boolean canGoBack;
    private boolean canGoForward;
    private boolean mAlertDialogEnabled;
    private Hashtable<String, String> mCustomHeaders;
    private String mWebViewUA;
    private Pattern mAllowRegex;
    private Pattern mDenyRegex;
    private Pattern mHookRegex;

    private static final int INPUT_FILE_REQUEST_CODE = 1;
    private ValueCallback<Uri> mUploadMessage;
    private ValueCallback<Uri[]> mFilePathCallback;
    private String mCameraPhotoPath;

    private static long instanceCount;
    private long mInstanceId;
    private boolean mPaused;
    private List<Pair<String, CWebViewPlugin>> mTransactions;

    private String mBasicAuthUserName;
    private String mBasicAuthPassword;

    public CWebViewPlugin() {
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != INPUT_FILE_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data);
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            if (mFilePathCallback == null) {
                super.onActivityResult(requestCode, resultCode, data);
                return;
            }
            Uri[] results = null;
            // Check that the response is a good one
            if (resultCode == Activity.RESULT_OK) {
                if (data == null) {
                    if (mCameraPhotoPath != null) {
                        results = new Uri[] { Uri.parse(mCameraPhotoPath) };
                    }
                } else {
                    String dataString = data.getDataString();
                    // cf. https://www.petitmonte.com/java/android_webview_camera.html
                    if (dataString == null) {
                        if (mCameraPhotoPath != null) {
                            results = new Uri[] { Uri.parse(mCameraPhotoPath) };
                        }
                    } else {
                        results = new Uri[] { Uri.parse(dataString) };
                    }
                }
            }
            mFilePathCallback.onReceiveValue(results);
            mFilePathCallback = null;
        } else {
            if (mUploadMessage == null) {
                super.onActivityResult(requestCode, resultCode, data);
                return;
            }
            Uri result = null;
            if (resultCode == Activity.RESULT_OK) {
                if (data != null) {
                    result = data.getData();
                }
            }
            mUploadMessage.onReceiveValue(result);
            mUploadMessage = null;
        }
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
        instanceCount++;
        mInstanceId = instanceCount;
        a.runOnUiThread(new Runnable() {public void run() {
            if (mWebView != null) {
                return;
            }

            setRetainInstance(true);
            if (mPaused) {
                if (mTransactions == null) {
                    mTransactions = new ArrayList<Pair<String, CWebViewPlugin>>();
                }
                mTransactions.add(Pair.create("add", self));
            } else {
                a
                    .getFragmentManager()
                    .beginTransaction()
                    .add(0, self, "CWebViewPlugin" + mInstanceId)
                    .commit();
            }

            mAlertDialogEnabled = true;
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

                // cf. https://stackoverflow.com/questions/40659198/how-to-access-the-camera-from-within-a-webview/47525818#47525818
                // cf. https://github.com/googlesamples/android-PermissionRequest/blob/eff1d21f0b9c91d67c7f2a2303b591447e61e942/Application/src/main/java/com/example/android/permissionrequest/PermissionRequestFragment.java#L148-L161
                @Override
                public void onPermissionRequest(final PermissionRequest request) {
                    final String[] requestedResources = request.getResources();
                    for (String r : requestedResources) {
                        if (r.equals(PermissionRequest.RESOURCE_VIDEO_CAPTURE) || r.equals(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) {
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

                // For Android < 3.0 (won't work because we cannot utilize FragmentActivity)
                // public void openFileChooser(ValueCallback<Uri> uploadFile) {
                //     openFileChooser(uploadFile, "");
                // }

                // For 3.0 <= Android < 4.1
                public void openFileChooser(ValueCallback<Uri> uploadFile, String acceptType) {
                    openFileChooser(uploadFile, acceptType, "");
                }

                // For 4.1 <= Android < 5.0
                public void openFileChooser(ValueCallback<Uri> uploadFile, String acceptType, String capture) {
                    if (mUploadMessage != null) {
                        mUploadMessage.onReceiveValue(null);
                    }
                    mUploadMessage = uploadFile;
                    Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);
                    intent.setType("*/*");
                    startActivityForResult(intent, INPUT_FILE_REQUEST_CODE);
                }

                // For Android 5.0+
                @Override
                public boolean onShowFileChooser(WebView webView, ValueCallback<Uri[]> filePathCallback, FileChooserParams fileChooserParams) {
                    // cf. https://github.com/googlearchive/chromium-webview-samples/blob/master/input-file-example/app/src/main/java/inputfilesample/android/chrome/google/com/inputfilesample/MainFragment.java
                    if (mFilePathCallback != null) {
                        mFilePathCallback.onReceiveValue(null);
                    }
                    mFilePathCallback = filePathCallback;

                    mCameraPhotoPath = null;
                    Intent takePictureIntent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
                    if (takePictureIntent.resolveActivity(getActivity().getPackageManager()) != null) {
                        // Create the File where the photo should go
                        File photoFile = null;
                        try {
                            photoFile = createImageFile();
                            takePictureIntent.putExtra("PhotoPath", mCameraPhotoPath);
                        } catch (IOException ex) {
                            // Error occurred while creating the File
                            Log.e("CWebViewPlugin", "Unable to create Image File", ex);
                        }
                        // Continue only if the File was successfully created
                        if (photoFile != null) {
                            mCameraPhotoPath = "file:" + photoFile.getAbsolutePath();
                            takePictureIntent.putExtra(MediaStore.EXTRA_OUTPUT,
                                                       Uri.fromFile(photoFile));
                        } else {
                            takePictureIntent = null;
                        }
                    }


                    Intent contentSelectionIntent = new Intent(Intent.ACTION_GET_CONTENT);
                    contentSelectionIntent.addCategory(Intent.CATEGORY_OPENABLE);
                    contentSelectionIntent.setType("*/*");

                    Intent[] intentArray;
                    if(takePictureIntent != null) {
                        intentArray = new Intent[]{takePictureIntent};
                    } else {
                        intentArray = new Intent[0];
                    }

                    Intent chooserIntent = new Intent(Intent.ACTION_CHOOSER);
                    chooserIntent.putExtra(Intent.EXTRA_INTENT, contentSelectionIntent);
                    // chooserIntent.putExtra(Intent.EXTRA_TITLE, "Image Chooser");
                    chooserIntent.putExtra(Intent.EXTRA_INITIAL_INTENTS, intentArray);

                    startActivityForResult(chooserIntent, INPUT_FILE_REQUEST_CODE);

                    return true;
                }

                private File createImageFile() throws IOException {
                    // Create an image file name
                    String timeStamp = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date());
                    String imageFileName = "JPEG_" + timeStamp + "_";
                    File storageDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES);
                    File imageFile = File.createTempFile(imageFileName,  /* prefix */
                                                         ".jpg",         /* suffix */
                                                         storageDir      /* directory */
                                                         );
                    return imageFile;
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
                    } else if (url.startsWith("http://") || url.startsWith("https://")
                        || url.startsWith("file://") || url.startsWith("javascript:")) {
                        mWebViewPlugin.call("CallOnStarted", url);
                        // Let webview handle the URL
                        return false;
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
        final CWebViewPlugin self = this;
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

            if (mPaused) {
                if (mTransactions == null) {
                    mTransactions = new ArrayList<Pair<String, CWebViewPlugin>>();
                }
                mTransactions.add(Pair.create("remove", self));
            } else {
                a
                    .getFragmentManager()
                    .beginTransaction()
                    .remove(self)
                    .commit();
            }

        }});
    }

    public boolean SetURLPattern(final String allowPattern, final String denyPattern, final String hookPattern)
    {
        try {
            final Pattern allow = (allowPattern == null || allowPattern.length() == 0) ? null : Pattern.compile(allowPattern);
            final Pattern deny = (denyPattern == null || denyPattern.length() == 0) ? null : Pattern.compile(denyPattern);
            final Pattern hook = (hookPattern == null || hookPattern.length() == 0) ? null : Pattern.compile(hookPattern);
            final Activity a = UnityPlayer.currentActivity;
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

    public void SetAlertDialogEnabled(final boolean enabled) {
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            mAlertDialogEnabled = enabled;
        }});
    }

    // cf. https://stackoverflow.com/questions/31788748/webview-youtube-videos-playing-in-background-on-rotation-and-minimise/31789193#31789193
    public void OnApplicationPause(boolean paused) {
        mPaused = paused;
        final Activity a = UnityPlayer.currentActivity;
        a.runOnUiThread(new Runnable() {public void run() {
            if (!mPaused) {
                if (mTransactions != null) {
                    for (Pair<String, CWebViewPlugin> pair : mTransactions) {
                        CWebViewPlugin self = pair.second;
                        switch (pair.first) {
                        case "add":
                            a
                                .getFragmentManager()
                                .beginTransaction()
                                .add(0, self, "CWebViewPlugin" + mInstanceId)
                                .commit();
                            break;
                        case "remove":
                            a
                                .getFragmentManager()
                                .beginTransaction()
                                .remove(self)
                                .commit();
                            break;
                        }
                    }
                    mTransactions.clear();
                }
            }
            if (mWebView == null) {
                return;
            }
            if (mPaused) {
                mWebView.onPause();
                if (mWebView.getVisibility() == View.VISIBLE) {
                    // cf. https://qiita.com/nbhd/items/d31711faa8852143f3a4
                    mWebView.pauseTimers();
                }
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

    public String GetCookies(String url)
    {
        CookieManager cookieManager = CookieManager.getInstance();
        return cookieManager.getCookie(url);
    }

    public void SetBasicAuthInfo(final String userName, final String password)
    {
        mBasicAuthUserName = userName;
        mBasicAuthPassword = password;
    }
}
