#!/bin/sh
DSTDIR="../../build/Packager/Assets/Plugins"
rm -rf DerivedData
xcodebuild -scheme WebView -configuration Release build
mkdir -p $DSTDIR
cp -r DerivedData/WebView/Build/Products/Release/WebView.bundle $DSTDIR
rm -rf DerivedData
