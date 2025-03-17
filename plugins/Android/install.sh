#!/bin/bash
set -euo pipefail

# directories
CWD=`dirname $0`
CWD=`cd $CWD && pwd -P`

case $(uname) in
Darwin)
    export JAVA_HOME='/Applications/Unity/Hub/Editor/2019.4.40f1/PlaybackEngines/AndroidPlayer/OpenJDK'
    export ANDROID_SDK_ROOT='/Applications/Unity/Hub/Editor/2019.4.40f1/PlaybackEngines/AndroidPlayer/SDK'
    export PATH=$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$JAVA_HOME/bin:$PATH
    ;;
MINGW64_NT*)
    export JAVA_HOME='/c/PROGRA~1/Unity/Hub/Editor/2019.4.40f1/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK'
    export ANDROID_SDK_ROOT='/c/PROGRA~1/Unity/Hub/Editor/2019.4.40f1/Editor/Data/PlaybackEngines/AndroidPlayer/SDK'
    export PATH=$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$JAVA_HOME/bin:$PATH
    ;;
esac
DEST_DIR='../../build/Packager/Assets/Plugins/Android'

if [ ! -d "$JAVA_HOME" ]
then
    echo 'From Unity Hub, please install 2019.4.40f1 with the android module.'
    exit 1
fi

# options
TARGET="webview"
MODE="Release"
UNITY='2019.4.40f1'
for OPT in $*
do
    case $OPT in
    '--nofragment')
        TARGET="webview-nofragment"
        ;;
    '--development')
        MODE="Development"
        ;;
    '--zorderpatch')
        UNITY='5.6.1f1'
        ;;
    *)
        cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:

  --nofragment		build a nofragment variant.
  --development		build a development variant.
  --zorderpatch		build with the patch for 5.6.0 and 5.6.1 (except 5.6.1p4).

EOF
        exit 1
        ;;
    esac
done

case $(uname) in
Darwin)
    UNITY_DIR="/Applications/Unity/Hub/Editor/${UNITY}"
    ;;
MINGW64_NT*)
    UNITY_DIR="/c/PROGRA~1/Unity/Hub/Editor/${UNITY}/Editor/Data"
    ;;
esac
if [ ! -d "$UNITY_DIR" ]
then
    echo 'From Unity Hub, please install $UNITY with the android module.'
    exit 1
fi

# save original *.java
tmp=$(mktemp -d -t _client_sh.XXX)
cp -a ${TARGET}/src/main/java/net/gree/unitywebview/*.java $tmp
cleanup() {
    ret=$?
    cp -a $tmp/*.java ${TARGET}/src/main/java/net/gree/unitywebview
    exit $ret
}
trap cleanup EXIT

# adjust CWebViewPlugin.java
case $MODE in
'Release')
    dst=${DEST_DIR}/WebViewPlugin-release.aar.tmpl
    sed '/^\/\/#if UNITYWEBVIEW_DEVELOPMENT$/,/^\/\/#endif$/d' < $tmp/CWebViewPlugin.java > ${TARGET}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java
    ;;
*)
    dst=${DEST_DIR}/WebViewPlugin-development.aar.tmpl
    cp -a $tmp/CWebViewPlugin.java ${TARGET}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java
    ;;
esac
# remove CUnityPlayer*.java if UNITY != 5.6.1f1.
case $UNITY in
'5.6.1f1')
    ;;
*)
    rm -f ${TARGET}/src/main/java/net/gree/unitywebview/CUnityPlayer*.java
    ;;
esac

pushd $CWD

# build
cp "${UNITY_DIR}/PlaybackEngines/AndroidPlayer/Variations/il2cpp/${MODE}/Classes/classes.jar" ${TARGET}/libs
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
