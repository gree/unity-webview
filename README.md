### Introduction

unity-webview is a plugin for Unity that attaches WebView component in the game scene. It works on Android, iOS, OS X, and **WebPlayer**.

unity-webview is derived from keijiro-san's unity-webview-integration https://github.com/keijiro/unity-webview-integration .

### Caution ###
** This plugin doesn't support Unity 3.*. **
But you can be able to run in Unity 3, if modified WebPlayerTemplates/unity-webview/index.html.

### How to use

(TBW)

### Document

(TBW)


### For iOS

CADisplayLink stops updating when UIWebView scrolled, thus you have to change AppController.mm as the following.

    -        [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    +        [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    
### For Web Player

Since using IFRAME, some problems can be occurred because of browsers' XSS prevention. It is desired that "an_unityplayer_page.html…" and "a_page_loaded_in_webview.html…" are located at same domain.


### Android: Uncaught TypeError: Object [object Object] has no method 'call'

https://github.com/gree/unity-webview/issues/10

### Sample Project

    $ open sample/Assets/Sample.unity
    $ open dist/unity-webview.unitypackage
    Import all files
