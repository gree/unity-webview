#!/bin/bash
# Ensures that the AAR are installed into the correct place for DIST directly.

set -euo pipefail

# directories
CWD=`dirname $0`
CWD=`cd $CWD && pwd -P`

case $(uname) in
Darwin)
    export JAVA_HOME='/Applications/Unity/Hub/Editor/2019.4.40f1/PlaybackEngines/AndroidPlayer/OpenJDK'
    export ANDROID_SDK_ROOT='/Applications/Unity/Hub/Editor/2019.4.40f1/PlaybackEngines/AndroidPlayer/SDK'
    export PATH=$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$JAVA_HOME/bin:$PATH
    UNITY='/Applications/Unity/Hub/Editor/2019.4.40f1'
    ;;
MINGW64_NT*)
    export JAVA_HOME='/c/PROGRA~1/Unity/Hub/Editor/2019.4.40f1/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK'
    export ANDROID_SDK_ROOT='/c/PROGRA~1/Unity/Hub/Editor/2019.4.40f1/Editor/Data/PlaybackEngines/AndroidPlayer/SDK'
    export PATH=$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$JAVA_HOME/bin:$PATH
    UNITY='/c/PROGRA~1/Unity/Hub/Editor/2019.4.40f1/Editor/Data'
    ;;
esac
DEST_DIR='../../dist/package/Assets/Plugins/Android'
# DEST_DIR='../../build/Packager/Assets/Plugins/Android'

if [ ! -d "$JAVA_HOME" ]
then
    echo 'From Unity Hub, please install 2019.4.40f1 with the android module.'
    exit 1
fi
if [ ! -d "$UNITY" ]
then
    echo 'From Unity Hub, please install 2019.4.40f1 with the android module.'
    exit 1
fi

# options
TARGET="webview"
MODE="Release"
for OPT in $*
do
    case $OPT in
    '--nofragment')
        TARGET="webview-nofragment"
        DEST_DIR='../../dist/package-nofragment/Assets/Plugins/Android'
        ;;
    '--development')
        MODE="Development"
        ;;
    *)
        cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:

  --nofragment		build a nofragment variant.
  --development		build a development variant.

EOF
        exit 1
        ;;
    esac
done
UNITY_JAVA_LIB="${UNITY}/PlaybackEngines/AndroidPlayer/Variations/il2cpp/${MODE}/Classes/classes.jar"

# save original CWebViewPlugin.java
tmp=$(mktemp -d -t _client_sh.XXX)
cp -a "${TARGET}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java" $tmp/CWebViewPlugin.java
cleanup() {
    ret=$?
    cp -a $tmp/CWebViewPlugin.java "${TARGET}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java"
    exit $ret
}
trap cleanup EXIT

# emit CWebViewPlugin.java for release by default
sed '/^\/\/#if UNITYWEBVIEW_DEVELOPMENT$/,/^\/\/#endif$/d' < $tmp/CWebViewPlugin.java > "${TARGET}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java"
case $MODE in
'Release')
    dst=${DEST_DIR}/WebViewPlugin-release.aar.tmpl
    cp -a $tmp/CWebViewPlugin.java "${TARGET}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java"
    ;;
*)
    dst=${DEST_DIR}/WebViewPlugin-development.aar.tmpl
    ;;
esac

pushd "$CWD"

# build
cp ${UNITY_JAVA_LIB} ${TARGET}/libs
./gradlew clean -p $TARGET
./gradlew assembleRelease -p $TARGET

# install
mkdir -p ${DEST_DIR}
echo cp ${TARGET}/build/outputs/aar/*.aar $dst
cp ${TARGET}/build/outputs/aar/*.aar $dst
case $TARGET in
'webview')
    core_aar=`basename ${TARGET}/libs-ext/core*.aar`
    echo cp ${TARGET}/libs-ext/$core_aar ${DEST_DIR}/$core_aar.tmpl
    cp ${TARGET}/libs-ext/$core_aar ${DEST_DIR}/$core_aar.tmpl
    ;;
esac

popd
