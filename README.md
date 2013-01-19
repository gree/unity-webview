### Introduction

unity-webview is a plugin for Unity that attaches WebView component in the game scene. It works on Android, iOS and OS X.

unity-webview is derived from keijiro-san's unity-webview-integration https://github.com/keijiro/unity-webview-integration .

### How to use

(TBW)

### Document

(TBW)

### For iOS with Unity 3.5.*

CADisplayLink stops updating when UIWebView scrolled, thus you have to change AppController.mm as the following.

    -        [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    +        [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

### Sample Project

    $ open sample/Assets/Sample.unity
    $ open dist/unity-webview.unitypackage
    Import all files

