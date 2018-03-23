#!/bin/bash
DSTDIR="../../build/Packager/Assets/Plugins"
UNITYAPP="/Applications/Unity/Unity.app"
version=`/usr/libexec/PlistBuddy -c "Print CFBundleVersion" ${UNITYAPP}/Contents/Info.plist`
if [ `echo $version | sed -e "s/\..*$//"` = "2017" ] ; then
    sed -i "" -e "s@/Applications/Unity/Unity.app/Contents/Frameworks/MonoEmbedRuntime/osx@${UNITYAPP}/Contents/Frameworks/Mono/MonoEmbedRuntime/osx@g" WebView.xcodeproj/project.pbxproj
else
    sed -i "" -e "s@/Applications/Unity/Unity.app/Contents/Frameworks/MonoEmbedRuntime/osx@${UNITYAPP}/Contents/Frameworks/MonoEmbedRuntime/osx@g" WebView.xcodeproj/project.pbxproj
fi
rm -rf DerivedData
xcodebuild -target WebView -configuration Release -arch i386 -arch x86_64 build CONFIGURATION_BUILD_DIR='DerivedData'
xcodebuild -target WebViewSeparated -configuration Release -arch x86_64 build CONFIGURATION_BUILD_DIR='DerivedData'
mkdir -p $DSTDIR

# adjust libmono.0.dylib paths
for i in WebView WebViewSeparated
do
    pushd DerivedData/$i.bundle/Contents/MacOS
    install_name_tool -change @executable_path/../Frameworks/MonoEmbedRuntime/osx/libmono.0.dylib @rpath/libmono.0.dylib $i
    install_name_tool -add_rpath @executable_path/../Frameworks/MonoEmbedRuntime/osx/ $i
    install_name_tool -add_rpath @executable_path/../Frameworks/Mono/MonoEmbedRuntime/osx/ $i
    popd
done

cp -r DerivedData/WebView.bundle $DSTDIR
cp -r DerivedData/WebViewSeparated.bundle $DSTDIR
rm -rf DerivedData
cp *.bundle.meta $DSTDIR
