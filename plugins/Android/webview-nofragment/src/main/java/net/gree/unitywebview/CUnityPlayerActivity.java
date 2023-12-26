package net.gree.unitywebview;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.WebView;
import com.unity3d.player.*;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

public class CUnityPlayerActivity
    extends UnityPlayerActivity
{
    private List<CWebViewPlugin> _webViewPlugins = new ArrayList<CWebViewPlugin>();
    private List<Rect> _masks = new ArrayList<Rect>();

    @Override
    protected void onCreate(Bundle savedInstanceState)
    {
        super.onCreate(savedInstanceState);
        // getWindow().getDecorView().setBackgroundColor(Color.BLACK);
        // cf. https://stackoverflow.com/questions/9812427/android-how-to-programmatically-make-an-activity-window-transluscent
        // cf. https://github.com/ikew0ng/SwipeBackLayout/blob/e4ddae6d2b8af9b606493cba36faef8beba94be2/library/src/main/java/me/imid/swipebacklayout/lib/Utils.java
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            setTranslucent(false);
        } else {
            try {
                Method method = Activity.class.getDeclaredMethod("convertFromTranslucent");
                method.setAccessible(true);
                method.invoke(this);
            } catch (Throwable t) {
            }
        }
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        boolean ret = super.dispatchTouchEvent(event);
        int pointerCount = event.getPointerCount();
        for (int p = 0; p < pointerCount; p++) {
            float x = event.getX(p);
            float y = event.getY(p);
            for (Rect mask : _masks) {
                if (mask.contains((int)x, (int)y)) {
                    return ret;
                }
            }
        }
        for (CWebViewPlugin webViewPlugin : _webViewPlugins) {
            // cf. https://stackoverflow.com/questions/17845545/custom-viewgroup-dispatchtouchevent-doesnt-work-correctly/17845670#17845670
            MotionEvent cp = MotionEvent.obtain(event);
            View view = (webViewPlugin.mVideoView != null) ? webViewPlugin.mVideoView : webViewPlugin.mWebView;
            cp.offsetLocation(-view.getLeft(), -view.getTop());
            view.dispatchTouchEvent(cp);
            cp.recycle();
        }
        return ret;
    }

    void add(CWebViewPlugin webViewPlugin) {
        _webViewPlugins.add(webViewPlugin);
    }

    void remove(CWebViewPlugin webViewPlugin) {
        _webViewPlugins.remove(webViewPlugin);
    }

    public void clearMasks() {
        _masks.clear();
    }

    public void addMask(int left, int top, int right, int bottom) {
        _masks.add(new Rect(left, top, right, bottom));
    }
}
