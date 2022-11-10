using System.Collections.Generic;
using System.Collections;
using UnityEngine.SceneManagement;
using UnityEngine;

public class Boot : MonoBehaviour
{
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    void OnGUI()
    {
        var x = 10;

        if (GUI.Button(new Rect(x, 10, 110, 80), "WebView 1")) {
            SampleWebView.Url = "https://www.atlassian.com/legal/privacy-policy";
            SceneManager.LoadScene("Sample", LoadSceneMode.Single);
        }
        x += 120;

        if (GUI.Button(new Rect(x, 10, 110, 80), "WebView 2")) {
            SampleWebView.Url = "https://www.youtube.com/playlist?list=PL1wNGMba9T63zX4ZtN4R7sxPdH7MQeob-";
            SceneManager.LoadScene("Sample", LoadSceneMode.Single);
        }
        x += 120;
    }
}
