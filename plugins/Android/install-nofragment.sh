#!/bin/bash -e

# directories
CWD=`dirname $0`
CWD=`cd $CWD && pwd -P`

BUILD_DIR="${CWD}/webview-nofragment"
LIBS_DIR="${BUILD_DIR}/libs"

# options
MODE="Release"
SCRIPTING_BACKEND="il2cpp"
UNITY="/Applications/Unity5.6.1f1"
for OPT in $*
do
    case $OPT in
    '--release' )
        MODE="Release";;
    '--develop' )
        MODE="Develop";;
    '--il2cpp' )
        SCRIPTING_BACKEND="il2cpp";;
    '--mono' )
        SCRIPTING_BACKEND="mono";;
    '--unity' )
        shift
        UNITY=$1
        ;;
    esac
done
UNITY_JAVA_LIB="${UNITY}/PlaybackEngines/AndroidPlayer/Variations/${SCRIPTING_BACKEND}/${MODE}/Classes/classes.jar"

pushd $CWD

# build
cp ${UNITY_JAVA_LIB} ${LIBS_DIR}
./gradlew clean -p webview-nofragment
./gradlew assembleRelease -p webview-nofragment

# install
DEST_DIR='../../build/Packager/Assets/Plugins/Android'
mkdir -p ${DEST_DIR}
cp ${BUILD_DIR}/build/outputs/aar/*.aar ${DEST_DIR}/WebViewPlugin.aar
rm -f ${DEST_DIR}/core*.aar.tmpl

popd
