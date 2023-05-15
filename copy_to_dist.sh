#!/bin/bash -e

cp ./plugins/WebViewObject.cs ./dist/package/Assets/Plugins/WebViewObject.cs
cp ./plugins/Android/webview/build/outputs/aar/*.aar ./dist/package/Assets/Plugins/Android/WebViewPlugin.aar
cp ./plugins/iOS/WebView.mm ./dist/package/Assets/Plugins/iOS/WebView.mm
cp ./plugins/iOS/WebViewWithUIWebView.mm ./dist/package/Assets/Plugins/iOS/WebViewWithUIWebView.mm
