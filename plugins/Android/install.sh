#!/bin/sh
UNITYLIBS="/Applications/Unity/Unity.app/Contents/PlaybackEngines/AndroidPlayer/bin/classes.jar"
if [ ! -f $UNITYLIBS ]
then
    UNITYLIBS="/Applications/Unity/Unity.app/Contents/PlaybackEngines/AndroidPlayer/release/bin/classes.jar"
fi
DSTDIR="../../build/Packager/Assets/Plugins/Android"
export ANT_OPTS=-Dfile.encoding=UTF8
android update project -t android-18 -p .
mkdir -p libs
cp $UNITYLIBS libs
ant release
mkdir -p $DSTDIR
cp -a bin/classes.jar $DSTDIR/WebViewPlugin.jar
ant clean
rm -rf libs res proguard-project.txt
