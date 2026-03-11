#!/usr/bin/env bash
DSTDIR="../../build/Packager/Assets/Plugins"

case $1 in
--build)
    MSBUILD="/c/Program Files/Microsoft Visual Studio/18/Community/MSBUILD/Current/Bin/MSBUILD.exe"
    powershell -File restore_webview2_sdk.ps1
    "$MSBUILD" WebViewPlugin.sln //p:Configuration=Release //p:Platform=x64
    "$MSBUILD" WebViewPlugin.sln //p:Configuration=Release //p:Platform=Win32
    ;;
esac

mkdir -p $DSTDIR/Windows/{x64,x86}
cp -a bin/x64/Release/WebView.dll $DSTDIR/Windows/x64
cp -a bin/Win32/Release/WebView.dll $DSTDIR/Windows/x86
