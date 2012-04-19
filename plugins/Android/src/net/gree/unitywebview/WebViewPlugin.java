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
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup.LayoutParams;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

class WebViewPluginInterface
{
	private String mGameObject;

	public WebViewPluginInterface(final String gameObject)
	{
		mGameObject = gameObject;
	}

	public void call(String message)
	{
		UnityPlayer.UnitySendMessage(mGameObject, "CallFromJS", message);
	}
}

public class WebViewPlugin
{
	private static FrameLayout layout = null;
	private WebView mWebView;
	private boolean mNeedsInput;
	private long mDownTime;

	public WebViewPlugin()
	{
	}

	public boolean Init(final String gameObject)
	{
		final Activity a = UnityPlayer.currentActivity;
		mNeedsInput = a.getClass().getSimpleName().compareTo(
			"UnityPlayerNativeActivity") == 0;
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

			mWebView.setWebChromeClient(new WebChromeClient());
			mWebView.setWebViewClient(new WebViewClient());
			mWebView.addJavascriptInterface(
				new WebViewPluginInterface(gameObject), "Unity");

			WebSettings webSettings = mWebView.getSettings();
			webSettings.setSupportZoom(false);
			webSettings.setJavaScriptEnabled(true);
			webSettings.setPluginsEnabled(true);

		}});

		return mNeedsInput;
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

	public void Update(final float x, final float y,
		final boolean down, final boolean press, final boolean release)
	{
		if (!mNeedsInput || mWebView == null)
			return;

		Activity a = UnityPlayer.currentActivity;
		a.runOnUiThread(new Runnable() {public void run() {

			long time = SystemClock.uptimeMillis();
			if (down)
				mDownTime = time;

			int action;
			if (press) {
				action = MotionEvent.ACTION_DOWN;
			} else if (release) {
				action = MotionEvent.ACTION_UP;
			} else {
				action = MotionEvent.ACTION_MOVE;
			}

			MotionEvent motionEvent = MotionEvent.obtain(
				mDownTime,
				time,
				action,
				x, 
				y, 
				0);

			mWebView.dispatchTouchEvent(motionEvent);

		}});
	}
}
