using UnityEngine;
using UnityEngine.UI;
using System.Collections;

public class WebViewManager : MonoBehaviour
{
    public string Url = "https://google.com";
    public WebViewObject webViewObject;

    IEnumerator Start()
    {
        int screenWidth = Screen.width;
        int screenHeight = Screen.height;
        webViewObject.Init((msg) =>
        {
            Debug.Log($"CallFromJS[{msg}]");
        });

        webViewObject.SetMargins(screenWidth / 4, screenHeight / 4, screenWidth / 4, screenHeight / 4);
        webViewObject.SetVisibility(true);

#if !UNITY_WEBPLAYER && !UNITY_WEBGL
        webViewObject.LoadURL(Url.Replace(" ", "%20"));
#else
        webViewObject.LoadURL("StreamingAssets/" + Url.Replace(" ", "%20"));
#endif

        yield break;
    }
}
