#!/bin/bash
DSTDIR="../../build/Packager/Assets/Plugins"
rm -rf DerivedData
xcodebuild -target WebView -configuration Release -arch i386 -arch x86_64 build CONFIGURATION_BUILD_DIR='DerivedData' | xcpretty
mkdir -p $DSTDIR

cp -r DerivedData/WebView.bundle $DSTDIR
rm -rf DerivedData
cp *.bundle.meta $DSTDIR
