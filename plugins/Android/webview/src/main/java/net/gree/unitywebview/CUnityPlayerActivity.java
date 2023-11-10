package net.gree.unitywebview;

import android.graphics.Color;
import android.graphics.Rect;
import android.os.Bundle;
import android.util.Log;
import android.view.MotionEvent;
import android.webkit.WebView;
import com.unity3d.player.*;
import java.util.ArrayList;
import java.util.List;

public class CUnityPlayerActivity
    extends UnityPlayerActivity
{
    private List<WebView> _webViews = new ArrayList<WebView>();
    private List<Rect> _masks = new ArrayList<Rect>();

    @Override
    protected void onCreate(Bundle savedInstanceState)
    {
        super.onCreate(savedInstanceState);
        getWindow().getDecorView().setBackgroundColor(Color.BLACK);
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
        for (WebView webView : _webViews) {
            // cf. https://stackoverflow.com/questions/17845545/custom-viewgroup-dispatchtouchevent-doesnt-work-correctly/17845670#17845670
            MotionEvent cp = MotionEvent.obtain(event);
            cp.offsetLocation(-webView.getLeft(), -webView.getTop());
            webView.dispatchTouchEvent(cp);
            cp.recycle();
        }
        return ret;
    }

    void add(WebView webView) {
        _webViews.add(webView);
    }

    void remove(WebView webView) {
        _webViews.remove(webView);
    }

    public void clearMasks() {
        _masks.clear();
    }

    public void addMask(int left, int top, int right, int bottom) {
        _masks.add(new Rect(left, top, right, bottom));
    }
}
