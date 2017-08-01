#!/bin/sh

# OS specific support.  $var _must_ be set to either true or false.
cygwin=false
case "`uname`" in
CYGWIN*) cygwin=true;;
esac

# For Cygwin, ensure paths are in UNIX format
if $cygwin; then
	[ -n "$ANT_HOME" ] && ANT_HOME=`cygpath --unix "$ANT_HOME"`
fi

if $cygwin; then
	UNITYLIBS=`find -L "/cygdrive/c/Program Files/Unity5" | grep classes.jar | tail -1`
else
	UNITYLIBS=`find -L /Applications/Unity | grep classes.jar | tail -1`
fi

DSTDIR="../../build/Packager/Assets/Plugins/Android"
export ANT_OPTS=-Dfile.encoding=UTF8
android update project -t android-21 -p .
mkdir -p libs
cp "$UNITYLIBS" libs
ant "-Djava.compilerargs=-Xlint:deprecation" release
mkdir -p "$DSTDIR"
cp -a bin/classes.jar "$DSTDIR/WebViewPlugin.jar"
ant clean
rm -rf libs res proguard-project.txt
