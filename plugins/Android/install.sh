#!/bin/bash -e

# directories
CWD=`dirname $0`
CWD=`cd $CWD && pwd -P`

# options
TARGET="webview"
MODE="Release"
DEST_DIR='../../build/Packager/Assets/Plugins/Android'
SCRIPTING_BACKEND="il2cpp"
UNITY="/Applications/Unity5.6.1f1"
for OPT in $*
do
    case $OPT in
    '--nofragment')
        TARGET="webview-nofragment"
        ;;
    '--development')
        MODE="Development"
        ;;
    '--unity')
        shift
        UNITY=$1
        ;;
    esac
done
BUILD_DIR="${CWD}/${TARGET}"
LIBS_DIR="${BUILD_DIR}/libs"
UNITY_JAVA_LIB="${UNITY}/PlaybackEngines/AndroidPlayer/Variations/${SCRIPTING_BACKEND}/${MODE}/Classes/classes.jar"

# save original CWebViewPlugin.java
tmp=$(mktemp -d -t _client_sh.XXX)
cp -a "${BUILD_DIR}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java" $tmp/CWebViewPlugin.java
cleanup() {
    ret=$?
    cp -a $tmp/CWebViewPlugin.java "${BUILD_DIR}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java"
    exit $ret
}
trap cleanup EXIT

# emit CWebViewPlugin.java for release by default
sed '/^\/\/#if UNITYWEBVIEW_DEVELOPMENT$/,/^\/\/#endif$/d' < $tmp/CWebViewPlugin.java > "${BUILD_DIR}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java"
case $MODE in
'Release')
    dst=${DEST_DIR}/WebViewPlugin-release.aar.tmpl
    cp -a $tmp/CWebViewPlugin.java "${BUILD_DIR}/src/main/java/net/gree/unitywebview/CWebViewPlugin.java"
    ;;
*)
    dst=${DEST_DIR}/WebViewPlugin-development.aar.tmpl
    ;;
esac

pushd $CWD

# build
cp ${UNITY_JAVA_LIB} ${LIBS_DIR}
./gradlew clean -p $TARGET
./gradlew assembleRelease -p $TARGET

# install
mkdir -p ${DEST_DIR}
cp ${BUILD_DIR}/build/outputs/aar/*.aar $dst
case $TARGET in
'webview')
    core_aar=`basename ${BUILD_DIR}/libs-ext/core*.aar`
    cp ${BUILD_DIR}/libs-ext/$core_aar ${DEST_DIR}/$core_aar.tmpl
    ;;
esac

popd
