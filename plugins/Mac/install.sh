#!/bin/bash
DSTDIR="../../build/Packager/Assets/Plugins"
rm -rf DerivedData
xcodebuild -target WebView -configuration Release -arch x86_64 -arch arm64 build CONFIGURATION_BUILD_DIR='DerivedData' | xcbeautify
mkdir -p $DSTDIR

cp -r DerivedData/WebView.bundle $DSTDIR
rm -rf DerivedData
cp *.bundle.meta $DSTDIR
