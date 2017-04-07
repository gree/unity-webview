using System.Collections;
using System.Collections.Generic;
using UnityEngine;


/// <summary>
/// Example for Custom header features.
/// If you want to try custom headers, put this class as a component to the scene.
/// </summary>
public class SampleCustomHeader : MonoBehaviour
{
    const float BUTTON_HEIGHT = 50.0f;
    const string CUSTOM_HEADER_KEY_NAME = "custom_timestamp";

    WebViewObject _webviewObject;

    // Use this for initialization
    void Start()
    {
    }
	
    // Update is called once per frame
    void Update()
    {
		
    }

    void OnGUI()
    {
        float h = Screen.height;
        if (GUI.Button(new Rect(.0f, h - BUTTON_HEIGHT, Screen.width, BUTTON_HEIGHT), "check for request header"))
        {
            this._webviewObject = GameObject.Find("WebViewObject").GetComponent<WebViewObject>();
            this._webviewObject.LoadURL("http://httpbin.org/headers");
        }
        h -= BUTTON_HEIGHT;

        if (GUI.Button(new Rect(.0f, h - BUTTON_HEIGHT, Screen.width, BUTTON_HEIGHT), "add custom header"))
        {
            this._webviewObject = GameObject.Find("WebViewObject").GetComponent<WebViewObject>();
            this._webviewObject.AddCustomHeader(CUSTOM_HEADER_KEY_NAME, System.DateTime.Now.ToString());
        }
        h -= BUTTON_HEIGHT;

        if (GUI.Button(new Rect(.0f, h - BUTTON_HEIGHT, Screen.width, BUTTON_HEIGHT), "get custom header"))
        {
            this._webviewObject = GameObject.Find("WebViewObject").GetComponent<WebViewObject>();
            Debug.Log("custom_timestamp is " + this._webviewObject.GetCustomHeaderValue(CUSTOM_HEADER_KEY_NAME));
        }
        h -= BUTTON_HEIGHT;

        if (GUI.Button(new Rect(.0f, h - BUTTON_HEIGHT, Screen.width, BUTTON_HEIGHT), "remove custom header"))
        {
            this._webviewObject = GameObject.Find("WebViewObject").GetComponent<WebViewObject>();
            this._webviewObject.RemoveCustomHeader(CUSTOM_HEADER_KEY_NAME);
        }
        h -= BUTTON_HEIGHT;

        if (GUI.Button(new Rect(.0f, h - BUTTON_HEIGHT, Screen.width, BUTTON_HEIGHT), "clear custom header"))
        {
            this._webviewObject = GameObject.Find("WebViewObject").GetComponent<WebViewObject>();
            this._webviewObject.ClearCustomHeader();
        }
        h -= BUTTON_HEIGHT;
    }
}
