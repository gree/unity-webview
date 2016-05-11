/*
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

using System.Collections;
using UnityEngine;

public class SampleWebView : MonoBehaviour
{
	public string Url;
	public string SameDomainUrl;
	public GUIText status;
	WebViewObject webViewObject;

#if !UNITY_WEBPLAYER
	IEnumerator Start()
#else
	void Start()
#endif
	{
		webViewObject =
			(new GameObject("WebViewObject")).AddComponent<WebViewObject>();
		webViewObject.Init((msg)=>{
			Debug.Log(string.Format("CallFromJS[{0}]", msg));
			status.text = msg;
			status.GetComponent<Animation>().Play();
		});
		
		webViewObject.SetMargins(5, 5, 5, Screen.height / 4);
		webViewObject.SetVisibility(true);

		switch (Application.platform) {
#if !UNITY_WEBPLAYER
		case RuntimePlatform.OSXEditor:
		case RuntimePlatform.OSXPlayer:
		case RuntimePlatform.IPhonePlayer:
		case RuntimePlatform.Android:
			if (Url.StartsWith("http")) {
				webViewObject.LoadURL(Url.Replace(" ", "%20"));
			} else {
				var src = System.IO.Path.Combine(Application.streamingAssetsPath, Url);
				var dst = System.IO.Path.Combine(Application.persistentDataPath, Url);
				var result = "";
				if (src.Contains("://")) {
					var www = new WWW(src);
					yield return www;
					result = www.text;
				} else {
					result = System.IO.File.ReadAllText(src);
				}
				System.IO.File.WriteAllText(dst, result);
				webViewObject.LoadURL("file://" + dst.Replace(" ", "%20"));
			}
			if (Application.platform != RuntimePlatform.Android) {
				webViewObject.EvaluateJS(
					"window.addEventListener('load', function() {" +
					"	window.Unity = {" +
					"		call:function(msg) {" +
					"			var iframe = document.createElement('IFRAME');" +
					"			iframe.setAttribute('src', 'unity:' + msg);" +
					"			document.documentElement.appendChild(iframe);" +
					"			iframe.parentNode.removeChild(iframe);" +
					"			iframe = null;" +
					"		}" +
					"	}" +
					"}, false);");
			}
			break;
#else
		case RuntimePlatform.OSXWebPlayer:
		case RuntimePlatform.WindowsWebPlayer:
			webViewObject.LoadURL(Url.Replace(" ", "%20"));
			webViewObject.EvaluateJS(
				"parent.$(function() {" +
				"	window.Unity = {" +
				"		call:function(msg) {" +
				"			parent.unityWebView.sendMessage('WebViewObject', msg)" +
				"		}" +
				"	};" +
				"});");
			break;
#endif
		}
	}
}
