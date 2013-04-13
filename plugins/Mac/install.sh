#!/bin/sh
DSTDIR="../../build/Packager/Assets/Plugins"
rm -rf DerivedData
xcodebuild -scheme WebView -configuration Release build CONFIGURATION_BUILD_DIR='DerivedData'
mkdir -p $DSTDIR
cp -r DerivedData/WebView.bundle $DSTDIR
rm -rf DerivedData
