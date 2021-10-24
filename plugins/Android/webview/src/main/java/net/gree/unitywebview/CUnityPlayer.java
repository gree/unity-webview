package net.gree.unitywebview;

import com.unity3d.player.*;
import android.content.ContextWrapper;
import android.view.SurfaceView;
import android.view.View;

public class CUnityPlayer
    extends UnityPlayer
{
    public CUnityPlayer(ContextWrapper contextwrapper) {
        super(contextwrapper);
    }

    public void addView(View child) {
        if (child instanceof SurfaceView) {
            ((SurfaceView)child).setZOrderOnTop(false);
        }
        super.addView(child);
    }
}
