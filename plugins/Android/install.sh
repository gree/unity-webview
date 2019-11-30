#!/bin/sh

# required command
JAR_CMD=`which jar`

# directories
CWD=`dirname $0`
CWD=`cd $CWD && pwd -P`

BUILD_DIR="${CWD}/gradle_build"
LIBS_DIR="${BUILD_DIR}/libs"
JAVA_DIR="${BUILD_DIR}/src/main/java"
BIN_DIR="${CWD}/bin"

# options
MODE="Release"
SCRIPTING_BACKEND="il2cpp"
UNITY="/Applications/Unity5.6.1f1"

for OPT in $*; do
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
      UNITY=$2
      shift 2
      ;;
  esac
  shift
done

UNITY_JAVA_LIB="${UNITY}/PlaybackEngines/AndroidPlayer/Variations/${SCRIPTING_BACKEND}/${MODE}/Classes/classes.jar"

# clean
rm -rf ${JAVA_DIR}/*
rm -rf ${LIB_DIR}
rm -f ${BUILD_DIR}/src/main/AndroidManifest.xml

pushd $CWD

# copy unity library
DEST_DIR='../../build/Packager/Assets/Plugins/Android'

mkdir -p ${LIBS_DIR}
mkdir -p ${BIN_DIR}
mkdir -p ${DEST_DIR}
mkdir -p ${JAVA_DIR}

cp ${UNITY_JAVA_LIB} ${LIBS_DIR}
cp -r src/net ${JAVA_DIR}
cp AndroidManifest.xml ${BUILD_DIR}/src/main

# build
./gradlew assembleRelease

if [ ${JAR_CMD} = "" ];then
  echo "jar command does not exist"
else
  jar cvf ${CWD}/bin/WebViewPlugin.jar -C ${BUILD_DIR}/build/intermediates/classes/release net
  cp -a ${BIN_DIR}/WebViewPlugin.jar ${DEST_DIR}
fi

./gradlew clean

popd # $BUILD_DIR
