package net.gree.unitywebview;

import com.unity3d.player.*;
import android.os.Bundle;

public class CUnityPlayerActivity
    extends UnityPlayerActivity
{
    @Override
    public void onCreate(Bundle bundle) {
        requestWindowFeature(1);
        super.onCreate(bundle);
        getWindow().setFormat(2);
        mUnityPlayer = new CUnityPlayer(this);
        setContentView(mUnityPlayer);
        mUnityPlayer.requestFocus();
    }
}
